export type Effort = "low" | "medium" | "high";

export interface Config {
  baseURL: string | undefined;
  apiKey: string | undefined;
  model: string;
  effort: Effort;
  serverFallback: boolean;
  dailyFreeQuota: number;
  subscriberDailyQuota: number;
  port: number;
  apple: {
    bundleId: string;
    /** App Store 里的数字 App ID，生产环境验证交易时需要 */
    appAppleId: number | undefined;
    environment: "Sandbox" | "Production";
    rootCertPaths: string[];
    subscriptionProductIds: string[];
  };
  sessionSecret: string | undefined;
  /** Postgres 连接串；留空时用内存存储，重启会丢数据 */
  databaseUrl?: string;
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const effort = env.EFFORT ?? "low";
  if (effort !== "low" && effort !== "medium" && effort !== "high") {
    throw new Error(`EFFORT must be low, medium or high, got "${effort}"`);
  }
  const list = (value: string | undefined) =>
    (value ?? "").split(",").map((s) => s.trim()).filter(Boolean);
  return {
    // 你的合规中转 API；未设置时 SDK 直连 Anthropic
    baseURL: env.ANTHROPIC_BASE_URL || undefined,
    apiKey: env.ANTHROPIC_API_KEY || undefined,
    model: env.MODEL || "claude-opus-5-5",
    effort,
    serverFallback: env.ENABLE_SERVER_FALLBACK !== "false",
    dailyFreeQuota: Number(env.DAILY_FREE_QUOTA ?? 20),
    subscriberDailyQuota: Number(env.SUBSCRIBER_DAILY_QUOTA ?? 300),
    port: Number(env.PORT ?? 8787),
    apple: {
      bundleId: env.APPLE_BUNDLE_ID || "com.yonghuizhang.eqkeyboard",
      appAppleId: env.APP_APPLE_ID ? Number(env.APP_APPLE_ID) : undefined,
      environment: env.APPSTORE_ENVIRONMENT === "Production" ? "Production" : "Sandbox",
      rootCertPaths: list(env.APPLE_ROOT_CERT_PATHS),
      subscriptionProductIds: list(
        env.SUBSCRIPTION_PRODUCT_IDS ?? "eqkeyboard.pro.monthly,eqkeyboard.pro.yearly",
      ),
    },
    sessionSecret: env.SESSION_SECRET || undefined,
    databaseUrl: env.DATABASE_URL || undefined,
  };
}
