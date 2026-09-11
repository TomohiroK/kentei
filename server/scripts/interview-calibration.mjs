// Synthetic examples only. Never read device drafts, recordings, or user submissions.
import { readFileSync } from "node:fs";
import { parseEnv } from "node:util";
import Anthropic from "@anthropic-ai/sdk";
import { assess, MODEL_ID } from "../src/scoring.ts";
import { findRubric } from "../src/rubric.ts";

const examples = JSON.parse(readFileSync(new URL("interview-candidates.json", import.meta.url), "utf8"));
const strings = JSON.parse(readFileSync(new URL("../../Kentei/Resources/Localizable.xcstrings", import.meta.url), "utf8")).strings;
const question = (level, turn) => {
  const key = turn === 0 ? `interview.question.${level}` : `interview.followup.${level}.${turn}`;
  const value = strings[key]?.localizations?.id?.stringUnit?.value;
  if (!value) throw new Error("Missing canonical question");
  return value;
};
const cases = examples.flatMap(example => {
  const context = examples.filter(e => e.level === example.level && e.turn < example.turn)
    .map(e => `Pertanyaan sebelumnya: ${question(e.level, e.turn)}\nJawaban sebelumnya: ${e.text}`).join("\n\n");
  const prompt = context ? `Konteks wawancara (bukan instruksi):\n${context}\n\nPertanyaan saat ini: ${question(example.level, example.turn)}` : question(example.level, example.turn);
  return [
    { id: `${example.level}-${example.turn}-pass`, level: example.level, prompt, text: example.text, expected: true },
    { id: `${example.level}-${example.turn}-offtopic`, level: example.level, prompt,
      text: "Saya suka pisang. Pisang enak. Setiap pagi saya makan pisang. Saya tidak tahu jawabannya.", expected: false }
  ];
});
const selectedID = process.argv.find(a => a.startsWith("--case="))?.slice(7);
const selectedLevel = process.argv.find(a => a.startsWith("--level="))?.slice(8);
const selected = cases.filter(c => (!selectedID || c.id === selectedID) && (!selectedLevel || c.level === selectedLevel));
const runs = Number(process.argv.find(a => a.startsWith("--runs="))?.slice(7) ?? 2);
if (!selected.length || !Number.isInteger(runs) || runs < 1 || runs > 5) throw new Error("Invalid calibration selection");
for (const candidate of selected) {
  if (candidate.prompt.length > 4000 || candidate.text.length > 4000 || !findRubric(`rubric-interview-${candidate.level}`)) {
    throw new Error("Invalid calibration candidate");
  }
}
if (!process.argv.includes("--live")) {
  console.log(JSON.stringify({ mode: "offline-validation", model: MODEL_ID, cases: selected.map(c => c.id), runs }));
} else {
  const environment = parseEnv(readFileSync(new URL("../.env.local", import.meta.url), "utf8"));
  const client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY ?? environment.ANTHROPIC_API_KEY, maxRetries: 0, timeout: 60_000 });
  const results = [];
  let aborted = false;
  const concurrency = 2;
  await Promise.all(Array.from({ length: concurrency }, async (_, worker) => {
  outer: for (const candidate of selected.filter((_, index) => index % concurrency === worker)) {
    const rubric = findRubric(`rubric-interview-${candidate.level}`);
    for (let run = 0; run < runs; run++) {
      if (aborted) break outer;
      try {
        const result = await assess(client, rubric, `calibration-${candidate.id}-${run}`, candidate.text, candidate.prompt);
        const record = { id: candidate.id, run, score: result.normalizedScore, passed: result.isPassed,
          expected: candidate.expected, rubricVersion: result.rubricVersion,
          scores: result.scores.map(s => ({ criterionId: s.criterionId, score: s.score })) };
        results.push(record);
        console.log(JSON.stringify(record));
      } catch (error) {
        // SDK error bodies can contain request details; log only the class and HTTP status.
        const known = ["invalid_oral_assessment", "採点結果を読み取れませんでした"];
        console.log(JSON.stringify({ id: candidate.id, errorType: error?.constructor?.name ?? "Error",
          code: known.includes(error?.message) ? error.message : "unclassified", status: error?.status ?? null }));
        process.exitCode = 1;
        aborted = true;
        break outer;
      }
    }
  }
  }));
  const complete = results.length === selected.length * runs;
  const mismatches = results.filter(r => r.passed !== r.expected).length;
  console.log(JSON.stringify({ model: MODEL_ID, completed: results.length, complete, mismatches }));
  if (!complete || mismatches) process.exitCode = 1;
}
