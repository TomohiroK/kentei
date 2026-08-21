# iOSアーキテクチャ

## 1. 技術ベースライン

- UI: SwiftUI
- 最低OS: iOS 17
- 言語: Swift 6、Strict Concurrencyを有効化
- 現在確認済みツールチェーン: Xcode 26.3 / Swift 6.2.4
- 永続化: SwiftDataを第一候補とし、リポジトリ越しに利用
- 通信: `URLSession` と `Codable`
- 音声再生・録音: AVFoundation
- ローカライズ: String Catalog
- テスト: Swift TestingまたはXCTest。UIテストはXCUITest
- 外部依存: MVPは0を既定とし、必要性と保守性を説明できる場合のみ追加

iPhone縦向きを最初の完成形とする。iPadは同じSwiftUI階層で安全に伸縮させるが、MVPで独自の三列画面を作らない。横向きを禁止するかは、実際の学習画面検証後に決める。

## 2. プロジェクト構造

初期は単一アプリターゲット、単体テストターゲット、UIテストターゲットで構成する。ビルド時間や再利用境界が実測で必要になるまで、ローカルパッケージへ分割しない。

```text
Kentei/
├── App/
├── Core/
│   ├── Audio/
│   ├── Networking/
│   ├── Persistence/
│   ├── Localization/
│   └── Observability/
├── Domain/
│   ├── Learning/
│   ├── Content/
│   ├── Progress/
│   └── Account/
├── Data/
│   ├── API/
│   ├── Stores/
│   └── Repositories/
├── DesignSystem/
├── Features/
│   ├── Onboarding/
│   ├── Home/
│   ├── LearningSession/
│   ├── ScenarioAtlas/
│   ├── Results/
│   └── Settings/
└── Resources/
```

FeatureはCoreやDataの具体実装を直接生成せず、Domainで定義したプロトコルを環境から受け取る。

現在の実装は上記の骨格のうち、必要になった部分だけを作っている。

```text
Kentei/
├── App/            KenteiApp, RootView, AppModel
├── Core/           SystemDependencies（時計・識別子）, LearningPreferences
├── Domain/         LearningSessionState, LearningSessionSnapshot, QuestionAudio
├── Data/           LearningSessionStore, SpeechQuestionAudioPlayer
├── DesignSystem/   KenteiTheme, KenteiComponents
├── Features/       Home, Learning, ScenarioAtlas, Supporting
└── Resources/      Assets.xcassets, Localizable.xcstrings
```

## 3. レイヤー責務

### Domain

Foundation以外への依存を最小化し、次を保持する。

- 型付きIDと列挙値
- 問題、セッション、回答、習得、行動のモデル
- 固定問題の採点
- セッション状態遷移
- 復習優先度と行動解放ルール
- リポジトリと時計等のプロトコル

### Data

- APIレスポンスとDomainモデルの変換
- SwiftDataモデルとDomainモデルの変換
- コンテンツパックの検証・適用
- オフラインキューと同期
- 音声ファイルのキャッシュ

API用DTO、永続化モデル、Domainモデルを同じ型にしない。サーバー変更や保存移行をUIへ波及させないためである。

### Features

- 画面固有の状態とユーザー操作
- Domainユースケースの呼び出し
- ローディング、空、内容、回復可能エラーの表示
- ナビゲーション状態

### DesignSystem

- 色、文字、余白、角丸、影
- ボタン、カード、進捗、選択肢、音声操作
- キャラクター表示と表情状態
- アクセシビリティ共通処理

## 4. 学習セッション状態機械

画面遷移は複数のBooleanではなく、関連値を持つ列挙型で表す。

```swift
enum LearningSessionPhase: Equatable, Sendable {
    case preparing
    case warmup
    case answering(QuestionPosition)
    case reviewing(AnswerFeedback)
    case midpoint(SessionCheckpoint)
    case answeringSecondSet(QuestionPosition)
    case finalResult(SessionResult)
    case paused(SessionResumePoint)
    case recoverableFailure(SessionFailure)
    case completed
}
```

許可する代表遷移:

