# Configlue README 日本語生成ベンチマーク

このフォルダは、**opencode で利用できる各モデルがどれだけ自然な日本語の技術文書を書けるか**を比較するための実験記録です。題材として OSS の .NET ライブラリ [Configlue](https://github.com/arika0093/Configlue) の README 解説を各モデルに書かせ、結果を保存しています。

## 目的

- モデルごとの日本語ドキュメント生成の品質（自然さ・構成・正確さ）を比較する。
- 同一の入力コンテキストを与え、条件だけを変えた複数の指示で挙動の差を見る。

## 手法

1. このセッションのモデル（`opencode-go/deepseek-v4.1-flash`）が Configlue リポジトリを調査し、共通コンテキスト `context.md`（README・設計ドキュメント・公開 API・パッケージ一覧などを要約）を作成。
2. 同じ `context.md` を添付して、各モデルに README 用の日本語解説を書かせる。
3. 生成結果を各 run の `output/` に保存する。

対象モデルは「各ファミリーの最新版」23件です（`opencode/` と `opencode-go/` の2プロバイダ）。

## run1 / run2 / run3 の違い

| | run1 | run2 | run3 |
| --- | --- | --- | --- |
| 指示の言語 | 日本語 | 日本語 | **英語** |
| コンテキストの言語 | 日本語 | 日本語 | **英語** |
| 指示 (`instruction.md`) | 詳細な要件付き | **2文のみ** | **1文のみ**（run2 の英訳） |
| 出力の受け取り方 | ツール使用禁止。最終メッセージを保存 | ファイル生成を許可（`README.md` を実際に作成） | 同左（run2 と同じ） |
| 成果物 | チャット本文 | `README.md`（生成できた場合）／チャット本文 | 同左 |
| 実行補助 | `run-bench.ps1` | `run-bench2.ps1`（`opencode.json` で bash 等を deny） | `run-bench3.ps1`（run2 と同一設定） |

run2 の指示文（日本語）:

> 添付の context.md は .NET ライブラリ「Configlue」の調査メモです。これを唯一の情報源として、Configlue の README に載せる日本語解説を作成してください。

run3 の指示文（英語）:

> The attached context.md is a research memo on the .NET library "Configlue". Using it as the only source of information, create a Japanese explanation to include in Configlue's README.

## ディレクトリ構成

```text
configlue-readme-bench/
├── README.md                     このファイル（取り組みの説明）
├── run1/                         [日本語コンテキスト + 詳細な日本語指示・ツール禁止]
│   ├── context.md
│   ├── instruction.md
│   ├── run-bench.ps1
│   └── output/  _summary.md / combined-all.md / <model>.md / <model>.metrics.txt
├── run2/                         [日本語コンテキスト + 最小の日本語指示・ファイル生成]
│   ├── context.md
│   ├── instruction.md
│   ├── opencode.json             edit=allow, bash 等=deny
│   ├── run-bench2.ps1
│   ├── files/                    ★ モデルが実際に生成したファイル（<model>/ 配下）
│   └── output/  _summary.md / combined-all.md / <model>.md / <model>.metrics.txt
└── run3/                         [英語コンテキスト + 最小の英語指示・ファイル生成]
    ├── context.md
    ├── instruction.md
    ├── opencode.json             run2 と同一
    ├── run-bench3.ps1
    ├── files/                    ★ モデルが実際に生成したファイル（<model>/ 配下）
    └── output/  _summary.md / combined-all.md / <model>.md / <model>.metrics.txt
```

`<model>` は `opencode-go/deepseek-v4.1-flash` のような ID を `opencode-go-deepseek-v4.1-flash` のように平坦化した名前です。各 run の `output/<model>.md` は最終成果物（生成された `README.md`、無ければチャット本文）です。

## 結果の見方

- まず各 run の `output/_summary.md` で一覧（出力形式・文字数・秒数・トークン・コスト）を確認。
- 読み比べは各 run の `output/combined-all.md` が便利。
- run2 / run3 でモデルが作った実ファイルは `files/<model>/` にあります（run1 はチャット出力のみなので該当なし）。

## 再実行方法

`opencode` の実体（`opencode.exe`）を解決したうえで、各スクリプトを実行します。モデル一覧はスクリプト内 `$models` を編集してください。

```powershell
pwsh -File .\run1\run-bench.ps1   # 詳細指示・ツール禁止
pwsh -File .\run2\run-bench2.ps1  # 最小指示（日本語）
pwsh -File .\run3\run-bench3.ps1  # 最小指示（英語）
```

## 注意点（実行時に判明したこと）

- **無料枠モデルの制約**: `opencode/` プロバイダの一部の無料モデルは、プロジェクト設定（`opencode.json`）や `OPENCODE_CONFIG_CONTENT` が存在すると `403 FreeTierError: OpenCode's free tier can only be used from within OpenCode` で拒否されます。そのため run2 / run3 の該当モデルは権限設定なしで実行しています（結果は `output/` に統合済み）。
- **プロバイダ障害**: `opencode/ling-3.0-flash-fin-free` は `Endpoint is unavailable` により出力が得られませんでした。
- **run3 の grok-4.7**: 実行中に「ファイルは作らずチャットのみ」の応答になったため、opencode のセッション DB から本文を復元して `output/opencode-go-grok-4.7.md` に保存しています。
- 生成内容はモデルごとに文体・構成・情報の取捨が大きく異なります。優劣の判断は実際に読み比べてください。

## 出典

- 題材: [Configlue](https://github.com/arika0093/Configlue)（Apache-2.0）
- `context.md` は上記リポジトリの README および `docs/` を要約したものです。
