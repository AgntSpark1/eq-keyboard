import { describe, expect, it } from "vitest";
import { applyTransaction } from "../src/subscriptions.js";
import { isSubscribed, MemoryUserStore } from "../src/users.js";

const PRODUCTS = ["eqkeyboard.pro.monthly"];

describe("applyTransaction", async () => {
  it("activates the subscription of the user named by appAccountToken", async () => {
    const users = new MemoryUserStore();
    const user = await users.findOrCreateByAppleSub("a");
    const expires = Date.now() + 86_400_000;
    const result = await applyTransaction(
      { productId: PRODUCTS[0], appAccountToken: user.id.toUpperCase(), expiresDate: expires },
      users,
      PRODUCTS,
      user.id,
    );
    expect(result).toBe(expires);
    expect(isSubscribed(await users.get(user.id))).toBe(true);
  });

  it("ignores unknown products and other users' transactions", async () => {
    const users = new MemoryUserStore();
    const me = await users.findOrCreateByAppleSub("a");
    const other = await users.findOrCreateByAppleSub("b");
    const expiresDate = Date.now() + 1000;
    expect(await applyTransaction({ productId: "x", appAccountToken: me.id, expiresDate }, users, PRODUCTS)).toBeNull();
    expect(
      await applyTransaction({ productId: PRODUCTS[0], appAccountToken: other.id, expiresDate }, users, PRODUCTS, me.id),
    ).toBeNull();
    expect(isSubscribed(await users.get(me.id))).toBe(false);
  });

  it("keeps the later expiry and ends the subscription on revocation", async () => {
    const users = new MemoryUserStore();
    const user = await users.findOrCreateByAppleSub("a");
    const later = Date.now() + 2 * 86_400_000;
    await applyTransaction({ productId: PRODUCTS[0], appAccountToken: user.id, expiresDate: later }, users, PRODUCTS);
    await applyTransaction({ productId: PRODUCTS[0], appAccountToken: user.id, expiresDate: Date.now() + 1000 }, users, PRODUCTS);
    expect((await users.get(user.id))?.subscriptionExpiresAt).toBe(later);
    await applyTransaction(
      { productId: PRODUCTS[0], appAccountToken: user.id, expiresDate: later, revocationDate: Date.now() },
      users,
      PRODUCTS,
    );
    expect(isSubscribed(await users.get(user.id))).toBe(false);
  });
});
