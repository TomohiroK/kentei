/**
 * 基準回答の実測。
 *
 * モデルやプロンプトを変えたら、期待範囲を推測で決めずにここで測り直す。
 * 同じ提出を複数回採点し、揺れ幅を見たうえで範囲に余裕を持たせる。
 *
 *   RUBRIC_ID=rubric-writing-a node --experimental-strip-types scripts/measure-golden.mjs <候補JSON> [回数] [基準ID]
 *
 * 候補JSON: [{ "id": "...", "text": "...", "prompt": "（任意）設問" }, ...]
 * ANTHROPIC_API_KEY は server/.env.local から読む（この出力には値を含めない）。
 */
import { readFileSync } from "node:fs";
import Anthropic from "@anthropic-ai/sdk";
import { assess } from "../src/scoring.ts";
import { findRubric } from "../src/rubric.ts";

for (const line of readFileSync(new URL("../.env.local", import.meta.url), "utf8").split("\n")) {
  const at = line.indexOf("=");
  if (at > 0) process.env[line.slice(0, at).trim()] ??= line.slice(at + 1).trim().replace(/^["']|["']$/g, "");
}

const RUNS = Number(process.argv[3] ?? 3);
// 基準IDは候補ファイルで指定する。級ごとに基準が違うため既定値に頼らない。
// 候補ごとに基準を切り替える。第4引数を渡すとその基準だけを測る。
const ONLY_RUBRIC_ID = process.argv[4];
const candidates = JSON.parse(readFileSync(process.argv[2], "utf8"));
const client = new Anthropic();

const targets = candidates.filter(
  (candidate) => !ONLY_RUBRIC_ID || (candidate.rubricId ?? "rubric-writing-b") === ONLY_RUBRIC_ID,
);
if (targets.length === 0) throw new Error("測定対象がありません");

const jobs = targets.flatMap((candidate) =>
  Array.from({ length: RUNS }, (_, run) => ({ candidate, run })),
);

const settled = await Promise.all(
  jobs.map(async ({ candidate, run }) => {
    try {
      const rubric = findRubric(candidate.rubricId ?? "rubric-writing-b");
      if (!rubric) throw new Error(`基準が見つかりません: ${candidate.rubricId}`);
      const outcome = await assess(
        client,
        rubric,
        `${candidate.id}-${run}`,
        candidate.text,
        candidate.prompt ?? null,
      );
      return { id: candidate.id, score: outcome.normalizedScore, passed: outcome.isPassed };
    } catch (error) {
      return { id: candidate.id, error: error instanceof Error ? error.message : "unknown" };
    }
  }),
);

const byId = new Map();
for (const entry of settled) {
  if (!byId.has(entry.id)) byId.set(entry.id, []);
  byId.get(entry.id).push(entry);
}

console.log("ID".padEnd(26) + "最小    最大    合否");
for (const candidate of candidates) {
  const entries = byId.get(candidate.id) ?? [];
  const failures = entries.filter((e) => e.error);
  const scores = entries.filter((e) => !e.error).map((e) => e.score);
  if (scores.length === 0) {
    console.log(`${candidate.id.padEnd(26)} 全失敗 ${failures[0]?.error ?? ""}`);
    continue;
  }
  const passed = entries.filter((e) => !e.error).map((e) => e.passed);
  const verdict = passed.every((p) => p) ? "全て合格" : passed.every((p) => !p) ? "全て不合格" : "★揺れあり";
  console.log(
    `${candidate.id.padEnd(26)}${Math.min(...scores).toFixed(3)}   ${Math.max(...scores).toFixed(3)}   ${verdict}` +
      (failures.length ? `  (失敗${failures.length}件)` : ""),
  );
}
