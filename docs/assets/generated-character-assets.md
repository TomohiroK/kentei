# 生成キャラクター素材記録

## 目的

`character-reference.png` を造形の正として、画面デザインプロトタイプで使う透過PNGを作成した。元の設定資料そのものを切り抜かず、表情・ポーズ別の派生素材として管理する。

## 出力

| Asset Catalog名 | 用途 | ポーズ |
| --- | --- | --- |
| `CompanionListening` | ホーム以外の待機、問題の聞き取り | 正面、穏やかな表情、両手を下ろす |
| `CompanionEncourage` | ホーム、再挑戦、新しい行動 | 正面、片方の肉球を見せて手を振る |
| `CompanionHappy` | 中間結果、総合結果、小さな成功 | 正面、両方の肉球を上げて笑う |

アプリ内ファイルは `Kentei/Resources/Assets.xcassets/Companion*.imageset/` に置く。

## 共通生成指示

```text
Create a production-ready iOS UI character asset derived strictly from the attached authoritative character sheet. Preserve the exact same photorealistic fluffy white and light silver-gray kitten, round face, oversized glossy green-teal eyes, soft pink nose and paw pads, upright ears, short chibi proportions, turquoise hoodie, white drawstrings, small white fish emblem, realistic fur and warm friendly personality. Do not redesign, stylize, cartoonize, age, recolor, or change species. Use one centered full-body character with generous padding, no crop, no text, no props, no watermark, and a perfectly flat chroma-key background.
```

各素材では上記に表のポーズを追加した。ピンクの鼻・肉球を保護するため、励まし・祝福は純青 `#0000FF`、通常は純マゼンタ `#FF00FF` を背景に生成し、背景色だけをアルファへ変換した。

## 品質確認

- 白〜薄灰の毛色、大きな緑〜青緑の瞳、ピンクの鼻と肉球を維持
- ターコイズのパーカー、白い紐、白い魚のワンポイントを維持
- 毛先の透過境界をライト／ダーク画面で確認
- ホーム、問題、中間結果、総合結果、日本語、インドネシア語、大きな文字で表示確認

## 本番ゲート

本番利用前に、参照画像と派生画像の出典、権利者、生成条件、商用利用可否を確認する。確認が完了するまで、これらは画面デザインプロトタイプ用素材として扱う。
