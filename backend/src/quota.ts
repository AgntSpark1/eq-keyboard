export interface Quota {
  /** 消耗一次额度，返回是否成功。 */
  take(id: string, limit: number): Promise<boolean>;
  remaining(id: string, limit: number): Promise<number>;
}

/** 按 UTC 日期分天计数 */
export const utcToday = () => new Date().toISOString().slice(0, 10);

/** 本地开发和测试用；生产配置 DATABASE_URL 后改用 Postgres。 */
export class MemoryQuota implements Quota {
  private counts = new Map<string, number>();

  constructor(private readonly today: () => string = utcToday) {}

  async take(id: string, limit: number): Promise<boolean> {
    const key = `${this.today()}:${id}`;
    const used = this.counts.get(key) ?? 0;
    if (used >= limit) return false;
    this.counts.set(key, used + 1);
    return true;
  }

  async remaining(id: string, limit: number): Promise<number> {
    return Math.max(0, limit - (this.counts.get(`${this.today()}:${id}`) ?? 0));
  }
}
