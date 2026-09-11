import type { Rubric } from "./rubric.ts";

export type AssessmentRequest = {
  submissionId: string;
  taskType: string;
  level: string;
  rubricId: string;
  rubricVersion: string;
  /** 学習者が読んだ設問。「課題への対応」の観点はこれがないと採点できない。 */
  prompt?: string | null;
  text?: string | null;
  audioReference?: string | null;
};

export type GateRejection = {
  status: number;
  code: string;
  message: string;
};

/** 本文の上限。長すぎる提出は採点せず弾く。 */
export const MAX_TEXT_LENGTH = 4000;

/** 設問の上限。資料を含む設問があるため本文とは別に持つ。 */
export const MAX_PROMPT_LENGTH = 4000;

/**
 * 外部へ出す前の受け付け判定。
 *
 * ここで弾くものは Claude API を呼ばない。無駄な課金と、
 * 受け付けられない提出（録音など）の外部送信を防ぐ。
 */
export function validateRequest(
  body: unknown,
  rubric: Rubric | undefined,
  oralAssessmentEnabled = false,
): { request: AssessmentRequest } | { rejection: GateRejection } {
  if (typeof body !== "object" || body === null) {
    return { rejection: { status: 400, code: "invalid_body", message: "本文がありません" } };
  }

  const request = body as AssessmentRequest;

  if (typeof request.submissionId !== "string" || request.submissionId.length === 0) {
    return { rejection: { status: 400, code: "invalid_submission", message: "提出IDがありません" } };
  }

  // 音声は端末内に限定し、確認済みテキストだけを受け付ける。
  if (request.audioReference != null) {
    return {
      rejection: { status: 400, code: "recording_not_available", message: "録音は受け付けていません" },
    };
  }

  if (!rubric) {
    return { rejection: { status: 404, code: "rubric_not_found", message: "基準が見つかりません" } };
  }

  if (["speaking", "interview"].includes(rubric.taskType) && !oralAssessmentEnabled) {
    return { rejection: { status: 503, code: "oral_assessment_not_ready", message: "発話の採点は準備中です" } };
  }
  if (request.level !== rubric.level) {
    return { rejection: { status: 409, code: "level_mismatch", message: "級が基準と一致しません" } };
  }
  if ((request.text != null && typeof request.text !== "string") ||
      (request.prompt != null && typeof request.prompt !== "string")) {
    return { rejection: { status: 400, code: "invalid_submission", message: "テキストの形式が不正です" } };
  }

  // 版がずれたまま採点しない。結果に記録する版と実際の基準を一致させる。
  if (request.rubricVersion !== rubric.version) {
    return {
      rejection: {
        status: 409,
        code: "rubric_version_mismatch",
        message: `基準の版が違います（アプリ: ${request.rubricVersion} / サーバー: ${rubric.version}）`,
      },
    };
  }

  if (request.taskType !== rubric.taskType) {
    return { rejection: { status: 409, code: "task_type_mismatch", message: "課題種別が基準と一致しません" } };
  }

  const text = (request.text ?? "").trim();
  if (text.length === 0) {
    return { rejection: { status: 400, code: "empty_text", message: "本文が空です" } };
  }
  if (text.length > MAX_TEXT_LENGTH) {
    return { rejection: { status: 413, code: "text_too_long", message: "本文が長すぎます" } };
  }

  const prompt = (request.prompt ?? "").trim();
  if (["speaking", "interview"].includes(rubric.taskType) && !prompt) {
    return { rejection: { status: 400, code: "invalid_submission", message: "発話課題の設問がありません" } };
  }
  if (prompt.length > MAX_PROMPT_LENGTH) {
    return { rejection: { status: 413, code: "prompt_too_long", message: "設問が長すぎます" } };
  }

  return { request: { ...request, text, prompt: prompt.length > 0 ? prompt : null } };
}

/**
 * 呼び出し元の検証。
 *
 * 暫定措置である。配布前に App Attest（DCAppAttestService）へ置き換える。
 * 共有トークンはアプリのバイナリから取り出せるため、これ単体では
 * 第三者の利用を防げない。未設定の場合は採点を受け付けない。
 */
export function verifyClient(headerValue: string | undefined, expectedToken: string | undefined): GateRejection | null {
  if (!expectedToken) {
    return { status: 503, code: "client_token_not_configured", message: "サーバーの設定が未完了です" };
  }
  if (!headerValue || headerValue !== expectedToken) {
    return { status: 401, code: "unauthorized", message: "呼び出しが許可されていません" };
  }
  return null;
}
