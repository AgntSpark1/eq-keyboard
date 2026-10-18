import { z } from "zod";

export const ReplyRequestSchema = z
  .object({
    mode: z.enum(["reply", "polish"]),
    conversation: z
      .array(
        z.object({
          speaker: z.enum(["me", "them"]),
          text: z.string().min(1).max(2000),
        }),
      )
      .min(1)
      .max(30),
    draft: z.string().min(1).max(1000).optional(),
    profile: z
      .object({
        name: z.string().max(40).optional(),
        stage: z.enum(["just_met", "flirting", "dating", "relationship"]).optional(),
        interests: z.array(z.string().max(40)).max(10).optional(),
        notes: z.string().max(500).optional(),
      })
      .optional(),
    tone: z
      .object({
        humor: z.boolean().optional(),
        warm: z.boolean().optional(),
        direct: z.boolean().optional(),
        brief: z.boolean().optional(),
      })
      .optional(),
    uiLanguage: z.string().min(2).max(16).default("zh-Hans"),
  })
  .refine((r) => r.mode !== "polish" || r.draft, {
    message: "draft is required when mode is polish",
    path: ["draft"],
  });

export type ReplyRequest = z.infer<typeof ReplyRequestSchema>;

export const ReplySuggestionsSchema = z.object({
  reply_language: z.string(),
  replies: z
    .array(z.object({ text: z.string().min(1), why: z.string().min(1) }))
    .min(1),
});

export type ReplySuggestions = z.infer<typeof ReplySuggestionsSchema>;

// 交给模型的结构化输出约束，与 ReplySuggestionsSchema 保持一致
export const REPLY_OUTPUT_JSON_SCHEMA = {
  type: "object",
  properties: {
    reply_language: {
      type: "string",
      description: "BCP 47 tag of the language the replies are written in",
    },
    replies: {
      type: "array",
      items: {
        type: "object",
        properties: {
          text: { type: "string" },
          why: { type: "string" },
        },
        required: ["text", "why"],
        additionalProperties: false,
      },
    },
  },
  required: ["reply_language", "replies"],
  additionalProperties: false,
} as const;
