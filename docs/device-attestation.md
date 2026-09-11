# 端末確認（App Attest）

## 現状

**有効化できていません。** 無料の Personal Team では App Attest の権限が取得できないためです。

```
error: Cannot create a iOS App Development provisioning profile for "com.tomohirok.kentei".
       Personal development teams do not support the App Attest capability.
```

有効化には **Apple Developer Program（有料・年99ドル）** への加入が必要です。
それまでの間、採点サーバーは共有トークンで保護されています。

## トークンの持ち方

利用者に入力を求めない。トークンは開発中の都合であって、学習者が知る必要のあるものではない。

| 取得元 | 内容 |
|---|---|
| アプリに同梱 | `Secrets/assessment-token.txt`（追跡対象外）からビルド時に埋め込む |
| この端末に保存 | 以前に保存された値（Keychain）。同梱が無いときだけ使う |
| なし | 採点だけができない。作文は書けて、端末に残る |

同梱の値は端末側の値より優先し、アプリからは書き換えない。どちらが使われているか
追えなくなるためである。状態は設定画面に表示する（値そのものは表示しない）。

ファイルが無い環境でもビルドと起動は通る。詳細は `Secrets/README.md`。

## 共有トークンの限界

| 守れるもの | 守れないもの |
|---|---|
| 無差別なアクセス | トークンを知った第三者の利用 |
| 総当たりの呼び出し | 端末が本物のアプリかどうかの判別 |

配布するアプリにこの方式のまま採点機能を載せることはできません。
アプリを解析すればトークンは取り出せるためです。

## サーバー側の準備状況

App Attest の検証はすでに実装・試験済みで、有料化後に設定だけで有効になります。

| 部品 | 状態 |
|---|---|
| `src/appattest/verify.ts` | Attestation / Assertion の検証。実装済み |
| `src/appattest/der.ts` | 証明書に埋め込まれた nonce の取り出し。実装済み |
| `src/appattest/appleRootCA.ts` | Apple のルート証明書（埋め込み）。取得済み |
| `src/attestation.ts` | チャレンジ発行・登録・提出の認可。実装済み |
| `src/attestHandler.ts` | `/api/attest` エンドポイント。実装済み |
| `src/redisAttestStore.ts` | 鍵とカウンタの保存。実装済み（保存先は未提供） |
| 試験 | 18件（署名の改ざん・使い回し・別アプリ・別鍵・壊れた入力） |

検証は Apple の手順どおり、以下をすべて確認します。1つでも省くと別のアプリや
改ざんされた要求を通してしまうため、省略はしていません。

1. 証明書チェーンを Apple のルート証明書まで検証する
2. サーバーが発行したチャレンジから nonce を再計算し、証明書の拡張と一致させる
3. 公開鍵の SHA-256 が鍵IDと一致することを確認する
4. authData のアプリIDハッシュが `TeamID.BundleID` と一致することを確認する
5. aaguid が本番か開発かを判別し、許可した環境だけを受け入れる
6. Assertion の署名をチャレンジと提出IDに対して検証する
7. カウンタが前回より進んでいることを確認し、不可分に更新する

## 有効化の手順（有料化後）

1. Apple Developer Program に加入する
2. `Kentei/Kentei.entitlements` を対象に加える（アプリ本体の Debug / Release のみ）

   ```
   CODE_SIGN_ENTITLEMENTS = Kentei/Kentei.entitlements;
   ```

3. 配布時は entitlements の値を `development` から `production` に変える
4. 保存先（Upstash Redis 等）を用意し、環境変数を設定する

   | 変数 | 内容 |
   |---|---|
   | `KV_REST_API_URL` | 保存先の URL |
   | `KV_REST_API_TOKEN` | 保存先のトークン |
   | `KENTEI_TEAM_ID` | `MZV3DAL469` |
   | `KENTEI_BUNDLE_ID` | `com.tomohirok.kentei` |
   | `KENTEI_ALLOW_DEVELOPMENT_ATTESTATION` | 開発ビルドを受け入れる間だけ `true` |
   | `KENTEI_REQUIRE_ATTESTATION` | 端末確認を強制するとき `true` |

5. アプリ側に `DCAppAttestService` の処理を実装する（未着手）

`KENTEI_REQUIRE_ATTESTATION` は明示的に `true` にしたときだけ強制されます。
設定漏れで静かに保護が外れることを避けるためです。

## 通信の流れ（有効化後）

```
アプリ                                  サーバー
  |  POST /api/attest {action:challenge}   |
  |--------------------------------------->|  使い捨てのチャレンジを発行
  |<---------------------------------------|
  |  初回のみ: 鍵を生成し attestKey         |
  |  POST /api/attest {action:register}     |
  |--------------------------------------->|  証明書チェーンと nonce を検証し
  |<---------------------------------------|  公開鍵を保存
  |                                         |
  |  提出ごと: generateAssertion            |
  |  POST /api/assess + 3つのヘッダ          |
  |--------------------------------------->|  署名とカウンタを確認して採点
  |<---------------------------------------|
```

Assertion が署名する文字列は `<チャレンジ>:<提出ID>` です。
Vercel が本文を解析するため、本文のバイト列の完全な再現には依存させていません。
