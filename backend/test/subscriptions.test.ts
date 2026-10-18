import { describe, expect, it } from "vitest";
import { applyTransaction } from "../src/subscriptions.js";
import { UserStore } from "../src/users.js";

const PRODUCTS = ["eqkeyboard.pro.monthly"];

describe("applyTransaction", () => {
  it("activates the subscription of the user named by appAccountToken", () => {
    const users = new UserStore();
    const user = users.findOrCreateByAppleSub("a");
    const expires = Date.now() + 86_400_000;
    const result = applyTransaction(
      { productId: PRODUCTS[0], appAccountToken: user.id.toUpperCase(), expiresDate: expires },
      users,
      PRODUCTS,
      user.id,
    );
    expect(result).toBe(expires);
    expect(users.isSubscribed(user)).toBe(true);
  });

  it("ignores unknown products and other users' transactions", () => {
    const users = new UserStore();
    const me = users.findOrCreateByAppleSub("a");
    const other = users.findOrCreateByAppleSub("b");
    const expiresDate = Date.now() + 1000;
    expect(applyTransaction({ productId: "x", appAccountToken: me.id, expiresDate }, users, PRODUCTS)).toBeNull();
    expect(
      applyTransaction({ productId: PRODUCTS[0], appAccountToken: other.id, expiresDate }, users, PRODUCTS, me.id),
    ).toBeNull();
    expect(users.isSubscribed(me)).toBe(false);
  });

  it("keeps the later expiry and ends the subscription on revocation", () => {
    const users = new UserStore();
    const user = users.findOrCreateByAppleSub("a");
    const later = Date.now() + 2 * 86_400_000;
    applyTransaction({ productId: PRODUCTS[0], appAccountToken: user.id, expiresDate: later }, users, PRODUCTS);
    applyTransaction({ productId: PRODUCTS[0], appAccountToken: user.id, expiresDate: Date.now() + 1000 }, users, PRODUCTS);
    expect(user.subscriptionExpiresAt).toBe(later);
    applyTransaction(
      { productId: PRODUCTS[0], appAccountToken: user.id, expiresDate: later, revocationDate: Date.now() },
      users,
      PRODUCTS,
    );
    expect(users.isSubscribed(user)).toBe(false);
  });
});
