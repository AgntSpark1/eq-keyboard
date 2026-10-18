import { createRemoteJWKSet, jwtVerify, SignJWT, type JWTVerifyGetKey } from "jose";

const APPLE_ISSUER = "https://appleid.apple.com";
const appleKeys = createRemoteJWKSet(new URL("https://appleid.apple.com/auth/keys"));

/** 校验 Sign in with Apple 的 identityToken，返回 Apple 用户标识 sub */
export type AppleTokenVerifier = (identityToken: string) => Promise<string>;

export function createAppleTokenVerifier(
  bundleId: string,
  keys: JWTVerifyGetKey = appleKeys,
): AppleTokenVerifier {
  return async (identityToken) => {
    const { payload } = await jwtVerify(identityToken, keys, {
      issuer: APPLE_ISSUER,
      audience: bundleId,
    });
    if (!payload.sub) throw new Error("identity token has no sub");
    return payload.sub;
  };
}

/** 我们自己签发的会话令牌，App 和键盘共用 */
export class Sessions {
  private readonly key: Uint8Array;

  constructor(secret: string) {
    if (secret.length < 32) throw new Error("SESSION_SECRET must be at least 32 characters");
    this.key = new TextEncoder().encode(secret);
  }

  issue(userId: string): Promise<string> {
    return new SignJWT({})
      .setProtectedHeader({ alg: "HS256" })
      .setSubject(userId)
      .setIssuedAt()
      .setExpirationTime("30d")
      .sign(this.key);
  }

  /** 返回用户 ID；令牌无效或过期时返回 undefined */
  async verify(token: string): Promise<string | undefined> {
    try {
      const { payload } = await jwtVerify(token, this.key, { algorithms: ["HS256"] });
      return payload.sub;
    } catch {
      return undefined;
    }
  }
}
