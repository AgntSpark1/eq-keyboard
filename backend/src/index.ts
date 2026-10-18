import { createAppleTokenVerifier, Sessions } from "./auth.js";
import { loadConfig } from "./config.js";
import { createClient, createGenerator } from "./generate.js";
import { DailyQuota } from "./quota.js";
import { buildServer } from "./server.js";
import { createAppStoreVerifier } from "./subscriptions.js";
import { UserStore } from "./users.js";

const config = loadConfig();
const app = buildServer({
  generate: createGenerator(createClient(config), config),
  quota: new DailyQuota(),
  users: new UserStore(),
  limits: { free: config.dailyFreeQuota, subscriber: config.subscriberDailyQuota },
  sessions: config.sessionSecret ? new Sessions(config.sessionSecret) : undefined,
  verifyAppleToken: createAppleTokenVerifier(config.apple.bundleId),
  appStore: config.apple.rootCertPaths.length ? createAppStoreVerifier(config.apple) : undefined,
  subscriptionProductIds: config.apple.subscriptionProductIds,
});
await app.listen({ port: config.port, host: "0.0.0.0" });
