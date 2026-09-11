import assert from "node:assert/strict";
import test from "node:test";
import { validateRequest } from "./gate.ts";
import { ORAL_RUBRICS, hasCompleteScores, isPassing, normalizedScore } from "./rubric.ts";

for (const rubric of ORAL_RUBRICS) {
  const body = { submissionId: "test", rubricId: rubric.id, rubricVersion: rubric.version,
    taskType: rubric.taskType, level: rubric.level, text: "Menurut saya perlu ada perubahan.", prompt: "Jelaskan usulan Anda." };
  test(`${rubric.id}: closed by default; text only after review`, () => {
    const closed = validateRequest(body, rubric);
    assert.ok("rejection" in closed);
    assert.equal(closed.rejection.code, "oral_assessment_not_ready");
    assert.ok("request" in validateRequest(body, rubric, true));
    for (const audioReference of ["file:///audio.m4a", "", 0]) {
      const rejected = validateRequest({ ...body, audioReference }, rubric, true);
      assert.ok("rejection" in rejected);
      assert.equal(rejected.rejection.code, "recording_not_available");
    }
    assert.ok("rejection" in validateRequest({ ...body, prompt: "" }, rubric, true));
    assert.ok("rejection" in validateRequest({ ...body, text: {} }, rubric, true));
    assert.ok("rejection" in validateRequest({ ...body, level: "e" }, rubric, true));
    assert.ok(Math.abs(rubric.criteria.reduce((sum, c) => sum + c.weight, 0) - 1) < 0.0001);
    assert.deepEqual(rubric.criteria.map(c => c.id), ["task", "coherence", "grammar", "vocabulary"]);
  });
}

test("interview practice requires 75 percent and every criterion floor", () => {
  for (const rubric of ORAL_RUBRICS.filter(r => r.taskType === "interview")) {
    const passing = new Map(rubric.criteria.map(c => [c.id, 3]));
    assert.equal(isPassing(rubric, normalizedScore(rubric, passing), passing), true);
    const failing = new Map(rubric.criteria.map(c => [c.id, c.id === "grammar" ? 1 : 4]));
    assert.ok(normalizedScore(rubric, failing) >= 0.75);
    assert.equal(isPassing(rubric, normalizedScore(rubric, failing), failing), false);
    assert.equal(isPassing(rubric, 1), false);
  }
});

test("incomplete, duplicate, unknown and invalid oral scores are not zero-point answers", () => {
  const rubric = ORAL_RUBRICS[0];
  assert.ok(rubric);
  const valid = rubric.criteria.map(c => ({ criterionId: c.id, score: 3 }));
  assert.equal(hasCompleteScores(rubric, valid), true);
  for (const invalid of [valid.slice(1), [...valid.slice(1), valid[1]!],
    [...valid.slice(1), { criterionId: "unknown", score: 3 }],
    ...[-1, 5, 2.5, NaN].map(score => valid.map(s => ({ ...s, score })))]) {
    assert.equal(hasCompleteScores(rubric, invalid), false);
  }
});
