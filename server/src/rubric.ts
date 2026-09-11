/**
 * 採点基準。
 *
 * アプリ側の `Kentei/Domain/DemoAssessment.swift` と同じ内容・同じ版を保つ。
 * 版がずれたまま採点すると、結果に記録した版と実際の基準が食い違うため、
 * リクエストの版と一致しない場合は採点せずに拒否する。
 */
export type Criterion = {
  readonly id: string;
  readonly titleJa: string;
  readonly weight: number;
  readonly maxScore: number;
  readonly guidance: string;
};

export type Rubric = {
  readonly id: string;
  readonly version: string;
  readonly level: string;
  readonly taskType: string;
  readonly criteria: readonly Criterion[];
  readonly passingScore: number;
  readonly minimumCriterionRatio?: number;
};

export const WRITING_RUBRIC_B: Rubric = {
  id: "rubric-writing-b",
  version: "rubric-2026-08-v1",
  level: "b",
  taskType: "writing",
  passingScore: 0.6,
  criteria: [
    {
      id: "task",
      titleJa: "課題への対応",
      weight: 0.3,
      maxScore: 4,
      guidance: "設問が求めた内容を過不足なく書けているか。話題がずれていないか。",
    },
    {
      id: "grammar",
      titleJa: "文法",
      weight: 0.3,
      maxScore: 4,
      guidance: "接辞（me-, di-, -kan, -i, per-an, ke-an）と受動の使い分けが正しいか。時制表現と語順が自然か。",
    },
    {
      id: "vocabulary",
      titleJa: "語彙",
      weight: 0.2,
      maxScore: 4,
      guidance: "場面に合った語を選べているか。口語と標準語の使い分けが適切か。",
    },
    {
      id: "coherence",
      titleJa: "構成",
      weight: 0.2,
      maxScore: 4,
      guidance: "文と文のつながりが追えるか。接続表現が適切か。",
    },
  ],
};

/**
 * A級の作文基準。
 *
 * A級は時事・議論・複数資料の統合を扱う。事実を並べられるかではなく、
 * 主張と根拠を結びつけて書けるかを見る。そのため「論の展開」を最も重く置き、
 * 書き言葉としての文体の一貫性を独立した観点にした。
 */
export const WRITING_RUBRIC_A: Rubric = {
  id: "rubric-writing-a",
  version: "rubric-2026-08-v1",
  level: "a",
  taskType: "writing",
  // 最上位の級なので合格線をB級（0.6）より高く置く。
  passingScore: 0.7,
  criteria: [
    {
      id: "task",
      titleJa: "課題への対応",
      weight: 0.2,
      maxScore: 4,
      guidance:
        "設問が求めた論点に答えているか。資料や条件が示されている場合、それを踏まえているか。設問と無関係な一般論で埋めていないか。",
    },
    {
      id: "argument",
      titleJa: "論の展開",
      weight: 0.3,
      maxScore: 4,
      guidance:
        "主張が明確で、根拠が主張を支えているか。根拠が具体的か（数値・事例・因果）。反対の立場や例外に触れられているか。主張と根拠が入れ替わったり、根拠なく断定していないか。",
    },
    {
      id: "grammar",
      titleJa: "文法",
      weight: 0.2,
      maxScore: 4,
      guidance:
        "接辞（me-, di-, -kan, -i, per-an, ke-an, memper-）と受動の使い分けが正しいか。複文（yang, sehingga, meskipun, karena）の構造が崩れていないか。",
    },
    {
      id: "vocabulary",
      titleJa: "語彙",
      weight: 0.15,
      maxScore: 4,
      guidance:
        "議論に必要な抽象語・分野語を使えているか。同じ語の繰り返しに頼っていないか。語の意味を取り違えていないか。",
    },
    {
      id: "register",
      titleJa: "文体",
      weight: 0.15,
      maxScore: 4,
      guidance:
        "書き言葉（bahasa baku）で一貫しているか。話し言葉（gue, nggak, kayak, banget 等）や省略形が混ざっていないか。硬すぎて不自然になっていないか。",
    },
  ],
};

// Draft transcript-only rubrics. Release requires calibration and retention review.
export const ORAL_RUBRICS: readonly Rubric[] = ["b", "a"].flatMap((level) =>
  ["speaking", "interview"].map((taskType): Rubric => ({
    id: `rubric-${taskType}-${level}`, version: taskType === "interview" ? "interview-2026-09-v2" : "oral-2026-09-v1", level, taskType,
    passingScore: taskType === "interview" ? 0.75 : (level === "a" ? 0.7 : 0.6),
    minimumCriterionRatio: taskType === "interview" ? 0.3 : undefined,
    criteria: [
      { id: "task", titleJa: "課題への対応", weight: 0.35, maxScore: 4,
        guidance: taskType === "interview"
          ? "質問に直接答え、必要な説明と具体例を示しているか。音声由来の確認済みテキストだけを評価し、発音・抑揚・流暢さは評価しない。"
          : "与えられたテーマで立場と根拠を説明しているか。音声由来の確認済みテキストだけを評価し、発音・抑揚・流暢さは評価しない。" },
      { id: "coherence", titleJa: "構成", weight: 0.25, maxScore: 4,
        guidance: "話の内容の順序と理由・結論のつながりを評価する。話す速さ、間、言い直し、音響的な流暢さは推定しない。" },
      { id: "grammar", titleJa: "文法", weight: 0.2, maxScore: 4,
        guidance: "意味を伝える語順・接辞・文構造を評価する。自然な話し言葉の省略を作文の文体違反として扱わない。" },
      { id: "vocabulary", titleJa: "語彙", weight: 0.2, maxScore: 4,
        guidance: "場面に適した語彙で意図を具体的に伝えているか。発音の正しさをテキストから推定しない。" },
    ],
  })),
);

const RUBRICS: readonly Rubric[] = [WRITING_RUBRIC_B, WRITING_RUBRIC_A, ...ORAL_RUBRICS];

export function findRubric(id: string): Rubric | undefined {
  return RUBRICS.find((rubric) => rubric.id === id);
}

export function hasCompleteScores(rubric: Rubric, scores: readonly { criterionId: string; score: number }[]): boolean {
  return scores.length === rubric.criteria.length &&
    new Set(scores.map(s => s.criterionId)).size === rubric.criteria.length &&
    rubric.criteria.every(c => scores.some(s => s.criterionId === c.id &&
      Number.isInteger(s.score) && s.score >= 0 && s.score <= c.maxScore));
}

/**
 * 観点ごとの素点から正規化スコア（0.0〜1.0）を出す。
 *
 * 重み付けはサーバーで決定的に計算する。モデルに算術をさせない。
 * 同じ素点からは必ず同じ結果になり、採点の再現性を保てる。
 */
export function normalizedScore(rubric: Rubric, scores: ReadonlyMap<string, number>): number {
  return rubric.criteria.reduce((total, criterion) => {
    const raw = scores.get(criterion.id);
    if (raw === undefined || criterion.maxScore <= 0) return total;
    const clamped = Math.min(Math.max(raw, 0), criterion.maxScore);
    return total + (clamped / criterion.maxScore) * criterion.weight;
  }, 0);
}

export function isPassing(rubric: Rubric, score: number, scores?: ReadonlyMap<string, number>): boolean {
  if (score < rubric.passingScore) return false;
  const floor = rubric.minimumCriterionRatio;
  if (floor === undefined) return true;
  return rubric.criteria.every(c => (scores?.get(c.id) ?? 0) / c.maxScore >= floor);
}
