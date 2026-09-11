import assert from "node:assert/strict";
import { test } from "node:test";
import handler from "./handler.ts";
import { WRITING_RUBRIC_B } from "./rubric.ts";

type Captured = { status: number; body: Record<string, unknown> };

/** VercelRequest / VercelResponse の最小の代役。HTTP層の配線を確かめる。 */
function invoke(
  options: { method?: string; token?: string; body?: unknown },
): Promise<Captured> {
  const request = {
    method: options.method ?? "POST",
    headers: options.token ? { "x-kentei-client": options.token } : {},
    body: options.body,
  };

  return new Promise((resolve) => {
    const response = {
      status(code: number) {
        return {
          json(body: Record<string, unknown>) {
            resolve({ status: code, body });
          },
        };
      },
    };
    void handler(request as never, response as never);
  });
}

const validBody = {
  submissionId: "submission-1",
  taskType: "writing",
  level: "b",
  rubricId: WRITING_RUBRIC_B.id,
  rubricVersion: WRITING_RUBRIC_B.version,
  text: "Saya sudah tinggal di Jakarta selama dua tahun.",
};

test("GET は受け付けない", async () => {
  const result = await invoke({ method: "GET" });
  assert.equal(result.status, 405);
});

test("クライアントトークン未設定なら採点しない", async () => {
  delete process.env.KENTEI_CLIENT_TOKEN;
  const result = await invoke({ body: validBody });
  assert.equal(result.status, 503);
  assert.equal(result.body.code, "client_token_not_configured");
});

test("トークンが違う呼び出しは拒否する", async () => {
  process.env.KENTEI_CLIENT_TOKEN = "correct-token";
  const result = await invoke({ token: "wrong", body: validBody });
  assert.equal(result.status, 401);
});

test("録音を含む提出は外部へ出さずに弾く", async () => {
  process.env.KENTEI_CLIENT_TOKEN = "correct-token";
  const result = await invoke({
    token: "correct-token",
    body: { ...validBody, audioReference: "file://recording.m4a" },
  });
  assert.equal(result.status, 400);
  assert.equal(result.body.code, "recording_not_available");
});

test("基準の版がずれていたら採点しない", async () => {
  process.env.KENTEI_CLIENT_TOKEN = "correct-token";
  const result = await invoke({
    token: "correct-token",
    body: { ...validBody, rubricVersion: "rubric-old" },
  });
  assert.equal(result.status, 409);
  assert.equal(result.body.code, "rubric_version_mismatch");
});

test("APIキー未設定なら採点を受け付けない", async () => {
  process.env.KENTEI_CLIENT_TOKEN = "correct-token";
  delete process.env.ANTHROPIC_API_KEY;
  const result = await invoke({ token: "correct-token", body: validBody });
  assert.equal(result.status, 503);
  assert.equal(result.body.code, "api_key_not_configured");
});
