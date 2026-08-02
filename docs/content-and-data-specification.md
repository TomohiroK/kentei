# コンテンツ・データ仕様

## 1. コンテンツ階層

教材は三種類のタグを持つ。

### 行動タグ

```text
大分類 → 中分類 → 小分類 → 行動
```

例:

```text
空港 → 空港利用 → 荷物預け → 重量超過に対応する
```

### 検定タグ

- 級
- 語彙
- 文法
- 聴解
- 読解
- 発話
- 作文
- 時事
- 難易度
- 頻度
- 口語／標準語
- 正式／日常表現

### 教材種別タグ

- 単語
- 句
- 文
- 会話
- アナウンス
- ニュース
- ロールプレイ
- 面接
- 説明
- 要約

## 2. 生活図鑑

MVPカテゴリは空港、ワルン、コンビニ、Grabとする。将来カテゴリはホテル、レストラン、病院、薬局、銀行、SIM・通信、e-money、家・不動産、配送・郵便、警察、VISA・行政、税務署、学校、会社、工場、市場、美容院、修理、災害、ニュース・時事である。

カテゴリは次の情報を返す。

- 表示名とローカライズキー
- 達成率
- 習得済み・未習得行動
- 必要級
- 推奨語彙・文法
- 直近の復習対象
- 実戦チェック結果
- 解放条件

## 3. 問題スキーマ v1

```yaml
schema_version: 1
question_id: q-airport-e-000001
version: 1
level: e
question_type: audio_meaning_choice
prompt:
  audio_id: id-sentence-female-000001
  text: "Selamat pagi."
  image_id: null
choices:
  - choice_id: c1
    localized_text_key: question.q-airport-e-000001.choice.c1
    image_id: null
    is_correct: true
    distractor_reason: null
  - choice_id: c2
    localized_text_key: question.q-airport-e-000001.choice.c2
    image_id: null
    is_correct: false
    distractor_reason: semantic_neighbor
accepted_answers: []
explanation_key: question.q-airport-e-000001.explanation
tags:
  grammar: []
  vocabulary: [selamat_pagi]
  scenarios: [airport.greeting]
difficulty: 1
estimated_seconds: 12
speaker:
  gender: female
register: standard
ai_scoring:
  enabled: false
  rubric_id: null
status: approved
```

E〜C級では `prompt.text` が必須でも、通常の回答画面には渡さない表示モデルを作る。UIで隠すだけでなく、アクセシビリティツリーや分析ログにも漏らさない。

## 4. 列挙値

### `question_type`

- `audio_meaning_choice`
- `audio_image_choice`
- `response_choice`
- `grammar_function_choice`
- `ordering`
- `fill_in_blank`
- `content_match`
- `action_decision`
- `speaking`
- `summarization`
- `related_words`

### `distractor_reason`

- `similar_sound`
- `semantic_neighbor`
- `different_affix`
- `different_part_of_speech`
- `subject_object_reversed`
- `wrong_politeness`
- `wrong_context`
- `register_confusion`
- `known_common_error`

### `content_status`

```text
draft → content_review → language_review → audio_review → test_delivery → approved → published
```

`rejected` は各レビューから設定でき、理由を必須とする。公開済みコンテンツは上書きせず、新しい版を作る。`deprecated` は新規セッションへの利用を止めるが、過去回答の参照可能性を維持する。

## 5. 音声スキーマ

```yaml
schema_version: 1
audio_id: id-sentence-female-000001
language: id-ID
speaker_id: speaker-female-01
speaker_gender: female
audio_type: sentence
text: "Selamat pagi."
normalized_text: "Selamat pagi"
duration_ms: 1260
sample_rate: 44100
format: m4a
speed: 1.0
emotion: neutral
register: standard
version: 1
storage_path: audio/v1/id-sentence-female-000001.m4a
checksum: sha256:...
review_status: approved
```

IDの接頭辞:

- `id-word-female-000001`
- `id-word-male-000001`
- `id-sentence-female-000001`
- `id-dialogue-000001`

音声は単語、句、文、会話、長文、効果音、システム音声の単位で再利用する。

### 公開フロー

1. 教材テキスト登録
2. 正規化
3. 音声生成または収録
4. 自動検査
5. 人間による発音確認
6. 問題としての一意性確認
7. 承認・公開

自動検査は破損、無音、音量、異常な尺、話者、重複、生成版、チェックサムを確認する。人間は自然さ、接辞、数字、略語、固有名詞、区切り、正解の一意性を確認する。

## 6. セッション構成

20問の初期構成:

