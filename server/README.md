# 採点中継サーバー

B級以上の記述課題を Claude で採点するための中継。**このサーバーが存在する理由は、
APIキーを端末へ置かないためである**（`docs/product-specification.md` §10「サーバー秘密鍵をアプリへ保存しない」）。

## 何をする / しない

やること:

- アプリからの提出（テキスト）を受け取り、基準に沿って採点して返す
- 外部へ出す前に、受け付けられない提出を弾く
- 重み付けと合否判定をサーバー側で決定的に計算する

やらないこと:

- 提出物・採点結果の保存（ステートレス。学習記録は端末内に置く設計のまま）
- 録音の受け取り（録音データ方針が決まるまで拒否する）
- ユーザー認証（決定ゲート）

## 構成

| ファイル | 役割 |
| --- | --- |
| `src/handler.ts` | 採点エンドポイント。HTTPの入口 |
| `src/rubric.ts` | 採点基準と重み計算。アプリ側と同じ版を保つ |
| `src/gate.ts` | 受け付け判定と呼び出し元の検証 |
| `src/scoring.ts` | Claude 呼び出し |
| `src/attestHandler.ts` | 端末登録エンドポイント（App Attest） |
| `src/attestation.ts` | チャレンジ発行・登録・提出の認可 |
| `src/attestStore.ts` | 鍵とカウンタの保存の抽象 |
| `src/redisAttestStore.ts` | 保存の Redis 実装 |
| `src/appattest/verify.ts` | Apple の attestation / assertion 検証 |
| `src/appattest/der.ts` | 証明書に埋め込まれた nonce の取り出し |
| `src/appattest/appleRootCA.ts` | Apple のルート証明書（埋め込み） |
| `scripts/extract-golden.py` | 基準回答の提出文を Swift の定義から取り出す |
| `scripts/measure-golden.mjs` | 基準回答の実測。期待範囲の較正に使う |
| `api/assess.js` `api/attest.js` | **デプロイ時の生成物**。`vercel-build` が esbuild で1ファイルずつまとめる。追跡しない |

### なぜバンドルするのか

Vercel の Node ランタイムは `api/*.ts` を個別にコンパイルするが、
`./gate.ts` のような拡張子付きの import 指定子をそのまま出力するため、
実行時に `ERR_MODULE_NOT_FOUND` になる。ローカルの `vercel dev` は型ストリップが効くので
再現せず、**本番でだけ落ちる**。

依存の解決をビルド時に閉じるため、`src/handler.ts` を起点に1ファイルへまとめて配置する。

## 採点の設計

- モデルは **`claude-sonnet-5`**。変更する場合は基準回答の回帰試験を通してから切り替える
- 構造化出力（Zodスキーマ）で「観点ごとの整数スコアと短評」だけを返させる
- **重み付けと合否はサーバーが計算する。** モデルに算術と閾値判定をさせない。
  同じ素点からは必ず同じ正規化スコアになり、採点の再現性を保てる
- 応答には使用したモデル版とルーブリック版を必ず含める

## 拒否する条件

| 条件 | 応答 |
| --- | --- |
| POST 以外 | 405 |
| クライアントトークン不一致 | 401 |
| トークン未設定（サーバー側） | 503 |
| 録音を含む提出 | 400 `recording_not_available` |
| 基準の版がアプリと違う | 409 `rubric_version_mismatch` |
| 課題種別が基準と違う | 409 |
| 本文が空 / 長すぎる | 400 / 413 |
| APIキー未設定 | 503 |

版がずれたまま採点しないのは、**結果に記録した版と実際の基準を一致させる**ためである。
アプリとサーバーを同じリポジトリに置いているのも同じ理由による。

## 呼び出し元の検証

現在は共有トークン（`KENTEI_CLIENT_TOKEN`）による検証である。**これは暫定措置**で、
トークンはアプリのバイナリから取り出せるため、これ単体では第三者の利用を防げない。

App Attest による端末確認は**サーバー側の実装と試験を終えている**が、有効化できていない。
無料の Personal Team では App Attest の権限が取得できず、有料の Apple Developer Program
が必要なためである。詳細と有効化手順は `docs/device-attestation.md` を参照。

`KENTEI_REQUIRE_ATTESTATION=true` を設定したときだけ端末確認を強制する。
設定漏れで静かに保護が外れることを避けるため、既定では強制しない。

