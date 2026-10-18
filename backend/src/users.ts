import { randomUUID } from "node:crypto";

export interface User {
  /** 我们自己的用户 ID，也作为 StoreKit 的 appAccountToken */
  id: string;
  appleSub: string;
  /** 订阅到期时间（毫秒时间戳），没有订阅为 undefined */
  subscriptionExpiresAt?: number;
}

export interface UserStore {
  findOrCreateByAppleSub(appleSub: string): Promise<User>;
  get(id: string): Promise<User | undefined>;
  setSubscription(id: string, expiresAt: number | undefined): Promise<void>;
}

export function isSubscribed(user: User | undefined, now = Date.now()): boolean {
  return !!user?.subscriptionExpiresAt && user.subscriptionExpiresAt > now;
}

/** 本地开发和测试用；生产配置 DATABASE_URL 后改用 Postgres。 */
export class MemoryUserStore implements UserStore {
  private byId = new Map<string, User>();
  private byAppleSub = new Map<string, User>();

  async findOrCreateByAppleSub(appleSub: string): Promise<User> {
    const existing = this.byAppleSub.get(appleSub);
    if (existing) return { ...existing };
    const user: User = { id: randomUUID(), appleSub };
    this.byId.set(user.id, user);
    this.byAppleSub.set(appleSub, user);
    return { ...user };
  }

  async get(id: string): Promise<User | undefined> {
    const user = this.byId.get(id);
    return user && { ...user };
  }

  async setSubscription(id: string, expiresAt: number | undefined): Promise<void> {
    const user = this.byId.get(id);
    if (user) user.subscriptionExpiresAt = expiresAt;
  }
}
