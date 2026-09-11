import { randomBytes } from "node:crypto";
import type { AttestationStoring } from "./attestStore.ts";
import { AppAttestError, verifyAssertion, verifyAttestation } from "./appattest/verify.ts";
import type { AppAttestEnvironment } from "./appattest/verify.ts";

/** チャレンジの有効期間。往復2回分に足りる長さで、使い回しの余地は残さない。 */
export const CHALLENGE_TTL_SECONDS = 300;
const CHALLENGE_BYTES = 32;

export type AttestationSettings = {
  teamId: string;
  bundleId: string;
  allowedEnvironments: readonly AppAttestEnvironment[];
};

export type AttestationFailure = { status: number; code: string; message: string };

/** 環境変数から設定を組み立てる。揃っていなければ null。 */
export function readAttestationSettings(
  env: NodeJS.ProcessEnv,
): AttestationSettings | null {
  const teamId = env.KENTEI_TEAM_ID;
  const bundleId = env.KENTEI_BUNDLE_ID;
  if (!teamId || !bundleId) return null;
  // 開発ビルドの受け入れは明示的に許可した場合だけ。既定は本番のみ。
  const allowDevelopment = env.KENTEI_ALLOW_DEVELOPMENT_ATTESTATION === "true";
  return {
    teamId,
    bundleId,
    allowedEnvironments: allowDevelopment
      ? (["production", "development"] as const)
      : (["production"] as const),
  };
}

export function issueChallenge(): string {
  return randomBytes(CHALLENGE_BYTES).toString("base64url");
}

/** Assertion が署名した文字列。両側が同じ組み立て方をする。 */
export function clientDataFor(challenge: string, submissionId: string): string {
  return `${challenge}:${submissionId}`;
}

function toFailure(error: unknown): AttestationFailure {
  if (error instanceof AppAttestError) {
    return { status: 401, code: `attest_${error.code}`, message: error.message };
  }
  return { status: 401, code: "attest_failed", message: "端末を確認できません" };
}

export async function registerAttestation(params: {
  store: AttestationStoring;
  settings: AttestationSettings;
  keyId: unknown;
  attestation: unknown;
  challenge: unknown;
  now?: Date;
}): Promise<{ keyId: string } | { failure: AttestationFailure }> {
  const { keyId, attestation, challenge } = params;
  if (
    typeof keyId !== "string" ||
    typeof attestation !== "string" ||
    typeof challenge !== "string"
  ) {
    return { failure: { status: 400, code: "invalid_body", message: "登録内容が不足しています" } };
  }

  // チャレンジは1回だけ使える。ここで消費してから重い検証に進む。
  if (!(await params.store.consumeChallenge(challenge))) {
    return {
      failure: { status: 401, code: "attest_challenge_invalid", message: "チャレンジが無効です" },
    };
  }

  let verified;
  try {
    verified = verifyAttestation({
      attestation,
      keyId,
      challenge,
      teamId: params.settings.teamId,
      bundleId: params.settings.bundleId,
      allowedEnvironments: params.settings.allowedEnvironments,
      ...(params.now ? { now: params.now } : {}),
    });
  } catch (error) {
    return { failure: toFailure(error) };
  }

  await params.store.saveKey({
    keyId: verified.keyId,
    publicKey: verified.publicKey,
    counter: 0,
    registeredAt: (params.now ?? new Date()).toISOString(),
  });

  return { keyId: verified.keyId };
}

/**
 * 採点要求に添えられた Assertion を確認する。
 *
 * チャレンジの消費・署名・カウンタの3つが揃って初めて通す。
 */
export async function authorizeSubmission(params: {
  store: AttestationStoring;
  settings: AttestationSettings;
  keyId: string | undefined;
  assertion: string | undefined;
  challenge: string | undefined;
  submissionId: string;
}): Promise<{ ok: true } | { failure: AttestationFailure }> {
  const { keyId, assertion, challenge } = params;
  if (!keyId || !assertion || !challenge) {
    return {
      failure: { status: 401, code: "attest_required", message: "端末の確認が必要です" },
    };
  }

  const stored = await params.store.findKey(keyId);
  if (!stored) {
    return {
      failure: { status: 401, code: "attest_key_unknown", message: "端末が登録されていません" },
    };
  }

  if (!(await params.store.consumeChallenge(challenge))) {
    return {
      failure: { status: 401, code: "attest_challenge_invalid", message: "チャレンジが無効です" },
    };
  }

  let counter: number;
  try {
    counter = verifyAssertion({
      assertion,
      clientData: clientDataFor(challenge, params.submissionId),
      publicKey: stored.publicKey,
      teamId: params.settings.teamId,
      bundleId: params.settings.bundleId,
      previousCounter: stored.counter,
    }).counter;
  } catch (error) {
    return { failure: toFailure(error) };
  }

  // 署名が正しくても、カウンタを進められなければ同時に届いた再送とみなす。
  if (!(await params.store.advanceCounter(keyId, counter))) {
    return {
      failure: { status: 401, code: "attest_counter_replay", message: "要求が重複しています" },
    };
  }

  return { ok: true };
}