### 端末確認の流れ（有効化後）

| 要求 | 内容 |
| --- | --- |
| `POST /api/attest` `{"action":"challenge"}` | 使い捨てのチャレンジを発行する |
| `POST /api/attest` `{"action":"register",...}` | attestation を検証して公開鍵を保存する |
| `POST /api/assess` + 3つのヘッダ | `x-kentei-key-id` `x-kentei-assertion` `x-kentei-challenge` |

assertion が署名する文字列は `<チャレンジ>:<提出ID>` である。
Vercel が本文を解析するため、本文のバイト列の完全な再現には依存させていない。

## 採点の較正

面接の合成基準回答は `scripts/interview-candidates.json` に置く。質問はアプリの `Localizable.xcstrings` から読み、初問・掘り下げとUIの文言を一致させる。端末の録音・下書き・個人の回答は読み込まない。

```bash
node --experimental-strip-types scripts/interview-calibration.mjs
node --experimental-strip-types scripts/interview-calibration.mjs --live --runs=2
```

既定はオフライン検証のみ。`--live` は既存の `server/.env.local` のキーを使って課金APIを呼ぶ。同時実行は2件、各呼出し60秒まで、SDK自動再試行なし。認証・通信エラー時は新たな採点を停止する。出力はケースID・観点得点・合否等だけで、キー、本文、SDKエラー本文は出さない。`--case=b-0-pass --runs=1` で最初に1件確認できる。期待した合否との不一致・未完了は非ゼロ終了とする。この基本例の通過は境界回答の較正や公式採点との一致を保証しない。

期待範囲は推測で決めず、実測してから決める。手順と測定結果は
`docs/assessment-calibration.md` にある。

```bash
python3 scripts/extract-golden.py
node --experimental-strip-types scripts/measure-golden.mjs scripts/golden-candidates.json 5
```

モデル・プロンプト・ルーブリックのいずれかを変えたら測り直す。

## 環境変数

| 変数 | 用途 |
| --- | --- |
| `ANTHROPIC_API_KEY` | Claude API のキー |
| `KENTEI_CLIENT_TOKEN` | アプリからの呼び出しを識別する暫定トークン |
| `KENTEI_REQUIRE_ATTESTATION` | `true` のとき端末確認を強制する。既定は強制しない |
| `KENTEI_ORAL_ASSESSMENT_READY` | 既定は無効。`true` のとき専用基準に一致するスピーチ・面接のテキストを受け付ける |
| `KENTEI_TEAM_ID` | Apple の Team ID（端末確認に使う） |
| `KENTEI_BUNDLE_ID` | アプリの Bundle ID（端末確認に使う） |
| `KENTEI_ALLOW_DEVELOPMENT_ATTESTATION` | 開発ビルドを受け入れる間だけ `true` |
| `KV_REST_API_URL` / `KV_REST_API_TOKEN` | 鍵とカウンタの保存先（未提供） |

値はリポジトリへ入れない。Vercel の環境変数、またはローカルの `.env.local`（gitignore 済み）に置く。

発話採点はClaudeアカウントの保持条件確認と専用基準の較正が完了するまで有効化しない。スピーチ `oral-2026-09-v1` と面接 `interview-2026-09-v2` は未較正の開発案であり、作文の較正結果を代用しない。面接は75％以上かつ各観点30％以上。不完全・重複・範囲外の発話採点結果はエラーとし0点に補完しない。iOS側も現在はローカル保存のみで、サーバーフラグだけではアプリの送信は開始しない。フラグにかかわらず音声データ・音声参照は受け付けない。

```bash
vercel env add ANTHROPIC_API_KEY production
```

## ローカル確認

```bash
npm install
```

```bash
npm run typecheck && npm test && npm run vercel-build
```

APIキーなしでも、受け付け判定・重み計算・HTTPの配線は検証できる。
実際の採点まで確かめる場合は `.env.local` にキーを置いて `vercel dev` を使う。

## デプロイ

```bash
cd server && vercel --prod --scope tomohiros-projects-47a483a4
```

Vercel プロジェクトの Root Directory は `server` に設定する。
push 経由のデプロイは使わない（`.claude/rules/local-first-then-push.md`）。
