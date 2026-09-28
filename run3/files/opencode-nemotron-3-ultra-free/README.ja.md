# Configlue

**.NET アプリケーションの構成管理をシンプルに。**

Configlue は、複数の場所に分散した設定を単一のモデルに **glue（接着）** する .NET ライブラリです。
「Make easy configuration management.」を掲げ、設定の読み取り・書き込み・監視・移行・バックアップまでを包括的に支援します。

- 対象: .NET 10 SDK 以降（C# ソースジェネレータ必須、`LangVersion: preview` 推奨）
- ライセンス: Apache-2.0
- 現状: 「アーキテクチャ基盤」として提供。`Configuration.Writable` の完全な代替ではありません。

---

## なぜ Configlue か？

JSON ファイルの読み書き自体は数行で済みますが、実運用では以下の要件が積み重なります。

- 設定が **複数の場所** にある: グローバル/ローカル設定ファイル、環境変数、コマンドライン引数、暗号化資格情報、HTTP API や企業ポリシー等のリモート管理
- ファイル書き換えを **再起動なしで反映**（変更通知）
- 書き込み先を **自動判別**。環境変数由来の値への書き込みはエラーにしたい
- **人間が編集する** ファイル: コメント保持、JSON Schema 対応、壊れたファイルへの耐性
- **デフォルト値は書き出さない**（ユーザーが明示的に `null` を設定した場合は尊重）
- 設定ファイルの **バージョンアップ**（旧形式から新形式への自動変換）
- **バックアップと自動クリーンアップ**
- **安全な書き込み**: 原子性（クラッシュ時の破損防止）、競合検知・自動マージ、自動リトライ

これらを自前で実装するのは骨が折れます。Configlue はこの負担を肩代わりします。

---

## コアアーキテクチャ（6 つの概念）

依存関係は一直線で、学習順序も同じです。

```
Resource（場所） → Codec（変換） → Source（寄与） → Fragment（差分） → Options（ファサード）
                                                      ↘ Patch（編集片）
```

| 概念 | 一言で | 例 |
|------|--------|-----|
| **Resource** | バイト列が置かれている場所 | ファイル、ZIP エントリ、HTTP レスポンス、メモリ |
| **Codec** | バイト列 ⇔ 値の変換 | JSON / XML / YAML の読み書き |
| **Source** | 論理的な寄与（どのフィールドをどの優先度で） | 「ユーザー設定ファイルの `Server` 部分」 |
| **Fragment** | 存在を記憶する差分 | 「`Port` だけ持っている」状態 |
| **Patch** | 単一フィールドの編集 | 「`Port` を 9000 にする」 |
| **Options** | アプリが見るファサード | 読み取り、保存、監視、説明、診断 |

**読み取り**: 各 Source が Resource からバイト列を取得し、Codec で Fragment に変換。ランタイムは「存在する」フィールドだけを優先度順に重ね合わせ、単一モデルを構築します。

**書き込み**: 逆方向。アプリが通常のモデル値を編集すると、内部で Fragment 差分になり、`WriteRoute`/`WritePlan` で指定された Source のみに到達。無関係な Source は変更されません。

- Fragment は「メンバーが欠けている」ことと「null/デフォルトとして存在する」ことを区別。レイヤー合成で「未設定」が「デフォルト設定」を上書きすることはありません。
- Patch は生成される `TModel.Patch`（単一フィールド編集片）。`Unset()` でその Source の寄与だけを取り下げ、より低優先度の値を露出させます。
- `[ConfiglueMerge]` でメンバー単位のマージ挙動を変更可能（組み込み: `Append`、`Deep`、`Replace`、`SetUnion`、カスタム戦略も可）。コレクションの合成順序もここで決めます。

---

## 主な機能

