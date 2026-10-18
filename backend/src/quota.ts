// MVP 用内存计数；上线前换成 Redis 并接入订阅状态。
export class DailyQuota {
  private counts = new Map<string, number>();

  constructor(
    private readonly limit: number,
    private readonly today: () => string = () => new Date().toISOString().slice(0, 10),
  ) {}

  /** 消耗一次额度，返回是否成功。 */
  take(deviceId: string): boolean {
    const key = `${this.today()}:${deviceId}`;
    const used = this.counts.get(key) ?? 0;
    if (used >= this.limit) return false;
    this.counts.set(key, used + 1);
    return true;
  }

  remaining(deviceId: string): number {
    return Math.max(0, this.limit - (this.counts.get(`${this.today()}:${deviceId}`) ?? 0));
  }
}
