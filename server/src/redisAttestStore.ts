import { Redis } from "@upstash/redis";
import type { AttestationStoring, AttestedKey } from "./attestStore.ts";

const KEY_PREFIX = "attest:key:";
const CHALLENGE_PREFIX = "attest:challenge:";

/**
 * カウンタの判定と更新を1つの操作にまとめる。
 *
 * 読んでから書くと、同時に届いた再送が両方とも「前回より大きい」と
 * 判定されて通ってしまう。Lua で不可分に行う。
 */
const ADVANCE_COUNTER_SCRIPT = `
local raw = redis.call('GET', KEYS[1])
if not raw then return -1 end
local record = cjson.decode(raw)
local next = tonumber(ARGV[1])
if next <= record.counter then return 0 end
record.counter = next
redis.call('SET', KEYS[1], cjson.encode(record))
return 1
`;

export class RedisAttestationStore implements AttestationStoring {
  private readonly redis: Redis;

  constructor(redis: Redis) {
    this.redis = redis;
  }

  /** 環境変数が揃っていなければ null。呼び出し側で保存なしを検知できるようにする。 */
  static fromEnvironment(env: NodeJS.ProcessEnv): RedisAttestationStore | null {
    const url = env.KV_REST_API_URL ?? env.UPSTASH_REDIS_REST_URL;
    const token = env.KV_REST_API_TOKEN ?? env.UPSTASH_REDIS_REST_TOKEN;
    if (!url || !token) return null;
    return new RedisAttestationStore(new Redis({ url, token }));
  }

  async findKey(keyId: string): Promise<AttestedKey | null> {
    const raw = await this.redis.get<AttestedKey | string>(`${KEY_PREFIX}${keyId}`);
    if (raw === null || raw === undefined) return null;
    return typeof raw === "string" ? (JSON.parse(raw) as AttestedKey) : raw;
  }

  async saveKey(key: AttestedKey): Promise<void> {
    await this.redis.set(`${KEY_PREFIX}${key.keyId}`, JSON.stringify(key));
  }

  async advanceCounter(keyId: string, counter: number): Promise<boolean> {
    const outcome = await this.redis.eval(
      ADVANCE_COUNTER_SCRIPT,
      [`${KEY_PREFIX}${keyId}`],
      [String(counter)],
    );
    return Number(outcome) === 1;
  }

  async putChallenge(challenge: string, ttlSeconds: number): Promise<void> {
    await this.redis.set(`${CHALLENGE_PREFIX}${challenge}`, "1", { ex: ttlSeconds });
  }

  async consumeChallenge(challenge: string): Promise<boolean> {
    const value = await this.redis.getdel(`${CHALLENGE_PREFIX}${challenge}`);
    return value !== null && value !== undefined;
  }
}
