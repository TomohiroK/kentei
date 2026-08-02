# Kentei documentation

このフォルダは、インドネシア語検定・生活シミュレーション学習アプリの実装仕様を管理する。

## 文書一覧

| 文書 | 役割 |
| --- | --- |
| [product-specification.md](product-specification.md) | プロダクト目的、対象レベル、MVP機能、受入条件 |
| [ios-architecture.md](ios-architecture.md) | iOS構成、状態管理、永続化、音声、同期、テスト方針 |
| [design-system.md](design-system.md) | UI原則、色、文字、レイアウト、キャラクター、モーション、文体 |
| [screen-design-prototype.md](screen-design-prototype.md) | 実装済み画面、遷移、スクリーンショット、現在の実装境界 |
| [content-and-data-specification.md](content-and-data-specification.md) | 問題、音声、タグ、進捗、API、AI評価、分析イベント |
| [delivery-plan.md](delivery-plan.md) | 段階開発、Definition of Done、リスク、未確定事項 |
| [assets/character-reference.png](assets/character-reference.png) | キャラクターのデザイン参照資料 |
| [assets/generated-character-assets.md](assets/generated-character-assets.md) | プロトタイプ用派生素材、生成指示、品質確認、本番ゲート |

## ステータス

- 文書整理日: 2026-08-02
- プロダクト仕様: MVP実装開始に必要な範囲を確定
- iOS実装: 主要5タブと20問学習フローの画面デザインプロトタイプを実装
- 対象プラットフォーム: iOS 17以上
- 現在確認済みのローカルツールチェーン: Xcode 26.3 / Swift 6.2.4
- 正式アプリ名、Bundle ID、Signing Team、外部サービス、素材権利: 未確定

## 仕様の読み方

`product-specification.md` に記載された「確定仕様」が実装の基準である。「将来範囲」は先行実装しない。「決定ゲート」は、決定するまでプロバイダー固有コードや公開設定を追加しない。

元の詳細設計で「今回の設計整理」とされていた項目は、MVPの実装に必要なものだけ確定仕様へ取り込んだ。数値を運用検証で調整する項目は、設定値として扱い、コードへ埋め込まない。