- **複数ソースの優先度マージ**: `Priority` が大きい Source が勝つ。`GetDetailsAsync` で「どの値がどこから来たか」を検査可能。
- **読み取り専用ソース**: 環境変数、コマンドライン、既定の HTTP ソースは読み取り専用。書き込み試行はサイレント無視せず **競合エラー** を発生。
- **射影 / マウント**: 既存 Source を別モデルに射影（プロジェクション）、または別 Source をネストしたパスにマウント（`AddMounted`）。
- **プリセット**: `UseCommonSources` で標準的なレイヤー構成（グローバル/ローカル/環境等）を一括組み立て。
- **スパース書き込み**: 変更したフィールドのみを対象レイヤーに保存。デフォルトのままのフィールドは書き出さない。
- **編集セッション**: `OpenEditSessionAsync` で複数変更をまとめて適用。メモリ上で完結し `CommitAsync` で確定。競合時は既定で失敗、`WriteConflictResolution.LastWriteWins` も選択可。
- **スキーマ移行 / ストレージ移行**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` で旧バージョン設定を自動変換。既存ファイルを Source として登録可能。
- **バックアップと復元**: `FileResource` が原子的書き込みとバックアップ世代管理を提供。既定で `.bak` 1 世代、`RestoreLatestBackupAsync` で復元。
- **安全な書き込み**: 原子性、競合検知、リトライ。
- **セクション**: `JsonSectionResource` / XML 要素 / YAML マッピングで、ファイルの一部分を独立した Resource として扱える。書き込み時はコメント・空白・クォート・スカラスタイルを保持。同一ファイル内の独立セクションは 1 回の物理書き込みにバッチ処理。
- **ZIP / HTTP / S3 / Dapr**: `ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込みとポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **JSON Schema 生成**: `Configlue.JsonSchema`。人間が設定を書くためのスキーマを出力。
- **Native AOT 対応**: ソース生成された `JsonSerializerContext` を渡すことでトリミング/AOT 耐性を向上。
- **リアクティブ連携（オプション）**: `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）、`Configlue.Extensions.R3`（R3 1.3.1）。`ObserveChanges()`、`ObserveValues()`、`ObserveReloadFailures()`、`ObserveActiveValues()`、`ObserveActiveProfileNames()`。
- **DI 統合**: `Configlue.Extensions.DI`。Microsoft Options アダプタは `Configlue.Extensions.MSOptions`（`IOptions<T>` 等。同期ゲッターは非同期ソースの読み取り中にブロックするため、非同期フローでは `GetValueAsync` 推奨）。
- **プロファイル / 動的オプション**: 名前付きオプションと永続プロファイルで、ランタイムを単位として作成・削除。
- **既知の制限**: 異なる Resource 間の書き込みは原子的ではない。Source のリタイアは現在のオプション インスタンスにスコープされ、バックエンド データは残る。ソース集合はオプション ランタイムの生存中固定。

---

## パッケージ構成（主要なもの）

- `Configlue` … ユーザー向けメタパッケージ（Core / DI / JSON プロバイダ / JSON Schema / HTTP リソース / 共通ソース / 環境変数ソース / ジェネレータ アナライザをバンドル。実装アセンブリは持たない）
- `Configlue.Abstraction` … 契約（プロバイダ/コーデック/リソース/生成モデル）
- `Configlue.Core` … 解決と永続化のランタイム
- `Configlue.Extensibility` … プロバイダ SDK
- `Configlue.Extensions.DI` / `Configlue.Extensions.MSOptions` / `Configlue.Extensions.R3` / `Configlue.Extensions.Reactive`
- `Configlue.Generator` … Roslyn アナライザ（スパースモデルサポートを生成）
- `Configlue.Testing` … インメモリテストダブル
- `Configlue.Provider.Json` / `.Xml` / `.Yaml` … 各フォーマットのコーデック、セクションリソース、ファイル登録
- `Configlue.JsonSchema` … JSON Schema 生成とエクスポート
- `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml`
- `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip`
- `Configlue.Transformer.AES` … Resource と Codec の間のバイト列に対する AES-GCM 暗号化と認証

導入は `dotnet add package Configlue` から。必要な機能パッケージを追加してください。

---

## クイックスタート

`example.cs` として保存し、`dotnet run example.cs` で実行（.NET 10 以降）：

```csharp
#!/usr/bin/env dotnet
#:package Configlue@*

using Configlue;
using Configlue.Source.Presets;

// 1. 設定モデルを宣言。ジェネレータが Fragment/Patch サポートを生成。
[ConfiglueModel("SampleSetting", Version = 1)]
public partial class SampleSetting
{
    public string Name { get; set; } = "World";
    public int RunCount { get; set; }
    public bool DefaultValue { get; set; } = true;
}

// 2. プリセットレイヤーを宣言。ここに列挙した Source のみ有効化される。
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);

// 3. オプションインスタンス経由で読み書き。
var options = context.GetOptions<SampleSetting>();
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// スパース編集: 変更したフィールドのみ対象レイヤーに保存される。
await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue は未変更なので対象レイヤーに書き出されない。
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

---

## 値の由来を検査 / スパース保存

```csharp
var options = context.GetOptions<AppSettings>();
// 1. 現在値を取得（全ソースからマージ済み）
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 2. 各値がどこから来たかを検査
var details = await options.GetDetailsAsync();
Console.WriteLine($"Name came from {details.Name.Source?.Locator}");
Console.WriteLine($"Can write Name? {details.Name.IsEditable}");
foreach (var contribution in details.Name.Sources)
{
    var source = contribution.Source;
    Console.WriteLine(
        $"  {source.Kind} | {source.Locator} | writable: {source.CanWrite} | state: {contribution.State}"
    );
}
```

指定したメンバーだけを更新するパッチを保存。`Unset()` でその Source の寄与を取り下げ、より低優先度の値を露出させます：

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

その他の API：
- `IReadOnlyOptions<T>` … 日常的な読み取り面は `GetValueAsync` と `OnChange`。
- `SaveAsync(patch => ...)` … 生成された Patch でスパース保存。
- `OpenEditSessionAsync()` … 複数変更をまとめて編集、`CommitAsync` で確定。
- `ApplyPatchesAsync` + `StateSourcePatch` … ソース単位の明示的マルチ書き込み。
- `StateWritePlan.For<T>().Route(...)` … 書き込みルーティング。
- `SourceKey<TModel>` と `options.Source(key)` … ソース単位操作。

---

## 対象読者とトーン

- 対象: .NET 開発者、特に構成管理の悩みを持つ方
- トーン: 技術的、簡潔、誇張なし。`Microsoft.Extensions.Configuration` との違い（`IConfiguration` は読み取り志向、Configlue は独立したソースの合成・由来検査・スパース保存に適している）を示唆すると良いでしょう。