import Anthropic from "@anthropic-ai/sdk";
import type { Config } from "./config.js";
import { buildUserMessage, SYSTEM_PROMPT } from "./prompt.js";
import {
  REPLY_OUTPUT_JSON_SCHEMA,
  ReplySuggestionsSchema,
  type ReplyRequest,
  type ReplySuggestions,
} from "./schema.js";

export class RefusedError extends Error {}
export class BadModelOutputError extends Error {}

export type Generator = (req: ReplyRequest) => Promise<ReplySuggestions>;

export function createClient(config: Config): Anthropic {
  return new Anthropic({ baseURL: config.baseURL, apiKey: config.apiKey });
}

export function createGenerator(client: Anthropic, config: Config): Generator {
  return async (req) => {
    const response = await client.beta.messages.create({
      model: config.model,
      // 留出空间给推理，正常回复只有几百 token
      max_tokens: 4000,
      system: [{ type: "text", text: SYSTEM_PROMPT, cache_control: { type: "ephemeral" } }],
      messages: [{ role: "user", content: buildUserMessage(req) }],
      output_config: {
        effort: config.effort,
        format: { type: "json_schema", schema: REPLY_OUTPUT_JSON_SCHEMA },
      },
      ...(config.serverFallback
        ? { betas: ["server-side-fallback-2026-07-01"], fallbacks: "default" as const }
        : {}),
    });

    if (response.stop_reason === "refusal") {
      throw new RefusedError(response.stop_details?.category ?? "refused");
    }
    if (response.stop_reason === "max_tokens") {
      throw new BadModelOutputError("response hit max_tokens");
    }

    const text = response.content
      .flatMap((block) => (block.type === "text" ? [block.text] : []))
      .join("");
    let parsed: unknown;
    try {
      parsed = JSON.parse(text);
    } catch {
      throw new BadModelOutputError("model did not return JSON");
    }
    const result = ReplySuggestionsSchema.safeParse(parsed);
    if (!result.success) throw new BadModelOutputError(result.error.message);
    return { ...result.data, replies: result.data.replies.slice(0, 3) };
  };
}
