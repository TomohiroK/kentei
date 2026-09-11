/**
 * App Attest の鍵とカウンタの保存。
 *
 * Assertion にはカウンタが含まれ、前回より増えていることを確認しないと
 * 署名の使い回し（リプレイ）を防げない。そのため保存が要る。
 */
export type AttestedKey = {
  keyId: string;
  /** DER形式の公開鍵（base64）。 */
  publicKey: string;
  /** 直近に受理した Assertion のカウンタ。 */
  counter: number;
  registeredAt: string;
};

export interface AttestationStoring {
  findKey(keyId: string): Promise<AttestedKey | null>;
  saveKey(key: AttestedKey): Promise<void>;
  /**
   * カウンタを進める。与えた値が保存済み以下なら false を返し、更新しない。
   * 判定と更新をまとめることで、同時に来た再送で両方が通ることを防ぐ。
   */
  advanceCounter(keyId: string, counter: number): Promise<boolean>;
  /** 使い捨てのチャレンジを登録する。 */
  putChallenge(challenge: string, ttlSeconds: number): Promise<void>;
  /** チャレンジを消費する。未登録または消費済みなら false。 */
  consumeChallenge(challenge: string): Promise<boolean>;
}

/** 単一インスタンス内でのみ有効な保存。テストと、保存先が未提供の場合に使う。 */
export class InMemoryAttestationStore implements AttestationStoring {
  private keys = new Map<string, AttestedKey>();
  private challenges = new Map<string, number>();

  async findKey(keyId: string): Promise<AttestedKey | null> {
    return this.keys.get(keyId) ?? null;
  }

  async saveKey(key: AttestedKey): Promise<void> {
    this.keys.set(key.keyId, key);
  }

  async advanceCounter(keyId: string, counter: number): Promise<boolean> {
    const stored = this.keys.get(keyId);
    if (!stored || counter <= stored.counter) return false;
    this.keys.set(keyId, { ...stored, counter });
    return true;
  }

  async putChallenge(challenge: string, ttlSeconds: number): Promise<void> {
    this.challenges.set(challenge, Date.now() + ttlSeconds * 1000);
  }

  async consumeChallenge(challenge: string): Promise<boolean> {
    const expiry = this.challenges.get(challenge);
    this.challenges.delete(challenge);
    return expiry !== undefined && expiry > Date.now();
  }
}
