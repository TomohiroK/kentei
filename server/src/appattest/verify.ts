import { createHash, createPublicKey, createVerify, X509Certificate } from "node:crypto";
import { decode as decodeCbor } from "cbor-x";
import { APPLE_APP_ATTEST_ROOT_CA_PEM } from "./appleRootCA.ts";
import { extractAppAttestNonce } from "./der.ts";

/** authData の固定長レイアウト（Apple の仕様による）。 */
const RP_ID_HASH_LENGTH = 32;
const FLAGS_LENGTH = 1;
const COUNTER_LENGTH = 4;
const AAGUID_LENGTH = 16;
const CREDENTIAL_ID_LENGTH_FIELD = 2;
const COUNTER_OFFSET = RP_ID_HASH_LENGTH + FLAGS_LENGTH;
const AAGUID_OFFSET = COUNTER_OFFSET + COUNTER_LENGTH;
const CREDENTIAL_ID_LENGTH_OFFSET = AAGUID_OFFSET + AAGUID_LENGTH;
const CREDENTIAL_ID_OFFSET = CREDENTIAL_ID_LENGTH_OFFSET + CREDENTIAL_ID_LENGTH_FIELD;

/** 本番の端末が返す aaguid。開発ビルドは別の値になる。 */
const AAGUID_PRODUCTION = "appattest\0\0\0\0\0\0\0";
const AAGUID_DEVELOPMENT = "appattestdevelop";

const EXPECTED_ATTESTATION_FORMAT = "apple-appattest";
const KEY_ID_LENGTH = 32;

export const APPLE_ROOT_CA_PEM = APPLE_APP_ATTEST_ROOT_CA_PEM;

export type AppAttestEnvironment = "production" | "development";

export type AttestationVerificationInput = {
  /** 端末が返した attestation object（base64）。 */
  attestation: string;
  /** 端末が返した鍵ID（base64）。 */
  keyId: string;
  /** サーバーが発行したチャレンジ。 */
  challenge: string;
  teamId: string;
  bundleId: string;
  /** 受理する環境。開発ビルドを本番で受け入れないために明示する。 */
  allowedEnvironments: readonly AppAttestEnvironment[];
  now?: Date;
};

export type AttestationVerificationResult = {
  keyId: string;
  /** DER 形式の公開鍵（base64）。以降の Assertion 検証に使う。 */
  publicKey: string;
  environment: AppAttestEnvironment;
};

export class AppAttestError extends Error {
  readonly code: string;

  constructor(code: string, message: string) {
    super(message);
    this.name = "AppAttestError";
    this.code = code;
  }
}

function fail(code: string, message: string): never {
  throw new AppAttestError(code, message);
}

function sha256(...parts: Buffer[]): Buffer {
  const hash = createHash("sha256");
  for (const part of parts) hash.update(part);
  return hash.digest();
}

function decodeBase64(value: string, label: string): Buffer {
  const buffer = Buffer.from(value, "base64");
  if (buffer.length === 0) fail("malformed_input", `${label} が空です`);
  // base64 として解釈できない文字が混ざっていた場合を弾く。
  if (buffer.toString("base64").replace(/=+$/, "") !== value.replace(/=+$/, "")) {
    fail("malformed_input", `${label} が base64 ではありません`);
  }
  return buffer;
}

type AttestationObject = {
  fmt?: unknown;
  attStmt?: { x5c?: unknown; receipt?: unknown };
  authData?: unknown;
};

/**
 * Attestation を検証し、以降の Assertion 検証に使う公開鍵を返す。
 *
 * Apple の手順に沿って、証明書チェーン・nonce・鍵ID・アプリID・カウンタを
 * すべて確認する。1つでも省くと、別のアプリや改ざんされた要求を通してしまう。
 */
