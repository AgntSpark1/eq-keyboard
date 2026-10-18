import { expect, it } from "vitest";
import { MemoryQuota } from "../src/quota.js";

it("allows the daily limit per id and resets the next day", async () => {
  let day = "2026-10-18";
  const quota = new MemoryQuota(() => day);
  expect(await quota.take("device-a", 2)).toBe(true);
  expect(await quota.take("device-a", 2)).toBe(true);
  expect(await quota.take("device-a", 2)).toBe(false);
  expect(await quota.take("device-a", 5)).toBe(true);
  expect(await quota.take("device-b", 2)).toBe(true);
  day = "2026-10-19";
  expect(await quota.remaining("device-a", 2)).toBe(2);
});
