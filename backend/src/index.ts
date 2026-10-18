import { loadConfig } from "./config.js";
import { createClient, createGenerator } from "./generate.js";
import { DailyQuota } from "./quota.js";
import { buildServer } from "./server.js";

const config = loadConfig();
const app = buildServer(
  createGenerator(createClient(config), config),
  new DailyQuota(config.dailyFreeQuota),
);
await app.listen({ port: config.port, host: "0.0.0.0" });
