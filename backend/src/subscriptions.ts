import { readFileSync } from "node:fs";
import { Environment, SignedDataVerifier } from "@apple/app-store-server-library";
import type { Config } from "./config.js";
import type { UserStore } from "./users.js";

/** StoreKit 2 交易里我们关心的字段 */
export interface TransactionInfo {
  productId?: string;
  appAccountToken?: string;
  expiresDate?: number;
  revocationDate?: number;
}

export interface AppStoreVerifier {
  transaction(signedTransaction: string): Promise<TransactionInfo>;
  /** 返回通知里附带的交易；与交易无关的通知返回 undefined */
  notification(signedPayload: string): Promise<TransactionInfo | undefined>;
}

export function createAppStoreVerifier(config: Config["apple"]): AppStoreVerifier {
  const roots = config.rootCertPaths.map((path) => readFileSync(path));
  const environment = config.environment === "Production" ? Environment.PRODUCTION : Environment.SANDBOX;
  const verifier = new SignedDataVerifier(roots, true, environment, config.bundleId, config.appAppleId);
  return {
    transaction: (signed) => verifier.verifyAndDecodeTransaction(signed),
    async notification(signedPayload) {
      const decoded = await verifier.verifyAndDecodeNotification(signedPayload);
      const signed = decoded.data?.signedTransactionInfo;
      return signed ? verifier.verifyAndDecodeTransaction(signed) : undefined;
    },
  };
}

/**
 * 根据交易更新用户订阅状态。只认我们自己的订阅商品，并用 appAccountToken 找到用户。
 * 返回更新后的到期时间；交易不属于任何用户时返回 null。
 */
export function applyTransaction(
  tx: TransactionInfo,
  users: UserStore,
  productIds: string[],
  expectedUserId?: string,
): number | undefined | null {
  if (!tx.productId || !productIds.includes(tx.productId)) return null;
  const userId = tx.appAccountToken?.toLowerCase();
  if (!userId || (expectedUserId && userId !== expectedUserId.toLowerCase())) return null;
  const user = users.get(userId);
  if (!user) return null;
  // 退款或撤销立即失效；否则取较晚的到期时间，避免乱序到达的旧通知把订阅改短
  const expiresAt = tx.revocationDate
    ? undefined
    : Math.max(tx.expiresDate ?? 0, user.subscriptionExpiresAt ?? 0) || undefined;
  users.setSubscription(user.id, expiresAt);
  return expiresAt;
}
