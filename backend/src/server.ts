import Fastify, { type FastifyInstance, type FastifyRequest } from "fastify";
import Anthropic from "@anthropic-ai/sdk";
import { z } from "zod";
import type { AppleTokenVerifier, Sessions } from "./auth.js";
import { BadModelOutputError, RefusedError, type Generator } from "./generate.js";
import type { Quota } from "./quota.js";
import { ReplyRequestSchema } from "./schema.js";
import { applyTransaction, type AppStoreVerifier } from "./subscriptions.js";
import { isSubscribed, type User, type UserStore } from "./users.js";

export interface ServerDeps {
  generate: Generator;
  quota: Quota;
  users: UserStore;
  limits: { free: number; subscriber: number };
  /** 未配置 SESSION_SECRET 时为 undefined，登录相关接口返回 503 */
  sessions?: Sessions;
  verifyAppleToken?: AppleTokenVerifier;
  appStore?: AppStoreVerifier;
  subscriptionProductIds: string[];
}

const AppleSignInSchema = z.object({ identityToken: z.string().min(1) });
const VerifyTransactionSchema = z.object({ signedTransaction: z.string().min(1) });
const NotificationSchema = z.object({ signedPayload: z.string().min(1) });

export function buildServer(deps: ServerDeps): FastifyInstance {
  // 默认日志只记录方法、路径、状态码和耗时，不记录请求体，聊天内容不落盘
  const app = Fastify({ logger: process.env.NODE_ENV !== "test" });
  const { quota, users, limits } = deps;

  async function currentUser(request: FastifyRequest): Promise<User | undefined> {
    const header = request.headers.authorization;
    if (!deps.sessions || !header?.startsWith("Bearer ")) return undefined;
    const userId = await deps.sessions.verify(header.slice("Bearer ".length));
    return userId ? await users.get(userId) : undefined;
  }

  /** 登录用户按用户计额度，未登录按设备计 */
  function quotaIdentity(request: FastifyRequest, user: User | undefined) {
    if (user) {
      return { id: `user:${user.id}`, limit: isSubscribed(user) ? limits.subscriber : limits.free };
    }
    const deviceId = request.headers["x-device-id"];
    if (typeof deviceId !== "string" || deviceId.length < 8) return undefined;
    return { id: `device:${deviceId}`, limit: limits.free };
  }

  app.get("/healthz", async () => ({ ok: true }));

  app.post("/v1/auth/apple", async (request, reply) => {
    if (!deps.sessions || !deps.verifyAppleToken) return reply.code(503).send({ error: "auth_not_configured" });
    const body = AppleSignInSchema.safeParse(request.body);
    if (!body.success) return reply.code(400).send({ error: "invalid_request" });
    let appleSub: string;
    try {
      appleSub = await deps.verifyAppleToken(body.data.identityToken);
    } catch {
      return reply.code(401).send({ error: "invalid_identity_token" });
    }
    const user = await users.findOrCreateByAppleSub(appleSub);
    return { sessionToken: await deps.sessions.issue(user.id), userId: user.id };
  });

  app.get("/v1/me", async (request, reply) => {
    const user = await currentUser(request);
    if (!user) return reply.code(401).send({ error: "unauthorized" });
    const identity = quotaIdentity(request, user)!;
    return {
      userId: user.id,
      subscribed: isSubscribed(user),
      subscriptionExpiresAt: user.subscriptionExpiresAt ?? null,
      quotaRemaining: await quota.remaining(identity.id, identity.limit),
    };
  });

  app.post("/v1/subscription/verify", async (request, reply) => {
    if (!deps.appStore) return reply.code(503).send({ error: "app_store_not_configured" });
    const user = await currentUser(request);
    if (!user) return reply.code(401).send({ error: "unauthorized" });
    const body = VerifyTransactionSchema.safeParse(request.body);
    if (!body.success) return reply.code(400).send({ error: "invalid_request" });
    let tx;
    try {
      tx = await deps.appStore.transaction(body.data.signedTransaction);
    } catch {
      return reply.code(400).send({ error: "invalid_transaction" });
    }
    const result = await applyTransaction(tx, users, deps.subscriptionProductIds, user.id);
    if (result === null) return reply.code(400).send({ error: "transaction_not_for_user" });
    const updated = { ...user, subscriptionExpiresAt: result };
    return { subscribed: isSubscribed(updated), subscriptionExpiresAt: result ?? null };
  });

  // App Store Server Notifications V2：续订、退款、过期都会推到这里
  app.post("/v1/appstore/notifications", async (request, reply) => {
    if (!deps.appStore) return reply.code(503).send({ error: "app_store_not_configured" });
    const body = NotificationSchema.safeParse(request.body);
    if (!body.success) return reply.code(400).send({ error: "invalid_request" });
    try {
      const tx = await deps.appStore.notification(body.data.signedPayload);
      if (tx) await applyTransaction(tx, users, deps.subscriptionProductIds);
    } catch {
      return reply.code(400).send({ error: "invalid_notification" });
    }
    return { ok: true };
  });

  app.post("/v1/replies", async (request, reply) => {
    const user = await currentUser(request);
    const identity = quotaIdentity(request, user);
    if (!identity) return reply.code(401).send({ error: "missing_device_id" });

    const parsed = ReplyRequestSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: "invalid_request", detail: parsed.error.issues });
    }

    if (!(await quota.take(identity.id, identity.limit))) {
      return reply.code(429).send({ error: "daily_quota_exceeded" });
    }

    try {
      const suggestions = await deps.generate(parsed.data);
      return { ...suggestions, quota_remaining: await quota.remaining(identity.id, identity.limit) };
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
