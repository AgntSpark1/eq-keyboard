import { afterAll, describe, expect, it } from "vitest";
import { PostgresStore } from "../src/postgres.js";
import { MemoryQuota, type Quota } from "../src/quota.js";
import { MemoryUserStore, type UserStore } from "../src/users.js";

// 同一组用例跑内存实现和 Postgres 实现；设置 DATABASE_URL 时才测 Postgres
const DATABASE_URL = process.env.DATABASE_URL;
const opened: PostgresStore[] = [];
afterAll(async () => Promise.all(opened.map((s) => s.close())));

class MemoryStore extends MemoryUserStore implements Quota {
  constructor(private readonly quota: MemoryQuota) {
    super();
  }
  take(id: string, limit: number) {
    return this.quota.take(id, limit);
  }
  remaining(id: string, limit: number) {
    return this.quota.remaining(id, limit);
  }
}

const unique = () => `${Date.now()}-${Math.random()}`;

const impls: [string, (today?: () => string) => Promise<UserStore & Quota>][] = [
  ["memory", async (today) => new MemoryStore(new MemoryQuota(today))],
];
if (DATABASE_URL) {
  impls.push([
    "postgres",
    async (today) => {
      const store = await PostgresStore.connect(DATABASE_URL, today);
      opened.push(store);
      return store;
    },
  ]);
}

describe.each(impls)("%s store", (_name, make) => {
  it("creates a user once per Apple account", async () => {
    const store = await make();
    const sub = unique();
    const a = await store.findOrCreateByAppleSub(sub);
    const b = await store.findOrCreateByAppleSub(sub);
    expect(b.id).toBe(a.id);
    expect(await store.get(a.id)).toEqual(a);
    expect(await store.get("not-a-uuid")).toBeUndefined();
  });

  it("stores and clears the subscription expiry", async () => {
    const store = await make();
    const user = await store.findOrCreateByAppleSub(unique());
    const expires = Date.now() + 86_400_000;
    await store.setSubscription(user.id, expires);
    expect((await store.get(user.id))?.subscriptionExpiresAt).toBe(expires);
    await store.setSubscription(user.id, undefined);
    expect((await store.get(user.id))?.subscriptionExpiresAt).toBeUndefined();
  });

  it("counts the daily quota per id and resets the next day", async () => {
    let day = "2026-10-18";
    const store = await make(() => day);
    const id = unique();
    expect(await store.take(id, 2)).toBe(true);
    expect(await store.take(id, 2)).toBe(true);
    expect(await store.take(id, 2)).toBe(false);
    expect(await store.remaining(id, 2)).toBe(0);
    expect(await store.take(id, 5)).toBe(true);
    day = "2026-10-19";
    expect(await store.remaining(id, 2)).toBe(2);
  });

  it("never lets concurrent requests exceed the limit", async () => {
    const store = await make();
    const id = unique();
    const results = await Promise.all(Array.from({ length: 20 }, () => store.take(id, 5)));
    expect(results.filter(Boolean)).toHaveLength(5);
  });
});
