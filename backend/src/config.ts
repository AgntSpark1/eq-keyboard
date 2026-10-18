export type Effort = "low" | "medium" | "high";

export interface Config {
  baseURL: string | undefined;
  apiKey: string | undefined;
  model: string;
  effort: Effort;
  serverFallback: boolean;
  dailyFreeQuota: number;
  port: number;
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const effort = env.EFFORT ?? "low";
  if (effort !== "low" && effort !== "medium" && effort !== "high") {
    throw new Error(`EFFORT must be low, medium or high, got "${effort}"`);
  }
  return {
    // 你的合规中转 API；未设置时 SDK 直连 Anthropic
    baseURL: env.ANTHROPIC_BASE_URL || undefined,
    apiKey: env.ANTHROPIC_API_KEY || undefined,
    model: env.MODEL || "claude-opus-5-5",
    effort,
    serverFallback: env.ENABLE_SERVER_FALLBACK !== "false",
    dailyFreeQuota: Number(env.DAILY_FREE_QUOTA ?? 20),
    port: Number(env.PORT ?? 8787),
  };
}
