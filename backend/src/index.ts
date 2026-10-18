import { createAppleTokenVerifier, Sessions } from "./auth.js";
import { loadConfig } from "./config.js";
import { createClient, createGenerator } from "./generate.js";
import { PostgresStore } from "./postgres.js";
import { MemoryQuota } from "./quota.js";
import { buildServer } from "./server.js";
import { createAppStoreVerifier } from "./subscriptions.js";
import { MemoryUserStore } from "./users.js";

const config = loadConfig();
const db = config.databaseUrl ? await PostgresStore.connect(config.databaseUrl) : undefined;
const app = buildServer({
  generate: createGenerator(createClient(config), config),
  quota: db ?? new MemoryQuota(),
  users: db ?? new MemoryUserStore(),
  limits: { free: config.dailyFreeQuota, subscriber: config.subscriberDailyQuota },
  sessions: config.sessionSecret ? new Sessions(config.sessionSecret) : undefined,
  verifyAppleToken: createAppleTokenVerifier(config.apple.bundleId),
  appStore: config.apple.rootCertPaths.length ? createAppStoreVerifier(config.apple) : undefined,
  subscriptionProductIds: config.apple.subscriptionProductIds,
});
if (!db) app.log.warn("DATABASE_URL 未配置，用户和额度存在内存里，重启会丢失");
app.addHook("onClose", async () => db?.close());
await app.listen({ port: config.port, host: "0.0.0.0" });