export function verifyAttestation(
  input: AttestationVerificationInput,
): AttestationVerificationResult {
  const now = input.now ?? new Date();
  const attestationBytes = decodeBase64(input.attestation, "attestation");
  const keyIdBytes = decodeBase64(input.keyId, "keyId");
  if (keyIdBytes.length !== KEY_ID_LENGTH) {
    fail("malformed_input", "keyId の長さが不正です");
  }

  let decoded: AttestationObject;
  try {
    decoded = decodeCbor(attestationBytes) as AttestationObject;
  } catch {
    fail("malformed_input", "attestation を CBOR として読めません");
  }

  if (decoded.fmt !== EXPECTED_ATTESTATION_FORMAT) {
    fail("unexpected_format", "attestation の形式が想定と異なります");
  }

  const chain = decoded.attStmt?.x5c;
  if (!Array.isArray(chain) || chain.length < 2) {
    fail("malformed_input", "証明書チェーンがありません");
  }
  const authData = decoded.authData;
  if (!(authData instanceof Uint8Array)) {
    fail("malformed_input", "authData がありません");
  }
  const authDataBytes = Buffer.from(authData);

  const certificates = chain.map((entry, index) => {
    if (!(entry instanceof Uint8Array)) {
      fail("malformed_input", `証明書 ${index} を読めません`);
    }
    try {
      return new X509Certificate(Buffer.from(entry));
    } catch {
      return fail("malformed_input", `証明書 ${index} が不正です`);
    }
  });

  const credentialCertificate = certificates[0];
  const intermediateCertificate = certificates[1];
  if (!credentialCertificate || !intermediateCertificate) {
    fail("malformed_input", "証明書チェーンが不足しています");
  }

  verifyCertificateChain(credentialCertificate, intermediateCertificate, now);

  // nonce は「サーバーが出したチャレンジ」と authData の両方に依存する。
  // これが証明書の拡張と一致して初めて、この端末がこの要求に応じたと言える。
  const clientDataHash = sha256(Buffer.from(input.challenge, "utf8"));
  const expectedNonce = sha256(authDataBytes, clientDataHash);
  const certificateNonce = extractAppAttestNonce(Buffer.from(credentialCertificate.raw));
  if (!certificateNonce) {
    fail("nonce_missing", "証明書に nonce 拡張がありません");
  }
  if (!certificateNonce.equals(expectedNonce)) {
    fail("nonce_mismatch", "nonce が一致しません");
  }

  const publicKeyDer = credentialCertificate.publicKey.export({
    type: "spki",
    format: "der",
  });
  const derivedKeyId = sha256(uncompressedPoint(publicKeyDer));
  if (!derivedKeyId.equals(keyIdBytes)) {
    fail("key_id_mismatch", "keyId が公開鍵と一致しません");
  }

  const environment = verifyAuthenticatorData({
    authData: authDataBytes,
    teamId: input.teamId,
    bundleId: input.bundleId,
    keyId: keyIdBytes,
    allowedEnvironments: input.allowedEnvironments,
  });

  return {
    keyId: input.keyId,
    publicKey: publicKeyDer.toString("base64"),
    environment,
  };
}

/** SPKI から X9.62 非圧縮形式の公開鍵（0x04 始まりの65バイト）を取り出す。 */
function uncompressedPoint(spkiDer: Buffer): Buffer {
  const marker = spkiDer.lastIndexOf(0x04);
  const candidate = spkiDer.subarray(spkiDer.length - 65);
  if (candidate.length === 65 && candidate[0] === 0x04) return candidate;
  if (marker >= 0 && spkiDer.length - marker === 65) {
    return spkiDer.subarray(marker);
  }
  return fail("malformed_input", "公開鍵の形式が想定と異なります");
}

function verifyCertificateChain(
  credentialCertificate: X509Certificate,
  intermediateCertificate: X509Certificate,
  now: Date,
): void {
  const root = new X509Certificate(APPLE_ROOT_CA_PEM);

  for (const [label, certificate] of [
    ["端末証明書", credentialCertificate],
    ["中間証明書", intermediateCertificate],
    ["ルート証明書", root],
  ] as const) {
    const notBefore = new Date(certificate.validFrom);
    const notAfter = new Date(certificate.validTo);
    if (now < notBefore || now > notAfter) {
      fail("certificate_expired", `${label} の有効期間外です`);
    }
  }

  if (!credentialCertificate.verify(intermediateCertificate.publicKey)) {
    fail("chain_invalid", "端末証明書が中間証明書で署名されていません");
  }
  if (!intermediateCertificate.verify(root.publicKey)) {
    fail("chain_invalid", "中間証明書が Apple のルート証明書で署名されていません");
  }
  if (!credentialCertificate.checkIssued(intermediateCertificate)) {
    fail("chain_invalid", "証明書の発行者が一致しません");
  }
  if (!intermediateCertificate.checkIssued(root)) {
    fail("chain_invalid", "中間証明書の発行者が Apple ではありません");
  }
}

