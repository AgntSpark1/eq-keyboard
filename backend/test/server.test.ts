import { describe, expect, it, vi } from "vitest";
import { RefusedError } from "../src/generate.js";
import { DailyQuota } from "../src/quota.js";
import { buildServer } from "../src/server.js";

const body = {
  mode: "reply",
  conversation: [{ speaker: "them", text: "今天好累" }],
};
const headers = { "x-device-id": "device-12345" };
const ok = { reply_language: "zh-Hans", replies: [{ text: "辛苦啦，怎么了？", why: "先共情" }] };

describe("POST /v1/replies", () => {
  it("returns suggestions and remaining quota", async () => {
    const app = buildServer(vi.fn().mockResolvedValue(ok), new DailyQuota(5));
    const res = await app.inject({ method: "POST", url: "/v1/replies", headers, payload: body });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ ...ok, quota_remaining: 4 });
  });

  it("rejects requests without a device id or with a bad body", async () => {
    const app = buildServer(vi.fn(), new DailyQuota(5));
    expect((await app.inject({ method: "POST", url: "/v1/replies", payload: body })).statusCode).toBe(401);
    const bad = await app.inject({ method: "POST", url: "/v1/replies", headers, payload: { mode: "polish", conversation: body.conversation } });
    expect(bad.statusCode).toBe(400);
  });

  it("returns 429 once the daily quota is used up", async () => {
    const app = buildServer(vi.fn().mockResolvedValue(ok), new DailyQuota(1));
    await app.inject({ method: "POST", url: "/v1/replies", headers, payload: body });
    const res = await app.inject({ method: "POST", url: "/v1/replies", headers, payload: body });
    expect(res.statusCode).toBe(429);
  });

  it("maps a model refusal to 422", async () => {
    const app = buildServer(vi.fn().mockRejectedValue(new RefusedError("x")), new DailyQuota(5));
    const res = await app.inject({ method: "POST", url: "/v1/replies", headers, payload: body });
    expect(res.statusCode).toBe(422);
  });
});
