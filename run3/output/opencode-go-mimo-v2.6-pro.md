I've reviewed the research notes and the benchmark harness. Here's my plan.

## Plan

**Deliverable:** a new file `README.md` in the working directory (`work/opencode-go-mimo-v2.6-pro/`), containing a Japanese README for Configlue. The harness collects any file created in that folder besides `context.md`, so that single file is the artifact. I'll also produce a short chat summary of the content (the harness captures stdout as well).

**Structure of the README** (mapped to the research memo):

1. **タイトル + タグライン** — `Configlue` / 「Make easy configuration management.」 + 名前の由来（configuration + glue）と一文要約
2. **Configlue とは** — 複数の場所に散らばった設定を1つのモデルに「グルー」する .NET ライブラリ。.NET 10 SDK 以降 / Apache-2.0 / 現状は「アーキテクチャ基盤」であり `Configuration.Writable` の完全な代替ではない、と明記
3. **なぜ Configlue か（解決する課題）** — メモ §2 の箇条書きを自然な日本語のリストに（複数ソース・変更通知・書き込み先の自動選択・人間が書く設定ファイル対応・スパース書き込み・バージョンアップ・バックアップ・書き込み安全性）
4. **コアアーキテクチャ** — `Resource → Codec → Source → Fragment → Options`（+ Patch）の依存図、6概念の表（日本語の説明 + 例）、読み取り/書き込みの流れ、Fragment の「未設定 vs null/default」区別、`[ConfiglueMerge]`
5. **主な機能** — メモ §4 の項目を過不足なく（優先度マージ / 読み取り専用ソース / プロジェクション・マウント / プリセット / スパース書き込み / 編集セッション / スキーマ移行 / バックアップ・復元 / セーフライト / セクション / ZIP・HTTP・S3・Dapr / JSON Schema / Native AOT / リアクティブ連携 / DI・MSOptions / プロファイル / 既知の制限）
6. **パッケージ構成** — メモ §5 の一覧 + `dotnet add package Configlue` から始める導入手順
7. **クイックスタート** — メモ §6 のサンプルコードをそのまま（C# のまま）掲載し、1〜3のコメントを日本語のセクション見出しで補足
8. **値の出所の確認とスパース保存** — メモ §7 の `GetDetailsAsync` サンプルと `Unset()` の説明、その他の API（`IReadOnlyOptions<T>` など）の簡潔な一覧
9. **既知の制限事項** — メモ §4 末尾の3点（他 Resource への書き込みは非アトミック等）
10. **ライセンス** — Apache-2.0

**トーン方針**（メモ §8 準拠）：.NET 開発者向け、技術的で簡潔、誇張なし。`Microsoft.Extensions.Configuration` との違い（読み取り重視の `IConfiguration` に対し、Configlue は独立ソースの合成・出所の追跡・スパース保存に向く）を導入部か機能の節に1段落で入れる。

**方針：**
- コードブロックは原文の C# サンプルをそのまま使い、コメントだけ自然な日本語のまま維持（既に日本語寄りの英語コメントがある箇所も一貫させる）
- 囲みコード・表は GFM 形式を維持
- 「不明なことは書かない」— メモにない API や数値を創作しない
- 不要なファイル（追加の .md 等）は作らない。出力は `README.md` のみ

質問が1点あります：ファイル名は **`README.md`**（日本語本文でよい）で確定してよいですか？それとも `README.ja.md` を希望されますか？（他のモデルの出力例には両方の命名が混在しています）
