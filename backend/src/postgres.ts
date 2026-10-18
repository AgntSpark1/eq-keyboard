import pg from "pg";
import { utcToday, type Quota } from "./quota.js";
import type { User, UserStore } from "./users.js";

const SCHEMA = `
CREATE TABLE IF NOT EXISTS users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  apple_sub text NOT NULL UNIQUE,
  subscription_expires_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS quota_usage (
  day date NOT NULL,
  identity text NOT NULL,
  used integer NOT NULL,
  PRIMARY KEY (day, identity)
);
`;

interface UserRow {
  id: string;
  apple_sub: string;
  subscription_expires_at: Date | null;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function toUser(row: UserRow): User {
  return {
    id: row.id,
    appleSub: row.apple_sub,
    subscriptionExpiresAt: row.subscription_expires_at?.getTime(),
  };
}

/** 用户和每日额度都存在 Postgres，服务重启或多实例部署都不丢数据。 */
export class PostgresStore implements UserStore, Quota {
  constructor(
    private readonly pool: pg.Pool,
    private readonly today: () => string = utcToday,
  ) {}

  static async connect(connectionString: string, today?: () => string): Promise<PostgresStore> {
    const store = new PostgresStore(new pg.Pool({ connectionString }), today);
    await store.pool.query(SCHEMA);
    return store;
  }

  async close(): Promise<void> {
    await this.pool.end();
  }

  async findOrCreateByAppleSub(appleSub: string): Promise<User> {
    // DO UPDATE 让已存在的行也能 RETURNING
    const { rows } = await this.pool.query<UserRow>(
      `INSERT INTO users (apple_sub) VALUES ($1)
       ON CONFLICT (apple_sub) DO UPDATE SET apple_sub = EXCLUDED.apple_sub
       RETURNING id, apple_sub, subscription_expires_at`,
      [appleSub],
    );
    return toUser(rows[0]);
  }

  async get(id: string): Promise<User | undefined> {
    if (!UUID.test(id)) return undefined;
    const { rows } = await this.pool.query<UserRow>(
      "SELECT id, apple_sub, subscription_expires_at FROM users WHERE id = $1",
      [id],
    );
    return rows[0] && toUser(rows[0]);
  }

  async setSubscription(id: string, expiresAt: number | undefined): Promise<void> {
    if (!UUID.test(id)) return;
    await this.pool.query("UPDATE users SET subscription_expires_at = $2 WHERE id = $1", [
      id,
      expiresAt === undefined ? null : new Date(expiresAt),
    ]);
  }

  async take(identity: string, limit: number): Promise<boolean> {
    if (limit <= 0) return false;
    // 一条语句完成判断和加一，并发请求也不会超额
    const { rowCount } = await this.pool.query(
      `INSERT INTO quota_usage (day, identity, used) VALUES ($1, $2, 1)
       ON CONFLICT (day, identity) DO UPDATE SET used = quota_usage.used + 1
       WHERE quota_usage.used < $3`,
      [this.today(), identity, limit],
    );
    return rowCount === 1;
  }

  async remaining(identity: string, limit: number): Promise<number> {
    const { rows } = await this.pool.query<{ used: number }>(
      "SELECT used FROM quota_usage WHERE day = $1 AND identity = $2",
      [this.today(), identity],
    );
    return Math.max(0, limit - (rows[0]?.used ?? 0));
  }
}
