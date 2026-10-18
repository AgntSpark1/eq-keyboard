import { expect, it } from "vitest";
import { DailyQuota } from "../src/quota.js";

it("allows the daily limit per id and resets the next day", () => {
  let day = "2026-10-18";
  const quota = new DailyQuota(() => day);
  expect(quota.take("device-a", 2)).toBe(true);
  expect(quota.take("device-a", 2)).toBe(true);
  expect(quota.take("device-a", 2)).toBe(false);
  expect(quota.take("device-a", 5)).toBe(true);
  expect(quota.take("device-b", 2)).toBe(true);
  day = "2026-10-19";
  expect(quota.remaining("device-a", 2)).toBe(2);
});
