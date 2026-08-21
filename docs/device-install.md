# 実機インストールと署名

## 1. 確定済みの署名設定

| 項目 | 値 |
| --- | --- |
| アプリ Bundle ID | `com.tomohirok.kentei` |
| テスト Bundle ID | `com.tomohirok.kentei.tests` |
| Signing Team | `MZV3DAL469`（TOMOHIRO KOYANO） |
| 署名方式 | Automatic |
| アカウント種別 | 無料（Personal Team） |

`com.example.*` はシミュレーター用プロトタイプの名残であり、現在は使用しない。

## 2. 無料アカウントの制約

無料の Personal Team には、実機配布に関する制約がある。

| 制約 | 内容 | 影響 |
| --- | --- | --- |
| プロビジョニングプロファイルの有効期限 | 発行から **7日** | 8日目以降、実機のアプリが起動しなくなる |
| 1台あたりのアプリ数 | **3つまで** | 4つ目を入れるには、どれかを削除する |
| 配布 | TestFlight・App Store は不可 | 端末を接続して直接インストールする |

「証明書の期限が切れました」と表示されて起動できなくなるのは、証明書ではなく
このプロファイルの7日制限による。**署名証明書自体の有効期限は約1年**で、別物である。

有料の Apple Developer Program に加入するとプロファイルは1年有効になり、
アプリ数の制限もなくなる。加入手続きは本人が行う必要がある。

## 3. 再インストール手順（7日ごと）

端末を Mac に接続し、リポジトリのルートで次を実行する。

```bash
xcodebuild -project Kentei.xcodeproj -scheme Kentei \
  -destination 'platform=iOS,id=<デバイスUDID>' \
  -derivedDataPath build -allowProvisioningUpdates build
```

```bash
xcrun devicectl device install app --device <デバイスUDID> \
  build/Build/Products/Debug-iphoneos/Kentei.app
```

デバイスUDIDは次で確認する。

```bash
xcrun xctrace list devices
```

初回のみ、端末側で「設定 → 一般 → VPNとデバイス管理」からデベロッパを信頼する。

## 4. インストールに失敗する場合

| 症状 | 原因 | 対応 |
| --- | --- | --- |
| `maximum number of installed apps using a free developer profile` | 1台3アプリの上限 | 不要なデベロッパアプリを端末から削除する |
| 起動直後に「デベロッパを検証できません」 | デベロッパ未信頼 | 設定 → 一般 → VPNとデバイス管理 で信頼する |
| 8日目以降に起動しない | プロファイル期限切れ | 上記の再インストールを実行する |

## 5. 学習データへの影響

再インストールでもアプリを削除しなければ、保存済みの学習セッションは残る。
アプリを削除した場合、および教材パックの版が変わった場合は、
保存済みセッションは復帰対象から外れ、次の学習は最初から始まる。