- 6問: 復習
- 8問: 現在のテーマ
- 4問: 弱点補強
- 2問: 実戦問題

各10問セットでは、認知負荷が連続して上がり続けないように並べる。完全ランダムにしない。話者は原則として女性・男性を交互にするが、会話の役割と自然さを優先する。

セッション作成時点で `session_questions` を固定し、コンテンツ更新が途中セッションの問題列を変更しないようにする。

## 7. 採点

### 固定問題

- 単一選択: 選択肢IDの完全一致
- 複数選択: 仕様で指定した場合のみ完全一致または部分点
- 並べ替え: 正規化済みトークン列の完全一致
- 自由入力: 正規化後の許容回答一致
- 音声画像選択: 選択肢ID一致

正規化は大文字小文字、余分な空白、句読点、承認済み綴り揺れ、口語、数字表記に限定する。意味を推測する生成AIを固定問題の正規化に使わない。

### 習得点

初期参考値:

```text
正解            +10
高速正解         +2
再生1回          +1
再生3回以上       0
不正解           -5
同一誤り反復      -3
実戦問題正解     +15
```

この数値は運用設定であり、コード定数ではない。設定版を各判定結果に記録し、係数変更前後の説明可能性を保つ。

## 8. 主要データモデル

```text
users
user_profiles
levels
scenarios
scenario_nodes
skills
vocabularies
grammar_points
learning_contents
questions
question_choices
question_tags
audio_assets
speakers
sessions
session_questions
answers
answer_events
mastery_states
skill_progress
scenario_progress
review_schedules
avatars
avatar_progress
ai_rubrics
ai_evaluations
content_versions
```

### `answers`

```text
id
idempotency_key
user_id
session_id
question_id
question_version
selected_choice_id
text_answer
audio_answer_id
is_correct
score
response_time_ms
audio_play_count
playback_speed
confidence
evaluated_by
scoring_config_version
created_at
```

### `mastery_states`

```text
id
user_id
target_type
target_id
state
mastery_score
last_answered_at
next_review_at
correct_streak
incorrect_streak
updated_at
```

`target_type` は語彙、文法、スキル、行動を表す閉じた列挙値として扱う。文字列で任意の対象型を追加しない。

## 9. API境界

初期契約:

```text
GET    /api/home
POST   /api/sessions
GET    /api/sessions/{id}
POST   /api/sessions/{id}/answers
POST   /api/sessions/{id}/complete
GET    /api/reviews
GET    /api/scenarios
GET    /api/scenarios/{id}
GET    /api/progress
```

管理・将来機能:

```text
GET    /api/admin/questions
POST   /api/admin/questions
PUT    /api/admin/questions/{id}
POST   /api/admin/audio/generate
POST   /api/admin/content/review
POST   /api/audio/upload
POST   /api/speech/transcribe
POST   /api/ai/evaluate
```

iOSクライアントは管理APIへアクセスしない。音声アップロードとAI評価は、B級以降の録音機能を導入するまでクライアントへ露出しない。

APIエラーは機械可読コード、ユーザー向けローカライズキー、再試行可否、追跡IDを返す。内部メッセージや秘密情報を返さない。

## 10. AI評価

AI評価はB級以上に限定する。評価結果は数値だけでなく次を含む構造化データとする。

- 総合点
- 課題達成、文法、語彙、発音、流暢さ、適切性
- 誤り、修正、理由
- 次の重点項目
- AIモデル、モデル版、プロンプト版、ルーブリック版
- 音声認識結果と認識信頼度
- 評価状態

評価状態:

```text
queued → transcribing → evaluating → completed
                              ↘ pending_reevaluation
                              ↘ needs_human_review
```

同一回答の再評価揺れ、地域差・口語差、音声認識誤りを検証する。重要な合否をAIだけで確定しないモードを用意する。

## 11. 分析イベント

追跡するイベント:

- `session_started`
- `question_presented`
- `audio_play_started`
- `audio_play_completed`
- `answer_submitted`
- `checkpoint_reached`
- `session_completed`
- `session_abandoned`
- `review_due_presented`
- `scenario_action_unlocked`
- `content_download_failed`
- `answer_sync_failed`
- `ai_evaluation_retried`
- `speech_recognition_failed`

分析にはユーザー回答本文、録音、アクセストークンを含めない。問題ID、版、イベント時刻、必要最小限の性能値、集計用属性を送る。

主要指標は、開始率、10問到達率、20問完了率、中間離脱率、再生回数、問題別正答率、誤答分布、回答時間、復習実施率、行動達成率、級別到達率、7日・30日継続率である。