function verifyAuthenticatorData(params: {
  authData: Buffer;
  teamId: string;
  bundleId: string;
  keyId: Buffer;
  allowedEnvironments: readonly AppAttestEnvironment[];
}): AppAttestEnvironment {
  const { authData } = params;
  if (authData.length < CREDENTIAL_ID_OFFSET + KEY_ID_LENGTH) {
    fail("malformed_input", "authData が短すぎます");
  }

  const appId = `${params.teamId}.${params.bundleId}`;
  const expectedRpIdHash = sha256(Buffer.from(appId, "utf8"));
  if (!authData.subarray(0, RP_ID_HASH_LENGTH).equals(expectedRpIdHash)) {
    fail("app_id_mismatch", "別のアプリの attestation です");
  }

  const counter = authData.readUInt32BE(COUNTER_OFFSET);
  if (counter !== 0) {
    fail("counter_invalid", "attestation のカウンタが0ではありません");
  }

  const aaguid = authData
    .subarray(AAGUID_OFFSET, AAGUID_OFFSET + AAGUID_LENGTH)
    .toString("binary");
  let environment: AppAttestEnvironment;
  if (aaguid === AAGUID_PRODUCTION) {
    environment = "production";
  } else if (aaguid === AAGUID_DEVELOPMENT) {
    environment = "development";
  } else {
    return fail("environment_unknown", "aaguid が想定と異なります");
  }
  if (!params.allowedEnvironments.includes(environment)) {
    fail("environment_not_allowed", `${environment} の attestation は受け付けません`);
  }

  const credentialIdLength = authData.readUInt16BE(CREDENTIAL_ID_LENGTH_OFFSET);
  if (credentialIdLength !== KEY_ID_LENGTH) {
    fail("malformed_input", "credentialId の長さが不正です");
  }
  const credentialId = authData.subarray(
    CREDENTIAL_ID_OFFSET,
    CREDENTIAL_ID_OFFSET + KEY_ID_LENGTH,
  );
  if (!credentialId.equals(params.keyId)) {
    fail("key_id_mismatch", "authData の credentialId が keyId と一致しません");
  }

  return environment;
}

export type AssertionVerificationInput = {
  /** 端末が返した assertion（base64）。 */
  assertion: string;
  /** 署名対象となった本文（リクエストボディそのもの）。 */
  clientData: string;
  /** 登録済みの公開鍵（DER, base64）。 */
  publicKey: string;
  teamId: string;
  bundleId: string;
  /** 保存済みのカウンタ。これ以下の値は受け付けない。 */
  previousCounter: number;
};

export type AssertionVerificationResult = { counter: number };

/**
 * Assertion を検証する。
 *
 * 署名が本文に紐づくため、本文を書き換えた要求は通らない。
 * カウンタが前回以下なら、以前の要求の使い回しとみなして拒否する。
 */
export function verifyAssertion(
  input: AssertionVerificationInput,
): AssertionVerificationResult {
  const assertionBytes = decodeBase64(input.assertion, "assertion");

  let decoded: { signature?: unknown; authenticatorData?: unknown };
  try {
    decoded = decodeCbor(assertionBytes) as { signature?: unknown; authenticatorData?: unknown };
  } catch {
    fail("malformed_input", "assertion を CBOR として読めません");
  }

  const { signature, authenticatorData } = decoded;
  if (!(signature instanceof Uint8Array) || !(authenticatorData instanceof Uint8Array)) {
    fail("malformed_input", "assertion の中身が不足しています");
  }
  const authDataBytes = Buffer.from(authenticatorData);
  if (authDataBytes.length < COUNTER_OFFSET + COUNTER_LENGTH) {
    fail("malformed_input", "authenticatorData が短すぎます");
  }

  const appId = `${input.teamId}.${input.bundleId}`;
  if (!authDataBytes.subarray(0, RP_ID_HASH_LENGTH).equals(sha256(Buffer.from(appId, "utf8")))) {
    fail("app_id_mismatch", "別のアプリの assertion です");
  }

  const clientDataHash = sha256(Buffer.from(input.clientData, "utf8"));
  const nonce = sha256(authDataBytes, clientDataHash);

  const key = createPublicKey({
    key: Buffer.from(input.publicKey, "base64"),
    format: "der",
    type: "spki",
  });
  const verifier = createVerify("SHA256");
  verifier.update(nonce);
  verifier.end();
  if (!verifier.verify(key, Buffer.from(signature))) {
    fail("signature_invalid", "assertion の署名が一致しません");
  }

  const counter = authDataBytes.readUInt32BE(COUNTER_OFFSET);
  if (counter <= input.previousCounter) {
    fail("counter_replay", "assertion のカウンタが進んでいません");
  }

  return { counter };
}
