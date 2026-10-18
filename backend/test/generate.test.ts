import type Anthropic from "@anthropic-ai/sdk";
import { describe, expect, it, vi } from "vitest";
import { loadConfig } from "../src/config.js";
import { BadModelOutputError, createGenerator, RefusedError } from "../src/generate.js";

const request = {
  mode: "reply" as const,
  uiLanguage: "zh-Hans",
  conversation: [{ speaker: "them" as const, text: "Just got back from Kyoto!" }],
};

function fakeClient(response: object) {
  const create = vi.fn().mockResolvedValue(response);
  return { client: { beta: { messages: { create } } } as unknown as Anthropic, create };
}

describe("createGenerator", () => {
  it("sends the configured model, effort and fallback, and returns at most 3 replies", async () => {
    const replies = Array.from({ length: 4 }, (_, i) => ({ text: `reply ${i}`, why: `因为 ${i}` }));
    const { client, create } = fakeClient({
      stop_reason: "end_turn",
      content: [{ type: "text", text: JSON.stringify({ reply_language: "en", replies }) }],
    });
    const config = loadConfig({ MODEL: "relay-claude", EFFORT: "low" });
    const result = await createGenerator(client, config)(request);

    expect(result.reply_language).toBe("en");
    expect(result.replies).toHaveLength(3);
    const params = create.mock.calls[0][0];
    expect(params.model).toBe("relay-claude");
    expect(params.output_config.effort).toBe("low");
    expect(params.output_config.format.type).toBe("json_schema");
    expect(params.fallbacks).toBe("default");
    expect(params.betas).toEqual(["server-side-fallback-2026-07-01"]);
  });

  it("omits fallback params when the relay does not support them", async () => {
    const { client, create } = fakeClient({
      stop_reason: "end_turn",
      content: [{ type: "text", text: '{"reply_language":"zh","replies":[{"text":"好","why":"简短"}]}' }],
    });
    await createGenerator(client, loadConfig({ ENABLE_SERVER_FALLBACK: "false" }))(request);
    expect(create.mock.calls[0][0]).not.toHaveProperty("fallbacks");
    expect(create.mock.calls[0][0]).not.toHaveProperty("betas");
  });

  it("returns the check verdict and drops alternatives for a good draft", async () => {
    const checkRequest = { ...request, mode: "check" as const, draft: "好呀，周六见" };
    const good = fakeClient({
      stop_reason: "end_turn",
      content: [{ type: "text", text: JSON.stringify({
        reply_language: "zh",
        check: { verdict: "good", note: "语气自然，可以直接发。" },
        replies: [{ text: "好呀", why: "更短" }],
      }) }],
    });
    const result = await createGenerator(good.client, loadConfig({}))(checkRequest);
    expect(result.check).toEqual({ verdict: "good", note: "语气自然，可以直接发。" });
    expect(result.replies).toEqual([]);
    expect(good.create.mock.calls[0][0].output_config.format.schema.required).toContain("check");

    const risky = fakeClient({
      stop_reason: "end_turn",
      content: [{ type: "text", text: JSON.stringify({
        reply_language: "zh",
        check: { verdict: "risky", note: "像在质问。" },
        replies: [1, 2, 3].map((i) => ({ text: `改法 ${i}`, why: "更轻松" })),
      }) }],
    });
    const riskyResult = await createGenerator(risky.client, loadConfig({}))(checkRequest);
    expect(riskyResult.check?.verdict).toBe("risky");
    expect(riskyResult.replies).toHaveLength(2);
  });

  it("rejects check output without a verdict", async () => {
    const { client } = fakeClient({
      stop_reason: "end_turn",
      content: [{ type: "text", text: '{"reply_language":"zh","replies":[]}' }],
    });
    await expect(
      createGenerator(client, loadConfig({}))({ ...request, mode: "check", draft: "在吗" }),
    ).rejects.toBeInstanceOf(BadModelOutputError);
  });

  it("raises RefusedError on a refusal", async () => {
    const { client } = fakeClient({ stop_reason: "refusal", stop_details: { category: null }, content: [] });
    await expect(createGenerator(client, loadConfig({}))(request)).rejects.toBeInstanceOf(RefusedError);
  });

  it("raises BadModelOutputError on malformed JSON", async () => {
    const { client } = fakeClient({ stop_reason: "end_turn", content: [{ type: "text", text: "not json" }] });
    await expect(createGenerator(client, loadConfig({}))(request)).rejects.toBeInstanceOf(BadModelOutputError);
  });
});