```text
preparing → warmup → answering
answering 10問完了 → midpoint
midpoint → answeringSecondSet
answeringSecondSet 10問完了 → finalResult → completed
任意の回答前状態 → paused → 保存済み位置へ復帰
通信・音声取得失敗 → recoverableFailure → 同じ位置で再試行
```

回答確定処理は次の順で行う。

1. 回答をDomainで評価する。
2. 回答とイベントを一つのローカルトランザクションで保存する。
3. 画面へフィードバックを公開する。
4. 同期対象をキューへ追加する。
5. 次問音声の利用可能性を確認する。

サーバー応答待ちで固定問題の次画面を止めない。

## 5. 主要Domain型

文字列IDを画面全体へ渡さない。

```swift
struct QuestionID: Hashable, Codable, Sendable { let rawValue: UUID }
struct SessionID: Hashable, Codable, Sendable { let rawValue: UUID }
struct ScenarioNodeID: Hashable, Codable, Sendable { let rawValue: String }

enum ExamLevel: String, Codable, Sendable {
    case e, d, c, b, a
}

enum QuestionType: String, Codable, Sendable {
    case audioMeaningChoice
    case audioImageChoice
    case responseChoice
    case grammarFunctionChoice
    case ordering
    case fillInBlank
    case contentMatch
    case actionDecision
    case speaking
    case summarization
    case relatedWords
}
```

E〜D級MVPで到達不能な形式はパーサーで認識できても、セッション作成時に明示的に拒否する。

## 6. 永続化

### ローカル保存対象

- アクティブセッションと復帰位置
- 回答と回答イベント
- 習得状態と復習予定
- シナリオ・スキル進捗
- コンテンツパックの版とチェックサム
- 音声キャッシュ索引
- ユーザー設定
- 未同期操作キュー

各回答を保存してから画面進行する。アプリ強制終了時に、未回答の表示位置だけを破棄し、確定済み回答は保持する。

保存モデルには `schemaVersion` を持たせる。モデル変更時は、旧バージョンの代表データからの移行、途中セッション復元、ロールバック不能条件をテストする。

### 実装状況

`LearningSessionSnapshot`（`schemaVersion = 1`）を `FileLearningSessionStore` が
Application Support 配下へアトミックに書き込む。保存の起点は `LearningSessionModel` で、
回答確定・区切り通過・再挑戦のたびに保存し、保存順序は直列につなぐ。

- 未確定の選択は保存しない。復帰は常に確定済み回答の次の問題から始まる。
- 保存済みデータは次の場合に復帰させず破棄する: `schemaVersion` 不一致、
  教材パックの版違い、出題順の不一致、存在しない問題・選択肢の参照、同一問題の重複回答。
- 保存ファイルが壊れている場合は `LearningSessionStoreError.corruptedData` として扱い、
  破棄して新規セッションから始められる状態へ戻す。
- 保存に失敗した場合は学習画面に警告を表示する。失敗を黙って握りつぶさない。
- セッション完了（総合結果の「終わる」）で保存データを破棄する。

## 7. コンテンツ配信とオフライン

教材はバージョン付きコンテンツパックとして扱う。

```text
manifest.json
questions.json
contents.json
tags.json
audio-manifest.json
```

マニフェストには、版、公開日時、最低アプリ版、ファイルサイズ、チェックサムを含める。適用手順はダウンロード、チェックサム検証、デコード検証、一時領域への保存、原子的切替とする。検証失敗時は現在の有効版を保持する。

セッション開始時には最初の10問と音声を利用可能にする。学習中に後半10問を先読みする。通信断の場合、取得済みセットを完了できるようにし、未取得の後半へ進む前に回復可能な案内を出す。

## 8. 音声

`AudioPlaybackClient` をDomain境界に置き、AVFoundationの具体実装をCoreに閉じ込める。

必要な振る舞い:

- ローカルキャッシュ優先、ネットワーク取得のフォールバック
- 自動再生と手動再生
- 0.8倍、1.0倍
- 再生開始、完了、中断、失敗イベント
- 次問の先読み
- オーディオセッションの中断・経路変更
- 画面離脱時の停止とタスクキャンセル

