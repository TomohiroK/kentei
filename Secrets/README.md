# Secrets

採点サーバーの呼び出しトークンを置く場所。**このフォルダの中身は追跡しない**（この README を除く）。

## assessment-token.txt

```
Secrets/assessment-token.txt
```

呼び出しトークンだけを1行で書く。引用符や変数名は書かない。

ビルド時に `Embed assessment token` フェーズがこの値を読み、アプリ内の
`AssessmentSecrets.plist` に埋め込む。ファイルが無ければ何も埋め込まれず、
アプリはトークンなしで動く（採点だけができない）。

## なぜこの形か

- **入力を求めない**: 設定画面での手入力は開発中の負担でしかない。会員機能ができれば
  トークン自体が不要になるため、UIを作り込まない
- **リポジトリに入れない**: 値が履歴に残ると、消しても取り出せる
- **無くてもビルドできる**: ファイルが無い環境でもビルドと起動が通る。
  採点だけが使えない状態になり、その旨がアプリ内に表示される

## 値の取得元

Vercel の環境変数 `KENTEI_CLIENT_TOKEN` と同じ値を使う。

```bash
vercel env pull --environment production
```
