import Anthropic from "@anthropic-ai/sdk";
import type { VercelRequest, VercelResponse } from "@vercel/node";
import { authorizeSubmission, readAttestationSettings } from "./attestation.ts";
import { validateRequest, verifyClient } from "./gate.ts";
import { RedisAttestationStore } from "./redisAttestStore.ts";
import { findRubric } from "./rubric.ts";
import { assess } from "./scoring.ts";

/**
 * 採点の中継。
 *
 * APIキーを端末へ置かないために存在する。受け取るのはテキストだけで、
 * 提出物も採点結果もサーバーには保存しない。
 */
export default async function handler(request: VercelRequest, response: VercelResponse) {
  if (request.method !== "POST") {
    response.status(405).json({ code: "method_not_allowed", message: "POST のみ受け付けます" });
    return;
  }

  const unauthorized = verifyClient(
    typeof request.headers["x-kentei-client"] === "string" ? request.headers["x-kentei-client"] : undefined,
    process.env.KENTEI_CLIENT_TOKEN,
  );
  if (unauthorized) {
    response.status(unauthorized.status).json({ code: unauthorized.code, message: unauthorized.message });
    return;
  }

  const rubricId = typeof (request.body as { rubricId?: unknown })?.rubricId === "string"
    ? (request.body as { rubricId: string }).rubricId
    : "";
  const validated = validateRequest(request.body, findRubric(rubricId), process.env.KENTEI_ORAL_ASSESSMENT_READY === "true");

  if ("rejection" in validated) {
    response
      .status(validated.rejection.status)
      .json({ code: validated.rejection.code, message: validated.rejection.message });
    return;
  }

  const rubric = findRubric(validated.request.rubricId);
  if (!rubric) {
    response.status(404).json({ code: "rubric_not_found", message: "基準が見つかりません" });
    return;
  }

  // 端末確認の強制は明示的に有効化する。設定漏れで静かに緩むことを避ける。
  if (process.env.KENTEI_REQUIRE_ATTESTATION === "true") {
    const settings = readAttestationSettings(process.env);
    const store = RedisAttestationStore.fromEnvironment(process.env);
    if (!settings || !store) {
      response
        .status(503)
        .json({ code: "attest_not_configured", message: "端末確認を利用できません" });
      return;
    }
    const authorized = await authorizeSubmission({
      store,
      settings,
      keyId: headerValue(request, "x-kentei-key-id"),
      assertion: headerValue(request, "x-kentei-assertion"),
      challenge: headerValue(request, "x-kentei-challenge"),
      submissionId: validated.request.submissionId,
    });
    if ("failure" in authorized) {
      response
        .status(authorized.failure.status)
        .json({ code: authorized.failure.code, message: authorized.failure.message });
      return;
    }
  }

  if (!process.env.ANTHROPIC_API_KEY) {
    response.status(503).json({ code: "api_key_not_configured", message: "採点を利用できません" });
    return;
  }

  try {
    const client = new Anthropic();
    const outcome = await assess(
      client,
      rubric,
      validated.request.submissionId,
      validated.request.text ?? "",
      validated.request.prompt,
    );
    response.status(200).json(outcome);
  } catch (error) {
    // 提出本文はログへ残さない。再送できるよう一時的な失敗として返す。
    console.error("assessment_failed", error instanceof Error ? error.name : "unknown");
    response.status(502).json({ code: "temporary_failure", message: "採点に失敗しました" });
  }
}

/** ヘッダは配列で届くことがある。文字列のときだけ採用する。 */
function headerValue(request: VercelRequest, name: string): string | undefined {
  const value = request.headers[name];
  return typeof value === "string" ? value : undefined;
}
