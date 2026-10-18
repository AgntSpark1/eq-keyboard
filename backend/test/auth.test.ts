import { createLocalJWKSet, exportJWK, generateKeyPair, SignJWT } from "jose";
import { describe, expect, it } from "vitest";
import { createAppleTokenVerifier, Sessions } from "../src/auth.js";

const BUNDLE = "com.yonghuizhang.eqkeyboard";

async function appleFixture() {
  const { publicKey, privateKey } = await generateKeyPair("RS256");
  const jwk = { ...(await exportJWK(publicKey)), kid: "k1", alg: "RS256" };
  const sign = (claims: { aud?: string; iss?: string; sub?: string }) =>
    new SignJWT({})
      .setProtectedHeader({ alg: "RS256", kid: "k1" })
      .setIssuer(claims.iss ?? "https://appleid.apple.com")
      .setAudience(claims.aud ?? BUNDLE)
      .setSubject(claims.sub ?? "apple-user-1")
      .setIssuedAt()
      .setExpirationTime("10m")
      .sign(privateKey);
  return { keys: createLocalJWKSet({ keys: [jwk] }), sign };
}

describe("createAppleTokenVerifier", () => {
  it("returns the Apple user id for a valid token", async () => {
    const { keys, sign } = await appleFixture();
    await expect(createAppleTokenVerifier(BUNDLE, keys)(await sign({}))).resolves.toBe("apple-user-1");
  });

  it("rejects tokens for another app or issuer", async () => {
    const { keys, sign } = await appleFixture();
    const verify = createAppleTokenVerifier(BUNDLE, keys);
    await expect(verify(await sign({ aud: "com.other.app" }))).rejects.toThrow();
    await expect(verify(await sign({ iss: "https://evil.example.com" }))).rejects.toThrow();
  });
});

describe("Sessions", () => {
  const secret = "x".repeat(32);

  it("round-trips a user id", async () => {
    const sessions = new Sessions(secret);
    await expect(sessions.verify(await sessions.issue("user-1"))).resolves.toBe("user-1");
  });

  it("rejects tokens signed with another secret", async () => {
    const token = await new Sessions("y".repeat(32)).issue("user-1");
    await expect(new Sessions(secret).verify(token)).resolves.toBeUndefined();
  });

  it("requires a long secret", () => {
    expect(() => new Sessions("short")).toThrow();
  });
});
