import assert from "node:assert/strict";
import { test } from "node:test";
import { validateRequest, MAX_TEXT_LENGTH, verifyClient } from "./gate.ts";
import { findRubric, isPassing, normalizedScore, WRITING_RUBRIC_B } from "./rubric.ts";

const rubric = WRITING_RUBRIC_B;

test("満点は正規化スコア1.0になる", () => {
  const scores = new Map(rubric.criteria.map((criterion) => [criterion.id, criterion.maxScore]));
  assert.equal(normalizedScore(rubric, scores), 1);
  assert.equal(isPassing(rubric, 1), true);
});

test("重みの合計は1.0である", () => {
  const total = rubric.criteria.reduce((sum, criterion) => sum + criterion.weight, 0);
  assert.ok(Math.abs(total - 1) < 0.0001, `重み合計が ${total}`);
});

test("観点ごとの寄与は重みに従う", () => {
  assert.ok(Math.abs(normalizedScore(rubric, new Map([["task", 4]])) - 0.3) < 0.0001);
  assert.ok(Math.abs(normalizedScore(rubric, new Map([["coherence", 4]])) - 0.2) < 0.0001);
});

test("範囲外の素点は丸める", () => {
  const scores = new Map([["task", 99], ["grammar", -5]]);
  assert.ok(Math.abs(normalizedScore(rubric, scores) - 0.3) < 0.0001);
});

test("合格ラインは設定値に従う", () => {
  assert.equal(isPassing(rubric, 0.59), false);
  assert.equal(isPassing(rubric, 0.6), true);
});

test("アプリと同じ基準の版を持つ", () => {
  // Kentei/Domain/DemoAssessment.swift と一致させる。
  assert.equal(rubric.id, "rubric-writing-b");
  assert.equal(rubric.version, "rubric-2026-08-v1");
  assert.deepEqual(
    rubric.criteria.map((criterion) => criterion.id),
    ["task", "grammar", "vocabulary", "coherence"],
  );
});

test("録音を含む提出は受け付けない", () => {
  const result = validateRequest(
    { submissionId: "a", taskType: "writing", level: "b", rubricId: rubric.id, rubricVersion: rubric.version, audioReference: "file://x.m4a" },
    rubric,
  );
  assert.ok("rejection" in result);
  assert.equal(result.rejection.code, "recording_not_available");
});

test("基準の版がずれた提出は採点しない", () => {
  const result = validateRequest(
    { submissionId: "a", taskType: "writing", level: "b", rubricId: rubric.id, rubricVersion: "rubric-old", text: "Saya tinggal di Jakarta." },
    rubric,
  );
  assert.ok("rejection" in result);
  assert.equal(result.rejection.status, 409);
});

test("空の本文は受け付けない", () => {
  const result = validateRequest(
    { submissionId: "a", taskType: "writing", level: "b", rubricId: rubric.id, rubricVersion: rubric.version, text: "   " },
    rubric,
  );
  assert.ok("rejection" in result);
  assert.equal(result.rejection.code, "empty_text");
});

test("長すぎる本文は受け付けない", () => {
  const result = validateRequest(
    { submissionId: "a", taskType: "writing", level: "b", rubricId: rubric.id, rubricVersion: rubric.version, text: "a".repeat(MAX_TEXT_LENGTH + 1) },
    rubric,
  );
  assert.ok("rejection" in result);
  assert.equal(result.rejection.status, 413);
});

test("正しい提出は通る", () => {
  const result = validateRequest(
    { submissionId: "a", taskType: "writing", level: "b", rubricId: rubric.id, rubricVersion: rubric.version, text: " Saya tinggal di Jakarta. " },
    rubric,
  );
  assert.ok("request" in result);
  assert.equal(result.request.text, "Saya tinggal di Jakarta.");
});

test("基準が見つからない場合は404", () => {
  const result = validateRequest(
    { submissionId: "a", taskType: "writing", level: "b", rubricId: "missing", rubricVersion: "x", text: "abc" },
    findRubric("missing"),
  );
  assert.ok("rejection" in result);
  assert.equal(result.rejection.status, 404);
});

test("トークン未設定なら採点を受け付けない", () => {
  const rejection = verifyClient("anything", undefined);
  assert.equal(rejection?.status, 503);
});

test("トークンが一致しない呼び出しは拒否する", () => {
  assert.equal(verifyClient("wrong", "correct")?.status, 401);
  assert.equal(verifyClient("correct", "correct"), null);
});
