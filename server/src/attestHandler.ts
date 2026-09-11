import type { VercelRequest, VercelResponse } from "@vercel/node";
import { CHALLENGE_TTL_SECONDS, issueChallenge, readAttestationSettings, registerAttestation } from "./attestation.ts";
import { RedisAttestationStore } from "./redisAttestStore.ts";

/**
 * 端末登録の窓口。
 *
 * challenge でサーバー発行の使い捨て値を配り、register でその値に対する
 * Apple の attestation を検証して公開鍵を保存する。
 */
export default async function attestHandler(request: VercelRequest, response: VercelResponse) {
  if (request.method !== "POST") {
    response.status(405).json({ code: "method_not_allowed", message: "POST のみ受け付けます" });
    return;
  }

  const settings = readAttestationSettings(process.env);
  if (!settings) {
    response.status(503).json({ code: "attest_not_configured", message: "端末確認を利用できません" });
    return;
  }

  // 保存できない状態で登録を受けると、再送を防げないまま通してしまう。
  const store = RedisAttestationStore.fromEnvironment(process.env);
  if (!store) {
    response.status(503).json({ code: "attest_store_unavailable", message: "端末確認を利用できません" });
    return;
  }

  const body = (request.body ?? {}) as Record<string, unknown>;
  const action = typeof body.action === "string" ? body.action : "";

  if (action === "challenge") {
    const challenge = issueChallenge();
    await store.putChallenge(challenge, CHALLENGE_TTL_SECONDS);
    response.status(200).json({ challenge, expiresInSeconds: CHALLENGE_TTL_SECONDS });
    return;
  }

  if (action === "register") {
    const outcome = await registerAttestation({
      store,
      settings,
      keyId: body.keyId,
      attestation: body.attestation,
      challenge: body.challenge,
    });
    if ("failure" in outcome) {
      response
        .status(outcome.failure.status)
        .json({ code: outcome.failure.code, message: outcome.failure.message });
      return;
    }
    response.status(200).json({ registered: true, keyId: outcome.keyId });
    return;
  }

  response.status(400).json({ code: "unknown_action", message: "action が不正です" });
}
