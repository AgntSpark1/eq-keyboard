import { expect, it } from "vitest";
import { DailyQuota } from "../src/quota.js";

it("allows the daily limit per device and resets the next day", () => {
  let day = "2026-10-18";
  const quota = new DailyQuota(2, () => day);
  expect(quota.take("device-a")).toBe(true);
  expect(quota.take("device-a")).toBe(true);
  expect(quota.take("device-a")).toBe(false);
  expect(quota.take("device-b")).toBe(true);
  day = "2026-10-19";
  expect(quota.remaining("device-a")).toBe(2);
});
