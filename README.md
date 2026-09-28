# Configlue README 日本語生成ベンチマーク

このフォルダは、**opencode で利用できる各モデルがどれだけ自然な日本語の技術文書を書けるか**を比較するための実験記録です。題材として OSS の .NET ライブラリ [Configlue](https://github.com/arika0093/Configlue) の README 解説を各モデルに書かせ、結果を保存しています。

## 目的

- モデルごとの日本語ドキュメント生成の品質（自然さ・構成・正確さ）を比較する。
- 同一の入力コンテキストを与え、条件だけを変えた2つの指示で挙動の差を見る。

## 手法

1. このセッションのモデル（`opencode-go/deepseek-v4.1-flash`）が Configlue リポジトリを調査し、共通コンテキスト `context.md`（README・設計ドキュメント・公開 API・パッケージ一覧などを要約）を作成。
2. 同じ `context.md` を添付して、各モデルに README 用の日本語解説を書かせる。
3. 生成結果を `output/` に保存する。

対象モデルは「各ファミリーの最新版」23件です（`opencode/` と `opencode-go/` の2プロバイダ）。

## run1 と run2 の違い

| | run1 | run2 |
| --- | --- | --- |
| 指示 (`instruction.md`) | 詳細な要件付き（3部構成、日本語、創作禁止、Markdownのみ、ツール使用禁止など） | **2文のみ**（下記） |
| 出力の受け取り方 | ツール使用禁止。最終メッセージの Markdown をそのまま保存 | ファイル生成を許可。モデルが `README.md` を実際に作成 |
| 成果物 | チャット本文 | `README.md`（生成できた場合）／チャット本文（しなかった場合） |
| 実行補助 | `run-bench.ps1` | `run-bench2.ps1`（`opencode.json` で bash 等を deny） |

run2 の指示文は次の2文だけです。

> 添付の context.md は .NET ライブラリ「Configlue」の調査メモです。これを唯一の情報源として、Configlue の README に載せる日本語解説を作成してください。

## ディレクトリ構成

```text
configlue-readme-bench/
├── README.md                     このファイル（取り組みの説明）
├── run1/
│   ├── context.md                共通コンテキスト（調査メモ）
│   ├── instruction.md            詳細な指示
│   ├── run-bench.ps1             実行スクリプト
│   └── output/
│       ├── _summary.md           モデル別メトリクス一覧
│       ├── combined-all.md       全モデル出力の連結（読み比べ用）
│       ├── <model>.md            各モデルの生成結果
│       └── <model>.metrics.txt   秒数・トークン・コスト
└── run2/
    ├── context.md                共通コンテキスト（run1 と同一）
    ├── instruction.md            最小の指示（2文のみ）
    ├── opencode.json             run2 用の権限設定（edit=allow, bash 等=deny）
    ├── run-bench2.ps1            実行スクリプト
    ├── files/                    ★ モデルが実際に生成したファイル（<model>/ 配下に保存）
    └── output/
        ├── _summary.md
        ├── combined-all.md
        ├── <model>.md            最終成果物（README.md or チャット本文）
        └── <model>.metrics.txt
```

`<model>` は `opencode-go/deepseek-v4.1-flash` のような ID を `opencode-go-deepseek-v4.1-flash` のように平坦化した名前です。

## 結果の見方

- まず `run1/output/_summary.md` と `run2/output/_summary.md` で一覧を確認。
- 読み比べは `run1/output/combined-all.md` / `run2/output/combined-all.md` が便利。
- run2 でモデルが作った実ファイルは `run2/files/<model>/` にあります（run1 はチャット出力のみなので該当なし）。

## 再実行方法

`opencode` の実体（`opencode.exe`）を解決したうえで、各スクリプトを実行します。モデル一覧はスクリプト内 `$models` を編集してください。

```powershell
# run1（詳細指示・ツール禁止・チャット出力を保存）
pwsh -File .\run1\run-bench.ps1

# run2（最小指示・ファイル生成を許可）
pwsh -File .\run2\run-bench2.ps1
```

## 出典

- 題材: [Configlue](https://github.com/arika0093/Configlue)（Apache-2.0）
- `context.md` は上記リポジトリの README および `docs/` を要約したものです。