再生回数は、再生開始が実際に成功した時点で加算する。先読みや失敗した開始は再生回数へ含めない。

### 実装状況

`QuestionAudioPlaying`（Domain）に対する実装は `SpeechQuestionAudioPlayer` で、
端末内の音声合成でインドネシア語を読み上げる **暫定実装** である。教材の正式音声
（2話者の録音）が確定するまでの代替であり、合成音声を基準記録として扱わない。

- 0.8倍 / 1.0倍を設定として保持し、学習画面と設定画面のどちらからも変更できる。
- 自動再生は設定で切り替える。問題が変わるたびに再生を開始する。
- 再生中に次の再生要求が来た場合、前の再生を止めてから始める。多重再生しない。
- 画面離脱・問題送り・セッション終了で再生を止め、再生タスクをキャンセルする。
- オーディオセッションの中断（電話・Siri 等）を購読し、中断は失敗として表示しない。
- 端末にインドネシア語の音声が無い場合は、追加方法を案内する文言を表示する。
- 発話の区切りを `onSpeechMark` で通知し、キャラクターの口の動きへ同期させる。

実音声アセットへ移行するときは、同じプロトコルの別実装を用意し、
`prepare(_:)` を次問の先読みに使う。

録音を導入するB級以降では、マイク権限を録音操作の直前に説明して要求し、拒否・制限・許可を分けて表示する。

## 9. ネットワークと同期

`APIClient` はactorとして実装し、型付きリクエストとレスポンスを使用する。

- 2xx以外を成功デコードしない。
- 通信、認証、サーバー、レート制限、デコード、キャンセルを区別する。
- 読み取りは限定的に再試行できる。回答送信は冪等キーなしに自動再送しない。
- ログからトークン、録音URL、回答本文、個人情報を除外する。

回答同期の冪等キーは、ユーザー、セッション、問題、回答試行を一意に表す。ローカル保存済み回答は、サーバー確認後にのみ同期済みへ変更する。

バックエンド、認証、データベース、オブジェクトストレージの提供者は決定ゲートであり、本仕様では固定しない。決定前にプロバイダーSDKをクライアントへ直接追加しない。

## 10. ナビゲーション

トップレベルは `TabView` を基本とする。

- ホーム
- 学ぶ
- 生活図鑑
- 進捗
- 設定

アクティブな学習セッションは独立したフローとして表示し、誤ってタブ移動した際に状態を失わない。終了操作には未回答位置が保存されることを伝える。ナビゲーションパスは必要な範囲で復元可能にするが、古いコンテンツ版の存在しない画面はホームへ安全に戻す。

## 11. エラー表示

エラーはユーザーが次に行える操作を持つ。

| 状況 | 表示・操作 |
| --- | --- |
| 音声取得失敗 | 同じ問題で再試行、接続案内、取得済み問題へ戻る |
| コンテンツ破損 | 旧版を維持し再ダウンロード |
| 回答同期失敗 | 学習は継続し、未同期表示と自動再送 |
| 認証期限切れ | ローカル進捗を保持して再認証 |
| AI採点不能 | `pendingReevaluation` として再評価、0点にしない |

## 12. テスト戦略

### 単体テスト

- 10問・20問境界の状態遷移
- 二重タップで回答が一度だけ保存されること
- 途中離脱と復帰
- 固定問題の各採点形式
- 習得状態と復習期限
- 行動解放条件
- コンテンツ版とチェックサム拒否
- 同期の冪等性、失敗、キャンセル

### UIテスト

- オンボーディングから最初の20問完了
- 10問時の中間結果、20問時の総合結果
- アプリ再起動後の途中復帰
- 日本語・インドネシア語
- Dynamic Type最大付近、VoiceOver用ラベル
- オフライン10問と再接続同期

### 実機確認

- 音声の初動と連続再生
- スピーカー、イヤホン、Bluetooth切替
- 電話・Siri等による中断と復帰
- 録音導入後のマイク権限と録音品質

