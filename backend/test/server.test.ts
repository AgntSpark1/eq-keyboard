import { describe, expect, it, vi } from "vitest";
import { Sessions } from "../src/auth.js";
import { RefusedError, type Generator } from "../src/generate.js";
import { MemoryQuota } from "../src/quota.js";
import { buildServer, type ServerDeps } from "../src/server.js";
import type { AppStoreVerifier, TransactionInfo } from "../src/subscriptions.js";
import { isSubscribed, MemoryUserStore } from "../src/users.js";

const body = {
  mode: "reply",
  conversation: [{ speaker: "them", text: "今天好累" }],
};
const headers = { "x-device-id": "device-12345" };
const ok = { reply_language: "zh-Hans", replies: [{ text: "辛苦啦，怎么了？", why: "先共情" }] };
const PRODUCTS = ["eqkeyboard.pro.monthly"];

function setup(overrides: Partial<ServerDeps> = {}) {
  const deps: ServerDeps = {
    generate: vi.fn<Generator>().mockResolvedValue(ok),
    quota: new MemoryQuota(),
    users: new MemoryUserStore(),
    limits: { free: 2, subscriber: 5 },
    sessions: new Sessions("s".repeat(32)),
    verifyAppleToken: async (token) => {
      if (token !== "good-apple-token") throw new Error("bad");
      return "apple-sub-1";
    },
    subscriptionProductIds: PRODUCTS,
    ...overrides,
  };
  return { app: buildServer(deps), deps };
}

async function signIn(app: ReturnType<typeof setup>["app"]) {
  const res = await app.inject({ method: "POST", url: "/v1/auth/apple", payload: { identityToken: "good-apple-token" } });
  return res.json() as { sessionToken: string; userId: string };
}

function fakeAppStore(tx: TransactionInfo): AppStoreVerifier {
  return { transaction: async () => tx, notification: async () => tx };
}

describe("POST /v1/replies", () => {
  it("returns suggestions and remaining quota", async () => {
    const { app } = setup();
    const res = await app.inject({ method: "POST", url: "/v1/replies", headers, payload: body });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ ...ok, quota_remaining: 1 });
  });

  it("rejects requests without a device id or session, or with a bad body", async () => {
    const { app } = setup();
    expect((await app.inject({ method: "POST", url: "/v1/replies", payload: body })).statusCode).toBe(401);
    const bad = await app.inject({ method: "POST", url: "/v1/replies", headers, payload: { mode: "polish", conversation: body.conversation } });
    expect(bad.statusCode).toBe(400);
  });

  it("returns 429 once the daily quota is used up", async () => {
    const { app } = setup();
    for (let i = 0; i < 2; i++) await app.inject({ method: "POST", url: "/v1/replies", headers, payload: body });
    const res = await app.inject({ method: "POST", url: "/v1/replies", headers, payload: body });
    expect(res.statusCode).toBe(429);
  });

  it("maps a model refusal to 422", async () => {
    const { app } = setup({ generate: vi.fn<Generator>().mockRejectedValue(new RefusedError("x")) });
    const res = await app.inject({ method: "POST", url: "/v1/replies", headers, payload: body });
    expect(res.statusCode).toBe(422);
  });
});

describe("Sign in with Apple and subscriptions", () => {
  it("issues a session for a valid Apple token and rejects a bad one", async () => {
    const { app } = setup();
    const session = await signIn(app);
    expect(session.sessionToken).toBeTruthy();
    const me = await app.inject({ method: "GET", url: "/v1/me", headers: { authorization: `Bearer ${session.sessionToken}` } });
    expect(me.json()).toMatchObject({ userId: session.userId, subscribed: false, quotaRemaining: 2 });
    const bad = await app.inject({ method: "POST", url: "/v1/auth/apple", payload: { identityToken: "forged" } });
    expect(bad.statusCode).toBe(401);
  });

  it("returns 503 for sign-in when no session secret is configured", async () => {
    const { app } = setup({ sessions: undefined });
    const res = await app.inject({ method: "POST", url: "/v1/auth/apple", payload: { identityToken: "good-apple-token" } });
    expect(res.statusCode).toBe(503);
  });

  it("raises the daily limit after a verified purchase", async () => {
    const appStore: AppStoreVerifier = { transaction: async () => tx, notification: async () => undefined };
    let tx: TransactionInfo = {};
    const { app } = setup({ appStore });
    const session = await signIn(app);
    const auth = { authorization: `Bearer ${session.sessionToken}` };
    tx = { productId: PRODUCTS[0], appAccountToken: session.userId, expiresDate: Date.now() + 86_400_000 };

    const verify = await app.inject({ method: "POST", url: "/v1/subscription/verify", headers: auth, payload: { signedTransaction: "jws" } });
    expect(verify.json()).toMatchObject({ subscribed: true });

    for (let i = 0; i < 5; i++) {
      expect((await app.inject({ method: "POST", url: "/v1/replies", headers: auth, payload: body })).statusCode).toBe(200);
    }
    expect((await app.inject({ method: "POST", url: "/v1/replies", headers: auth, payload: body })).statusCode).toBe(429);
  });

  it("refuses a transaction that belongs to someone else", async () => {
    const { app } = setup({
      appStore: fakeAppStore({ productId: PRODUCTS[0], appAccountToken: "00000000-0000-0000-0000-000000000000", expiresDate: Date.now() + 1000 }),
    });
    const session = await signIn(app);
    const res = await app.inject({
      method: "POST",
      url: "/v1/subscription/verify",
      headers: { authorization: `Bearer ${session.sessionToken}` },
      payload: { signedTransaction: "jws" },
    });
    expect(res.statusCode).toBe(400);
  });

  it("applies App Store notifications, such as a refund", async () => {
    let tx: TransactionInfo = {};
    const { app, deps } = setup({ appStore: { transaction: async () => tx, notification: async () => tx } });
    const session = await signIn(app);
    tx = { productId: PRODUCTS[0], appAccountToken: session.userId, expiresDate: Date.now() + 86_400_000 };
    await app.inject({ method: "POST", url: "/v1/appstore/notifications", payload: { signedPayload: "p" } });
    expect(isSubscribed(await deps.users.get(session.userId))).toBe(true);
    tx = { ...tx, revocationDate: Date.now() };
    await app.inject({ method: "POST", url: "/v1/appstore/notifications", payload: { signedPayload: "p" } });
    expect(isSubscribed(await deps.users.get(session.userId))).toBe(false);
  });
});
