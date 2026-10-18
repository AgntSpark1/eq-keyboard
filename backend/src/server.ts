import Fastify, { type FastifyInstance } from "fastify";
import Anthropic from "@anthropic-ai/sdk";
import { BadModelOutputError, RefusedError, type Generator } from "./generate.js";
import { DailyQuota } from "./quota.js";
import { ReplyRequestSchema } from "./schema.js";

export function buildServer(generate: Generator, quota: DailyQuota): FastifyInstance {
  // 默认日志只记录方法、路径、状态码和耗时，不记录请求体，聊天内容不落盘
  const app = Fastify({ logger: process.env.NODE_ENV !== "test" });

  app.get("/healthz", async () => ({ ok: true }));

  app.post("/v1/replies", async (request, reply) => {
    // TODO: 上线前换成真实登录（Apple 登录）和订阅校验
    const deviceId = request.headers["x-device-id"];
    if (typeof deviceId !== "string" || deviceId.length < 8) {
      return reply.code(401).send({ error: "missing_device_id" });
    }

    const parsed = ReplyRequestSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: "invalid_request", detail: parsed.error.issues });
    }

    if (!quota.take(deviceId)) {
      return reply.code(429).send({ error: "daily_quota_exceeded" });
    }

    try {
      const suggestions = await generate(parsed.data);
      return { ...suggestions, quota_remaining: quota.remaining(deviceId) };
    } catch (err) {
      if (err instanceof RefusedError) {
        return reply.code(422).send({ error: "refused" });
      }
      if (err instanceof BadModelOutputError) {
        request.log.warn({ reason: err.message }, "bad model output");
        return reply.code(502).send({ error: "bad_model_output" });
      }
      if (err instanceof Anthropic.RateLimitError) {
        return reply.code(503).send({ error: "upstream_busy" });
      }
      if (err instanceof Anthropic.APIError) {
        request.log.error({ status: err.status }, "upstream error");
        return reply.code(502).send({ error: "upstream_error" });
      }
      throw err;
    }
  });

  return app;
}
