// MVP 用内存计数；上线前换成 Redis。
export class DailyQuota {
  private counts = new Map<string, number>();

  constructor(private readonly today: () => string = () => new Date().toISOString().slice(0, 10)) {}

  /** 消耗一次额度，返回是否成功。 */
  take(id: string, limit: number): boolean {
    const key = `${this.today()}:${id}`;
    const used = this.counts.get(key) ?? 0;
    if (used >= limit) return false;
    this.counts.set(key, used + 1);
    return true;
  }

  remaining(id: string, limit: number): number {
    return Math.max(0, limit - (this.counts.get(`${this.today()}:${id}`) ?? 0));
  }
}
