# Configlue README 日本語 - run2（最小プロンプト） 全モデル

---

# ===== opencode-go/deepseek-v4.1-flash =====

# Configlue

**Make easy configuration management.**

Configlue は、アプリケーションの設定管理（configuration management）を代行する .NET ライブラリです。複数の場所に散らばった設定を 1 つのモデルに**結合（glue）**することを中心的な考え方としています。名前も configuration + glue に由来します。

- 対象: .NET 10 SDK 以降
- 言語: C#（ソースジェネレーター対応の `LangVersion` が必要。リポジトリは preview でビルド）
- ライセンス: Apache-2.0

> 現状は「アーキテクチャ上の土台」であり、`Configuration.Writable` を完全に置き換えるものではありません。

## なぜ Configlue か（Why Configlue?）

JSON ファイルの読み書きだけなら数行で済みます。しかし実際のアプリケーションでは、次のような要件が積み重なっていきます。

- 設定が複数箇所にある: グローバル設定、実行フォルダー設定、環境変数、コマンドライン引数、暗号化された資格情報、社内ポリシーや HTTP API などのリモート管理。
- 設定ファイルが書き換わったら、再起動なしで反映したい（変更通知）。
- 書き込み先を自動で選びたい。環境変数から読んだ値への書き込みはエラーにしたい。
- 設定ファイルは人間が書く。コメントを消したくない、JSON Schema がほしい、壊れたファイルにも対処したい。
- 既定値のままなら書き出したくない（ただしユーザーが明示した `null` は尊重する）。
- 設定ファイルのバージョンアップ（旧形式から新形式への自動変換）。
- バックアップと自動整理。
- 書き込みの安全性: アトミック性（クラッシュしても壊れない）、他プロセスとの競合検出・自動マージ、自動リトライ。

これらを自前で実装するのは面倒です。Configlue はこの面倒を引き受けることを目的としています。

## 基本アーキテクチャ

依存関係は直線的で、学習順も同じです。

```text
Resource (location) → Codec (conversion) → Source (contribution) → Fragment (diff) → Options (facade)
                                                        ↘ Patch (edit fragment)
```

| 概念 | 一言で | 例 |
| --- | --- | --- |
| Resource | バイトがどこにあるか | ファイル、ZIP エントリ、HTTP 応答、メモリ |
| Codec | バイト ↔ 値の変換 | JSON / XML / YAML の読み書き |
| Source | 論理的な寄与（どのフィールドをどの優先度で） | 「ユーザー設定ファイルの Server 部分」 |
| Fragment | 存在を記憶する差分 | 「Port だけ」を持つ状態 |
| Patch | 単一フィールドの編集 | 「Port を 9000 にする」 |
| Options | アプリが見るファサード | 読み・保存・監視・説明・診断 |

**読み込み**: 各 Source が Resource からバイトを取得し、Codec が Fragment に変換します。ランタイムが優先度順に「存在する」フィールドだけを 1 つのモデルへ重ねます。

**書き込み**: 逆向きです。アプリは普通のモデル値を編集します。内部では変更が Fragment 差分になり、`WriteRoute` / `WritePlan` が指す Source にだけ届きます。無関係な Source は変更されません。

- Fragment は「メンバーが存在しない」と「null / 既定値で存在する」を区別します。層の合成で「未設定」が「既定値に設定」を上書きすることはありません。
- Patch は生成される `TModel.Patch`（単一フィールドの編集フラグメント）です。`Unset()` は書き込み先 Source の寄与だけを取り消し、下位優先度の値を再び見せます。
- `[ConfiglueMerge]` でメンバーごとのマージ挙動を変更できます（組み込み: `Append`, `Deep`, `Replace`, `SetUnion`、カスタム戦略も可）。コレクションの層合成・順序はここで決まります。

## インストール

```sh
dotnet add package Configlue
```

基本パッケージを入れたうえで、必要な機能パッケージを追加します。

## Quick Start

`example.cs` に保存し、`dotnet run example.cs` で実行します（.NET 10 以降）。

```csharp
#!/usr/bin/env dotnet
#:package Configlue@*

using Configlue;
using Configlue.Source.Presets;

// 1. 設定モデルを宣言する。ジェネレーターが Fragment / Patch サポートを生成する。
[ConfiglueModel("SampleSetting", Version = 1)]
public partial class SampleSetting
{
    public string Name { get; set; } = "World";
    public int RunCount { get; set; }
    public bool DefaultValue { get; set; } = true;
}

// 2. プリセットの層を宣言する。ここに列挙した Source だけが有効になる。
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);

// 3. options インスタンスを通して読み書きする。
var options = context.GetOptions<SampleSetting>();
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// スパース編集: 変更したフィールドだけが書き込み先の層に保存される。
await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue は変更していないので、書き込み先の層には保存されない。
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

## 値の由来を調べる

どの値がどの Source 由来なのかを `GetDetailsAsync` で検査できます。

```csharp
var options = context.GetOptions<AppSettings>();

// 1. 現在の値（全ソースをマージしたもの）を取得
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 2. 各値がどこから来たかを調べる
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

## スパース保存と `Unset()`

指定したメンバーだけを更新するパッチを保存します。`Unset()` はその Source の寄与を外し、下位優先度の Source が値を提供できるようにします。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

### その他の主な API

- `IReadOnlyOptions<T>` … 日常の読み取り面は `GetValueAsync` と `OnChange`。
- `SaveAsync(patch => ...)` … 生成 Patch でスパース保存。
- `OpenEditSessionAsync()` … まとめて編集し `CommitAsync`。
- `ApplyPatchesAsync` + `StateSourcePatch` … 明示的なソース別マルチ書き込み。
- `StateWritePlan.For<T>().Route(...)` … 書き込みルーティング。
- `SourceKey<TModel>` と `options.Source(key)` … ソース単位の操作。

## 主な機能

- **複数ソースの優先度マージ**: `Priority` が大きい Source が勝ちます。`GetDetailsAsync` で「どの値がどこ由来か」を検査できます。
- **読み取り専用ソース**: 環境変数・コマンドライン・既定の HTTP ソースは読み取り専用です。読み取り専用の値への書き込みは黙って無視せず、競合エラーになります。
- **プロジェクション / マウント**: 既存 Source を別モデルに整形（projection）したり、ネストしたパスに別 Source を接続（mount, `AddMounted`）できます。
- **プリセット**: `UseCommonSources` が標準的な層構成（global / local / environment など）を組み立てます。
- **スパース書き込み**: 変更したフィールドだけを対象層に保存します。既定値のままのフィールドは書かれません。
- **編集セッション**: `OpenEditSessionAsync` で複数の変更をまとめて適用できます。`CommitAsync` までインメモリで保持し、競合時は既定で失敗、`WriteConflictResolution.LastWriteWins` も選べます。
- **スキーマ移行 / ストレージ移行**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` による旧バージョン設定の自動変換。既存ファイルを Source として登録できます。
- **バックアップと復元**: `FileResource` はアトミック書き込みとバックアップ世代管理を行います。既定で `.bak` 1 世代、`RestoreLatestBackupAsync` で復元できます。
- **安全な書き込み**: アトミック性、競合検出、リトライ。
- **セクション**: `JsonSectionResource` / XML 要素 / YAML マッピングで、ファイルの一部を独立した Resource として扱えます。書き込み時はコメント・空白・引用・スカラー形式を保持します。同じファイル内の独立セクションは 1 回の物理書き込みにバッチされます。
- **ZIP / HTTP / S3 / Dapr**: `ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込み・ポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **JSON Schema 生成**: `Configlue.JsonSchema`。人間が設定を書くために使います。
- **Native AOT 対応**: ソース生成の `JsonSerializerContext` を渡すとトリミング / AOT に強くなります。
- **リアクティブ統合（任意）**: `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）。`ObserveChanges()`, `ObserveValues()`, `ObserveReloadFailures()`, `ObserveActiveValues()`, `ObserveActiveProfileNames()`。
- **DI 統合**: `Configlue.Extensions.DI`。Microsoft の options アダプター `Configlue.Extensions.MSOptions`（`IOptions<T>` など。同期ゲッターは非同期ソース読み取り中にブロックするため、非同期フローでは `GetValueAsync` を推奨）。
- **プロファイル / 動的オプション**: 名前付きオプションや永続プロファイルで、ランタイムを単位に作成・削除できます。

### 既知の制限

- 異なる Resource 間の書き込みはアトミックではありません。
- Source の退役は現在の options インスタンスに閉じ、実データは残ります。
- Source 集合は options ランタイムで固定されます。

## パッケージ構成

主要なパッケージは次のとおりです。

- `Configlue` … ユーザー向けメタパッケージ（Core / DI / JSON provider / JSON Schema / HTTP resources / common sources / environment source / generator analyzer を同梱。実装アセンブリは持たない）。
- `Configlue.Abstraction` … 契約（provider / codec / resource / generated-model）。
- `Configlue.Core` … 解決と永続化のランタイム。
- `Configlue.Extensibility` … プロバイダー SDK。
- `Configlue.Extensions.DI` / `Configlue.Extensions.MSOptions` / `Configlue.Extensions.R3` / `Configlue.Extensions.Reactive`
- `Configlue.Generator` … Roslyn アナライザー（スパースなモデルサポート生成）。
- `Configlue.Testing` … インメモリのテストダブル。
- `Configlue.Provider.Json` / `.Xml` / `.Yaml` … 各形式の Codec・セクションリソース・ファイル登録。
- `Configlue.JsonSchema` … JSON Schema 生成・エクスポート。
- `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml`
- `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip`
- `Configlue.Transformer.AES` … Resource と Codec の間のバイトを AES-GCM で暗号化・認証。

## Microsoft.Extensions.Configuration との違い

`Microsoft.Extensions.Configuration`（`IConfiguration`）は読み取り中心です。Configlue は、独立した Source の合成、値の来歴の検査、変更したフィールドだけを書き戻すスパース保存に向いています。

## ライセンス

Apache-2.0



---

# ===== opencode-go/glm-5.3 =====

# Configlue

Make easy configuration management.

Configlue は、.NET アプリケーションの設定管理（configuration management）を代行するライブラリです。グローバル設定ファイル、実行フォルダーの設定、環境変数、コマンドライン引数、リモート管理など、複数の場所に散らばった設定を 1 つのモデルに**結合（glue）**します。名前の由来も configuration + glue です。

- 対象: .NET 10 SDK 以降
- ライセンス: Apache-2.0

## Why Configlue?

JSON ファイルの読み書きだけなら数行で済みます。しかし実際の設定管理には次のような要件が積み重なります。

- 設定が複数箇所にある: グローバル設定、実行フォルダー設定、環境変数、コマンドライン引数、暗号化された資格情報、社内ポリシーや HTTP API などのリモート管理
- 設定ファイルが書き換わったら再起動なしで反映したい（変更通知）
- 書き込み先を自動で選びたい。環境変数から読んだ値への書き込みはエラーにしたい
- 設定ファイルは人間が書く: コメントを消さない、JSON Schema がほしい、壊れたファイルへの対処
- 既定値のままなら書き出さない（ただしユーザーが明示した `null` は尊重する）
- 設定ファイルのバージョンアップ（旧形式から新形式への自動変換）
- バックアップと自動整理
- 書き込みの安全性: アトミック性（クラッシュしても壊れない）、他プロセスとの競合検出・自動マージ、自動リトライ

Configlue はこれらを 1 つのアーキテクチャにまとめ、自前実装の手間を省きます。

## Quick Start

以下のコードを `example.cs` に保存し、`dotnet run example.cs` で実行できます（.NET 10 以降）。

```csharp
#!/usr/bin/env dotnet
#:package Configlue@*

using Configlue;
using Configlue.Source.Presets;

// 1. Declare the settings model. The generator creates Fragment/Patch support.
[ConfiglueModel("SampleSetting", Version = 1)]
public partial class SampleSetting
{
    public string Name { get; set; } = "World";
    public int RunCount { get; set; }
    public bool DefaultValue { get; set; } = true;
}

// 2. Declare the preset layers. Only the sources listed here are enabled.
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);

// 3. Read and write through the options instance.
var options = context.GetOptions<SampleSetting>();
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// Sparse edit: only modified fields are saved to the target layer.
await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue is not modified, so it will not be saved to the target layer.
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

## アーキテクチャ

Configlue は 6 つの概念で構成されます。依存関係は直線的で、この順番がそのまま学習順序になります。

```text
Resource (location) → Codec (conversion) → Source (contribution) → Fragment (diff) → Options (facade)
                                                        ↘ Patch (edit fragment)
```

| 概念 | 一言で | 例 |
| --- | --- | --- |
| Resource | バイトがどこにあるか | ファイル、ZIPエントリ、HTTP応答、メモリ |
| Codec | バイトと値の相互変換 | JSON / XML / YAML の読み書き |
| Source | 論理的な寄与（どのフィールドをどの優先度で） | 「ユーザー設定ファイルの Server 部分」 |
| Fragment | 存在を記憶する差分 | 「Port だけ」を持つ状態 |
| Patch | 単一フィールドの編集 | 「Port を 9000 にする」 |
| Options | アプリが見るファサード | 読み・保存・監視・説明・診断 |

**読み込み**: 各 Source が Resource からバイトを取得し、Codec が Fragment に変換します。ランタイムが優先度順に「存在する」フィールドだけを 1 つのモデルへ重ね合わせます。

**書き込み**: 逆向きに動きます。アプリは普通のモデル値を編集します。内部では変更が Fragment 差分になり、`WriteRoute` / `WritePlan` が指す Source にだけ届きます。無関係な Source は変更されません。

いくつかの重要な性質:

- Fragment は「メンバーが存在しない」と「null/既定値で存在する」を区別します。層の合成で「未設定」が「既定値に設定」を上書きすることはありません。
- Patch はソースジェネレーターが生成する `TModel.Patch`（単一フィールドの編集フラグメント）です。`Unset()` は書き込み先 Source の寄与だけを取り消し、下位優先度の値を再び見えるようにします。
- `[ConfiglueMerge]` 属性でメンバーごとのマージ挙動を変更できます（組み込み: `Append`, `Deep`, `Replace`, `SetUnion`。カスタム戦略も可）。コレクションの層合成・順序はここで決まります。

## 主な機能

- **複数ソースの優先度マージ**: `Priority` が大きい Source が勝ちます。`GetDetailsAsync` で「どの値がどこ由来か」を検査できます。
- **読み取り専用ソース**: 環境変数・コマンドライン・既定の HTTP ソースは読み取り専用です。読み取り専用の値への書き込みは黙って無視せず、競合エラーになります。
- **プロジェクション / マウント**: 既存 Source を別モデルに整形（projection）したり、ネストしたパスに別 Source を接続（mount, `AddMounted`）できます。
- **プリセット**: `UseCommonSources` が標準的な層構成（global / local / environment など）を組み立てます。
- **スパース書き込み**: 変更したフィールドだけを対象層に保存します。既定値のままのフィールドは書き出されません。
- **編集セッション**: `OpenEditSessionAsync` で複数変更をまとめて適用します。`CommitAsync` までインメモリで保持され、競合時は既定で失敗します（`WriteConflictResolution.LastWriteWins` も選択可能）。
- **スキーマ移行 / ストレージ移行**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` により、旧バージョン設定を自動変換できます。既存ファイルを Source として登録可能です。
- **バックアップと復元**: `FileResource` はアトミック書き込みとバックアップ世代管理を提供します。既定で `.bak` 1 世代、`RestoreLatestBackupAsync` で復元します。
- **安全な書き込み**: アトミック性、競合検出、リトライ。
- **セクション**: `JsonSectionResource` / XML 要素 / YAML マッピングで、ファイルの一部を独立した Resource として扱えます。書き込み時はコメント・空白・引用・スカラー形式を保持します。同じファイル内の独立セクションは 1 回の物理書き込みにバッチされます。
- **ZIP / HTTP / S3 / Dapr**: `ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込み・ポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **JSON Schema 生成**: `Configlue.JsonSchema` で人間が設定を書くためのスキーマを生成・エクスポートします。
- **Native AOT 対応**: ソース生成の `JsonSerializerContext` を渡すと、トリミング / AOT 環境で安全に動作します。
- **リアクティブ統合（任意）**: `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）。`ObserveChanges()`, `ObserveValues()`, `ObserveReloadFailures()`, `ObserveActiveValues()`, `ObserveActiveProfileNames()` が使えます。
- **DI 統合**: `Configlue.Extensions.DI`。Microsoft の options アダプター `Configlue.Extensions.MSOptions`（`IOptions<T>` など）も提供します。同期ゲッターは非同期ソース読み取り中ブロックするため、非同期フローでは `GetValueAsync` を推奨します。
- **プロファイル / 動的オプション**: 名前付きオプションや永続プロファイルで、ランタイムを単位に作成・削除できます。

## 値の由来を調べる / スパース保存

マージされた現在の値と、各値がどこから来たかを検査できます。

```csharp
var options = context.GetOptions<AppSettings>();
// 1. 現在の値（全ソースをマージしたもの）を取得
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 2. 各値がどこから来たかを調べる
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

指定したメンバーだけを更新するパッチを保存できます。`Unset()` はその Source の寄与を外し、下位優先度の Source が値を提供できるようにします。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

その他の API:

- `IReadOnlyOptions<T>` … 日常の読み取り面は `GetValueAsync` と `OnChange`
- `SaveAsync(patch => ...)` … 生成 Patch でスパース保存
- `OpenEditSessionAsync()` … まとめて編集し `CommitAsync`
- `ApplyPatchesAsync` + `StateSourcePatch` … 明示的なソース別マルチ書き込み
- `StateWritePlan.For<T>().Route(...)` … 書き込みルーティング
- `SourceKey<TModel>` と `options.Source(key)` … ソース単位の操作

## Microsoft.Extensions.Configuration との違い

`IConfiguration` は読み取り中心の API です。Configlue は独立したソースの合成、値の来歴の検査、スパース保存といった、読み書き両方の設定管理に向けて設計されています。

なお、現在の Configlue は「アーキテクチャ上の土台」であり、`Configuration.Writable` を完全に置き換えるものではありません。

## パッケージ構成

インストールはメタパッケージの `Configlue` から。必要に応じて機能パッケージを追加します。

```console
dotnet add package Configlue
```

| パッケージ | 内容 |
| --- | --- |
| `Configlue` | ユーザー向けメタパッケージ（Core / DI / JSON provider / JSON Schema / HTTP resources / common sources / environment source / generator analyzer を同梱。実装アセンブリは持たない） |
| `Configlue.Abstraction` | 契約（provider / codec / resource / generated-model） |
| `Configlue.Core` | 解決と永続化のランタイム |
| `Configlue.Extensibility` | プロバイダー SDK |
| `Configlue.Extensions.DI` | DI 統合 |
| `Configlue.Extensions.MSOptions` | Microsoft の options アダプター（`IOptions<T>` など） |
| `Configlue.Extensions.R3` / `Configlue.Extensions.Reactive` | リアクティブ統合 |
| `Configlue.Generator` | Roslyn アナライザー（スパースなモデルサポート生成） |
| `Configlue.Testing` | インメモリのテストダブル |
| `Configlue.Provider.Json` / `.Xml` / `.Yaml` | 各形式の Codec・セクションリソース・ファイル登録 |
| `Configlue.JsonSchema` | JSON Schema 生成・エクスポート |
| `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml` | 各種ソース・プリセット |
| `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip` | 各種リソース |
| `Configlue.Transformer.AES` | Resource と Codec の間のバイトを AES-GCM で暗号化・認証 |

## 既知の制限

- 異なる Resource 間の書き込みはアトミックではありません。
- Source の退役は現在の options インスタンスに閉じられ、実データは残ります。
- Source 集合は options ランタイムで固定されます。

## ライセンス

Apache-2.0



---

# ===== opencode-go/glm-5.3-flash =====

# Configlue

**Make easy configuration management.**

Configlue は、.NET アプリケーションの設定管理を代行するライブラリです。複数の場所に散らばった設定を、1 つのモデルへ**結合（glue）**する —— これが名前の由来であり、中心的な考え方です（configuration + glue）。

.NET 10 SDK 以降 / ライセンス: Apache-2.0

## なぜ Configlue か

JSON ファイルの読み書きだけなら数行で済みます。しかし実際のアプリケーションでは、次のような要件が積み重なります:

- 設定が複数箇所にある。グローバル設定・実行フォルダー設定・環境変数・コマンドライン引数・暗号化された資格情報・社内ポリシーや HTTP API によるリモート管理。
- 設定ファイルが書き換わったら再起動なしで反映したい（変更通知）。
- 書き込み先を自動で選びたい。環境変数から読んだ値への書き込みはエラーとして扱いたい。
- 設定ファイルは人間が書く。コメントを消したくない。JSON Schema がほしい。壊れたファイルにどう対処するか決めたい。
- 既定値のままのフィールドは書き出したくない。ただし、ユーザーが明示した `null` は尊重したい。
- 設定ファイルのバージョンアップ。旧形式から新形式への自動変換。
- バックアップと自動整理。
- 書き込みの安全性。アトミック性（クラッシュしても壊れない）、他プロセスとの競合検出と自動マージ、自動リトライ。

これらを自前で実装するのは面倒です。Configlue はその部分を引き受けます。

`Microsoft.Extensions.Configuration`（`IConfiguration`）が読み取り中心であるのに対し、Configlue は**独立したソースの合成・来歴（どの値がどこ由来か）の検査・スパース保存**に向いています。

> 現状はアーキテクチャ上の土台であり、`Configuration.Writable` を完全に置き換えるものではありません。

## Quick Start

`example.cs` に保存して `dotnet run example.cs` で実行できます（.NET 10 以降）。

```csharp
#!/usr/bin/env dotnet
#:package Configlue@*

using Configlue;
using Configlue.Source.Presets;

// 1. Declare the settings model. The generator creates Fragment/Patch support.
[ConfiglueModel("SampleSetting", Version = 1)]
public partial class SampleSetting
{
    public string Name { get; set; } = "World";
    public int RunCount { get; set; }
    public bool DefaultValue { get; set; } = true;
}

// 2. Declare the preset layers. Only the sources listed here are enabled.
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);

// 3. Read and write through the options instance.
var options = context.GetOptions<SampleSetting>();
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// Sparse edit: only modified fields are saved to the target layer.
await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue is not modified, so it will not be saved to the target layer.
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

インストールはメタパッケージから始め、必要な機能パッケージを追加します:

```text
dotnet add package Configlue
```

## 基本アーキテクチャ

依存関係は直線的で、学習順も同じです:

```text
Resource (location) → Codec (conversion) → Source (contribution) → Fragment (diff) → Options (facade)
                                                        ↘ Patch (edit fragment)
```

| 概念 | 一言で | 例 |
| --- | --- | --- |
| Resource | バイトがどこにあるか | ファイル、ZIP エントリ、HTTP 応答、メモリ |
| Codec | バイト↔値の変換 | JSON / XML / YAML の読み書き |
| Source | 論理的な寄与（どのフィールドをどの優先度で） | 「ユーザー設定ファイルの Server 部分」 |
| Fragment | 存在を記憶する差分 | 「Port だけ」を持つ状態 |
| Patch | 単一フィールドの編集 | 「Port を 9000 にする」 |
| Options | アプリが見るファサード | 読み・保存・監視・説明・診断 |

**読み込み**では、各 Source が Resource からバイトを取得し、Codec が Fragment に変換します。ランタイムが優先度順に「存在する」フィールドだけを 1 つのモデルへ重ねます。

**書き込み**は逆向きです。アプリは普通のモデル値を編集するだけで、内部では変更が Fragment 差分になり、`WriteRoute` / `WritePlan` が指す Source にだけ届きます。無関係な Source は変更されません。

設計上の要点:

- Fragment は「メンバーが存在しない」と「null/既定値で存在する」を区別します。層を合成しても「未設定」が「既定値に設定」を上書きすることはありません。
- Patch は生成される `TModel.Patch`（単一フィールドの編集フラグメント）です。`Unset()` は書き込み先 Source の寄与だけを取り消し、下位優先度の値を再び見せるようにします。
- `[ConfiglueMerge]` でメンバーごとのマージ挙動を変更できます。組み込みは `Append` / `Deep` / `Replace` / `SetUnion`、カスタム戦略も可能です。コレクションの層合成と順序はここで決まります。

## 主な機能

- **複数ソースの優先度マージ** — `Priority` が大きい Source が勝ちます。`GetDetailsAsync` で「どの値がどこ由来か」を検査できます。
- **読み取り専用ソース** — 環境変数・コマンドライン・既定の HTTP ソースは読み取り専用です。読み取り専用の値への書き込みは黙って無視されず、競合エラーになります。
- **スパース書き込み** — 変更したフィールドだけを対象の層に保存します。既定値のままのフィールドは書き出されません。
- **値の来歴の検査** — 各メンバーの値がどの Source から来たか、書き込み可能かを調べられます（下記コード例参照）。
- **編集セッション** — `OpenEditSessionAsync` で複数の変更をまとめて適用し、`CommitAsync` までインメモリで保持します。競合時は既定で失敗します（`WriteConflictResolution.LastWriteWins` も選択可）。
- **セクション** — `JsonSectionResource` / XML 要素 / YAML マッピングで、ファイルの一部を独立した Resource として扱えます。書き込み時はコメント・空白・引用・スカラー形式を保持します。同じファイル内の独立セクションは 1 回の物理書き込みにバッチされます。
- **スキーマ移行 / ストレージ移行** — `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` による旧バージョン設定の自動変換。既存ファイルを Source として登録することもできます。
- **バックアップと復元** — `FileResource` はアトミック書き込みとバックアップ世代管理を行います。既定で `.bak` 1 世代、`RestoreLatestBackupAsync` で復元。
- **安全な書き込み** — アトミック性、他プロセスとの競合検出、自動リトライ。
- **プロジェクション / マウント** — 既存 Source を別モデルに整形（projection）したり、ネストしたパスに別 Source を接続（mount, `AddMounted`）できます。
- **プリセット** — `UseCommonSources` が標準的な層構成（global / local / environment など）を組み立てます。
- **多様な Resource** — `ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込み・ポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **JSON Schema 生成** — `Configlue.JsonSchema` で、人間が設定を書くための Schema を生成・エクスポートします。
- **Native AOT 対応** — ソース生成の `JsonSerializerContext` を渡すとトリミング/AOT に対して強くなります。
- **リアクティブ統合（任意）** — `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）。`ObserveChanges()`, `ObserveValues()`, `ObserveReloadFailures()`, `ObserveActiveValues()`, `ObserveActiveProfileNames()` を提供します。
- **DI 統合** — `Configlue.Extensions.DI`。Microsoft の options アダプターは `Configlue.Extensions.MSOptions`（`IOptions<T>` など）。同期ゲッターは非同期ソース読み取り中にブロックするため、非同期フローでは `GetValueAsync` を推奨します。
- **プロファイル / 動的オプション** — 名前付きオプションや永続プロファイルをランタイム単位で作成・削除できます。
- **暗号化** — `Configlue.Transformer.AES` が Resource と Codec の間のバイトを AES-GCM で暗号化・認証します。

## 値の由来を調べる / スパース保存

```csharp
var options = context.GetOptions<AppSettings>();
// 1. 現在の値（全ソースをマージしたもの）を取得
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 2. 各値がどこから来たかを調べる
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

指定したメンバーだけを更新するパッチを保存します。`Unset()` はその Source の寄与を外し、下位優先度の Source が値を提供できるようにします:

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

その他の API:

- `IReadOnlyOptions<T>` — 日常の読み取りは `GetValueAsync` と `OnChange`。
- `SaveAsync(patch => ...)` — 生成 Patch でスパース保存。
- `OpenEditSessionAsync()` — まとめて編集し `CommitAsync`。
- `ApplyPatchesAsync` + `StateSourcePatch` — 明示的なソース別マルチ書き込み。
- `StateWritePlan.For<T>().Route(...)` — 書き込みルーティング。
- `SourceKey<TModel>` と `options.Source(key)` — ソース単位の操作。

## パッケージ構成

主要なパッケージ:

| パッケージ | 役割 |
| --- | --- |
| `Configlue` | ユーザー向けメタパッケージ（Core / DI / JSON provider / JSON Schema / HTTP resources / common sources / environment source / generator analyzer を同梱。実装アセンブリは持たない） |
| `Configlue.Abstraction` | 契約（provider / codec / resource / generated-model） |
| `Configlue.Core` | 解決と永続化のランタイム |
| `Configlue.Extensibility` | プロバイダー SDK |
| `Configlue.Extensions.DI` / `.MSOptions` / `.R3` / `.Reactive` | DI・options アダプター・リアクティブ統合 |
| `Configlue.Generator` | Roslyn アナライザー（スパースなモデルサポート生成） |
| `Configlue.Testing` | インメモリのテストダブル |
| `Configlue.Provider.Json` / `.Xml` / `.Yaml` | 各形式の Codec・セクションリソース・ファイル登録 |
| `Configlue.JsonSchema` | JSON Schema 生成・エクスポート |
| `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml` | 各種ソース / プリセット |
| `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip` | リモート・コンテナ系 Resource |
| `Configlue.Transformer.AES` | Resource と Codec の間のバイトを AES-GCM で暗号化・認証 |

## 既知の制限

- 異なる Resource 間の書き込みはアトミックではありません。
- Source の退役は現在の options インスタンスに閉じており、実データは残ります。
- Source 集合は options ランタイムで固定されます。

## ライセンス

Apache-2.0



---

# ===== opencode-go/gpt-6-luna =====

# Configlue

> Make easy configuration management.

Configlue は、複数の場所に分散したアプリケーション設定を一つのモデルに結び付け、読み取り・変更・保存・監視を扱う .NET ライブラリです。名前は *configuration* と *glue* を組み合わせたものです。

グローバル設定、実行フォルダーのファイル、環境変数、コマンドライン引数、暗号化された資格情報、リモートのポリシーや HTTP API などを、優先度と書き込み先を意識しながら扱えます。

> **ステータス:** Configlue は現在、設定管理のためのアーキテクチャ上の土台です。`Configuration.Writable` を完全に置き換えるものではありません。

## 主な特徴

- 複数の独立した設定ソースを優先度順に合成し、値の由来を `GetDetailsAsync` で調べられます。
- 変更したフィールドだけを適切な書き込み先に保存できます。未変更の既定値は書き出されず、明示的に設定された `null` や既定値は未設定と区別されます。
- 環境変数やコマンドラインなどの読み取り専用ソースへの書き込みは、黙って無視せず競合エラーになります。
- ファイル変更の監視、編集セッション、設定バージョンの移行、バックアップと復元、安全な書き込みをサポートします。
- JSON / XML / YAML のほか、ZIP、HTTP、S3、Dapr などのリソースを利用できます。
- JSON Schema 生成、DI、Microsoft Options、Reactive / R3、Native AOT 向けの統合を必要に応じて追加できます。

## インストール

.NET 10 SDK 以降が必要です。基本パッケージを追加します。

```sh
dotnet add package Configlue
```

`Configlue` は Core、DI、JSON provider、JSON Schema、HTTP resources、標準ソース、環境変数ソース、ソースジェネレーターアナライザーをまとめたユーザー向けメタパッケージです。XML / YAML や S3 など、追加機能に必要なパッケージは個別に追加できます。C# の言語バージョンはソースジェネレーターをサポートする必要があります。

## クイックスタート

次のコードを `example.cs` に保存し、.NET 10 以降で `dotnet run example.cs` を実行します。

```csharp
#!/usr/bin/env dotnet
#:package Configlue@*

using Configlue;
using Configlue.Source.Presets;

// モデルを宣言します。ジェネレーターが Fragment / Patch を生成します。
[ConfiglueModel("SampleSetting", Version = 1)]
public partial class SampleSetting
{
    public string Name { get; set; } = "World";
    public int RunCount { get; set; }
    public bool DefaultValue { get; set; } = true;
}

// 利用する設定ソースを登録します。
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);

// Options を通して値を読み書きします。
var options = context.GetOptions<SampleSetting>();
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 変更したフィールドだけが対象のレイヤーに保存されます。
await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue は変更していないため、対象レイヤーには保存されません。
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

## 仕組み

Configlue の概念は、リソースからアプリケーションの API へとつながります。

```text
Resource (場所) → Codec (変換) → Source (寄与) → Fragment (差分) → Options (ファサード)
                                                ↘ Patch (Fragment の編集)
```

| 概念 | 役割 | 例 |
| --- | --- | --- |
| **Resource** | バイト列の保存場所 | ファイル、ZIP エントリ、HTTP 応答、メモリ |
| **Codec** | バイト列と値の相互変換 | JSON / XML / YAML |
| **Source** | どのフィールドをどの優先度で提供するかを表す寄与 | ユーザー設定ファイルの `Server` 部分 |
| **Fragment** | 値の存在を記録した差分 | `Port` だけを持つ状態 |
| **Patch** | フィールドを編集する Fragment | `Port` を 9000 にする |
| **Options** | アプリケーションが使うファサード | 読み取り、保存、監視、説明、診断 |

**読み込み**では、各 Source が Resource からバイト列を取得し、Codec が Fragment に変換します。ランタイムは優先度順に、存在するフィールドだけをモデルへ重ねます。優先度の大きい Source が優先されます。

**書き込み**では、通常のモデル編集を Fragment の差分として扱い、`WriteRoute` / `WritePlan` が指定する Source にだけ反映します。無関係な Source は変更されません。Fragment は「メンバーがない」状態と、「`null` や既定値でメンバーが存在する」状態を区別するため、未設定の値が下位レイヤーの値を既定値で上書きすることはありません。

`[ConfiglueMerge]` を使うと、メンバーごとのマージ方法を指定できます。組み込みの戦略は `Append`、`Deep`、`Replace`、`SetUnion` で、カスタム戦略も利用できます。

## 値の由来を確認して変更する

`GetDetailsAsync` を使うと、各値の出所や編集可能性、ソースごとの寄与を確認できます。

```csharp
var options = context.GetOptions<AppSettings>();
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

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

生成された Patch は指定したメンバーだけを更新します。`Unset()` は書き込み先 Source の寄与を取り消し、下位優先度の Source が値を提供できるようにします。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

## 主な機能

### ソース、ルーティング、編集

- **共通ソースのプリセット:** `UseCommonSources` で global / local / environment などの標準的なレイヤー構成を設定できます。
- **プロジェクションとマウント:** 既存 Source を別モデルに整形したり、`AddMounted` でネストしたパスに Source を接続したりできます。
- **編集セッション:** `OpenEditSessionAsync` で複数の変更をまとめ、`CommitAsync` までインメモリで保持します。競合時は既定で失敗し、`WriteConflictResolution.LastWriteWins` も選べます。
- **ソース別操作:** `ApplyPatchesAsync` と `StateSourcePatch` による明示的な複数ソース書き込み、`StateWritePlan.For<T>().Route(...)` によるルーティング、`SourceKey<TModel>` と `options.Source(key)` によるソース単位の操作が可能です。
- **動的オプションとプロファイル:** 名前付きオプションや永続プロファイルをランタイム単位で作成・削除できます。

日常的な読み取りには `IReadOnlyOptions<T>` の `GetValueAsync` と `OnChange` を使います。書き込みには `SaveAsync(patch => ...)`、複数変更には編集セッションを利用できます。

### ファイルとストレージ

- `FileResource` はアトミック書き込みとバックアップ世代管理を提供します。既定では `.bak` を 1 世代保持し、`RestoreLatestBackupAsync` で復元できます。
- JSON セクション、XML 要素、YAML マッピングを独立した Resource として扱えます。セクションの書き込みではコメント、空白、引用、スカラー形式を保持します。同じファイル内の独立セクションは、1 回の物理書き込みにまとめられます。
- ZIP エントリ、HTTP、S3、Dapr の Resource を利用できます。HTTP Resource は ETag 条件付き書き込みとポーリングをサポートします。
- `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` により、旧バージョンの設定を自動変換できます。既存ファイルも Source として登録できます。
- 安全な書き込みとして、アトミック性、競合検出、リトライを扱います。

### 統合とツール

- **JSON Schema:** `Configlue.JsonSchema` で設定モデルの JSON Schema を生成・エクスポートできます。
- **Native AOT:** ソース生成された `JsonSerializerContext` を渡すことで、トリミング / AOT に強い構成にできます。
- **DI / Microsoft Options:** `Configlue.Extensions.DI` と `Configlue.Extensions.MSOptions` が利用できます。Microsoft Options の同期ゲッターは非同期ソース読み取り中にブロックするため、非同期フローでは `GetValueAsync` を推奨します。
- **リアクティブ:** 任意の `Configlue.Extensions.Reactive` と `Configlue.Extensions.R3` があり、`ObserveChanges()`、`ObserveValues()`、`ObserveReloadFailures()`、`ObserveActiveValues()`、`ObserveActiveProfileNames()` を利用できます。
- **テスト:** `Configlue.Testing` はインメモリのテストダブルを提供します。

## パッケージ

| パッケージ | 内容 |
| --- | --- |
| `Configlue` | Core、DI、JSON provider、JSON Schema、HTTP resources、標準ソース、環境変数ソース、ジェネレーターアナライザーをまとめたメタパッケージ |
| `Configlue.Abstraction` | Provider / Codec / Resource / 生成モデルの契約 |
| `Configlue.Core` | 解決と永続化のランタイム |
| `Configlue.Extensibility` | Provider SDK |
| `Configlue.Generator` | スパースなモデルサポートを生成する Roslyn アナライザー |
| `Configlue.Testing` | インメモリのテストダブル |
| `Configlue.Provider.Json` / `.Xml` / `.Yaml` | 各形式の Codec、セクション Resource、ファイル登録 |
| `Configlue.JsonSchema` | JSON Schema の生成とエクスポート |
| `Configlue.Source.Environment` / `.CommandLine` / `.Presets` | 環境変数、コマンドライン、標準ソースのプリセット |
| `Configlue.Source.Presets.Yaml` / `.Xml` | YAML / XML 用プリセット |
| `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip` | HTTP、ASP.NET Core、Dapr、S3、ZIP の Resource |
| `Configlue.Extensions.DI` / `.MSOptions` / `.R3` / `.Reactive` | DI、Microsoft Options、R3、Reactive の統合 |
| `Configlue.Transformer.AES` | Resource と Codec の間のバイト列を AES-GCM で暗号化・認証 |

## Microsoft.Extensions.Configuration との違い

`Microsoft.Extensions.Configuration` の `IConfiguration` は読み取りを中心とした構成モデルです。Configlue は独立した Source の合成に加え、値の由来の検査や、変更したフィールドだけを特定の Source に保存する用途に向いています。

## 制限

- 異なる Resource にまたがる書き込みはアトミックではありません。
- Source の退役は現在の Options インスタンスに対して行われ、保存された実データは残ります。
- Source の集合は Options ランタイムごとに固定です。

## ライセンス

Apache-2.0



---

# ===== opencode-go/grok-4.7 =====

# Configlue

**Make easy configuration management.**

Configlue は、アプリケーションの設定管理を代行する .NET ライブラリです。複数の場所に散らばった設定を、1 つのモデルに結合（glue）します。名前は configuration + glue です。

- 対象: .NET 10 SDK 以降。C#（`LangVersion` はソースジェネレーター対応が必要。リポジトリは preview でビルド）
- ライセンス: Apache-2.0
- 現状はアーキテクチャ上の土台であり、`Configuration.Writable` を完全に置き換えるものではない

`Microsoft.Extensions.Configuration` の `IConfiguration` は読み取りが中心です。Configlue は、独立したソースの合成、値の来歴の検査、変更したフィールドだけの保存に向きます。

## なぜ Configlue か

JSON ファイルの読み書きだけなら数行で済みます。実際には、次の要件が積み重なります。

- 設定が複数箇所にある。グローバル設定、実行フォルダー、環境変数、コマンドライン引数、暗号化された資格情報、社内ポリシーや HTTP API などのリモート管理
- ファイルが書き換わったら、再起動なしで反映したい（変更通知）
- 書き込み先を自動で選びたい。環境変数から読んだ値への書き込みはエラーにしたい
- 設定ファイルは人間が書く。コメントを消さない、JSON Schema がほしい、壊れたファイルに対処したい
- 既定値のままなら書き出さない。ただしユーザーが明示した `null` は尊重する
- 旧形式から新形式への自動変換
- バックアップと自動整理
- 書き込みの安全性。アトミック性（クラッシュしても壊れない）、他プロセスとの競合検出と自動マージ、自動リトライ

これらを自前で実装するのは面倒です。Configlue はその共通部分を引き受けます。

## アーキテクチャ

依存は直線的です。学習順も同じです。

```text
Resource (location) → Codec (conversion) → Source (contribution) → Fragment (diff) → Options (facade)
                                                        ↘ Patch (edit fragment)
```

| 概念 | 一言で | 例 |
| --- | --- | --- |
| Resource | バイトがどこにあるか | ファイル、ZIP エントリ、HTTP 応答、メモリ |
| Codec | バイトと値の変換 | JSON / XML / YAML の読み書き |
| Source | 論理的な寄与（どのフィールドをどの優先度で） | 「ユーザー設定ファイルの Server 部分」 |
| Fragment | 存在を記憶する差分 | 「Port だけ」を持つ状態 |
| Patch | 単一フィールドの編集 | 「Port を 9000 にする」 |
| Options | アプリが見るファサード | 読み・保存・監視・説明・診断 |

**読み込み。** 各 Source が Resource からバイトを取得し、Codec が Fragment に変換します。ランタイムは優先度順に、「存在する」フィールドだけを 1 つのモデルへ重ねます。

**書き込み。** 逆向きです。アプリは普通のモデル値を編集します。内部では変更が Fragment 差分になり、`WriteRoute` / `WritePlan` が指す Source にだけ届きます。無関係な Source は変わりません。

- Fragment は「メンバーが存在しない」と「null または既定値で存在する」を区別します。層の合成で、「未設定」が「既定値に設定」を上書きすることはありません。
- Patch は生成される `TModel.Patch`（単一フィールドの編集フラグメント）です。`Unset()` は書き込み先 Source の寄与だけを取り消し、下位優先度の値を再び見せます。
- `[ConfiglueMerge]` でメンバーごとのマージを変えられます。組み込みは `Append`、`Deep`、`Replace`、`SetUnion`。カスタム戦略も使えます。コレクションの層合成と順序はここで決まります。

## インストール

```sh
dotnet add package Configlue
```

`Configlue` はユーザー向けメタパッケージです。Core、DI、JSON provider、JSON Schema、HTTP resources、common sources、environment source、generator analyzer を同梱します。実装アセンブリは持ちません。XML、YAML、S3 など、必要な機能パッケージを追加します。

## Quick Start

`example.cs` に保存し、`dotnet run example.cs` で実行します（.NET 10 以降）。

```csharp
#!/usr/bin/env dotnet
#:package Configlue@*

using Configlue;
using Configlue.Source.Presets;

// 1. Declare the settings model. The generator creates Fragment/Patch support.
[ConfiglueModel("SampleSetting", Version = 1)]
public partial class SampleSetting
{
    public string Name { get; set; } = "World";
    public int RunCount { get; set; }
    public bool DefaultValue { get; set; } = true;
}

// 2. Declare the preset layers. Only the sources listed here are enabled.
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);

// 3. Read and write through the options instance.
var options = context.GetOptions<SampleSetting>();
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// Sparse edit: only modified fields are saved to the target layer.
await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue is not modified, so it will not be saved to the target layer.
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

モデルは `partial` にし、`[ConfiglueModel]` を付けます。ジェネレーターが Fragment / Patch を作ります。`UseCommonSources` は、ここで列挙した層だけを有効にします。`SaveAsync` は変更したフィールドだけを対象層へ書きます。

## 値の由来とスパース保存

`GetDetailsAsync` で、各値がどの Source から来たか、書き込めるかを調べられます。

```csharp
var options = context.GetOptions<AppSettings>();
// 1. 現在の値（全ソースをマージしたもの）を取得
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 2. 各値がどこから来たかを調べる
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

指定したメンバーだけを更新するパッチを保存します。`Unset()` はその Source の寄与を外し、下位優先度の Source が値を提供できるようにします。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

日常的に使う面は次のとおりです。

- `IReadOnlyOptions<T>` … 読み取りは `GetValueAsync` と `OnChange`
- `SaveAsync(patch => ...)` … 生成 Patch によるスパース保存
- `OpenEditSessionAsync()` … まとめて編集し、`CommitAsync` までインメモリ
- `ApplyPatchesAsync` と `StateSourcePatch` … ソースを明示した複数書き込み
- `StateWritePlan.For<T>().Route(...)` … 書き込みルーティング
- `SourceKey<TModel>` と `options.Source(key)` … ソース単位の操作

## 主な機能

- **優先度マージ。** `Priority` が大きい Source が勝ちます。由来は `GetDetailsAsync` で検査できます。
- **読み取り専用ソース。** 環境変数、コマンドライン、既定の HTTP ソースは読み取り専用です。そこから来た値への書き込みは黙って無視せず、競合エラーになります。
- **プロジェクション / マウント。** 既存 Source を別モデルに整形（projection）できます。ネストしたパスへ別 Source を接続する（mount、`AddMounted`）こともできます。
- **プリセット。** `UseCommonSources` が global / local / environment などの標準的な層を組み立てます。
- **スパース書き込み。** 変更したフィールドだけを対象層に保存します。既定値のままのフィールドは書かれません。
- **編集セッション。** `OpenEditSessionAsync` で複数変更をまとめます。`CommitAsync` までインメモリです。競合時は既定で失敗します。`WriteConflictResolution.LastWriteWins` も選べます。
- **スキーマ移行 / ストレージ移行。** `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` で、旧バージョンを自動変換します。既存ファイルを Source として登録できます。
- **バックアップと復元。** `FileResource` はアトミック書き込みとバックアップ世代管理をします。既定は `.bak` 1 世代です。`RestoreLatestBackupAsync` で復元します。
- **安全な書き込み。** アトミック性、競合検出、リトライ。
- **セクション。** `JsonSectionResource`、XML 要素、YAML マッピングで、ファイルの一部を独立した Resource として扱えます。書き込み時はコメント、空白、引用、スカラー形式を保持します。同じファイル内の独立セクションは、1 回の物理書き込みにバッチされます。
- **ZIP / HTTP / S3 / Dapr。** `ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込みとポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **JSON Schema。** `Configlue.JsonSchema` で生成・エクスポートします。人間が設定を書くためです。
- **Native AOT。** ソース生成の `JsonSerializerContext` を渡すと、トリミングと AOT に強くなります。
- **リアクティブ（任意）。** `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）。`ObserveChanges()`、`ObserveValues()`、`ObserveReloadFailures()`、`ObserveActiveValues()`、`ObserveActiveProfileNames()`。
- **DI。** `Configlue.Extensions.DI`。Microsoft の options アダプターは `Configlue.Extensions.MSOptions`（`IOptions<T>` など）。同期ゲッターは非同期ソースの読み取り中にブロックするため、非同期フローでは `GetValueAsync` を使います。
- **プロファイル / 動的オプション。** 名前付きオプションや永続プロファイルで、ランタイムを単位に作成・削除できます。

## パッケージ

| パッケージ | 役割 |
| --- | --- |
| `Configlue` | ユーザー向けメタパッケージ。実装アセンブリは持たない |
| `Configlue.Abstraction` | 契約（provider / codec / resource / generated-model） |
| `Configlue.Core` | 解決と永続化のランタイム |
| `Configlue.Extensibility` | プロバイダー SDK |
| `Configlue.Extensions.DI` | DI 統合 |
| `Configlue.Extensions.MSOptions` | `IOptions<T>` などのアダプター |
| `Configlue.Extensions.Reactive` | System.Reactive 統合 |
| `Configlue.Extensions.R3` | R3 統合 |
| `Configlue.Generator` | Roslyn アナライザー（スパースなモデルサポートの生成） |
| `Configlue.Testing` | インメモリのテストダブル |
| `Configlue.Provider.Json` / `.Xml` / `.Yaml` | 各形式の Codec、セクションリソース、ファイル登録 |
| `Configlue.JsonSchema` | JSON Schema の生成・エクスポート |
| `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml` | 環境変数、コマンドライン、プリセット |
| `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip` | リモートおよびアーカイブの Resource |
| `Configlue.Transformer.AES` | Resource と Codec の間のバイトを AES-GCM で暗号化・認証 |

## 既知の制限

- 異なる Resource 間の書き込みはアトミックではない
- Source の退役は現在の options インスタンスに閉じる。実データは残る
- Source の集合は、options ランタイムで固定される

## ライセンス

Apache-2.0



---

# ===== opencode-go/hy4-preview =====

# Configlue

**Make easy configuration management.**

Configlue は、アプリケーションの設定管理を代行する .NET ライブラリです。

複数の場所に散らばった設定（グローバル設定ファイル、実行フォルダーの設定、環境変数、コマンドライン引数、暗号化された資格情報、リモートの管理 API など）を、優先度付きの「層」として合成し、アプリケーションには 1 つのモデルとして見せます。読み取りだけでなく、**どこへ書き戻すか**まで面倒を見るのが特徴です。

- 対象: .NET 10 SDK 以降 / C#
- ライセンス: Apache-2.0

なお現時点の Configlue は「アーキテクチャ上の土台」であり、`Configuration.Writable` を完全に置き換えるものではありません。

---

## Why Configlue?

JSON ファイルを 1 つ読み書きするだけなら、数行のコードで済みます。しかし実際のアプリケーションでは、次のような要件が次々に積み重なります。

| 課題 | Configlue での扱い |
| --- | --- |
| 設定が複数箇所に散らばっている | Source ごとに優先度を付けて 1 つのモデルへ合成 |
| ファイルの変更を再起動なしで反映したい | 変更通知（`OnChange` / リアクティブ拡張） |
| 書き込み先を自動で選びたい | `WriteRoute` / `WritePlan` による書き込みルーティング |
| 読み取り専用の値（環境変数など）への書き込み | 黙って無視せず競合エラーにする |
| 設定ファイルは人間が書く | コメント・書式の保持、JSON Schema 生成、壊れたファイルの扱い |
| 既定値のままの項目は書き出したくない | スパース書き込み（ただしユーザーが明示した `null` は尊重） |
| 設定ファイルのバージョンアップ | `[ConfigluePreviousVersion]` による旧形式からの自動変換 |
| 書き込みで設定を壊したくない | アトミック書き込み、競合検出、自動リトライ、バックアップ |

これらを個別に自前実装するのは手間がかかります。Configlue はこの一連の処理を、後述する 6 つの概念に分解して提供します。

---

## インストール

```bash
dotnet add package Configlue
```

`Configlue` はユーザー向けのメタパッケージです（Core / DI / JSON provider / JSON Schema / HTTP resources / common sources / environment source / generator analyzer を同梱。実装アセンブリは持ちません）。ZIP・XML・YAML・S3・Dapr・リアクティブ統合などを使う場合は、後述のパッケージ一覧から必要なものを追加します。

---

## Quick Start

以下を `example.cs` に保存し、`dotnet run example.cs` で実行できます（.NET 10 以降）。

```csharp
#!/usr/bin/env dotnet
#:package Configlue@*

using Configlue;
using Configlue.Source.Presets;

// 1. Declare the settings model. The generator creates Fragment/Patch support.
[ConfiglueModel("SampleSetting", Version = 1)]
public partial class SampleSetting
{
    public string Name { get; set; } = "World";
    public int RunCount { get; set; }
    public bool DefaultValue { get; set; } = true;
}

// 2. Declare the preset layers. Only the sources listed here are enabled.
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);

// 3. Read and write through the options instance.
var options = context.GetOptions<SampleSetting>();
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// Sparse edit: only modified fields are saved to the target layer.
await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue is not modified, so it will not be saved to the target layer.
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

ポイントは 3 つです。

1. `[ConfiglueModel]` を付けた `partial` クラスを宣言すると、ソースジェネレーターがスパースな読み書きに必要な `Fragment` / `Patch` のサポートを生成します。
2. `UseCommonSources` で「どの層を有効にするか」を明示します。ここに書いた Source だけが使われます。
3. アプリケーションは `GetOptions<T>()` が返すファサードに対して、モデルの読み取りと保存だけを行います。

---

## 基本アーキテクチャ（6 つの概念）

概念の依存関係は直線的で、学習順も同じです。

```text
Resource (location) → Codec (conversion) → Source (contribution) → Fragment (diff) → Options (facade)
                                                        ↘ Patch (edit fragment)
```

| 概念 | 一言で | 例 |
| --- | --- | --- |
| Resource | バイトがどこにあるか | ファイル、ZIP エントリ、HTTP 応答、メモリ |
| Codec | バイト ↔ 値の変換 | JSON / XML / YAML の読み書き |
| Source | 論理的な寄与（どのフィールドをどの優先度で） | 「ユーザー設定ファイルの Server 部分」 |
| Fragment | 存在を記憶する差分 | 「`Port` だけ」を持つ状態 |
| Patch | 単一フィールドの編集 | 「`Port` を 9000 にする」 |
| Options | アプリが見るファサード | 読み・保存・監視・説明・診断 |

### 読み込み

各 Source が Resource からバイトを取得し、Codec がそれを Fragment に変換します。ランタイムは優先度順に、**「存在する」フィールドだけ**を 1 つのモデルへ重ねていきます。

Fragment は「メンバーが存在しない」ことと、「`null` / 既定値で存在する」ことを区別します。そのため層の合成時に、「未設定」が下位優先度の「既定値に設定」を誤って上書きすることがありません。

### 書き込み

書き込みは逆向きです。アプリケーションは通常のモデル値を編集しますが、内部では変更が Fragment の差分になり、`WriteRoute` / `WritePlan` が指す Source にだけ届きます。無関係な Source は変更されません。

`Patch` はソースジェネレーターが生成する `TModel.Patch` 型です。`Unset()` を呼ぶと書き込み先 Source の寄与だけを取り消し、下位優先度の Source が再び値を提供できるようになります。

メンバーごとのマージ挙動は `[ConfiglueMerge]` で変更できます。組み込みの戦略は `Append` / `Deep` / `Replace` / `SetUnion` で、カスタム戦略も定義可能です。コレクションを層をまたいでどう合成し、どう並べるかはここで決まります。

---

## 主な機能

- **複数ソースの優先度マージ**: `Priority` が大きい Source が勝ちます。`GetDetailsAsync` で「どの値がどこ由来か」を検査できます。
- **読み取り専用ソース**: 環境変数・コマンドライン・既定の HTTP ソースは読み取り専用です。読み取り専用の値への書き込みは黙って無視されず、競合エラーになります。
- **プロジェクション / マウント**: 既存 Source を別モデルに整形（projection）したり、ネストしたパスに別 Source を接続（mount, `AddMounted`）できます。
- **プリセット**: `UseCommonSources` が標準的な層構成（global / local / environment など）を組み立てます。
- **スパース書き込み**: 変更されたフィールドだけが対象の層に保存されます。既定値のままのフィールドは書き出されません。
- **編集セッション**: `OpenEditSessionAsync()` で複数の変更をまとめて適用できます。`CommitAsync` まではインメモリです。競合時は既定で失敗し、`WriteConflictResolution.LastWriteWins` も選択できます。
- **スキーマ移行 / ストレージ移行**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` により、旧バージョンの設定を自動変換します。既存ファイルを Source としてそのまま登録できます。
- **バックアップと復元**: `FileResource` はアトミック書き込みとバックアップの世代管理を行います。既定は `.bak` 1 世代で、`RestoreLatestBackupAsync` で復元できます。
- **安全な書き込み**: アトミック性、競合検出、自動リトライ。
- **セクション**: `JsonSectionResource` / XML 要素 / YAML マッピングにより、ファイルの一部を独立した Resource として扱えます。書き込み時にコメント・空白・引用・スカラー形式は保持され、同一ファイル内の独立セクションは 1 回の物理書き込みにまとめられます。
- **ZIP / HTTP / S3 / Dapr**: `ZipEntryResource`、`Configlue.Resource.Http`（ETag による条件付き書き込みとポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **JSON Schema 生成**: `Configlue.JsonSchema`。人間が設定ファイルを書くためのスキーマを出力します。
- **Native AOT 対応**: ソース生成した `JsonSerializerContext` を渡すと、トリミング / AOT に強くなります。
- **リアクティブ統合（任意）**: `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）。`ObserveChanges()`, `ObserveValues()`, `ObserveReloadFailures()`, `ObserveActiveValues()`, `ObserveActiveProfileNames()` を提供します。
- **DI 統合**: `Configlue.Extensions.DI`。Microsoft の options アダプターとして `Configlue.Extensions.MSOptions`（`IOptions<T>` など）もあります。同期ゲッターは非同期ソースの読み取り中にブロックするため、非同期フローでは `GetValueAsync` を推奨します。
- **プロファイル / 動的オプション**: 名前付きオプションや永続プロファイルにより、ランタイムを単位として作成・削除できます。

### 既知の制限

- 異なる Resource をまたぐ書き込みはアトミックではありません。
- Source の退役は現在の options インスタンスに閉じ、実データは残ります。
- Source の集合は options ランタイム単位で固定されます。

---

## 値の由来を調べる / スパースに保存する

```csharp
var options = context.GetOptions<AppSettings>();

// 1. 現在の値（全ソースをマージしたもの）を取得
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 2. 各値がどこから来たかを調べる
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

指定したメンバーだけを更新するパッチを保存できます。`Unset()` はその Source の寄与を外し、下位優先度の Source が値を提供できるようにします。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

### その他の API

| API | 用途 |
| --- | --- |
| `IReadOnlyOptions<T>` | 日常の読み取り面（`GetValueAsync` と `OnChange`） |
| `SaveAsync(patch => ...)` | 生成された Patch によるスパース保存 |
| `OpenEditSessionAsync()` | 複数変更をまとめて編集し `CommitAsync` |
| `ApplyPatchesAsync` + `StateSourcePatch` | 明示的なソース別マルチ書き込み |
| `StateWritePlan.For<T>().Route(...)` | 書き込みルーティングの指定 |
| `SourceKey<TModel>` と `options.Source(key)` | ソース単位の操作 |

---

## Microsoft.Extensions.Configuration との違い

`Microsoft.Extensions.Configuration` の `IConfiguration` は読み取り中心のフラットなキー／値ストアで、「設定を読む」用途には十分です。一方 Configlue は、次に挙げるような要件に焦点を当てています。

- **独立したソースの合成**: 由来の異なる設定を、優先度付きの層として型付きモデルに合成する。
- **来歴の検査**: `GetDetailsAsync` により、どの値がどの Source 由来で、書き込み可能かどうかを実行時に確認できる。
- **スパース保存**: 変更したフィールドだけを、しかるべき層へ書き戻す。
- **人間が書く設定ファイルの尊重**: コメントや書式の保持、スキーマ生成、バージョン移行。

単純に設定を読むだけであれば既存の仕組みで十分です。書き戻し・優先度合成・来歴の可視化が必要になったときに、Configlue が選択肢になります。

---

## パッケージ構成（主要なもの）

| パッケージ | 内容 |
| --- | --- |
| `Configlue` | ユーザー向けメタパッケージ |
| `Configlue.Abstraction` | 契約（provider / codec / resource / generated-model） |
| `Configlue.Core` | 解決と永続化のランタイム |
| `Configlue.Extensibility` | プロバイダー SDK |
| `Configlue.Extensions.DI` | DI 統合 |
| `Configlue.Extensions.MSOptions` | `IOptions<T>` アダプター |
| `Configlue.Extensions.Reactive` / `.R3` | リアクティブ統合 |
| `Configlue.Generator` | Roslyn アナライザー（スパースなモデルサポート生成） |
| `Configlue.Testing` | インメモリのテストダブル |
| `Configlue.Provider.Json` / `.Xml` / `.Yaml` | 各形式の Codec・セクションリソース・ファイル登録 |
| `Configlue.JsonSchema` | JSON Schema 生成・エクスポート |
| `Configlue.Source.Environment` / `.CommandLine` | 環境変数 / コマンドラインソース |
| `Configlue.Source.Presets` / `.Presets.Yaml` / `.Presets.Xml` | 標準的な層構成のプリセット |
| `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip` | 各種 Resource |
| `Configlue.Transformer.AES` | Resource と Codec の間のバイトを AES-GCM で暗号化・認証 |

---

## ライセンス

Apache-2.0



---

# ===== opencode-go/kimi-k3 =====

# Configlue

**Make easy configuration management.**

Configlue は、アプリケーションの設定管理（configuration management）を代行する .NET ライブラリです。複数の場所に散らばった設定を 1 つのモデルに**結合（glue）**することを中心的な考え方としており、名前も configuration + glue に由来します。

- **対象**: .NET 10 SDK 以降（C#。ソースジェネレーター対応の `LangVersion` が必要。リポジトリは preview でビルド）
- **ライセンス**: Apache-2.0

> **現状について**: Configlue は現時点で「アーキテクチャ上の土台」であり、`Configuration.Writable` を完全に置き換えるものではありません。

## Why Configlue?

JSON ファイルの読み書きだけなら数行で済みます。しかし実際のアプリケーションでは、次のような要件が積み重なっていきます。

- **設定が複数箇所にある**: グローバル設定、実行フォルダー設定、環境変数、コマンドライン引数、暗号化された資格情報、社内ポリシーや HTTP API などのリモート管理。
- **変更通知**: 設定ファイルが書き換わったら、再起動なしで反映したい。
- **書き込み先の自動選択**: 環境変数から読んだ値への書き込みはエラーにしたい。
- **人間が書く設定ファイル**: コメントを消さない、JSON Schema がほしい、壊れたファイルへの対処。
- **スパースな保存**: 既定値のままなら書き出さない（ただしユーザーが明示した `null` は尊重する）。
- **設定ファイルのバージョンアップ**: 旧形式から新形式への自動変換。
- **バックアップと自動整理**。
- **書き込みの安全性**: アトミック性（クラッシュしても壊れない）、他プロセスとの競合検出・自動マージ、自動リトライ。

これらを自前で実装するのは面倒です。Configlue はこの「面倒」を引き受けます。

## インストール

```console
dotnet add package Configlue
```

`Configlue` はユーザー向けのメタパッケージで、Core / DI / JSON provider / JSON Schema / HTTP resources / common sources / environment source / generator analyzer を同梱します（実装アセンブリは持ちません）。必要に応じて機能パッケージを追加してください（[パッケージ構成](#パッケージ構成)を参照）。

## Quick Start

以下の内容を `example.cs` に保存し、`dotnet run example.cs` で実行できます（.NET 10 以降）。

```csharp
#!/usr/bin/env dotnet
#:package Configlue@*

using Configlue;
using Configlue.Source.Presets;

// 1. Declare the settings model. The generator creates Fragment/Patch support.
[ConfiglueModel("SampleSetting", Version = 1)]
public partial class SampleSetting
{
    public string Name { get; set; } = "World";
    public int RunCount { get; set; }
    public bool DefaultValue { get; set; } = true;
}

// 2. Declare the preset layers. Only the sources listed here are enabled.
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);

// 3. Read and write through the options instance.
var options = context.GetOptions<SampleSetting>();
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// Sparse edit: only modified fields are saved to the target layer.
await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue is not modified, so it will not be saved to the target layer.
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

ポイント:

1. **モデルの宣言**: `[ConfiglueModel]` を付けると、ジェネレーターが Fragment / Patch のサポートコードを生成します。
2. **層の宣言**: `UseCommonSources` が標準的な層構成（global / local / environment など）を組み立てます。ここに列挙した Source だけが有効になります。
3. **読み書き**: `GetValueAsync` で全ソースをマージした現在値を取得し、`SaveAsync` で変更したフィールドだけを対象層へスパース保存します。

## 基本アーキテクチャ（6 つの概念）

依存関係は直線的で、学習順も同じです。

```text
Resource (location) → Codec (conversion) → Source (contribution) → Fragment (diff) → Options (facade)
                                                        ↘ Patch (edit fragment)
```

| 概念 | 一言で | 例 |
| --- | --- | --- |
| Resource | バイトがどこにあるか | ファイル、ZIP エントリ、HTTP 応答、メモリ |
| Codec | バイト↔値の変換 | JSON / XML / YAML の読み書き |
| Source | 論理的な寄与（どのフィールドをどの優先度で） | 「ユーザー設定ファイルの Server 部分」 |
| Fragment | 存在を記憶する差分 | 「Port だけ」を持つ状態 |
| Patch | 単一フィールドの編集 | 「Port を 9000 にする」 |
| Options | アプリが見るファサード | 読み・保存・監視・説明・診断 |

**読み込み**: 各 Source が Resource からバイトを取得し、Codec が Fragment に変換します。ランタイムが優先度順に「存在する」フィールドだけを 1 つのモデルへ重ねます。

**書き込み**: 逆向きです。アプリは普通のモデル値を編集します。内部では変更が Fragment 差分になり、`WriteRoute` / `WritePlan` が指す Source にだけ届きます。無関係な Source は変更されません。

重要な性質:

- **Fragment は「存在」を記憶する**: 「メンバーが存在しない」と「null / 既定値で存在する」を区別します。層の合成で「未設定」が「既定値に設定」を上書きすることはありません。
- **Patch と `Unset()`**: Patch は生成される `TModel.Patch`（単一フィールドの編集フラグメント）です。`Unset()` は書き込み先 Source の寄与だけを取り消し、下位優先度の値を再び見せます。
- **マージ戦略**: `[ConfiglueMerge]` でメンバーごとのマージ挙動を変更できます（組み込み: `Append`, `Deep`, `Replace`, `SetUnion`。カスタム戦略も可能）。コレクションの層合成・順序はここで決まります。

## 主な機能

- **複数ソースの優先度マージ**: `Priority` が大きい Source が勝ちます。`GetDetailsAsync` で「どの値がどこ由来か」を検査できます。
- **読み取り専用ソース**: 環境変数・コマンドライン・既定の HTTP ソースは読み取り専用です。読み取り専用の値への書き込みは黙って無視されず、競合エラーになります。
- **プロジェクション / マウント**: 既存 Source を別モデルに整形（projection）したり、ネストしたパスに別 Source を接続（mount、`AddMounted`）したりできます。
- **プリセット**: `UseCommonSources` が標準的な層構成（global / local / environment など）を組み立てます。
- **スパース書き込み**: 変更したフィールドだけを対象層に保存します。既定値のままのフィールドは書かれません。
- **編集セッション**: `OpenEditSessionAsync` で複数変更をまとめて適用します。`CommitAsync` まではインメモリです。競合時は既定で失敗し、`WriteConflictResolution.LastWriteWins` も選べます。
- **スキーマ移行 / ストレージ移行**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` により、旧バージョン設定を自動変換します。既存ファイルを Source として登録できます。
- **バックアップと復元**: `FileResource` はアトミック書き込みとバックアップ世代管理を備えます。既定で `.bak` を 1 世代保持し、`RestoreLatestBackupAsync` で復元できます。
- **安全な書き込み**: アトミック性、競合検出、リトライ。
- **セクション**: `JsonSectionResource` / XML 要素 / YAML マッピングで、ファイルの一部を独立した Resource として扱えます。書き込み時はコメント・空白・引用・スカラー形式を保持します。同じファイル内の独立セクションは 1 回の物理書き込みにバッチされます。
- **ZIP / HTTP / S3 / Dapr**: `ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込み・ポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **JSON Schema 生成**: `Configlue.JsonSchema`。人間が設定を書くための支援です。
- **Native AOT 対応**: ソース生成の `JsonSerializerContext` を渡すと、トリミング / AOT に強くなります。
- **リアクティブ統合（任意）**: `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）。`ObserveChanges()`、`ObserveValues()`、`ObserveReloadFailures()`、`ObserveActiveValues()`、`ObserveActiveProfileNames()` を提供します。
- **DI 統合**: `Configlue.Extensions.DI`。Microsoft の options アダプター `Configlue.Extensions.MSOptions`（`IOptions<T>` など）もあります。同期ゲッターは非同期ソース読み取り中にブロックするため、非同期フローでは `GetValueAsync` を推奨します。
- **プロファイル / 動的オプション**: 名前付きオプションや永続プロファイルで、ランタイムを単位として作成・削除できます。

## 値の由来を調べる / スパース保存

```csharp
var options = context.GetOptions<AppSettings>();
// 1. 現在の値（全ソースをマージしたもの）を取得
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 2. 各値がどこから来たかを調べる
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

指定したメンバーだけを更新するパッチを保存できます。`Unset()` はその Source の寄与を外し、下位優先度の Source が値を提供できるようにします。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

### その他の API

- `IReadOnlyOptions<T>` … 日常の読み取り面は `GetValueAsync` と `OnChange`。
- `SaveAsync(patch => ...)` … 生成 Patch でスパース保存。
- `OpenEditSessionAsync()` … まとめて編集し `CommitAsync`。
- `ApplyPatchesAsync` + `StateSourcePatch` … 明示的なソース別マルチ書き込み。
- `StateWritePlan.For<T>().Route(...)` … 書き込みルーティング。
- `SourceKey<TModel>` と `options.Source(key)` … ソース単位の操作。

## パッケージ構成

| パッケージ | 役割 |
| --- | --- |
| `Configlue` | ユーザー向けメタパッケージ（Core / DI / JSON provider / JSON Schema / HTTP resources / common sources / environment source / generator analyzer を同梱。実装アセンブリは持たない） |
| `Configlue.Abstraction` | 契約（provider / codec / resource / generated-model） |
| `Configlue.Core` | 解決と永続化のランタイム |
| `Configlue.Extensibility` | プロバイダー SDK |
| `Configlue.Extensions.DI` | DI 統合 |
| `Configlue.Extensions.MSOptions` | Microsoft の options アダプター（`IOptions<T>` など） |
| `Configlue.Extensions.R3` / `Configlue.Extensions.Reactive` | リアクティブ統合 |
| `Configlue.Generator` | Roslyn アナライザー（スパースなモデルサポート生成） |
| `Configlue.Testing` | インメモリのテストダブル |
| `Configlue.Provider.Json` / `.Xml` / `.Yaml` | 各形式の Codec・セクションリソース・ファイル登録 |
| `Configlue.JsonSchema` | JSON Schema 生成・エクスポート |
| `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml` | 各種 Source とプリセット |
| `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip` | 各種 Resource |
| `Configlue.Transformer.AES` | Resource と Codec の間のバイトを AES-GCM 暗号化・認証 |

## 既知の制限

- 異なる Resource 間の書き込みはアトミックではありません。
- Source の退役は現在の options インスタンスに閉じ、実データは残ります。
- Source 集合は options ランタイムで固定です。

## Microsoft.Extensions.Configuration との違い

`IConfiguration` は読み取り中心の設計です。Configlue は、独立したソースの合成・値の来歴の検査・スパース保存に向いた設計になっています。設定を「読むだけ」でなく「どこから来た値かを把握し、安全に書き戻す」必要がある場合に適しています。

## ライセンス

Apache-2.0



---

# ===== opencode-go/longcat-2.5-preview-free =====

# Configlue

**Make easy configuration management.**

Configlue は、アプリケーションの設定管理を代行する .NET ライブラリです。複数の場所に散らばった設定を 1 つのモデルに結合（glue）します。名前のとおり、configuration + glue が由来です。

## 特徴

JSON ファイルの読み書きだけなら数行で済みます。しかし実際のアプリケーションでは、次のような要件が積み重なります。

- 設定が複数箇所にある: グローバル設定、実行フォルダー設定、環境変数、コマンドライン引数、暗号化された資格情報、社内ポリシーや HTTP API などのリモート管理
- 設定ファイルが書き換わったら再起動なしで反映したい（変更通知）
- 書き込み先を自動で選びたい。環境変数から読んだ値への書き込みはエラーにしたい
- 設定ファイルは人間が書く: コメントを消さない、JSON Schema がほしい、壊れたファイルへの対処
- 既定値のままなら書き出さない（ただしユーザーが明示した `null` は尊重する）
- 設定ファイルのバージョンアップ（旧形式→新形式への自動変換）
- バックアップと自動整理
- 書き込みの安全性: アトミック性（クラッシュしても壊れない）、他プロセスとの競合検出・自動マージ、自動リトライ

Configlue はこれらをまとめて処理します。

## アーキテクチャ

依存関係は直線的で、学習順も同じです。

```text
Resource (location) → Codec (conversion) → Source (contribution) → Fragment (diff) → Options (facade)
                                                        ↘ Patch (edit fragment)
```

| 概念 | 説明 | 例 |
| --- | --- | --- |
| Resource | バイトがどこにあるか | ファイル、ZIPエントリ、HTTP応答、メモリ |
| Codec | バイト↔値の変換 | JSON / XML / YAML の読み書き |
| Source | 論理的な寄与（どのフィールドをどの優先度で） | 「ユーザー設定ファイルの Server 部分」 |
| Fragment | 存在を記憶する差分 | 「Port だけ」を持つ状態 |
| Patch | 単一フィールドの編集 | 「Port を 9000 にする」 |
| Options | アプリが見るファサード | 読み・保存・監視・説明・診断 |

**読み込み**: 各 Source が Resource からバイトを取得し、Codec が Fragment に変換します。ランタイムが優先度順に「存在する」フィールドだけを 1 つのモデルへ重ねます。

**書き込み**: 逆向きです。アプリは普通のモデル値を編集します。内部では変更が Fragment 差分になり、`WriteRoute` / `WritePlan` が指す Source にだけ届きます。無関係な Source は変更されません。

- Fragment は「メンバーが存在しない」と「null/既定値で存在する」を区別します。層の合成で「未設定」が「既定値に設定」を上書きすることはありません。
- Patch は生成される `TModel.Patch`（単一フィールドの編集フラグメント）です。`Unset()` は書き込み先 Source の寄与だけを取り消し、下位優先度の値を再び見せます。
- `[ConfiglueMerge]` でメンバーごとのマージ挙動を変更できます（組み込み: `Append`, `Deep`, `Replace`, `SetUnion`、カスタム戦略も可）。コレクションの層合成・順序はここで決まります。

## 主な機能

- **複数ソースの優先度マージ**: `Priority` が大きい Source が勝ちます。`GetDetailsAsync` で「どの値がどこ由来か」を検査できます。
- **読み取り専用ソース**: 環境変数・コマンドライン・既定の HTTP ソースは読み取り専用です。読み取り専用の値への書き込みは黙って無視せず競合エラーになります。
- **プロジェクション / マウント**: 既存 Source を別モデルに整形（projection）したり、ネストしたパスに別 Source を接続（mount, `AddMounted`）できます。
- **プリセット**: `UseCommonSources` が標準的な層構成（global/local/environment など）を組み立てます。
- **スパース書き込み**: 変更したフィールドだけを対象層に保存します。既定値のままのフィールドは書かれません。
- **編集セッション**: `OpenEditSessionAsync` で複数変更をまとめて適用します。`CommitAsync` までインメモリです。競合時は既定で失敗し、`WriteConflictResolution.LastWriteWins` も選べます。
- **スキーマ移行 / ストレージ移行**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` による旧バージョン設定の自動変換。既存ファイルを Source として登録できます。
- **バックアップと復元**: `FileResource` はアトミック書き込みとバックアップ世代管理を行います。既定で `.bak` 1 世代、`RestoreLatestBackupAsync` で復元できます。
- **安全な書き込み**: アトミック性、競合検出、リトライ。
- **セクション**: `JsonSectionResource` / XML 要素 / YAML マッピングで、ファイルの一部を独立した Resource として扱えます。書き込み時はコメント・空白・引用・スカラー形式を保持します。同じファイル内の独立セクションは 1 回の物理書き込みにバッチされます。
- **ZIP / HTTP / S3 / Dapr**: `ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込み・ポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **JSON Schema 生成**: `Configlue.JsonSchema`。人間が設定を書くためのスキーマを生成・エクスポートします。
- **Native AOT 対応**: ソース生成の `JsonSerializerContext` を渡すとトリミング/AOT に強くなります。
- **リアクティブ統合（任意）**: `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）。`ObserveChanges()`, `ObserveValues()`, `ObserveReloadFailures()`, `ObserveActiveValues()`, `ObserveActiveProfileNames()` を提供します。
- **DI 統合**: `Configlue.Extensions.DI`。Microsoft の options アダプター `Configlue.Extensions.MSOptions`（`IOptions<T>` など。同期ゲッターは非同期ソース読み取り中ブロックするため、非同期フローでは `GetValueAsync` の使用を推奨）。
- **プロファイル / 動的オプション**: 名前付きオプションや永続プロファイルでランタイムを単位に作成・削除できます。

## 既知の制限

- 異なる Resource 間の書き込みはアトミックではありません。
- Source の退役は現在の options インスタンスに閉じ、実データは残ります。
- Source 集合は options ランタイムで固定されます。

## インストール

```bash
dotnet add package Configlue
```

必要な機能パッケージを追加してください。

## クイックスタート

`example.cs` に保存し `dotnet run example.cs` で実行します（.NET 10 以降）。

```csharp
#!/usr/bin/env dotnet
#:package Configlue@*

using Configlue;
using Configlue.Source.Presets;

// 1. Declare the settings model. The generator creates Fragment/Patch support.
[ConfiglueModel("SampleSetting", Version = 1)]
public partial class SampleSetting
{
    public string Name { get; set; } = "World";
    public int RunCount { get; set; }
    public bool DefaultValue { get; set; } = true;
}

// 2. Declare the preset layers. Only the sources listed here are enabled.
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);

// 3. Read and write through the options instance.
var options = context.GetOptions<SampleSetting>();
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// Sparse edit: only modified fields are saved to the target layer.
await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue is not modified, so it will not be saved to the target layer.
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

## 値の由来を調べる

```csharp
var options = context.GetOptions<AppSettings>();
// 1. 現在の値（全ソースをマージしたもの）を取得
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 2. 各値がどこから来たかを調べる
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

## スパース保存

指定したメンバーだけを更新するパッチを保存します。`Unset()` はその Source の寄与を外し、下位優先度の Source が値を提供できるようにします。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

## API 概要

- `IReadOnlyOptions<T>` … 日常の読み取り面は `GetValueAsync` と `OnChange`。
- `SaveAsync(patch => ...)` … 生成 Patch でスパース保存。
- `OpenEditSessionAsync()` … まとめて編集し `CommitAsync`。
- `ApplyPatchesAsync` + `StateSourcePatch` … 明示的なソース別マルチ書き込み。
- `StateWritePlan.For<T>().Route(...)` … 書き込みルーティング。
- `SourceKey<TModel>` と `options.Source(key)` … ソース単位の操作。

## パッケージ構成

- `Configlue` … ユーザー向けメタパッケージ（Core / DI / JSON provider / JSON Schema / HTTP resources / common sources / environment source / generator analyzer を同梱。実装アセンブリは持たない）
- `Configlue.Abstraction` … 契約（provider/codec/resource/generated-model）
- `Configlue.Core` … 解決と永続化のランタイム
- `Configlue.Extensibility` … プロバイダー SDK
- `Configlue.Extensions.DI` / `Configlue.Extensions.MSOptions` / `Configlue.Extensions.R3` / `Configlue.Extensions.Reactive`
- `Configlue.Generator` … Roslyn アナライザー（スパースなモデルサポート生成）
- `Configlue.Testing` … インメモリのテストダブル
- `Configlue.Provider.Json` / `.Xml` / `.Yaml` … 各形式の Codec・セクションリソース・ファイル登録
- `Configlue.JsonSchema` … JSON Schema 生成・エクスポート
- `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml`
- `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip`
- `Configlue.Transformer.AES` … Resource と Codec の間のバイトを AES-GCM 暗号化・認証

## Microsoft.Extensions.Configuration との違い

`Microsoft.Extensions.Configuration` の `IConfiguration` は読み取り中心の抽象化です。Configlue は独立したソースの合成、値の来歴の検査、スパース保存を主な用途とします。設定の書き込みや変更管理が重要な場面で力を発揮します。

## 動作要件

- .NET 10 SDK 以降
- C#（`LangVersion` はソースジェネレーター対応が必要、リポジトリは preview でビルド）

## ライセンス

Apache-2.0



---

# ===== opencode-go/mimo-v2.6-flash =====

context.md を唯一の情報源として、README 貼り用の日本語解説を作成しました（plan mode のためファイルには書き込んでいません。必要なら `README.ja.md` などへの保存を指示してください）。

---

```markdown
# Configlue

> Make easy configuration management.

Configlue は、アプリケーションの設定管理を代行する .NET ライブラリです。複数の場所に散らばった設定を 1 つのモデルに**結合（glue）** することを目指しており、名前は configuration + glue に由来します。

- 対象: .NET 10 SDK 以降（C#、ソースジェネレーター対応の `LangVersion`）
- ライセンス: Apache-2.0
- 現状は「アーキテクチャ上の土台」であり、`Configuration.Writable` を完全に置き換えるものではありません。

## なぜ Configlue なのか

JSON ファイルを読み書きするだけなら数行で済みます。しかし実際のアプリケーションでは、次の要件が積み重なっていきます。

- 設定が複数箇所にある: グローバル設定、実行フォルダー設定、環境変数、コマンドライン引数、暗号化された資格情報、社内ポリシーや HTTP API などのリモート管理。
- 設定ファイルが書き換わったら、再起動なしで反映したい（変更通知）。
- 書き込み先を自動で選びたい。環境変数から読んだ値への書き込みはエラーにしたい。
- 設定ファイルは人間が書く: コメントを消さない、JSON Schema がほしい、壊れたファイルへの対処をしたい。
- 既定値のままなら書き出したくない（ただし、ユーザーが明示した `null` は尊重する）。
- 設定ファイルのバージョンアップ（旧形式 → 新形式への自動変換）。
- バックアップと自動整理。
- 書き込みの安全性: アトミック性（クラッシュしても壊れない）、他プロセスとの競合検出・自動マージ、自動リトライ。

これらをすべて自前実装するのは面倒です。Configlue はその面倒を引き受けます。

## 基本アーキテクチャ

概念は 6 つだけです。依存関係は直線的なので、学習順も同じになります。

```text
Resource (location) → Codec (conversion) → Source (contribution) → Fragment (diff) → Options (facade)
                                                        ↘ Patch (edit fragment)
```

| 概念 | 一言で | 例 |
| --- | --- | --- |
| Resource | バイトがどこにあるか | ファイル、ZIP エントリ、HTTP 応答、メモリ |
| Codec | バイト ↔ 値の変換 | JSON / XML / YAML の読み書き |
| Source | 論理的な寄与（どのフィールドをどの優先度で） | 「ユーザー設定ファイルの Server 部分」 |
| Fragment | 存在を記憶する差分 | 「Port だけ」を持つ状態 |
| Patch | 単一フィールドの編集 | 「Port を 9000 にする」 |
| Options | アプリが見るファサード | 読み・保存・監視・説明・診断 |

**読み込み**では、各 Source が Resource からバイトを取得し、Codec がそれを Fragment に変換します。ランタイムが優先度順に「存在する」フィールドだけを 1 つのモデルへ重ね合わせます。

**書き込み**は逆方向です。アプリは普通のモデル値を編集するだけで、内部でその変更が Fragment 差分になり、`WriteRoute` / `WritePlan` が指す Source にだけ届きます。無関係な Source は変更されません。

設計上のポイント:

- Fragment は「メンバーが存在しない」と「null / 既定値で存在する」を区別します。層の合成で「未設定」が「既定値に設定」を上書きすることはありません。
- Patch は生成される `TModel.Patch`（単一フィールドの編集フラグメント）です。`Unset()` は書き込み先 Source の寄与だけを取り消し、下位優先度の値を再び見せます。
- `[ConfiglueMerge]` でメンバーごとのマージ挙動を変更できます（組み込み: `Append`, `Deep`, `Replace`, `SetUnion`、カスタム戦略も可）。コレクションの層合成と順序はここで決まります。

## Quick Start

`example.cs` に保存し、`dotnet run example.cs` で実行できます（.NET 10 以降）。

```csharp
#!/usr/bin/env dotnet
#:package Configlue@*

using Configlue;
using Configlue.Source.Presets;

// 1. Declare the settings model. The generator creates Fragment/Patch support.
[ConfiglueModel("SampleSetting", Version = 1)]
public partial class SampleSetting
{
    public string Name { get; set; } = "World";
    public int RunCount { get; set; }
    public bool DefaultValue { get; set; } = true;
}

// 2. Declare the preset layers. Only the sources listed here are enabled.
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);

// 3. Read and write through the options instance.
var options = context.GetOptions<SampleSetting>();
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// Sparse edit: only modified fields are saved to the target layer.
await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue is not modified, so it will not be saved to the target layer.
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

## 値の由来を調べる

どの値がどこから来たのか、書けるかどうかを検査できます。

```csharp
var options = context.GetOptions<AppSettings>();

// 1. 現在の値（全ソースをマージしたもの）を取得
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 2. 各値がどこから来たかを調べる
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

## スパース保存

指定したメンバーだけを更新するパッチを保存できます。`Unset()` はその Source の寄与を外し、下位優先度の Source が値を提供できるようにします。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

## 主な機能

- **複数ソースの優先度マージ**: `Priority` が大きい Source が勝ちます。`GetDetailsAsync` で「どの値がどこ由来か」を検査できます。
- **読み取り専用ソース**: 環境変数・コマンドライン・既定の HTTP ソースは読み取り専用です。読み取り専用の値への書き込みは黙って無視せず、競合エラーになります。
- **プロジェクション / マウント**: 既存 Source を別モデルに整形（projection）したり、ネストしたパスに別 Source を接続（mount、`AddMounted`）できます。
- **プリセット**: `UseCommonSources` が標準的な層構成（global / local / environment など）を組み立てます。
- **スパース書き込み**: 変更したフィールドだけを対象層に保存します。既定値のままのフィールドは書かれません。
- **編集セッション**: `OpenEditSessionAsync` で複数変更をまとめて適用し、`CommitAsync` までインメモリで保持します。競合時は既定で失敗、`WriteConflictResolution.LastWriteWins` も選べます。
- **スキーマ移行 / ストレージ移行**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` による旧バージョン設定の自動変換。既存ファイルを Source として登録できます。
- **バックアップと復元**: `FileResource` はアトミック書き込みとバックアップ世代管理を行います。既定で `.bak` 1 世代、`RestoreLatestBackupAsync` で復元します。
- **安全な書き込み**: アトミック性、競合検出、リトライ。
- **セクション**: `JsonSectionResource` / XML 要素 / YAML マッピングで、ファイルの一部を独立した Resource として扱えます。書き込み時はコメント・空白・引用・スカラー形式を保持し、同じファイル内の独立セクションは 1 回の物理書き込みにバッチされます。
- **ZIP / HTTP / S3 / Dapr**: `ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込み・ポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **JSON Schema 生成**: `Configlue.JsonSchema`。人間が設定を書くための支援です。
- **Native AOT 対応**: ソース生成の `JsonSerializerContext` を渡すと、トリミング / AOT に強くなります。
- **リアクティブ統合（任意）**: `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）。`ObserveChanges()`, `ObserveValues()`, `ObserveReloadFailures()`, `ObserveActiveValues()`, `ObserveActiveProfileNames()`。
- **DI 統合**: `Configlue.Extensions.DI`。Microsoft の options アダプターとして `Configlue.Extensions.MSOptions`（`IOptions<T>` など）もあります。同期ゲッターは非同期ソース読み取り中にブロックするため、非同期フローでは `GetValueAsync` を推奨します。
- **プロファイル / 動的オプション**: 名前付きオプションや永続プロファイルで、ランタイムを単位に作成・削除できます。

## 主要な API

- `IReadOnlyOptions<T>` … 日常の読み取り面は `GetValueAsync` と `OnChange`。
- `SaveAsync(patch => ...)` … 生成 Patch によるスパース保存。
- `OpenEditSessionAsync()` … まとめて編集し `CommitAsync`。
- `ApplyPatchesAsync` + `StateSourcePatch` … 明示的なソース別マルチ書き込み。
- `StateWritePlan.For<T>().Route(...)` … 書き込みルーティング。
- `SourceKey<TModel>` と `options.Source(key)` … ソース単位の操作。

## インストール

```bash
dotnet add package Configlue
```

`Configlue` はユーザー向けメタパッケージで、Core / DI / JSON provider / JSON Schema / HTTP resources / common sources / environment source / generator analyzer を同梱します（実装アセンブリ自体は持ちません）。必要な機能パッケージを追加してください。

| パッケージ | 役割 |
| --- | --- |
| `Configlue.Abstraction` | 契約（provider / codec / resource / generated-model） |
| `Configlue.Core` | 解決と永続化のランタイム |
| `Configlue.Extensibility` | プロバイダー SDK |
| `Configlue.Generator` | Roslyn アナライザー（スパースなモデルサポート生成） |
| `Configlue.Testing` | インメモリのテストダブル |
| `Configlue.Provider.Json` / `.Xml` / `.Yaml` | 各形式の Codec・セクションリソース・ファイル登録 |
| `Configlue.JsonSchema` | JSON Schema 生成・エクスポート |
| `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml` | 各種ソース |
| `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip` | 各種リソース |
| `Configlue.Extensions.DI` / `.MSOptions` / `.R3` / `.Reactive` | 統合拡張 |
| `Configlue.Transformer.AES` | Resource と Codec の間のバイトを AES-GCM で暗号化・認証 |

## Microsoft.Extensions.Configuration との違い

`IConfiguration` は読み取り中心の API で、providers の上位優先・下位フォールバックという片方向の合成モデルです。Configlue は独立した Source を優先度付きで合成し、各値の来歴（Source、書き込み可否、状態）を検査でき、変更したフィールドだけを対象層へ書き戻すことができます。読み取りだけでなく、書き込み経路・変更通知・スキーマ移行・バックアップまで含めて扱う場合に向いています。

## 既知の制限

- 異なる Resource 間の書き込みはアトミックではありません。
- Source の退役は現在の options インスタンスに閉じており、実データは残ります。
- Source 集合は options ランタイムで固定されます。

## ライセンス

Apache-2.0
```

---

必要であれば、この内容を `README.ja.md` などとして保存します（plan mode 解除後）。



---

# ===== opencode-go/mimo-v2.6-pro =====

# Configlue

**Make easy configuration management.**

Configlue は、アプリケーションの設定管理（configuration management）を代行する .NET ライブラリです。複数の場所に散らばった設定を 1 つのモデルに **結合（glue）** することを中心に設計されています（名前は configuration + glue）。

- 対象: .NET 10 SDK 以降 / C#（ソースジェネレーター対応の `LangVersion` が必要、リポジトリは preview でビルド）
- ライセンス: Apache-2.0
- 現状は「アーキテクチャ上の土台」であり、`Configuration.Writable` を完全に置き換えるものではありません

## なぜ Configlue なのか

JSON ファイルの読み書きだけなら数行で済みます。しかし実際のアプリケーションでは、次のような要件が積み重なります。

- 設定が複数箇所にある: グローバル設定、実行フォルダー設定、環境変数、コマンドライン引数、暗号化された資格情報、社内ポリシーや HTTP API などのリモート管理
- 設定ファイルが書き換わったら再起動なしで反映したい（変更通知）
- 書き込み先を自動で選びたい。環境変数から読んだ値への書き込みはエラーにしたい
- 設定ファイルは人間が書く: コメントを消さない、JSON Schema がほしい、壊れたファイルへの対処
- 既定値のままなら書き出さない（ただしユーザーが明示した `null` は尊重する）
- 設定ファイルのバージョンアップ（旧形式 → 新形式への自動変換）
- バックアップと自動整理
- 書き込みの安全性: アトミック性（クラッシュしても壊れない）、他プロセスとの競合検出・自動マージ、自動リトライ

これらを自前実装するのは面倒です。Configlue はこれらを一括で引き受けます。

### Microsoft.Extensions.Configuration との違い

`Microsoft.Extensions.Configuration` の `IConfiguration` は読み取り中心の構成です。Configlue は、独立したソースの合成・値の来歴の検査・スパース保存という、書き込みを含む設定管理に向いた構成を提供します。

## 基本アーキテクチャ

6 つの概念からなります。依存関係は直線的で、学習する順序も同じです。

```text
Resource (location) → Codec (conversion) → Source (contribution) → Fragment (diff) → Options (facade)
                                                        ↘ Patch (edit fragment)
```

| 概念 | 一言で | 例 |
| --- | --- | --- |
| Resource | バイトがどこにあるか | ファイル、ZIPエントリ、HTTP応答、メモリ |
| Codec | バイト ↔ 値の変換 | JSON / XML / YAML の読み書き |
| Source | 論理的な寄与（どのフィールドをどの優先度で） | 「ユーザー設定ファイルの Server 部分」 |
| Fragment | 存在を記憶する差分 | 「Port だけ」を持つ状態 |
| Patch | 単一フィールドの編集 | 「Port を 9000 にする」 |
| Options | アプリが見るファサード | 読み・保存・監視・説明・診断 |

**読み込み**: 各 Source が Resource からバイトを取得し、Codec が Fragment に変換します。ランタイムが優先度順に「存在する」フィールドだけを 1 つのモデルへ重ねます。

**書き込み**: 逆向きです。アプリは普通のモデル値を編集します。内部では変更が Fragment 差分になり、`WriteRoute` / `WritePlan` が指す Source にだけ届きます。無関係な Source は変更されません。

- Fragment は「メンバーが存在しない」と「null / 既定値で存在する」を区別します。層の合成で「未設定」が「既定値に設定」を上書きすることはありません。
- Patch は生成される `TModel.Patch`（単一フィールドの編集フラグメント）です。`Unset()` は書き込み先 Source の寄与だけを取り消し、下位優先度の値を再び見せます。
- `[ConfiglueMerge]` でメンバーごとのマージ挙動を変更できます（組み込み: `Append`, `Deep`, `Replace`, `SetUnion`、カスタム戦略も可）。コレクションの層合成・順序はここで決まります。

## 主な機能

- **複数ソースの優先度マージ** — `Priority` が大きい Source が勝ちます。`GetDetailsAsync` で「どの値がどこ由来か」を検査できます。
- **読み取り専用ソース** — 環境変数・コマンドライン・既定の HTTP ソースは読み取り専用です。読み取り専用の値への書き込みは黙って無視せず、競合エラーになります。
- **プロジェクション / マウント** — 既存 Source を別モデルに整形（projection）したり、ネストしたパスに別 Source を接続（mount, `AddMounted`）できます。
- **プリセット** — `UseCommonSources` が標準的な層構成（global / local / environment など）を組み立てます。
- **スパース書き込み** — 変更したフィールドだけを対象層に保存します。既定値のままのフィールドは書かれません。
- **編集セッション** — `OpenEditSessionAsync` で複数変更をまとめて適用します。`CommitAsync` までインメモリです。競合時は既定で失敗し、`WriteConflictResolution.LastWriteWins` も選べます。
- **スキーマ移行 / ストレージ移行** — `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` による旧バージョン設定の自動変換。既存ファイルを Source として登録できます。
- **バックアップと復元** — `FileResource` はアトミック書き込みとバックアップ世代管理。既定で `.bak` 1 世代、`RestoreLatestBackupAsync` で復元します。
- **安全な書き込み** — アトミック性、競合検出、リトライ。
- **セクション** — `JsonSectionResource` / XML 要素 / YAML マッピングで、ファイルの一部を独立した Resource として扱えます。書き込み時はコメント・空白・引用・スカラー形式を保持します。同じファイル内の独立セクションは 1 回の物理書き込みにバッチされます。
- **ZIP / HTTP / S3 / Dapr** — `ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込み・ポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **JSON Schema 生成** — `Configlue.JsonSchema`。人間が設定を書くための支援です。
- **Native AOT 対応** — ソース生成の `JsonSerializerContext` を渡すと、トリミング / AOT に強くなります。
- **リアクティブ統合（任意）** — `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）。`ObserveChanges()`, `ObserveValues()`, `ObserveReloadFailures()`, `ObserveActiveValues()`, `ObserveActiveProfileNames()`。
- **DI 統合** — `Configlue.Extensions.DI`。Microsoft の options アダプター `Configlue.Extensions.MSOptions`（`IOptions<T>` など）。同期ゲッターは非同期ソース読み取り中ブロックするので、非同期フローでは `GetValueAsync` の利用を推奨します。
- **プロファイル / 動的オプション** — 名前付きオプションや永続プロファイルで、ランタイムを単位に作成・削除できます。

### 既知の制限

- 異なる Resource 間の書き込みはアトミックではありません。
- Source の退役は現在の options インスタンスに閉じ、実データは残ります。
- Source 集合は options ランタイムで固定です。

## パッケージ構成

| パッケージ | 役割 |
| --- | --- |
| `Configlue` | ユーザー向けメタパッケージ。Core / DI / JSON provider / JSON Schema / HTTP resources / common sources / environment source / generator analyzer を同梱（実装アセンブリは持たない） |
| `Configlue.Abstraction` | 契約（provider / codec / resource / generated-model） |
| `Configlue.Core` | 解決と永続化のランタイム |
| `Configlue.Extensibility` | プロバイダー SDK |
| `Configlue.Extensions.DI` / `.MSOptions` / `.R3` / `.Reactive` | 各種統合 |
| `Configlue.Generator` | Roslyn アナライザー（スパースなモデルサポート生成） |
| `Configlue.Testing` | インメモリのテストダブル |
| `Configlue.Provider.Json` / `.Xml` / `.Yaml` | 各形式の Codec・セクションリソース・ファイル登録 |
| `Configlue.JsonSchema` | JSON Schema 生成・エクスポート |
| `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml` | 各種 Source |
| `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip` | 各種 Resource |
| `Configlue.Transformer.AES` | Resource と Codec の間のバイトを AES-GCM 暗号化・認証 |

インストールは `Configlue` メタパッケージから。必要に応じて機能パッケージを追加します。

```bash
dotnet add package Configlue
```

## Quick Start

`example.cs` に保存し、`dotnet run example.cs` で実行します（.NET 10 以降）。

```csharp
#!/usr/bin/env dotnet
#:package Configlue@*

using Configlue;
using Configlue.Source.Presets;

// 1. Declare the settings model. The generator creates Fragment/Patch support.
[ConfiglueModel("SampleSetting", Version = 1)]
public partial class SampleSetting
{
    public string Name { get; set; } = "World";
    public int RunCount { get; set; }
    public bool DefaultValue { get; set; } = true;
}

// 2. Declare the preset layers. Only the sources listed here are enabled.
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);

// 3. Read and write through the options instance.
var options = context.GetOptions<SampleSetting>();
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// Sparse edit: only modified fields are saved to the target layer.
await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue is not modified, so it will not be saved to the target layer.
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

## 値の由来を調べる / スパース保存

```csharp
var options = context.GetOptions<AppSettings>();
// 1. 現在の値（全ソースをマージしたもの）を取得
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 2. 各値がどこから来たかを調べる
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

指定したメンバーだけを更新するパッチを保存します。`Unset()` はその Source の寄与を外し、下位優先度の Source が値を提供できるようにします。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

### その他の API

- `IReadOnlyOptions<T>` … 日常の読み取り面は `GetValueAsync` と `OnChange`。
- `SaveAsync(patch => ...)` … 生成 Patch でスパース保存。
- `OpenEditSessionAsync()` … まとめて編集し `CommitAsync`。
- `ApplyPatchesAsync` + `StateSourcePatch` … 明示的なソース別マルチ書き込み。
- `StateWritePlan.For<T>().Route(...)` … 書き込みルーティング。
- `SourceKey<TModel>` と `options.Source(key)` … ソース単位の操作。



---

# ===== opencode-go/minimax-m3 =====

# Configlue

**設定管理を、簡単にする。**

Configlue は、.NET アプリケーション向けの設定管理ライブラリです。ファイル、環境変数、コマンドライン引数、リモート API など複数箇所に散らばった設定を、1 つのモデルに**結合（glue）**します。ライブラリ名は configuration + glue に由来します。

> **注意**: 現状は「アーキテクチャ上の土台」段階であり、`Microsoft.Extensions.Configuration.Writable` をそのまま置き換える完成品ではありません。

- **対象**: .NET 10 SDK 以降
- **言語**: C#（ソースジェネレーター対応版が必要、リポジトリは preview でビルド）
- **ライセンス**: Apache-2.0

---

## Configlue が解決する課題

JSON ファイルの読み書きは数行で済みます。しかし実運用では、次のような要件が積み重なります。

- **散在する設定**: グローバル設定、実行フォルダー設定、環境変数、コマンドライン、暗号化された資格情報、社内ポリシー、HTTP API などのリモート管理。
- **変更通知**: 設定ファイルが書き換わったら再起動なしで反映したい。
- **書き込み先の自動選択**: 環境変数から読んだ値への書き込みはエラーにしたい。
- **人が書く設定ファイル**: コメントを消さない、JSON Schema がほしい、壊れたファイルへの対処。
- **スパース保存**: 既定値のままなら書き出さない（明示的な `null` は尊重）。
- **スキーマ移行**: 旧形式から新形式への自動変換。
- **バックアップと世代管理**: 自動で整理したい。
- **安全な書き込み**: アトミック性（クラッシュしても壊れない）、他プロセスとの競合検出・自動マージ、自動リトライ。

これらを毎回自前で実装するのは面倒、というのが Configlue の動機です。

---

## 基本アーキテクチャ

依存関係は直線的で、学習もこの順です。

```
Resource (location) → Codec (conversion) → Source (contribution) → Fragment (diff) → Options (facade)
                                                          ↘ Patch (edit fragment)
```

| 概念 | 一言で | 例 |
| --- | --- | --- |
| **Resource** | バイトがどこにあるか | ファイル、ZIP エントリ、HTTP 応答、メモリ |
| **Codec** | バイト ↔ 値の変換 | JSON / XML / YAML の読み書き |
| **Source** | 論理的な寄与（どのフィールドをどの優先度で） | 「ユーザー設定ファイルの Server 部分」 |
| **Fragment** | 「存在」を記憶する差分 | 「Port だけ」を持つ状態 |
| **Patch** | 単一フィールドの編集 | 「Port を 9000 にする」 |
| **Options** | アプリが見るファサード | 読み・保存・監視・説明・診断 |

**読み込み**: 各 Source が Resource からバイトを取得し、Codec が Fragment に変換します。ランタイムが優先度順に「存在する」フィールドだけを 1 つのモデルへ重ねます。

**書き込み**: 逆向きです。アプリはモデル値を編集するだけ。内部では変更が Fragment 差分になり、`WriteRoute` / `WritePlan` が指す Source にだけ届きます。無関係な Source は変更されません。

- **Fragment** は「メンバーが存在しない」と「null/既定値で存在する」を区別します。層の合成で「未設定」が「既定値に設定」を上書きすることはありません。
- **Patch** はソースジェネレーターが生成する `TModel.Patch`（単一フィールドの編集フラグメント）。`Unset()` を呼ぶと、書き込み先 Source の寄与だけが取り消され、下位優先度の値が再び見えるようになります。
- **`[ConfiglueMerge]`** でメンバーごとのマージ挙動を変更可能（組み込み: `Append`, `Deep`, `Replace`, `SetUnion`、カスタム戦略も定義可）。

---

## 主な機能

- **複数ソースの優先度マージ**: `Priority` が大きい Source が勝つ。`GetDetailsAsync` で各値の**由来（プロvenance）**を検査できます。
- **読み取り専用ソース**: 環境変数・コマンドライン・既定の HTTP ソースは読み取り専用。読み取り専用 Source の値への書き込みは黙って無視されず、**競合エラー**として報告されます。
- **プロジェクション / マウント**: 既存 Source を別モデルへ整形（projection）したり、ネストしたパスに別 Source を接続（mount, `AddMounted`）できます。
- **プリセット**: `UseCommonSources` が global / local / environment などの標準的な層構成を組み立てます。
- **スパース書き込み**: 変更したフィールドだけを対象層に保存。既定値のままのフィールドは書き出されません。
- **編集セッション**: `OpenEditSessionAsync` で複数変更をまとめて適用し、`CommitAsync` で確定するまでインメモリで保持。競合時は既定で失敗、`WriteConflictResolution.LastWriteWins` も選べます。
- **スキーマ移行 / ストレージ移行**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` で旧バージョン設定を自動変換。既存ファイルを Source として登録できます。
- **バックアップと復元**: `FileResource` はアトミック書き込みとバックアップ世代管理（既定で `.bak` 1 世代）。`RestoreLatestBackupAsync` で復元。
- **安全な書き込み**: アトミック性、競合検出、自動リトライ。
- **セクション**: `JsonSectionResource` / XML 要素 / YAML マッピングで、ファイルの一部を独立した Resource として扱えます。書き込み時はコメント・空白・引用符・スカラー形式を保持。同じファイル内の独立セクションは 1 回の物理書き込みにバッチされます。
- **多彩なストレージ**: `ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込み・ポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **JSON Schema 生成**: `Configlue.JsonSchema`。人が設定を書くためのスキーマを出力。
- **Native AOT 対応**: ソース生成の `JsonSerializerContext` を渡すことでトリミング/AOT に強くなります。
- **リアクティブ統合**（任意）: `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）。`ObserveChanges()`, `ObserveValues()`, `ObserveReloadFailures()`, `ObserveActiveValues()`, `ObserveActiveProfileNames()` を提供。
- **DI 統合**: `Configlue.Extensions.DI` と、Microsoft の options アダプター `Configlue.Extensions.MSOptions`（`IOptions<T>` など）。同期ゲッターは非同期ソース読み取り中にブロックするため、非同期フローでは `GetValueAsync` の利用を推奨します。
- **プロファイル / 動的オプション**: 名前付きオプションや永続プロファイルをランタイム単位で作成・削除できます。

### 既知の制限

- 異なる Resource 間での書き込みはアトミックではありません。
- Source の退役は現在の options インスタンスに閉じた操作で、実データは残ります。
- Source 集合は options ランタイムで固定されます。

---

## インストール

```bash
dotnet add package Configlue
```

必要に応じて機能別パッケージを追加します。

### 主なパッケージ

| パッケージ | 役割 |
| --- | --- |
| `Configlue` | ユーザー向けメタパッケージ（Core / DI / JSON provider / JSON Schema / HTTP resources / common sources / environment source / generator analyzer を同梱。実装アセンブリは持たない）。 |
| `Configlue.Abstraction` | 契約（provider / codec / resource / generated-model）。 |
| `Configlue.Core` | 解決と永続化のランタイム。 |
| `Configlue.Extensibility` | プロバイダー SDK。 |
| `Configlue.Extensions.DI` / `.MSOptions` / `.R3` / `.Reactive` | DI、Microsoft.Extensions.Options 連携、リアクティブ統合。 |
| `Configlue.Generator` | Roslyn アナライザー。スパースなモデルサポートを生成。 |
| `Configlue.Testing` | インメモリテストダブル。 |
| `Configlue.Provider.Json` / `.Xml` / `.Yaml` | 各形式の Codec・セクションリソース・ファイル登録。 |
| `Configlue.JsonSchema` | JSON Schema 生成・エクスポート。 |
| `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml` | 各種 Source 実装。 |
| `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip` | 各種 Resource 実装。 |
| `Configlue.Transformer.AES` | Resource と Codec の間のバイトを AES-GCM で暗号化・認証。 |

---

## Quick Start

`example.cs` に保存し、.NET 10 以降で `dotnet run example.cs` で実行:

```csharp
#!/usr/bin/env dotnet
#:package Configlue@*

using Configlue;
using Configlue.Source.Presets;

// 1. 設定モデルを宣言。ジェネレーターが Fragment / Patch サポートを生成する。
[ConfiglueModel("SampleSetting", Version = 1)]
public partial class SampleSetting
{
    public string Name { get; set; } = "World";
    public int RunCount { get; set; }
    public bool DefaultValue { get; set; } = true;
}

// 2. プリセット層を宣言。ここで列挙した Source だけが有効になる。
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);

// 3. Options インスタンス越しに読み書きする。
var options = context.GetOptions<SampleSetting>();
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// スパース編集: 変更したフィールドだけが対象層に保存される。
await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue は変更していないので対象層には書き出されない。
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

---

## 値の由来を調べる / スパース保存

各フィールドがどの Source から来たかを確認できます。

```csharp
var options = context.GetOptions<AppSettings>();

// 1. 現在の値（全 Source をマージした結果）を取得
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 2. 各値の由来を調べる
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

指定したメンバーだけを更新するパッチを保存します。`Unset()` はその Source の寄与を外し、下位優先度の Source が値を提供できるようにします。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

---

## その他の API

- `IReadOnlyOptions<T>` — 日常の読み取り面は `GetValueAsync` と `OnChange`。
- `SaveAsync(patch => ...)` — 生成 Patch でスパース保存。
- `OpenEditSessionAsync()` — 複数変更をまとめて適用し、`CommitAsync` で確定。
- `ApplyPatchesAsync` + `StateSourcePatch` — 明示的なソース別マルチ書き込み。
- `StateWritePlan.For<T>().Route(...)` — 書き込みルーティング。
- `SourceKey<TModel>` と `options.Source(key)` — ソース単位の操作。

---

## `Microsoft.Extensions.Configuration` との関係

`IConfiguration` を主役とする `Microsoft.Extensions.Configuration` は主に**読み取り中心**の合成に向いています。Configlue は独立した Source を**対等な寄与**として扱い、

- 値の由来（プロvenance）の検査
- 読み取り専用 Source への書き込みを競合として検出
- スパース保存（変更箇所のみを対象層へ）
- アトミック書き込みとバックアップ世代管理

といった、書き込みを伴う「設定管理」に向きます。両者は対立するものではなく、用途や好みに応じて選び分けられます。設定の読み取りだけを軽く行いたい場面では `IConfiguration` の素朴さが有利です。一方、複数 Source を跨いで「どこ由来か」「ここは書き換えてはいけない」を扱いたいなら Configlue の方が素直に表現できます。

---

## ステータス

Configlue はまだアーキテクチャ上の土台段階です。`Microsoft.Extensions.Configuration.Writable` を完全に置き換える完成品ではなく、API は今後変更される可能性があります。フィードバックとコントリビューションを歓迎します。



---

# ===== opencode-go/muse-spark-1.3-contributor =====

調査メモを元にREADME用の日本語解説を作成します。# Configlue — Make easy configuration management.

Configlue は、アプリケーションの設定管理 (configuration management) を代行する .NET ライブラリです。

複数の場所に散らばった設定を 1 つのモデルに**結合 (glue)** するのが中心的な考え方で、名前も configuration + glue に由来します。

- 対象: .NET 10 SDK 以降 / C# (`LangVersion` はソースジェネレーター対応が必要、リポジトリは preview でビルド)
- ライセンス: Apache-2.0
- 現状は「アーキテクチャ上の土台」であり、`Configuration.Writable` を完全に置き換えるものではありません。

```sh
dotnet add package Configlue
```

必要に応じて機能パッケージを追加してください。ユーザー向けのメタパッケージ `Configlue` 自体に実装アセンブリは含まれません。

## Why Configlue?

JSON ファイルの読み書きだけなら数行で済みます。しかし実際には次のような要件が積み重なります。

- 設定が複数箇所にある: グローバル設定、実行フォルダー設定、環境変数、コマンドライン引数、暗号化された資格情報、社内ポリシーや HTTP API などのリモート管理
- 設定ファイルが書き換わったら再起動なしで反映したい (変更通知)
- 書き込み先を自動で選びたい。環境変数から読んだ値への書き込みはエラーにしたい
- 設定ファイルは人間が書く: コメントを消さない、JSON Schema がほしい、壊れたファイルへの対処
- 既定値のままなら書き出さない (ただしユーザーが明示した `null` は尊重する)
- 設定ファイルのバージョンアップ (旧形式→新形式への自動変換)
- バックアップと自動整理
- 書き込みの安全性: アトミック性 (クラッシュしても壊れない)、他プロセスとの競合検出・自動マージ、自動リトライ

これらを自前実装するのは面倒、というのが動機です。

`Microsoft.Extensions.Configuration` の `IConfiguration` が読み取り中心であるのに対し、Configlue は独立した Source の合成・値の来歴の検査・スパース保存に向いています。

## 基本アーキテクチャ: 6つの概念

依存関係は直線的で、学習順も同じです。

```text
Resource (location) → Codec (conversion) → Source (contribution) → Fragment (diff) → Options (facade)
                                                        ↘ Patch (edit fragment)
```

| 概念 | 一言で | 例 |
| --- | --- | --- |
| Resource | バイトがどこにあるか | ファイル、ZIP エントリ、HTTP 応答、メモリ |
| Codec | バイト↔値の変換 | JSON / XML / YAML の読み書き |
| Source | 論理的な寄与 (どのフィールドをどの優先度で) | 「ユーザー設定ファイルの Server 部分」 |
| Fragment | 存在を記憶する差分 | 「Port だけ」を持つ状態 |
| Patch | 単一フィールドの編集 | 「Port を 9000 にする」 |
| Options | アプリが見るファサード | 読み・保存・監視・説明・診断 |

**読み込み:** 各 Source が Resource からバイトを取得し、Codec が Fragment に変換します。ランタイムが優先度順に「存在する」フィールドだけを 1 つのモデルへ重ねます。

**書き込み:** 逆向きです。アプリは普通のモデル値を編集します。内部では変更が Fragment 差分になり、`WriteRoute` / `WritePlan` が指す Source にだけ届きます。無関係な Source は変更されません。

- Fragment は「メンバーが存在しない」と「null / 既定値で存在する」を区別します。層の合成で「未設定」が「既定値に設定」を上書きすることはありません。
- Patch は生成される `TModel.Patch` (単一フィールドの編集フラグメント) です。`Unset()` は書き込み先 Source の寄与だけを取り消し、下位優先度の値を再び見せます。
- `[ConfiglueMerge]` でメンバーごとのマージ挙動を変更できます (組み込み: `Append`, `Deep`, `Replace`, `SetUnion`、カスタム戦略も可)。コレクションの層合成・順序はここで決まります。

## Quick Start

`example.cs` に保存し `dotnet run example.cs` で実行 (.NET 10 以降):

```csharp
#!/usr/bin/env dotnet
#:package Configlue@*

using Configlue;
using Configlue.Source.Presets;

// 1. Declare the settings model. The generator creates Fragment/Patch support.
[ConfiglueModel("SampleSetting", Version = 1)]
public partial class SampleSetting
{
    public string Name { get; set; } = "World";
    public int RunCount { get; set; }
    public bool DefaultValue { get; set; } = true;
}

// 2. Declare the preset layers. Only the sources listed here are enabled.
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);

// 3. Read and write through the options instance.
var options = context.GetOptions<SampleSetting>();
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// Sparse edit: only modified fields are saved to the target layer.
await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue is not modified, so it will not be saved to the target layer.
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

1. `[ConfiglueModel]` を付けた partial クラスを宣言すると、Fragment / Patch サポートが生成されます。
2. `UseCommonSources` で有効にする層だけを宣言します。
3. `GetOptions<T>()` で取得した options 経由で読み書きします。`SaveAsync` では変更したフィールドだけが対象層に保存されます。

## 値の由来を調べる / スパース保存

```csharp
var options = context.GetOptions<AppSettings>();
// 1. 現在の値（全ソースをマージしたもの）を取得
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 2. 各値がどこから来たかを調べる
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

指定したメンバーだけを更新するパッチを保存します。`Unset()` はその Source の寄与を外し、下位優先度の Source が値を提供できるようにします:

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

その他の API:

- `IReadOnlyOptions<T>`: 日常の読み取り面は `GetValueAsync` と `OnChange`
- `SaveAsync(patch => ...)`: 生成 Patch でスパース保存
- `OpenEditSessionAsync()`: まとめて編集し `CommitAsync`
- `ApplyPatchesAsync` + `StateSourcePatch`: 明示的なソース別マルチ書き込み
- `StateWritePlan.For<T>().Route(...)`: 書き込みルーティング
- `SourceKey<TModel>` と `options.Source(key)`: ソース単位の操作

## 主な機能

- **複数ソースの優先度マージ:** `Priority` が大きい Source が勝ちます。`GetDetailsAsync` で「どの値がどこ由来か」を検査できます。
- **読み取り専用ソース:** 環境変数・コマンドライン・既定の HTTP ソースは読み取り専用です。読み取り専用の値への書き込みは黙って無視せず競合エラーになります。
- **プロジェクション / マウント:** 既存 Source を別モデルに整形 (projection) したり、ネストしたパスに別 Source を接続 (mount, `AddMounted`) できます。
- **プリセット:** `UseCommonSources` が標準的な層構成 (global / local / environment など) を組み立てます。
- **スパース書き込み:** 変更したフィールドだけを対象層に保存します。既定値のままのフィールドは書かれません。
- **編集セッション:** `OpenEditSessionAsync` で複数変更をまとめて適用します。`CommitAsync` までインメモリです。競合時は既定で失敗、`WriteConflictResolution.LastWriteWins` も選べます。
- **スキーマ移行 / ストレージ移行:** `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` による旧バージョン設定の自動変換です。既存ファイルを Source として登録できます。
- **バックアップと復元:** `FileResource` はアトミック書き込みとバックアップ世代管理を行います。既定で `.bak` 1 世代、`RestoreLatestBackupAsync` で復元します。
- **安全な書き込み:** アトミック性、競合検出、リトライを備えます。
- **セクション:** `JsonSectionResource` / XML 要素 / YAML マッピングで、ファイルの一部を独立した Resource として扱えます。書き込み時はコメント・空白・引用・スカラー形式を保持します。同じファイル内の独立セクションは 1 回の物理書き込みにバッチされます。
- **ZIP / HTTP / S3 / Dapr:** `ZipEntryResource`、`Configlue.Resource.Http` (ETag 条件付き書き込み・ポーリング)、`Configlue.Resource.S3`、`Configlue.Resource.Dapr` を用意しています。
- **JSON Schema 生成:** `Configlue.JsonSchema`。人間が設定を書くための支援です。
- **Native AOT 対応:** ソース生成の `JsonSerializerContext` を渡すとトリミング / AOT に強くなります。
- **リアクティブ統合 (任意):** `Configlue.Extensions.Reactive` (System.Reactive 7.0.0) と `Configlue.Extensions.R3` (R3 1.3.1)。`ObserveChanges()`, `ObserveValues()`, `ObserveReloadFailures()`, `ObserveActiveValues()`, `ObserveActiveProfileNames()` を提供します。
- **DI 統合:** `Configlue.Extensions.DI`。Microsoft の options アダプター `Configlue.Extensions.MSOptions` (`IOptions<T>` など。同期ゲッターは非同期ソース読み取り中ブロックするので非同期フローでは `GetValueAsync` 推奨) があります。
- **プロファイル / 動的オプション:** 名前付きオプションや永続プロファイルでランタイムを単位に作成・削除できます。

既知の制限:

- 異なる Resource 間の書き込みはアトミックではありません。
- Source の退役は現在の options インスタンスに閉じ、実データは残ります。
- Source 集合は options ランタイムで固定です。

## パッケージ構成 (主要なもの)

- `Configlue`: ユーザー向けメタパッケージ (Core / DI / JSON provider / JSON Schema / HTTP resources / common sources / environment source / generator analyzer を同梱。実装アセンブリは持たない)
- `Configlue.Abstraction`: 契約 (provider / codec / resource / generated-model)
- `Configlue.Core`: 解決と永続化のランタイム
- `Configlue.Extensibility`: プロバイダー SDK
- `Configlue.Extensions.DI` / `Configlue.Extensions.MSOptions` / `Configlue.Extensions.R3` / `Configlue.Extensions.Reactive`
- `Configlue.Generator`: Roslyn アナライザー (スパースなモデルサポート生成)
- `Configlue.Testing`: インメモリのテストダブル
- `Configlue.Provider.Json` / `.Xml` / `.Yaml`: 各形式の Codec・セクションリソース・ファイル登録
- `Configlue.JsonSchema`: JSON Schema 生成・エクスポート
- `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml`
- `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip`
- `Configlue.Transformer.AES`: Resource と Codec の間のバイトを AES-GCM 暗号化・認証




---

# ===== opencode-go/qwen3.8-flash =====

# Configlue

> Make easy configuration management.

Configlue は、アプリケーションの設定管理を代行する .NET ライブラリです。複数の場所に散らばった設定を 1 つのモデルに **結合（glue）** するのが中心的な考え方であり、名前は configuration + glue に由来します。

- 対象: .NET 10 SDK 以降（ソースジェネレーター対応の `LangVersion` が必要です。リポジトリは preview でビルド）
- ライセンス: Apache-2.0
- 現状はアーキテクチャ上の土台であり、`Configuration.Writable` を完全に置き換えるものではありません。

## Why Configlue?

JSON ファイルの読み書きだけなら数行で済みます。しかし実際のアプリでは、次のような要件が積み重なり、自前実装は面倒になります。

- 設定が複数箇所にある: グローバル設定、実行フォルダー設定、環境変数、コマンドライン引数、暗号化された資格情報、社内ポリシーや HTTP API などのリモート管理。
- 設定ファイルが書き換わったら再起動なしで反映したい（変更通知）。
- 書き込み先を自動で選びたい。環境変数から読んだ値への書き込みはエラーにしたい。
- 設定ファイルは人間が書く: コメントを消さない、JSON Schema がほしい、壊れたファイルへの対処。
- 既定値のままなら書き出さない（ただしユーザーが明示した `null` は尊重する）。
- 設定ファイルのバージョンアップ（旧形式→新形式への自動変換）。
- バックアップと自動整理。
- 書き込みの安全性: アトミック性（クラッシュしても壊れない）、他プロセスとの競合検出・自動マージ、自動リトライ。

`Microsoft.Extensions.Configuration` の `IConfiguration` は読み取り中心の抽象です。Configlue は、独立したソースの合成・値の来歴の検査・スパース保存という、書き込みを伴う設定管理に向いています。

## 基本アーキテクチャ

システムは 6 つの概念からなり、依存関係は直線的です。学習順も同じ順番になります。

```text
Resource (location) → Codec (conversion) → Source (contribution) → Fragment (diff) → Options (facade)
                                                        ↘ Patch (edit fragment)
```

| 概念 | 一言で | 例 |
| --- | --- | --- |
| Resource | バイトがどこにあるか | ファイル、ZIP エントリ、HTTP 応答、メモリ |
| Codec | バイト↔値の変換 | JSON / XML / YAML の読み書き |
| Source | 論理的な寄与（どのフィールドをどの優先度で） | 「ユーザー設定ファイルの Server 部分」 |
| Fragment | 存在を記憶する差分 | 「Port だけ」を持つ状態 |
| Patch | 単一フィールドの編集 | 「Port を 9000 にする」 |
| Options | アプリが見るファサード | 読み・保存・監視・説明・診断 |

**読み込み**: 各 Source が Resource からバイトを取得し、Codec が Fragment に変換します。ランタイムが優先度順に「存在する」フィールドだけを 1 つのモデルへ重ねます。

**書き込み**: 逆向きです。アプリは普通のモデル値を編集し、内部では変更が Fragment 差分になって `WriteRoute` / `WritePlan` が指す Source にだけ届きます。無関係な Source は変更されません。

- Fragment は「メンバーが存在しない」と「null/既定値で存在する」を区別します。層の合成で「未設定」が「既定値に設定」を上書きすることはありません。
- Patch は生成される `TModel.Patch`（単一フィールドの編集フラグメント）です。`Unset()` は書き込み先 Source の寄与だけを取り消し、下位優先度の値を再び見せます。
- `[ConfiglueMerge]` でメンバーごとのマージ挙動を変更できます（組み込み: `Append` / `Deep` / `Replace` / `SetUnion`、カスタム戦略も可）。コレクションの層合成・順序はここで決まります。

## Quick Start

`example.cs` に保存して `dotnet run example.cs` で実行できます（.NET 10 以降、file-based app）。

```csharp
#!/usr/bin/env dotnet
#:package Configlue@*

using Configlue;
using Configlue.Source.Presets;

// 1. Declare the settings model. The generator creates Fragment/Patch support.
[ConfiglueModel("SampleSetting", Version = 1)]
public partial class SampleSetting
{
    public string Name { get; set; } = "World";
    public int RunCount { get; set; }
    public bool DefaultValue { get; set; } = true;
}

// 2. Declare the preset layers. Only the sources listed here are enabled.
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);

// 3. Read and write through the options instance.
var options = context.GetOptions<SampleSetting>();
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// Sparse edit: only modified fields are saved to the target layer.
await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue is not modified, so it will not be saved to the target layer.
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

## 値の由来を調べる

`GetDetailsAsync` で、各値がどの Source から来たか・書き込めるかを検査できます。

```csharp
var options = context.GetOptions<AppSettings>();
// 1. 現在の値（全ソースをマージしたもの）を取得
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 2. 各値がどこから来たかを調べる
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

## スパース保存と Unset

指定したメンバーだけを更新するパッチを保存します。`Unset()` はその Source の寄与を外し、下位優先度の Source が値を提供できるようにします。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

その他の API:

- `IReadOnlyOptions<T>` … 日常の読み取り面は `GetValueAsync` と `OnChange`。
- `SaveAsync(patch => ...)` … 生成 Patch によるスパース保存。
- `OpenEditSessionAsync()` … 複数変更をまとめて編集し `CommitAsync` で確定（`CommitAsync` までインメモリ。競合時は既定で失敗、`WriteConflictResolution.LastWriteWins` も選択可）。
- `ApplyPatchesAsync` + `StateSourcePatch` … 明示的なソース別マルチ書き込み。
- `StateWritePlan.For<T>().Route(...)` … 書き込みルーティング。
- `SourceKey<TModel>` と `options.Source(key)` … ソース単位の操作。

## 主な機能

- **複数ソースの優先度マージ**: `Priority` が大きい Source が勝ちます。
- **読み取り専用ソース**: 環境変数・コマンドライン・既定の HTTP ソースは読み取り専用。読み取り専用の値への書き込みは黙って無視せず競合エラーになります。
- **プロジェクション / マウント**: 既存 Source を別モデルに整形（projection）したり、ネストしたパスに別 Source を接続（mount、`AddMounted`）できます。
- **プリセット**: `UseCommonSources` が標準的な層構成（global / local / environment など）を組み立てます。
- **スキーマ移行 / ストレージ移行**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` による旧バージョン設定の自動変換。既存ファイルを Source として登録できます。
- **バックアップと復元**: `FileResource` はアトミック書き込みとバックアップ世代管理。既定で `.bak` 1 世代、`RestoreLatestBackupAsync` で復元します。
- **セクション**: `JsonSectionResource` / XML 要素 / YAML マッピングで、ファイルの一部を独立した Resource として扱えます。書き込み時はコメント・空白・引用・スカラー形式を保持し、同じファイル内の独立セクションは 1 回の物理書き込みにバッチされます。
- **多様な Resource**: `ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込み・ポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **JSON Schema 生成**: `Configlue.JsonSchema`。人間が設定を書くために。
- **Native AOT 対応**: ソース生成の `JsonSerializerContext` を渡すとトリミング/AOT に強くなります。
- **暗号化**: `Configlue.Transformer.AES` が Resource と Codec の間のバイトを AES-GCM で暗号化・認証します。
- **リアクティブ統合（任意）**: `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）。`ObserveChanges()` / `ObserveValues()` / `ObserveReloadFailures()` / `ObserveActiveValues()` / `ObserveActiveProfileNames()`。
- **DI 統合**: `Configlue.Extensions.DI`。Microsoft の options アダプター `Configlue.Extensions.MSOptions`（`IOptions<T>` など）も提供。同期ゲッターは非同期ソース読み取り中にブロックするため、非同期フローでは `GetValueAsync` を推奨します。
- **プロファイル / 動的オプション**: 名前付きオプションや永続プロファイルをランタイム単位で作成・削除できます。
- **テスト**: `Configlue.Testing` にインメモリのテストダブルがあります。

## パッケージ構成

インストールは `dotnet add package Configlue` から始め、必要な機能パッケージを追加します。

| パッケージ | 内容 |
| --- | --- |
| `Configlue` | ユーザー向けメタパッケージ（Core / DI / JSON provider / JSON Schema / HTTP resources / common sources / environment source / generator analyzer を同梱。実装アセンブリは持たない） |
| `Configlue.Abstraction` | 契約（provider / codec / resource / generated-model） |
| `Configlue.Core` | 解決と永続化のランタイム |
| `Configlue.Extensibility` | プロバイダー SDK |
| `Configlue.Generator` | Roslyn アナライザー（スパースなモデルサポート生成） |
| `Configlue.Testing` | インメモリのテストダブル |
| `Configlue.Provider.Json` / `.Xml` / `.Yaml` | 各形式の Codec・セクションリソース・ファイル登録 |
| `Configlue.JsonSchema` | JSON Schema 生成・エクスポート |
| `Configlue.Extensions.DI` / `.MSOptions` / `.R3` / `.Reactive` | DI / MS options / リアクティブ統合 |
| `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml` | 環境変数・コマンドライン・プリセットソース |
| `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip` | 各種 Resource |
| `Configlue.Transformer.AES` | バイト列の AES-GCM 暗号化・認証 |

## 既知の制限

- 異なる Resource 間の書き込みはアトミックではありません。
- Source の退役は現在の options インスタンスに閉じ、実データは残ります。
- Source 集合は options ランタイムで固定です。

## ライセンス

Apache-2.0



---

# ===== opencode-go/qwen3.8-max =====

# Configlue

> Make easy configuration management.

Configlue は、アプリケーションの設定管理（configuration management）を代行する .NET ライブラリです。名前は **configuration + glue** に由来し、複数箇所に散らばった設定を **1 つのモデルに結合（glue）** することを中心的な考え方としています。

- 対象: **.NET 10 SDK 以降**（C#。ソースジェネレーターを使うため `LangVersion` には preview 相当が必要です。リポジトリは preview でビルドしています）
- ライセンス: **Apache-2.0**
- 位置づけ: 現時点では **アーキテクチャ上の土台** です。`Configuration.Writable` を完全に置き換えるものではありません。

---

## 目次

- [なぜ Configlue なのか](#なぜ-configlue-なのか)
- [インストール](#インストール)
- [Quick Start](#quick-start)
- [基本アーキテクチャ](#基本アーキテクチャ)
- [値の由来を調べる](#値の由来を調べる)
- [スパース保存と Unset](#スパース保存と-unset)
- [その他の API](#その他の-api)
- [主な機能](#主な機能)
- [Microsoft.Extensions.Configuration との違い](#microsoftextensionsconfiguration-との違い)
- [既知の制限](#既知の制限)
- [パッケージ構成](#パッケージ構成)

---

## なぜ Configlue なのか

JSON ファイルを読み書きするだけなら数行で済みます。しかし実際には、次のような要件が積み重なっていきます。

- **設定が複数箇所にある** — グローバル設定、実行フォルダー設定、環境変数、コマンドライン引数、暗号化された資格情報、社内ポリシーや HTTP API によるリモート管理。
- **変更を再起動なしで反映したい** — 設定ファイルが書き換わったときの変更通知。
- **書き込み先を自動で選びたい** — 環境変数から読んだ値への書き込みはエラーにしたい。
- **設定ファイルは人間が書く** — コメントを消したくない、JSON Schema がほしい、壊れたファイルへの対処がほしい。
- **既定値のままなら書き出したくない** — ただしユーザーが明示した `null` は尊重する。
- **設定ファイルのバージョンアップ** — 旧形式から新形式への自動変換。
- **バックアップと自動整理**。
- **書き込みの安全性** — アトミック性（クラッシュしても壊れない）、他プロセスとの競合検出と自動マージ、自動リトライ。

これらを自前実装するのは面倒です。Configlue はこの一式を、層（レイヤー）として宣言的に組み立てられるようにします。

## インストール

```bash
dotnet add package Configlue
```

`Configlue` はユーザー向けのメタパッケージです。XML / YAML や S3 など、必要に応じて機能パッケージを追加してください（後述の[パッケージ構成](#パッケージ構成)）。

## Quick Start

以下を `example.cs` に保存し、`dotnet run example.cs` で実行できます（.NET 10 以降）。

```csharp
#!/usr/bin/env dotnet
#:package Configlue@*

using Configlue;
using Configlue.Source.Presets;

// 1. Declare the settings model. The generator creates Fragment/Patch support.
[ConfiglueModel("SampleSetting", Version = 1)]
public partial class SampleSetting
{
    public string Name { get; set; } = "World";
    public int RunCount { get; set; }
    public bool DefaultValue { get; set; } = true;
}

// 2. Declare the preset layers. Only the sources listed here are enabled.
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);

// 3. Read and write through the options instance.
var options = context.GetOptions<SampleSetting>();
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// Sparse edit: only modified fields are saved to the target layer.
await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue is not modified, so it will not be saved to the target layer.
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

ポイントは 3 つです。

1. **モデルを宣言する** — `[ConfiglueModel]` を付けた `partial` クラスに対し、ジェネレーターが Fragment / Patch 用のサポートコードを生成します。
2. **層を宣言する** — `UseCommonSources` で global / local / environment などの標準的な層構成を組み立てます。**ここに列挙したソースだけが有効になります。**
3. **options 経由で読み書きする** — アプリ側は普通のモデル値を扱うだけで、差分の保存先は Configlue が選びます。

## 基本アーキテクチャ

Configlue は 6 つの概念から成ります。依存関係は直線的で、学習順も同じです。

```text
Resource (location) → Codec (conversion) → Source (contribution) → Fragment (diff) → Options (facade)
                                                        ↘ Patch (edit fragment)
```

| 概念 | 一言で | 例 |
| --- | --- | --- |
| **Resource** | バイトがどこにあるか | ファイル、ZIP エントリ、HTTP 応答、メモリ |
| **Codec** | バイト ↔ 値の変換 | JSON / XML / YAML の読み書き |
| **Source** | 論理的な寄与（どのフィールドをどの優先度で） | 「ユーザー設定ファイルの Server 部分」 |
| **Fragment** | 存在を記憶する差分 | 「Port だけ」を持つ状態 |
| **Patch** | 単一フィールドの編集 | 「Port を 9000 にする」 |
| **Options** | アプリが見るファサード | 読み・保存・監視・説明・診断 |

### 読み込み

各 Source が Resource からバイトを取得し、Codec がそれを Fragment に変換します。ランタイムは優先度順に、**「存在する」フィールドだけ**を 1 つのモデルへ重ね合わせます。

### 書き込み

逆向きです。アプリは普通のモデル値を編集するだけで、内部ではその変更が Fragment 差分になります。差分は `WriteRoute` / `WritePlan` が指す Source にだけ届き、無関係な Source は変更されません。

### Fragment と Patch

- Fragment は「メンバーが存在しない」と「null / 既定値で存在する」を区別します。この区別により、層の合成で **未設定が既定値を上書きしてしまう** ことが起きません。
- Patch はジェネレーターが生成する `TModel.Patch`（単一フィールドの編集フラグメント）です。`Unset()` は書き込み先 Source の寄与だけを取り消し、下位優先度の値を再び見えるようにします。
- `[ConfiglueMerge]` でメンバーごとのマージ挙動を変更できます。組み込み戦略は `Append` / `Deep` / `Replace` / `SetUnion` で、カスタム戦略も定義可能です。コレクションの層合成とその順序はここで決まります。

## 値の由来を調べる

```csharp
var options = context.GetOptions<AppSettings>();
// 1. 現在の値（全ソースをマージしたもの）を取得
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 2. 各値がどこから来たかを調べる
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

`GetDetailsAsync` は、メンバーごとに「採用された値の由来（`Source`）」「書き込み可能か（`IsEditable`）」「各 Source の寄与と状態（`Sources`）」を返します。設定が意図した層から来ているかを診断できます。

## スパース保存と Unset

指定したメンバーだけを更新するパッチを保存します。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

- **スパース書き込み** — 変更したフィールドだけが対象層に保存されます。既定値のままのフィールドは書き込まれません。
- **`Unset()`** — その Source の寄与を外し、下位優先度の Source が値を提供できるようにします。

## その他の API

| API | 用途 |
| --- | --- |
| `IReadOnlyOptions<T>` | 日常の読み取り面。`GetValueAsync` と `OnChange` |
| `SaveAsync(patch => ...)` | 生成 Patch によるスパース保存 |
| `OpenEditSessionAsync()` | 複数の変更をまとめて適用し `CommitAsync` |
| `ApplyPatchesAsync` + `StateSourcePatch` | 明示的なソース別マルチ書き込み |
| `StateWritePlan.For<T>().Route(...)` | 書き込みルーティング |
| `SourceKey<TModel>` / `options.Source(key)` | ソース単位の操作 |

### 編集セッション

`OpenEditSessionAsync` を使うと、複数の変更を `CommitAsync` までインメモリでまとめて適用できます。競合が起きた場合は既定で失敗します。`WriteConflictResolution.LastWriteWins` を選ぶこともできます。

## 主な機能

### 優先度マージと読み取り専用ソース

- `Priority` が大きい Source が勝ちます。
- 環境変数・コマンドライン・既定の HTTP ソースは読み取り専用です。**読み取り専用の値への書き込みは黙って無視されず、競合エラーになります。**
- 既存 Source を別モデルへ整形する **projection**、ネストしたパスに別 Source を接続する **mount**（`AddMounted`）をサポートします。
- `UseCommonSources` が global / local / environment などの標準的な層構成を組み立てるプリセットです。

### 安全な書き込み

- **アトミック書き込み** — クラッシュしても設定ファイルが壊れません。
- **競合検出と自動マージ、自動リトライ** — 他プロセスとの同時編集に対応します。
- **バックアップと復元** — `FileResource` はアトミック書き込みとバックアップ世代管理を行います。既定で `.bak` を 1 世代保持し、`RestoreLatestBackupAsync` で復元できます。

### セクション

`JsonSectionResource`（および XML の要素、YAML のマッピング）により、ファイルの一部を独立した Resource として扱えます。

- 書き込み時も **コメント・空白・引用・スカラー形式を保持** します。人間が書いたファイルを機械が上書きする用途に向きます。
- 同じファイル内の独立したセクションは、**1 回の物理書き込みにバッチ** されます。

### リソースの種類

ZIP / HTTP / S3 / Dapr を利用できます。

- `ZipEntryResource` — ZIP アーカイブ内のエントリ
- `Configlue.Resource.Http` — ETag 条件付き書き込みとポーリング
- `Configlue.Resource.S3` / `Configlue.Resource.Dapr`

### スキーマ移行とストレージ移行

- `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` により、旧バージョンの設定を新形式へ自動変換できます。
- 既存のファイルを Source として登録できます。

### JSON Schema 生成

`Configlue.JsonSchema` がモデルから JSON Schema を生成・エクスポートします。設定ファイルを人間が書く前提のライブラリとして、エディター補完や検証に使えるスキーマを用意できます。

### 暗号化

`Configlue.Transformer.AES` は Resource と Codec の間で流れるバイトを **AES-GCM で暗号化・認証** します。資格情報のような機微な層に使えます。

### Native AOT

ソース生成の `JsonSerializerContext` を渡すと、トリミングや Native AOT に対して強くなります。

### リアクティブ統合（任意）

- `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）
- `Configlue.Extensions.R3`（R3 1.3.1）

`ObserveChanges()` / `ObserveValues()` / `ObserveReloadFailures()` / `ObserveActiveValues()` / `ObserveActiveProfileNames()` を利用できます。

### DI / Microsoft.Extensions.Options 統合

- `Configlue.Extensions.DI` — DI コンテナ統合。
- `Configlue.Extensions.MSOptions` — `IOptions<T>` など Microsoft の options へのアダプター。同期ゲッターは非同期ソースの読み取り中にブロックするため、**非同期フローでは `GetValueAsync` の使用を推奨** します。

### プロファイルと動的オプション

名前付きオプションや永続プロファイルを使い、ランタイムを単位に options を作成・削除できます。

## Microsoft.Extensions.Configuration との違い

`IConfiguration` は読み取り中心の設計です。Configlue はそれに加え、**独立した複数のソースを合成し、値の来歴を検査し、変更したフィールドだけを目的の層にスパース保存する** ことに特化しています。設定を読み込むだけでなく、アプリケーションから書き戻す必要がある場合に適しています。

## 既知の制限

- 異なる Resource 間の書き込みはアトミックではありません。
- Source の退役（retirement）は現在の options インスタンスに閉じており、実データは残ります。
- Source の集合は options ランタイムで固定されます。

## パッケージ構成

| パッケージ | 内容 |
| --- | --- |
| `Configlue` | ユーザー向けメタパッケージ。Core / DI / JSON provider / JSON Schema / HTTP resources / common sources / environment source / generator analyzer を同梱（実装アセンブリは持ちません） |
| `Configlue.Abstraction` | 契約（provider / codec / resource / generated-model） |
| `Configlue.Core` | 解決と永続化のランタイム |
| `Configlue.Extensibility` | プロバイダー SDK |
| `Configlue.Generator` | Roslyn アナライザー（スパースなモデルサポートの生成） |
| `Configlue.Testing` | インメモリのテストダブル |
| `Configlue.Provider.Json` / `.Xml` / `.Yaml` | 各形式の Codec、セクションリソース、ファイル登録 |
| `Configlue.JsonSchema` | JSON Schema の生成・エクスポート |
| `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml` | ソース実装とプリセット |
| `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip` | リソース実装 |
| `Configlue.Transformer.AES` | Resource と Codec の間のバイトを AES-GCM で暗号化・認証 |
| `Configlue.Extensions.DI` / `.MSOptions` / `.Reactive` / `.R3` | DI・options・リアクティブ統合 |

## ライセンス

Apache-2.0



---

# ===== opencode-go/space-bunny-free =====

# Configlue

**Make easy configuration management.**

Configlue は .NET アプリケーションの設定管理（configuration management）を代行するライブラリです。グローバル設定、実行フォルダーの設定、環境変数、コマンドライン引数、社内ポリシーや HTTP API などのリモート管理といった、ばらばかれた設定を 1 つのモデルに**結合（glue）**します。名前も configuration + glue から来ています。

- 対象: .NET 10 SDK 以降 / C#（ソースジェネレーター対応の `LangVersion` が必要）
- ライセンス: Apache-2.0
- 現状: アーキテクチャ上の土台。`Microsoft.Extensions.Configuration` の `Configuration.Writable` を完全に置き換えるものではありません

---

## なぜ Configlue なのか

JSON ファイルを読み書きするだけなら数行で書けます。しかし実用的な設定管理では、その周辺に次のような要件が積み重なります。

- **設定が複数箇所にある。** グローバル設定、実行フォルダーの設定、環境変数、コマンドライン引数、暗号化された資格情報、社内ポリシーや HTTP API などのリモート管理。
- **ファイルが書き換わったら再起動なしで反映したい。** 変更通知で実行中のモデルを更新する。
- **書き込み先を自動で選びたい。** 環境変数から読んだ値への書き込みは、無視ではなくエラーにしたい。
- **設定ファイルは人間が書く。** コメントを消さない、JSON Schema を配る、壊れたファイルへ対処する。
- **既定値のままなら書き出さない。** ただしユーザーが明示した `null` は尊重する。
- **設定ファイルのバージョンアップ。** 旧形式から新形式へ自動変換する。
- **バックアップと自動整理。**
- **書き込みの安全性。** アトミック性、他プロセスとの競合検出と自動マージ、自動リトライ。

これらを毎回自前実装するのは面倒です。Configlue はその層をライブラリとして提供します。

---

## Quick Start

`example.cs` に保存し、`dotnet run example.cs` で実行できます（.NET 10 以降）。

```csharp
#!/usr/bin/env dotnet
#:package Configlue@*

using Configlue;
using Configlue.Source.Presets;

// 1. Declare the settings model. The generator creates Fragment/Patch support.
[ConfiglueModel("SampleSetting", Version = 1)]
public partial class SampleSetting
{
    public string Name { get; set; } = "World";
    public int RunCount { get; set; }
    public bool DefaultValue { get; set; } = true;
}

// 2. Declare the preset layers. Only the sources listed here are enabled.
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);

// 3. Read and write through the options instance.
var options = context.GetOptions<SampleSetting>();
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// Sparse edit: only modified fields are saved to the target layer.
await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue is not modified, so it will not be saved to the target layer.
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

---

## 基本アーキテクチャ

依存関係は直線的で、この順で読めば全体が掴めます。

```text
Resource (location) → Codec (conversion) → Source (contribution) → Fragment (diff) → Options (facade)
                                                        ↘ Patch (edit fragment)
```

| 概念 | 一言で | 例 |
| --- | --- | --- |
| **Resource** | バイトがどこにあるか | ファイル、ZIP エントリ、HTTP 応答、メモリ |
| **Codec** | バイトと値の相互変換 | JSON / XML / YAML の読み書き |
| **Source** | 論理的な寄与（どのフィールドをどの優先度で） | 「ユーザー設定ファイルの Server 部分」 |
| **Fragment** | 存在を記憶する差分 | 「Port だけ」を持つ状態 |
| **Patch** | 単一フィールドの編集 | 「Port を 9000 にする」 |
| **Options** | アプリが見るファサード | 読み・保存・監視・説明・診断 |

**読み込み** — 各 Source が Resource からバイトを取得し、Codec が Fragment に変換します。ランタイムは優先度順に、**存在する**フィールドだけを 1 つのモデルへ重ねます。

**書き込み** — 逆方向です。アプリは普通のモデル値を編集し、内部ではその変更が Fragment の差分になります。`WriteRoute` / `WritePlan` が指す Source にだけ届き、無関係な Source は変更されません。

この非対称性がポイントです。たとえば「環境変数から読んだ `Port` を、ユーザーが UI で 9000 に変えた」場合、書き込み先は管理可能なファイル Source に決まります。読み取り専用の値への書き込みは黙って無視されず、競合エラーになります。

### 存在と差分

Fragment は「メンバーが存在しない」と「`null` や既定値で存在する」を区別します。層を合成しても「未設定」が「既定値に設定」を上書きすることはありません。逆に、ユーザーが明示した `null` は尊重されます。

`Patch` はソースジェネレーターが生成する `TModel.Patch` で、単一フィールドの編集を表します。`Unset()` を呼ぶと、書き込み先 Source の寄与だけを取り除き、下位優先度の Source の値を再び見せます。

### マージ戦略

`[ConfiglueMerge]` でメンバーごとにマージ挙動を変更できます。組み込みは `Append`、`Deep`、`Replace`、`SetUnion` で、カスタム戦略も指定可能です。コレクションが層をどう合成され、どの順序になるかはここで決まります。

---

## 主な機能

**複数ソースの優先度マージ**
`Priority` が大きい Source が勝ちます。どの値も `GetDetailsAsync` で「どこから来たか」を検査できます。

**読み取り専用ソース**
環境変数、コマンドライン、既定の HTTP ソースは読み取り専用です。

**プロジェクション / マウント**
既存の Source を別モデルへ整形（projection）したり、ネストしたパスに別 Source を接続（mount、`AddMounted`）したりできます。

**プリセット**
`UseCommonSources` が global / local / environment といった標準的な層構成を組み立てます。列挙した Source だけが有効になります。

**スパース書き込み**
変更したフィールドだけを対象層へ保存します。既定値のままのフィールドはファイルに現れません。

**編集セッション**
`OpenEditSessionAsync` で複数の変更をまとめ、`CommitAsync` までインメモリで保持します。競合時は既定で失敗し、`WriteConflictResolution.LastWriteWins` を選ぶこともできます。

**スキーマ移行 / ストレージ移行**
`[ConfigluePreviousVersion]` と `Fragment.FromPrevious` により、旧バージョンの設定を自動変換します。既存ファイルをそのまま Source として登録することもできます。

**バックアップと復元**
`FileResource` はアトミック書き込みとバックアップ世代管理を行います。既定で `.bak` 1 世代を保持し、`RestoreLatestBackupAsync` で復元できます。

**安全な書き込み**
アトミック性、競合検出、リトライを扱います。他プロセスと競合した場合は検出・自動マージします。

**セクション**
`JsonSectionResource`、XML 要素、YAML マッピングで、ファイルの一部を独立した Resource として扱えます。書き込み時にコメント・空白・引用・スカラー形式を保持し、同じファイル内の独立セクションは 1 回の物理書き込みにバッチされます。

**ZIP / HTTP / S3 / Dapr**
`ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込み・ポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。

**JSON Schema 生成**
`Configlue.JsonSchema` がスキーマの生成とエクスポートを提供します。設定ファイルを人が手で書くことを前提にしています。

**Native AOT 対応**
ソース生成の `JsonSerializerContext` を渡すと、トリミング／AOT に対して強くなります。

**リアクティブ統合（任意）**
`Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）で `ObserveChanges()`、`ObserveValues()`、`ObserveReloadFailures()`、`ObserveActiveValues()`、`ObserveActiveProfileNames()` が使えます。

**DI 統合**
`Configlue.Extensions.DI`、および Microsoft の options アダプター `Configlue.Extensions.MSOptions`（`IOptions<T>` など）を用意しています。なお同期ゲッターは非同期ソースの読み取り中にブロックするため、非同期フローでは `GetValueAsync` の利用を推奨します。

**プロファイル / 動的オプション**
名前付きオプションや永続プロファイルで、ランタイム単位で options を作成・削除できます。

---

## 値の由来を調べる

マージされた値がどこから来たのかも取得できます。

```csharp
var options = context.GetOptions<AppSettings>();

// 1. 現在の値（全ソースをマージしたもの）を取得
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 2. 各値がどこから来たかを調べる
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

診断画面や「設定が効かない」という問い合わせへの回答に、そのまま使えます。

---

## スパース保存

更新したいメンバーだけをパッチで指定します。`Unset()` はその Source の寄与を外し、下位優先度の Source が値を提供できるようにします。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

その他の主な API:

| API | 用途 |
| --- | --- |
| `IReadOnlyOptions<T>` | 日常の読み取り面。`GetValueAsync` と `OnChange` |
| `SaveAsync(patch => ...)` | 生成 Patch によるスパース保存 |
| `OpenEditSessionAsync()` / `CommitAsync()` | 複数変更をまとめて適用 |
| `ApplyPatchesAsync` + `StateSourcePatch` | 明示的なソース別のマルチ書き込み |
| `StateWritePlan.For<T>().Route(...)` | 書き込みルーティング |
| `SourceKey<TModel>` / `options.Source(key)` | ソース単位の操作 |

---

## 既存の設定管理との違い

`Microsoft.Extensions.Configuration` の `IConfiguration` は読み取りを中心に設計されています。provider を並べて合成し、値を引くことに特化した API です。

Configlue が軸に置くのは次の点です。

- 独立した複数ソースの合成と、値ごとの来歴（`GetDetailsAsync`）の検査
- スパース保存と、書き込み先の安全な解決
- 人間向けの設定ファイル（コメント保持、JSON Schema）
- バックアップ、アトミック書き込み、競合処理

読み取り中心の構成だけなら `IConfiguration` のほうが軽量です。設定の**書き戻し**と**出典の可視化**が要件に入るなら Configlue の領域です。

---

## パッケージ

まずメタパッケージを入れ、必要な機能を足していきます。

```bash
dotnet add package Configlue
```

| パッケージ | 内容 |
| --- | --- |
| `Configlue` | ユーザー向けメタパッケージ（Core / DI / JSON provider / JSON Schema / HTTP resources / common sources / environment source / generator analyzer を同梱。実装アセンブリは持たない） |
| `Configlue.Abstraction` | 契約（provider / codec / resource / generated-model） |
| `Configlue.Core` | 解決と永続化のランタイム |
| `Configlue.Extensibility` | プロバイダー SDK |
| `Configlue.Generator` | Roslyn アナライザー（スパースなモデルサポート生成） |
| `Configlue.Extensions.DI` | DI 統合 |
| `Configlue.Extensions.MSOptions` | `IOptions<T>` などの Microsoft options アダプター |
| `Configlue.Extensions.R3` / `.Reactive` | リアクティブ統合 |
| `Configlue.Testing` | インメモリのテストダブル |
| `Configlue.Provider.Json` / `.Xml` / `.Yaml` | 各形式の Codec・セクションリソース・ファイル登録 |
| `Configlue.JsonSchema` | JSON Schema の生成・エクスポート |
| `Configlue.Source.Environment` / `.CommandLine` | 環境変数、コマンドライン引数のソース |
| `Configlue.Source.Presets` / `.Presets.Yaml` / `.Presets.Xml` | 標準的な層構成のプリセット |
| `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip` | 各種リソース |
| `Configlue.Transformer.AES` | Resource と Codec の間のバイトを AES-GCM で暗号化・認証 |

---

## 既知の制限

- 異なる Resource 間の書き込みはアトミックではありません。
- Source の退役は現在の options インスタンスに閉じており、実データは残ります。
- Source 集合は options ランタイムで固定です。

現時点ではアーキテクチャ上の土台であり、既存の設定管理をそのまま置き換えるものではありません。

---

## License

Apache-2.0



---

# ===== opencode/big-pickle =====

# Configlue

**Make easy configuration management.**

Configlue は .NET アプリケーションの設定管理（configuration management）を代行するライブラリです。
中心にある考え方は、**複数の場所に散らばった設定を 1 つのモデルに「糊付け（glue）」する**ことです。
グローバル設定、実行フォルダーの設定、環境変数、コマンドライン引数、暗号化された資格情報、社内ポリシーや HTTP API といったリモート管理 —
どの場所に何が書いてあるか意識せずに 1 つの型として扱い、**その値がどこから来たのかを説明でき**、**変更したフィールドだけを安全に書き戻せる**ようにします。

- **ライセンス**: Apache-2.0
- **対象**: .NET 10 SDK 以降（C# / ソースジェネレーター。ライブラリ自体は preview でビルド）

> **現状の位置づけ**: Configlue は現時点でアーキテクチャ上の土台です。`Microsoft.Extensions.Configuration` の読み取り機能を置き換えるものではありません。
> 独立した設定ソースの合成、来歴（provenance）の検査、スパースな保存を前提とした設計です。複数の場所に散らばった設定を 1 つの型として扱いたい場合に適しています（→ [Microsoft.Extensions.Configuration との関係](#microsoftextensionsconfiguration-との関係)）。

## 目次

- [インストール](#インストール)
- [Why Configlue?](#why-configlue)
- [Quick Start](#quick-start)
- [6 つの概念](#6-つの概念)
- [主な機能](#主な機能)
- [値の来歴を調べる](#値の来歴を調べる)
- [スパース保存と Unset()](#スパース保存と-unset)
- [API 一覧](#api-一覧)
- [パッケージ](#パッケージ)
- [Microsoft.Extensions.Configuration との関係](#microsoftextensionsconfiguration-との関係)
- [既知の制限](#既知の制限)

## インストール

```bash
dotnet add package Configlue
```

`Configlue` はユーザー向けのメタパッケージで、Core / DI / JSON provider / JSON Schema / HTTP resources / common sources / environment source / generator analyzer を同梱しています（実装アセンブリ自体は持たず、依存として解決されます）。
必要な機能に応じて [個別のパッケージ](#パッケージ)を追加してください。

## Why Configlue?

JSON ファイルを 1 つ読み書きするだけなら数行で済みます。しかし実際に運用しているアプリケーションでは、次の要件が積み重なります。

- **設定が複数箇所にある** — グローバル設定、実行フォルダーの設定、環境変数、コマンドライン引数、暗号化された資格情報、社内ポリシーや HTTP API などのリモート管理
- **設定ファイルが書き換わったら再起動なしで反映したい** — 変更通知
- **書き込み先を自動で選びたい** — 環境変数から読んだ値への書き込みはエラーにしたい
- **設定ファイルは人間が書く** — コメントを消さない、JSON Schema が欲しい、壊れたファイルへの対処
- **既定値のままなら書き出したくない** — ただしユーザーが明示した `null` は尊重する
- **設定ファイルのバージョンアップ** — 旧形式から新形式へ自動変換
- **バックアップと自動整理**
- **書き込みの安全性** — アトミック性（クラッシュしても壊れない）、他プロセスとの競合検出・自動マージ、自動リトライ

これらを毎回自前実装するのは面倒です。Configlue はその「面倒」をライブラリ側に閉じ込めます。

## Quick Start

以下のコードを `example.cs` に保存し、`dotnet run example.cs` で実行できます（.NET 10 以降）。

```csharp
#!/usr/bin/env dotnet
#:package Configlue@*

using Configlue;
using Configlue.Source.Presets;

// 1. Declare the settings model. The generator creates Fragment/Patch support.
[ConfiglueModel("SampleSetting", Version = 1)]
public partial class SampleSetting
{
    public string Name { get; set; } = "World";
    public int RunCount { get; set; }
    public bool DefaultValue { get; set; } = true;
}

// 2. Declare the preset layers. Only the sources listed here are enabled.
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);

// 3. Read and write through the options instance.
var options = context.GetOptions<SampleSetting>();
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// Sparse edit: only modified fields are saved to the target layer.
await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue is not modified, so it will not be saved to the target layer.
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

3 つのステップだけです。

1. **モデルを宣言する** — `[ConfiglueModel]` を付けた `partial class` に対し、ソースジェネレーターが Fragment / Patch のサポートを生成します。
2. **層を組み立てる** — `UseCommonSources` がグローバル / ローカル / 環境変数という標準的な層構成を組んでくれます。列挙したソースだけが有効になります。
3. **Options 経由で読み書きする** — `GetValueAsync` で読み、`SaveAsync(patch => ...)` で変更したフィールドだけを保存します。

保存されるのは `Name` と `RunCount` だけです。触っていない `DefaultValue` は対象層に書かれません。

## 6 つの概念

依存関係は直線的で、学習順も同じです。

```text
Resource (location) → Codec (conversion) → Source (contribution) → Fragment (diff) → Options (facade)
                                                        ↘ Patch (edit fragment)
```

| 概念 | 一言で | 例 |
| --- | --- | --- |
| **Resource** | バイトがどこにあるか | ファイル、ZIPエントリ、HTTP 応答、メモリ |
| **Codec** | バイト↔値の変換 | JSON / XML / YAML の読み書き |
| **Source** | 論理的な寄与（どのフィールドを、どの優先度で） | 「ユーザー設定ファイルの `Server` 部分」 |
| **Fragment** | 存在を記憶する差分 | 「`Port` だけ」を持つ状態 |
| **Patch** | 単一フィールドの編集 | 「`Port` を 9000 にする」 |
| **Options** | アプリが見るファサード | 読み・保存・監視・説明・診断 |

### 読み込み

各 Source が Resource からバイトを取得し、Codec が Fragment に変換します。
ランタイムは優先度順に Fragment を重ね、**存在するものだけ**を 1 つのモデルへ合成します。
`Priority` が大きい Source が勝ちます。

### 書き込み

逆向きです。アプリは普通のモデル値を編集します。
内部ではその変更が Fragment の差分になり、`WriteRoute` / `WritePlan` が指す Source にだけ届きます。**無関係な Source は変更されません。**

### Fragment は「不在」と「明示された値」を区別する

Fragment は「メンバーが存在しない」と「null や既定値として存在する」を区別します。
層を合成しても「未設定」が「既定値に設定」を上書きすることはありません。
つまり「触れなかったフィールド」が暗黙に層を壊すことはありません。

### Patch と `Unset()`

生成される `TModel.Patch` は単一フィールドの編集フラグメントです。
`Unset()` を呼ぶと、書き込み先 Source の寄与だけが取り消され、下位優先度の Source の値が再び見えるようになります。

### マージ戦略

`[ConfiglueMerge]` でメンバーごとにマージ挙動を変更できます。
組み込みは `Append` / `Deep` / `Replace` / `SetUnion`、カスタム戦略も指定可能です。
コレクションの層合成と順序はここで決まります。

## 主な機能

### 複数ソースの優先度マージ

`Priority` が大きい Source が勝ちます。`GetDetailsAsync` を使うことで、「どの値がどこから来たのか」を実行時に検査できます（→ [値の来歴を調べる](#値の来歴を調べる)）。

### 読み取り専用ソース

環境変数・コマンドライン・既定の HTTP ソースは読み取り専用です。
読み取り専用の値への書き込みは黙って無視されず、**競合エラー**になります。

### プロジェクション / マウント

既存 Source を別のモデルに整形（**projection**）したり、ネストしたパスに別の Source を接続（**mount**、`AddMounted`）できます。
たとえば 1 つの設定ファイルの中で、異なるモデルが担当するセクションを独立した Source として扱う、といった構成が可能です。

### プリセット

`UseCommonSources` が global / local / environment といった標準的な層構成を組み立てます（→ [Quick Start](#quick-start)）。

### スパース書き込み

変更したフィールドだけが対象層に保存されます。既定値のままのフィールドは書かれません（ただしユーザーが明示した `null` は尊重されます）。

### 編集セッション

`OpenEditSessionAsync` で複数の変更をまとめて適用し、`CommitAsync` までメモリ内で処理します。
競合時は既定で失敗しますが、`WriteConflictResolution.LastWriteWins` を選ぶこともできます。

### スキーマ移行 / ストレージ移行

`[ConfigluePreviousVersion]` と `Fragment.FromPrevious` により、旧バージョンの設定を新しい形式へ自動変換できます。
既存のファイルをそのまま Source として登録することもできます。

### バックアップとアトミック書き込み

`FileResource` はアトミック書き込みとバックアップ世代管理を提供します。
既定で `.bak` 1 世代を保持し、`RestoreLatestBackupAsync` で復元できます。

### セクション

`JsonSectionResource`（および XML 要素、YAML マッピング）により、ファイルの一部を独立した Resource として扱えます。
書き込み時にコメント・空白・引用・スカラー形式が保持されます。
同じファイル内の独立したセクションは、1 回の物理書き込みにバッチされます。

### その他のリソース

- `ZipEntryResource` — ZIP 内のエントリ
- `Configlue.Resource.Http` — ETag による条件付き書き込み・ポーリング
- `Configlue.Resource.S3`
- `Configlue.Resource.Dapr`

### 設定ファイルは人間が書く

- **JSON Schema 生成** — `Configlue.JsonSchema` がスキーマを生成・エクスポートします
- **コメントと書式の保持** — 上記のセクション対応で実現します

### Native AOT

ソース生成された `JsonSerializerContext` を渡すと、トリミング / AOT に強い挙動になります。

### リアクティブ統合（任意）

`Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）に対応しています。
`ObserveChanges()` / `ObserveValues()` / `ObserveReloadFailures()` / `ObserveActiveValues()` / `ObserveActiveProfileNames()` が利用できます。

### DI 統合

`Configlue.Extensions.DI` が Microsoft の DI と統合します。
Microsoft の options アダプターは `Configlue.Extensions.MSOptions`（`IOptions<T>` など）として提供されます。
なお `IOptions<T>` の同期ゲッターは非同期ソースの読み取り中にブロックするため、非同期フローでは `GetValueAsync` の利用を推奨します。

### プロファイル / 動的オプション

名前付きオプションや永続プロファイルにより、ランタイム単位で options インスタンスを作成・削除できます。

## 値の来歴を調べる

マージされた値だけを見ると、どこから来た値は分かりません。`GetDetailsAsync` は各メンバーの来歴を返します。

```csharp
var options = context.GetOptions<SampleSetting>();

// 1. 現在の値（全ソースをマージしたもの）を取得
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 2. 各値がどこから来たかを調べる
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

`details.Name.Sources` には、そのメンバーを提供したすべてのソースが「どの優先度で」「勝ち負けがどうだったか」とともに並びます。
診断用の UI やログ、あるいは「いま有効な値が書き込み可能か」を確認したいときに使えます。

## スパース保存と `Unset()`

指定したメンバーだけを更新するパッチを保存します。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

この例では:

- `Name` は `"Bob"` に更新される
- `RunCount` は書き込み先 Source の寄与が取り消され、下位優先度の Source の値が再び見える
- それ以外のメンバーは一切触られない

## API 一覧

| API | 役割 |
| --- | --- |
| `IReadOnlyOptions<T>` | 日常的な読み取り面。`GetValueAsync` と `OnChange` |
| `GetValueAsync()` | 全ソースをマージした現在の値を取得 |
| `GetDetailsAsync()` | 各メンバーの来歴（どのソースか・書き込み可能か）を取得 |
| `SaveAsync(patch => ...)` | 生成された Patch によるスパース保存 |
| `OpenEditSessionAsync()` / `CommitAsync()` | 複数の変更をまとめて適用 |
| `ApplyPatchesAsync` + `StateSourcePatch` | 明示的なソース別のマルチ書き込み |
| `StateWritePlan.For<T>().Route(...)` | 書き込みルーティング |
| `SourceKey<TModel>` / `options.Source(key)` | ソース単位の操作 |
| `RestoreLatestBackupAsync()` | `FileResource` の直近バックアップから復元 |

## パッケージ

| パッケージ | 役割 |
| --- | --- |
| `Configlue` | ユーザー向けメタパッケージ（実装アセンブリは持たない） |
| `Configlue.Abstraction` | 契約（provider / codec / resource / generated-model） |
| `Configlue.Core` | 解決と永続化のランタイム |
| `Configlue.Extensibility` | プロバイダー SDK |
| `Configlue.Generator` | Roslyn アナライザー（スパースなモデルサポートの生成） |
| `Configlue.Extensions.DI` | Microsoft DI 統合 |
| `Configlue.Extensions.MSOptions` | `IOptions<T>` などの Microsoft options アダプター |
| `Configlue.Extensions.R3` | R3 との統合 |
| `Configlue.Extensions.Reactive` | System.Reactive との統合 |
| `Configlue.Testing` | インメモリのテストダブル |
| `Configlue.Provider.Json` / `.Xml` / `.Yaml` | 各形式の Codec・セクションリソース・ファイル登録 |
| `Configlue.JsonSchema` | JSON Schema の生成・エクスポート |
| `Configlue.Source.Environment` / `.CommandLine` | 環境変数・コマンドライン引数のソース |
| `Configlue.Source.Presets` / `.Presets.Yaml` / `.Presets.Xml` | プリセット（層構成） |
| `Configlue.Resource.Http` / `.Http.AspNetCore` | HTTP ベースのリソース（ETag 条件付き書き込み・ポーリング） |
| `Configlue.Resource.S3` | S3 ベースのリソース |
| `Configlue.Resource.Dapr` | Dapr ベースのリソース |
| `Configlue.Resource.Zip` | ZIP エントリのリソース |
| `Configlue.Transformer.AES` | Resource と Codec の間のバイトを AES-GCM で暗号化・認証 |

## Microsoft.Extensions.Configuration との関係

`IConfiguration` は優れた読み取り中心の設計です。階層的なキー、provider の合成、リロードにも対応しています。
一方で、書き込みは主たる対象ではなく、「どの provider のどの値が勝ったか」を後から説明する方法が限られ、フィールド単位で「この値だけ対象層に書く」という操作も素朴ではありません。

Configlue はこの延長ではなく、別の軸に立っています。

- 設定ソースを**独立した Source** として明示的に管理し、合成結果は Priority で決まる
- **来歴を第一級の対象**にする（`GetDetailsAsync`）
- **スパースな保存**を前提とする（変更したフィールドだけが対象層に届く）
- 書き込み安全性（アトミック性・競合検出・バックアップ）を標準で提供する

設定の読み取りだけが目的で、階層的なキーで十分なら `Microsoft.Extensions.Configuration` が適しています。
一方、複数の独立した設定置き場を合成し、その来歴を説明し、変更だけを安全に反映させる必要があるなら、Configlue がその形に合います。

## 既知の制限

- **異なる Resource 間の書き込みはアトミックではありません** — 1 回の保存が複数の Resource にまたがる場合、それぞれの書き込みは個別にアトミックですが、まとめてはアトミックになりません
- **Source の退役は現在の options インスタンスに閉じ、実データは残ります** — Source を削除しても、削除前の Source が書き込んだ実データは消えません
- **Source 集合は options ランタイムで固定** — ランタイム作成後に Source を追加・削除して、既存の options インスタンスに反映させることはできません



---

# ===== opencode/ling-3.0-flash-fin-free =====





---

# ===== opencode/longcat-2.5-preview-free =====

# Configlue

**Make easy configuration management.**

Configlue は、アプリケーションの設定管理を代行する .NET ライブラリです。複数の場所に散らばった設定を 1 つのモデルに**結合（glue）**するのが中心的な考え方で、名前も configuration + glue に由来します。

## 概要

JSON ファイルの読み書きだけなら数行で済みます。しかし実際のアプリケーションでは、次のような要件が積み重なります。

- 設定が複数箇所にある: グローバル設定、実行フォルダー設定、環境変数、コマンドライン引数、暗号化された資格情報、社内ポリシーや HTTP API などのリモート管理
- 設定ファイルが書き換わったら再起動なしで反映したい（変更通知）
- 書き込み先を自動で選びたい。環境変数から読んだ値への書き込みはエラーにしたい
- 設定ファイルは人間が書く: コメントを消さない、JSON Schema がほしい、壊れたファイルへの対処
- 既定値のままなら書き出さない（ただしユーザーが明示した `null` は尊重する）
- 設定ファイルのバージョンアップ（旧形式→新形式への自動変換）
- バックアップと自動整理
- 書き込みの安全性: アトミック性（クラッシュしても壊れない）、他プロセスとの競合検出・自動マージ、自動リトライ

Configlue はこれらの課題に取り組みます。

`Microsoft.Extensions.Configuration` の `IConfiguration` が読み取り中心であるのに対し、Configlue は独立したソースの合成、値の来歴の検査、スパース保存に向いています。

## アーキテクチャ

依存関係は直線的で、学習順も同じです。

```text
Resource (location) → Codec (conversion) → Source (contribution) → Fragment (diff) → Options (facade)
                                                        ↘ Patch (edit fragment)
```

| 概念 | 一言で | 例 |
| --- | --- | --- |
| Resource | バイトがどこにあるか | ファイル、ZIPエントリ、HTTP応答、メモリ |
| Codec | バイト↔値の変換 | JSON / XML / YAML の読み書き |
| Source | 論理的な寄与（どのフィールドをどの優先度で） | 「ユーザー設定ファイルの Server 部分」 |
| Fragment | 存在を記憶する差分 | 「Port だけ」を持つ状態 |
| Patch | 単一フィールドの編集 | 「Port を 9000 にする」 |
| Options | アプリが見るファサード | 読み・保存・監視・説明・診断 |

**読み込み**: 各 Source が Resource からバイトを取得し、Codec が Fragment に変換します。ランタイムが優先度順に「存在する」フィールドだけを 1 つのモデルへ重ねます。

**書き込み**: 逆向きです。アプリは普通のモデル値を編集します。内部では変更が Fragment 差分になり、`WriteRoute` / `WritePlan` が指す Source にだけ届きます。無関係な Source は変更されません。

- Fragment は「メンバーが存在しない」と「null/既定値で存在する」を区別します。層の合成で「未設定」が「既定値に設定」を上書きすることはありません。
- Patch は生成される `TModel.Patch`（単一フィールドの編集フラグメント）です。`Unset()` は書き込み先 Source の寄与だけを取り消し、下位優先度の値を再び見せます。
- `[ConfiglueMerge]` でメンバーごとのマージ挙動を変更できます（組み込み: `Append`, `Deep`, `Replace`, `SetUnion`、カスタム戦略も可）。コレクションの層合成・順序はここで決まります。

## 主な機能

- **複数ソースの優先度マージ**: `Priority` が大きい Source が勝ちます。`GetDetailsAsync` で「どの値がどこ由来か」を検査できます。
- **読み取り専用ソース**: 環境変数・コマンドライン・既定の HTTP ソースは読み取り専用です。読み取り専用の値への書き込みは黙って無視せず競合エラーになります。
- **プロジェクション / マウント**: 既存 Source を別モデルに整形（projection）したり、ネストしたパスに別 Source を接続（mount, `AddMounted`）できます。
- **プリセット**: `UseCommonSources` が標準的な層構成（global/local/environment など）を組み立てます。
- **スパース書き込み**: 変更したフィールドだけを対象層に保存します。既定値のままのフィールドは書かれません。
- **編集セッション**: `OpenEditSessionAsync` で複数変更をまとめて適用します。`CommitAsync` までインメモリです。競合時は既定で失敗し、`WriteConflictResolution.LastWriteWins` も選べます。
- **スキーマ移行 / ストレージ移行**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` による旧バージョン設定の自動変換。既存ファイルを Source として登録できます。
- **バックアップと復元**: `FileResource` はアトミック書き込みとバックアップ世代管理を行います。既定で `.bak` 1 世代、`RestoreLatestBackupAsync` で復元できます。
- **安全な書き込み**: アトミック性、競合検出、リトライ。
- **セクション**: `JsonSectionResource` / XML 要素 / YAML マッピングで、ファイルの一部を独立した Resource として扱えます。書き込み時はコメント・空白・引用・スカラー形式を保持します。同じファイル内の独立セクションは 1 回の物理書き込みにバッチされます。
- **ZIP / HTTP / S3 / Dapr**: `ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込み・ポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **JSON Schema 生成**: `Configlue.JsonSchema`。人間が設定を書くためのスキーマを生成・エクスポートします。
- **Native AOT 対応**: ソース生成の `JsonSerializerContext` を渡すとトリミング/AOT に強くなります。
- **リアクティブ統合（任意）**: `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）。`ObserveChanges()`, `ObserveValues()`, `ObserveReloadFailures()`, `ObserveActiveValues()`, `ObserveActiveProfileNames()`。
- **DI 統合**: `Configlue.Extensions.DI`。Microsoft の options アダプター `Configlue.Extensions.MSOptions`（`IOptions<T>` など。同期ゲッターは非同期ソース読み取り中ブロックするため、非同期フローでは `GetValueAsync` を推奨）。
- **プロファイル / 動的オプション**: 名前付きオプションや永続プロファイルでランタイムを単位に作成・削除できます。

## インストール

```bash
dotnet add package Configlue
```

必要な機能パッケージを追加してください。

## クイックスタート

`example.cs` に保存し `dotnet run example.cs` で実行します（.NET 10 以降）。

```csharp
#!/usr/bin/env dotnet
#:package Configlue@*

using Configlue;
using Configlue.Source.Presets;

// 1. Declare the settings model. The generator creates Fragment/Patch support.
[ConfiglueModel("SampleSetting", Version = 1)]
public partial class SampleSetting
{
    public string Name { get; set; } = "World";
    public int RunCount { get; set; }
    public bool DefaultValue { get; set; } = true;
}

// 2. Declare the preset layers. Only the sources listed here are enabled.
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);

// 3. Read and write through the options instance.
var options = context.GetOptions<SampleSetting>();
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// Sparse edit: only modified fields are saved to the target layer.
await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue is not modified, so it will not be saved to the target layer.
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

## 値の由来を調べる / スパース保存

```csharp
var options = context.GetOptions<AppSettings>();
// 1. 現在の値（全ソースをマージしたもの）を取得
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 2. 各値がどこから来たかを調べる
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

指定したメンバーだけを更新するパッチを保存します。`Unset()` はその Source の寄与を外し、下位優先度の Source が値を提供できるようにします。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

その他の主な API:

- `IReadOnlyOptions<T>` … 日常の読み取り面は `GetValueAsync` と `OnChange`
- `SaveAsync(patch => ...)` … 生成 Patch でスパース保存
- `OpenEditSessionAsync()` … まとめて編集し `CommitAsync`
- `ApplyPatchesAsync` + `StateSourcePatch` … 明示的なソース別マルチ書き込み
- `StateWritePlan.For<T>().Route(...)` … 書き込みルーティング
- `SourceKey<TModel>` と `options.Source(key)` … ソース単位の操作

## パッケージ構成

- `Configlue` … ユーザー向けメタパッケージ（Core / DI / JSON provider / JSON Schema / HTTP resources / common sources / environment source / generator analyzer を同梱。実装アセンブリは持たない）
- `Configlue.Abstraction` … 契約（provider/codec/resource/generated-model）
- `Configlue.Core` … 解決と永続化のランタイム
- `Configlue.Extensibility` … プロバイダー SDK
- `Configlue.Extensions.DI` / `Configlue.Extensions.MSOptions` / `Configlue.Extensions.R3` / `Configlue.Extensions.Reactive`
- `Configlue.Generator` … Roslyn アナライザー（スパースなモデルサポート生成）
- `Configlue.Testing` … インメモリのテストダブル
- `Configlue.Provider.Json` / `.Xml` / `.Yaml` … 各形式の Codec・セクションリソース・ファイル登録
- `Configlue.JsonSchema` … JSON Schema 生成・エクスポート
- `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml`
- `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip`
- `Configlue.Transformer.AES` … Resource と Codec の間のバイトを AES-GCM 暗号化・認証

## 既知の制限

- 異なる Resource 間の書き込みはアトミックではありません。
- Source の退役は現在の options インスタンスに閉じ、実データは残ります。
- Source 集合は options ランタイムで固定されます。

## 動作要件

- .NET 10 SDK 以降
- C#（`LangVersion` はソースジェネレーター対応が必要、リポジトリは preview でビルド）

## ライセンス

Apache-2.0



---

# ===== opencode/mimo-v2.6-flash-free =====

# Configlue

**Make easy configuration management.**

Configlue は、アプリケーションの設定管理を代行する .NET ライブラリです。複数の場所に散らばった設定を 1 つのモデルに**結合（glue）**することを目指しており、名前は configuration + glue に由来します。

- 対象: .NET 10 SDK 以降（C#、ソースジェネレーター対応の `LangVersion`）
- ライセンス: Apache-2.0

現時点では「アーキテクチャ上の土台」であり、`Configuration.Writable` を完全に置き換えるものではありません。

---

## Why Configlue?

JSON ファイルの読み書きだけなら数行で済みます。しかし実際のアプリでは、次のような要件が積み重なっていきます。

- 設定が複数箇所にある: グローバル設定、実行フォルダー設定、環境変数、コマンドライン引数、暗号化された資格情報、社内ポリシーや HTTP API などのリモート管理。
- 設定ファイルが書き換わったら再起動なしで反映したい（変更通知）。
- 書き込み先を自動で選びたい。環境変数から読んだ値への書き込みはエラーにしたい。
- 設定ファイルは人間が書く: コメントを消さない、JSON Schema がほしい、壊れたファイルへの対処をしたい。
- 既定値のままなら書き出さない（ただしユーザーが明示した `null` は尊重する）。
- 設定ファイルのバージョンアップ（旧形式→新形式への自動変換）。
- バックアップと自動整理。
- 書き込みの安全性: アトミック性（クラッシュしても壊れない）、他プロセスとの競合検出・自動マージ、自動リトライ。

これらを自前実装するのは面倒、というのが Configlue の動機です。

---

## 基本アーキテクチャ（6つの概念）

依存関係は直線的で、学習順も同じです。

```text
Resource (location) → Codec (conversion) → Source (contribution) → Fragment (diff) → Options (facade)
                                                        ↘ Patch (edit fragment)
```

| 概念 | 一言で | 例 |
| --- | --- | --- |
| Resource | バイトがどこにあるか | ファイル、ZIPエントリ、HTTP応答、メモリ |
| Codec | バイト↔値の変換 | JSON / XML / YAML の読み書き |
| Source | 論理的な寄与（どのフィールドをどの優先度で） | 「ユーザー設定ファイルの Server 部分」 |
| Fragment | 存在を記憶する差分 | 「Port だけ」を持つ状態 |
| Patch | 単一フィールドの編集 | 「Port を 9000 にする」 |
| Options | アプリが見るファサード | 読み・保存・監視・説明・診断 |

**読み込み**: 各 Source が Resource からバイトを取得し、Codec が Fragment に変換します。ランタイムは優先度順に「存在する」フィールドだけを 1 つのモデルへ重ね合わせます。

**書き込み**: 逆方向に流れます。アプリは普通のモデル値を編集するだけで、内部で変更が Fragment 差分になり、`WriteRoute` / `WritePlan` が指す Source にだけ届きます。無関係な Source は変更されません。

補足:

- Fragment は「メンバーが存在しない」と「null/既定値で存在する」を区別します。層の合成で「未設定」が「既定値に設定」を上書きすることはありません。
- Patch は生成される `TModel.Patch`（単一フィールドの編集フラグメント）です。`Unset()` は書き込み先 Source の寄与だけを取り消し、下位優先度の値を再び見せます。
- `[ConfiglueMerge]` でメンバーごとのマージ挙動を変更できます（組み込み: `Append`, `Deep`, `Replace`, `SetUnion`、カスタム戦略も可）。コレクションの層合成・順序はここで決まります。

---

## 主な機能

- **複数ソースの優先度マージ**: `Priority` が大きい Source が勝ちます。`GetDetailsAsync` で「どの値がどこ由来か」を検査できます。
- **読み取り専用ソース**: 環境変数・コマンドライン・既定の HTTP ソースは読み取り専用です。読み取り専用の値への書き込みは黙って無視せず、競合エラーになります。
- **プロジェクション / マウント**: 既存 Source を別モデルに整形（projection）したり、ネストしたパスに別 Source を接続（mount, `AddMounted`）できます。
- **プリセット**: `UseCommonSources` が標準的な層構成（global / local / environment など）を組み立てます。
- **スパース書き込み**: 変更したフィールドだけを対象層に保存します。既定値のままのフィールドは書き出されません。
- **編集セッション**: `OpenEditSessionAsync` で複数変更をまとめて適用し、`CommitAsync` までインメモリで保持します。競合時は既定で失敗、`WriteConflictResolution.LastWriteWins` も選べます。
- **スキーマ移行 / ストレージ移行**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` で旧バージョン設定を自動変換できます。既存ファイルを Source として登録できます。
- **バックアップと復元**: `FileResource` はアトミック書き込みとバックアップ世代管理を提供します。既定で `.bak` 1 世代、`RestoreLatestBackupAsync` で復元できます。
- **安全な書き込み**: アトミック性、競合検出、リトライ。
- **セクション**: `JsonSectionResource` / XML 要素 / YAML マッピングで、ファイルの一部を独立した Resource として扱えます。書き込み時はコメント・空白・引用・スカラー形式を保持し、同じファイル内の独立セクションは 1 回の物理書き込みにバッチされます。
- **ZIP / HTTP / S3 / Dapr**: `ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込み・ポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **JSON Schema 生成**: `Configlue.JsonSchema`。人間が設定を書くための支援に使えます。
- **Native AOT 対応**: ソース生成の `JsonSerializerContext` を渡すとトリミング / AOT に強くなります。
- **リアクティブ統合（任意）**: `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）。`ObserveChanges()`, `ObserveValues()`, `ObserveReloadFailures()`, `ObserveActiveValues()`, `ObserveActiveProfileNames()` を提供します。
- **DI 統合**: `Configlue.Extensions.DI`。Microsoft の options アダプター `Configlue.Extensions.MSOptions`（`IOptions<T>` など）も用意しています。同期ゲッターは非同期ソースの読み取り中にブロックするため、非同期フローでは `GetValueAsync` を推奨します。
- **プロファイル / 動的オプション**: 名前付きオプションや永続プロファイルで、ランタイムを単位に作成・削除できます。

既知の制限:

- 異なる Resource 間の書き込みはアトミックではありません。
- Source の退役は現在の options インスタンスに閉じており、実データは残ります。
- Source 集合は options ランタイムで固定されています。

---

## パッケージ構成

| パッケージ | 役割 |
| --- | --- |
| `Configlue` | ユーザー向けメタパッケージ（Core / DI / JSON provider / JSON Schema / HTTP resources / common sources / environment source / generator analyzer を同梱。実装アセンブリは持たない） |
| `Configlue.Abstraction` | 契約（provider / codec / resource / generated-model） |
| `Configlue.Core` | 解決と永続化のランタイム |
| `Configlue.Extensibility` | プロバイダー SDK |
| `Configlue.Extensions.DI` / `.MSOptions` / `.R3` / `.Reactive` | 各種統合 |
| `Configlue.Generator` | Roslyn アナライザー（スパースなモデルサポート生成） |
| `Configlue.Testing` | インメモリのテストダブル |
| `Configlue.Provider.Json` / `.Xml` / `.Yaml` | 各形式の Codec・セクションリソース・ファイル登録 |
| `Configlue.JsonSchema` | JSON Schema 生成・エクスポート |
| `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml` | 各種ソース |
| `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip` | 各種リソース |
| `Configlue.Transformer.AES` | Resource と Codec の間のバイトを AES-GCM で暗号化・認証 |

インストールは `dotnet add package Configlue` から始め、必要な機能パッケージを追加します。

---

## Quick Start

`example.cs` に保存し、.NET 10 以降で `dotnet run example.cs` として実行できます。

```csharp
#!/usr/bin/env dotnet
#:package Configlue@*

using Configlue;
using Configlue.Source.Presets;

// 1. Declare the settings model. The generator creates Fragment/Patch support.
[ConfiglueModel("SampleSetting", Version = 1)]
public partial class SampleSetting
{
    public string Name { get; set; } = "World";
    public int RunCount { get; set; }
    public bool DefaultValue { get; set; } = true;
}

// 2. Declare the preset layers. Only the sources listed here are enabled.
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);

// 3. Read and write through the options instance.
var options = context.GetOptions<SampleSetting>();
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// Sparse edit: only modified fields are saved to the target layer.
await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue is not modified, so it will not be saved to the target layer.
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

---

## 値の由来を調べる / スパース保存

現在の値がどこから来たか、書き込み可能かを検査できます。

```csharp
var options = context.GetOptions<AppSettings>();
// 1. 現在の値（全ソースをマージしたもの）を取得
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 2. 各値がどこから来たかを調べる
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

指定したメンバーだけを更新するパッチを保存できます。`Unset()` はその Source の寄与を外し、下位優先度の Source が値を提供できるようにします。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

### 主な API

- `IReadOnlyOptions<T>` … 日常の読み取り面は `GetValueAsync` と `OnChange`
- `SaveAsync(patch => ...)` … 生成 Patch によるスパース保存
- `OpenEditSessionAsync()` … まとめて編集し `CommitAsync`
- `ApplyPatchesAsync` + `StateSourcePatch` … 明示的なソース別マルチ書き込み
- `StateWritePlan.For<T>().Route(...)` … 書き込みルーティング
- `SourceKey<TModel>` と `options.Source(key)` … ソース単位の操作

---

## Microsoft.Extensions.Configuration との違い

`IConfiguration` が読み取り中心の API であるのに対し、Configlue は**独立したソースの合成・値の来歴の検査・スパース保存**に向いています。複数ソースを優先度でマージし、どの値がどこから来たかを調べ、変更したフィールドだけを正しい書き込み先に保存したい場合に適合します。



---

# ===== opencode/muse-spark-1.3-contributor-free =====

調査メモを基にREADME用の日本語解説を作成します。# Configlue

> Make easy configuration management.

Configlue は、アプリケーションの設定管理（configuration management）を代行する **.NET ライブラリ**です。

複数の場所に散らばった設定を 1 つのモデルに**結合（glue）**するのが中心的な考え方です。名前も configuration + glue に由来します。

- 対象: .NET 10 SDK 以降。C#（`LangVersion` はソースジェネレーター対応が必要、リポジトリは preview でビルド）
- ライセンス: Apache-2.0
- 現状は「アーキテクチャ上の土台」であり、`Configuration.Writable` を完全に置き換えるものではありません。

インストールは `dotnet add package Configlue` から開始し、必要な機能パッケージを追加します。

## Why Configlue?

JSON ファイルの読み書きだけなら数行で済みます。しかし実際には次のような要件が積み重なります:

- 設定が複数箇所にある: グローバル設定、実行フォルダー設定、環境変数、コマンドライン引数、暗号化された資格情報、社内ポリシーや HTTP API などのリモート管理
- 設定ファイルが書き換わったら再起動なしで反映したい（変更通知）
- 書き込み先を自動で選びたい。環境変数から読んだ値への書き込みはエラーにしたい
- 設定ファイルは人間が書く: コメントを消さない、JSON Schema がほしい、壊れたファイルへの対処
- 既定値のままなら書き出さない（ただしユーザーが明示した `null` は尊重する）
- 設定ファイルのバージョンアップ（旧形式→新形式への自動変換）
- バックアップと自動整理
- 書き込みの安全性: アトミック性（クラッシュしても壊れない）、他プロセスとの競合検出・自動マージ、自動リトライ

これらを自前実装するのは面倒、というのが動機です。

## 基本アーキテクチャ: 6つの概念

依存関係は直線的で、学習順も同じです:

```text
Resource (location) → Codec (conversion) → Source (contribution) → Fragment (diff) → Options (facade)
                                                        ↘ Patch (edit fragment)
```

| 概念 | 一言で | 例 |
| --- | --- | --- |
| Resource | バイトがどこにあるか | ファイル、ZIPエントリ、HTTP応答、メモリ |
| Codec | バイト↔値の変換 | JSON / XML / YAML の読み書き |
| Source | 論理的な寄与（どのフィールドをどの優先度で） | 「ユーザー設定ファイルの Server 部分」 |
| Fragment | 存在を記憶する差分 | 「Port だけ」を持つ状態 |
| Patch | 単一フィールドの編集 | 「Port を 9000 にする」 |
| Options | アプリが見るファサード | 読み・保存・監視・説明・診断 |

**読み込み**: 各 Source が Resource からバイトを取得し、Codec が Fragment に変換します。ランタイムが優先度順に「存在する」フィールドだけを 1 つのモデルへ重ねます。

**書き込み**: 逆向きです。アプリは普通のモデル値を編集します。内部では変更が Fragment 差分になり、`WriteRoute` / `WritePlan` が指す Source にだけ届きます。無関係な Source は変更されません。

- Fragment は「メンバーが存在しない」と「null/既定値で存在する」を区別します。層の合成で「未設定」が「既定値に設定」を上書きすることはありません。
- Patch は生成される `TModel.Patch`（単一フィールドの編集フラグメント）です。`Unset()` は書き込み先 Source の寄与だけを取り消し、下位優先度の値を再び見せます。
- `[ConfiglueMerge]` でメンバーごとのマージ挙動を変更できます（組み込み: `Append`, `Deep`, `Replace`, `SetUnion`、カスタム戦略も可）。コレクションの層合成・順序はここで決まります。

## 主な機能

- **複数ソースの優先度マージ**: `Priority` が大きい Source が勝ちます。`GetDetailsAsync` で「どの値がどこ由来か」を検査できます。
- **読み取り専用ソース**: 環境変数・コマンドライン・既定の HTTP ソースは読み取り専用です。読み取り専用の値への書き込みは黙って無視せず競合エラーになります。
- **プロジェクション / マウント**: 既存 Source を別モデルに整形（projection）したり、ネストしたパスに別 Source を接続（mount, `AddMounted`）できます。
- **プリセット**: `UseCommonSources` が標準的な層構成（global/local/environment など）を組み立てます。
- **スパース書き込み**: 変更したフィールドだけを対象層に保存します。既定値のままのフィールドは書かれません。
- **編集セッション**: `OpenEditSessionAsync` で複数変更をまとめて適用します。`CommitAsync` までインメモリです。競合時は既定で失敗、`WriteConflictResolution.LastWriteWins` も選べます。
- **スキーマ移行 / ストレージ移行**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` による旧バージョン設定の自動変換。既存ファイルを Source として登録できます。
- **バックアップと復元**: `FileResource` はアトミック書き込みとバックアップ世代管理を行います。既定で `.bak` 1 世代、`RestoreLatestBackupAsync` で復元します。
- **安全な書き込み**: アトミック性、競合検出、リトライ。
- **セクション**: `JsonSectionResource` / XML 要素 / YAML マッピングで、ファイルの一部を独立した Resource として扱えます。書き込み時はコメント・空白・引用・スカラー形式を保持します。同じファイル内の独立セクションは 1 回の物理書き込みにバッチされます。
- **ZIP / HTTP / S3 / Dapr**: `ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込み・ポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **JSON Schema 生成**: `Configlue.JsonSchema`。人間が設定を書くため。
- **Native AOT 対応**: ソース生成の `JsonSerializerContext` を渡すとトリミング/AOT に強くなります。
- **リアクティブ統合（任意）**: `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）。`ObserveChanges()`, `ObserveValues()`, `ObserveReloadFailures()`, `ObserveActiveValues()`, `ObserveActiveProfileNames()`。
- **DI 統合**: `Configlue.Extensions.DI`。Microsoft の options アダプター `Configlue.Extensions.MSOptions`（`IOptions<T>` など。同期ゲッターは非同期ソース読み取り中ブロックするので非同期フローでは `GetValueAsync` 推奨）。
- **プロファイル / 動的オプション**: 名前付きオプションや永続プロファイルでランタイムを単位に作成・削除できます。

既知の制限:

- 異なる Resource 間の書き込みはアトミックではありません。
- Source の退役は現在の options インスタンスに閉じ、実データは残ります。
- Source 集合は options ランタイムで固定です。

## パッケージ構成

- `Configlue` … ユーザー向けメタパッケージ（Core / DI / JSON provider / JSON Schema / HTTP resources / common sources / environment source / generator analyzer を同梱。実装アセンブリは持たない）
- `Configlue.Abstraction` … 契約（provider/codec/resource/generated-model）
- `Configlue.Core` … 解決と永続化のランタイム
- `Configlue.Extensibility` … プロバイダー SDK
- `Configlue.Extensions.DI` / `Configlue.Extensions.MSOptions` / `Configlue.Extensions.R3` / `Configlue.Extensions.Reactive`
- `Configlue.Generator` … Roslyn アナライザー（スパースなモデルサポート生成）
- `Configlue.Testing` … インメモリのテストダブル
- `Configlue.Provider.Json` / `.Xml` / `.Yaml` … 各形式の Codec・セクションリソース・ファイル登録
- `Configlue.JsonSchema` … JSON Schema 生成・エクスポート
- `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml`
- `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip`
- `Configlue.Transformer.AES` … Resource と Codec の間のバイトを AES-GCM 暗号化・認証

## Quick Start

`example.cs` に保存し `dotnet run example.cs` で実行（.NET 10 以降）:

```csharp
#!/usr/bin/env dotnet
#:package Configlue@*

using Configlue;
using Configlue.Source.Presets;

// 1. Declare the settings model. The generator creates Fragment/Patch support.
[ConfiglueModel("SampleSetting", Version = 1)]
public partial class SampleSetting
{
    public string Name { get; set; } = "World";
    public int RunCount { get; set; }
    public bool DefaultValue { get; set; } = true;
}

// 2. Declare the preset layers. Only the sources listed here are enabled.
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);

// 3. Read and write through the options instance.
var options = context.GetOptions<SampleSetting>();
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// Sparse edit: only modified fields are saved to the target layer.
await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue is not modified, so it will not be saved to the target layer.
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

## 値の由来を調べる / スパース保存

```csharp
var options = context.GetOptions<AppSettings>();
// 1. 現在の値（全ソースをマージしたもの）を取得
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 2. 各値がどこから来たかを調べる
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

指定したメンバーだけを更新するパッチを保存します。`Unset()` はその Source の寄与を外し、下位優先度の Source が値を提供できるようにします:

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

その他の API:

- `IReadOnlyOptions<T>` … 日常の読み取り面は `GetValueAsync` と `OnChange`
- `SaveAsync(patch => ...)` … 生成 Patch でスパース保存
- `OpenEditSessionAsync()` … まとめて編集し `CommitAsync`
- `ApplyPatchesAsync` + `StateSourcePatch` … 明示的なソース別マルチ書き込み
- `StateWritePlan.For<T>().Route(...)` … 書き込みルーティング
- `SourceKey<TModel>` と `options.Source(key)` … ソース単位の操作

## Microsoft.Extensions.Configuration との違い

`IConfiguration` は読み取り中心であるのに対し、Configlue は独立した Source の合成・来歴の検査・スパース保存に向きます。読み取り専用ソースへの書き込み防止、優先度マージ、変更通知、セクション単位の保持書き込みなどを前提としています。




---

# ===== opencode/nemotron-3-ultra-free =====

# Configlue

**.NET アプリケーションの設定管理を簡単に。**

> "Make easy configuration management."

Configlue は、複数の場所に散らばった設定を 1 つのモデルに **結合（glue）** する .NET ライブラリです。  
.NET 10 SDK 以降 / Apache-2.0 ライセンス。

---

## なぜ Configlue か？

JSON の読み書きだけなら数行で済みます。しかし現実には次の要件が積み重なります：

- 設定が複数箇所にある（グローバル / ローカル / 環境変数 / コマンドライン / 暗号化資格情報 / リモート API 等）
- ファイル変更を再起動なしで反映したい（変更通知）
- 書き込み先を自動で選びたい（環境変数由来の値への書き込みはエラーにしたい）
- 人間が編集するファイル：コメントを消さない、JSON Schema がほしい、壊れたファイルへの対処
- 既定値のままなら書き出さない（明示的な `null` は尊重）
- 設定ファイルのバージョンアップ（旧形式→新形式への自動変換）
- バックアップと自動整理
- 安全な書き込み：アトミック性、競合検出・自動マージ、リトライ

これらを自前実装するのは面倒です。Configlue がそれを肩代わりします。

---

## 基本アーキテクチャ（6つの概念）

依存関係は直線的で、学習順も同じです：

```
Resource (場所) → Codec (変換) → Source (寄与) → Fragment (差分) → Options (ファサード)
                                                      ↘ Patch (編集フラグメント)
```

| 概念 | 一言で | 例 |
| --- | --- | --- |
| **Resource** | バイトがどこにあるか | ファイル、ZIPエントリ、HTTP応答、メモリ |
| **Codec** | バイト↔値の変換 | JSON / XML / YAML の読み書き |
| **Source** | 論理的な寄与（どのフィールドをどの優先度で） | 「ユーザー設定ファイルの Server 部分」 |
| **Fragment** | 存在を記憶する差分 | 「Port だけ」を持つ状態 |
| **Patch** | 単一フィールドの編集 | 「Port を 9000 にする」 |
| **Options** | アプリが見るファサード | 読み・保存・監視・説明・診断 |

**読み込み**：各 Source が Resource からバイトを取得し、Codec が Fragment に変換。ランタイムが優先度順に「存在する」フィールドだけを 1 つのモデルへ重ねます。

**書き込み**：逆向き。アプリは普通のモデル値を編集し、内部では変更が Fragment 差分になり、対象 Source にだけ届きます。無関係な Source は変更されません。

- Fragment は「メンバーが存在しない」と「null/既定値で存在する」を区別します。層の合成で「未設定」が「既定値に設定」を上書きすることはありません。
- Patch は生成される `TModel.Patch`（単一フィールドの編集フラグメント）。`Unset()` は書き込み先 Source の寄与だけを取り消し、下位優先度の値を再び見せます。
- `[ConfiglueMerge]` でメンバーごとのマージ挙動を変更可能（組み込み: `Append`, `Deep`, `Replace`, `SetUnion`、カスタム戦略も可）。コレクションの層合成・順序はここで決まります。

---

## 主な機能

- **複数ソースの優先度マージ**：`Priority` が大きい Source が勝つ。`GetDetailsAsync` で「どの値がどこ由来か」を検査可能
- **読み取り専用ソース**：環境変数・コマンドライン・既定の HTTP ソースは読み取り専用。書き込みは黙って無視せず競合エラーになる
- **プロジェクション / マウント**：既存 Source を別モデルに整形（projection）したり、ネストしたパスに別 Source を接続（mount, `AddMounted`）可能
- **プリセット**：`UseCommonSources` が標準的な層構成（global/local/environment など）を組み立てる
- **スパース書き込み**：変更したフィールドだけを対象層に保存。既定値のままのフィールドは書かれない
- **編集セッション**：`OpenEditSessionAsync` で複数変更をまとめて適用。`CommitAsync` までインメモリ。競合時は既定で失敗、`WriteConflictResolution.LastWriteWins` も選択可能
- **スキーマ移行 / ストレージ移行**：`[ConfigluePreviousVersion]` と `Fragment.FromPrevious` による旧バージョン設定の自動変換。既存ファイルを Source として登録可能
- **バックアップと復元**：`FileResource` はアトミック書き込みとバックアップ世代管理。既定で `.bak` 1 世代、`RestoreLatestBackupAsync` で復元
- **安全な書き込み**：アトミック性、競合検出、リトライ
- **セクション**：`JsonSectionResource` / XML 要素 / YAML マッピングで、ファイルの一部を独立した Resource として扱える。書き込み時はコメント・空白・引用・スカラー形式を保持。同じファイル内の独立セクションは 1 回の物理書き込みにバッチされる
- **ZIP / HTTP / S3 / Dapr**：`ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込み・ポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`
- **JSON Schema 生成**：`Configlue.JsonSchema`。人間が設定を書くため
- **Native AOT 対応**：ソース生成の `JsonSerializerContext` を渡すとトリミング/AOT に強くなる
- **リアクティブ統合（任意）**：`Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）。`ObserveChanges()`, `ObserveValues()`, `ObserveReloadFailures()`, `ObserveActiveValues()`, `ObserveActiveProfileNames()`
- **DI 統合**：`Configlue.Extensions.DI`。Microsoft の options アダプター `Configlue.Extensions.MSOptions`（`IOptions<T>` など。同期ゲッターは非同期ソース読み取り中ブロックするので非同期フローでは `GetValueAsync` 推奨）
- **プロファイル / 動的オプション**：名前付きオプションや永続プロファイルでランタイムを単位に作成・削除可能

### 既知の制限

- 異なる Resource 間の書き込みはアトミックでない
- Source の退役は現在の options インスタンスに閉じ、実データは残る
- Source 集合は options ランタイムで固定

---

## パッケージ構成（主要なもの）

| パッケージ | 説明 |
| --- | --- |
| `Configlue` | ユーザー向けメタパッケージ（Core / DI / JSON provider / JSON Schema / HTTP resources / common sources / environment source / generator analyzer を同梱。実装アセンブリは持たない） |
| `Configlue.Abstraction` | 契約（provider/codec/resource/generated-model） |
| `Configlue.Core` | 解決と永続化のランタイム |
| `Configlue.Extensibility` | プロバイダー SDK |
| `Configlue.Extensions.DI` / `Configlue.Extensions.MSOptions` / `Configlue.Extensions.R3` / `Configlue.Extensions.Reactive` | 統合パッケージ |
| `Configlue.Generator` | Roslyn アナライザー（スパースなモデルサポート生成） |
| `Configlue.Testing` | インメモリのテストダブル |
| `Configlue.Provider.Json` / `.Xml` / `.Yaml` | 各形式の Codec・セクションリソース・ファイル登録 |
| `Configlue.JsonSchema` | JSON Schema 生成・エクスポート |
| `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml` | 組み込みソース |
| `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip` | リモートリソース |
| `Configlue.Transformer.AES` | Resource と Codec の間のバイトを AES-GCM 暗号化・認証 |

**インストール**：
```bash
dotnet add package Configlue
```
必要な機能パッケージを追加してください。

---

## Quick Start

`example.cs` に保存し `dotnet run example.cs` で実行（.NET 10 以降）：

```csharp
#!/usr/bin/env dotnet
#:package Configlue@*

using Configlue;
using Configlue.Source.Presets;

// 1. 設定モデルを宣言。ジェネレーターが Fragment/Patch サポートを生成
[ConfiglueModel("SampleSetting", Version = 1)]
public partial class SampleSetting
{
    public string Name { get; set; } = "World";
    public int RunCount { get; set; }
    public bool DefaultValue { get; set; } = true;
}

// 2. プリセット層を宣言。ここに列挙した Source のみ有効化される
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);

// 3. Options インスタンス経由で読み書き
var options = context.GetOptions<SampleSetting>();
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// スパース編集：変更したフィールドだけ対象層に保存
await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue は未変更なので対象層に書かれない
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

---

## 値の由来を調べる / スパース保存

```csharp
var options = context.GetOptions<AppSettings>();

// 1. 現在の値（全ソースをマージしたもの）を取得
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 2. 各値がどこから来たかを調べる
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

指定したメンバーだけを更新するパッチを保存。`Unset()` はその Source の寄与を外し、下位優先度の Source が値を提供できるようにします：

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

### その他の API

- `IReadOnlyOptions<T>` … 日常の読み取り面は `GetValueAsync` と `OnChange`
- `SaveAsync(patch => ...)` … 生成 Patch でスパース保存
- `OpenEditSessionAsync()` … まとめて編集し `CommitAsync`
- `ApplyPatchesAsync` + `StateSourcePatch` … 明示的なソース別マルチ書き込み
- `StateWritePlan.For<T>().Route(...)` … 書き込みルーティング
- `SourceKey<TModel>` と `options.Source(key)` … ソース単位の操作

---

## Microsoft.Extensions.Configuration との違い

| 観点 | `IConfiguration` | Configlue |
| --- | --- | --- |
| 主眼 | 読み取り中心 | **独立ソースの合成・来歴の検査・スパース保存** |
| 書き込み | ほぼ非対応 | **スパース書き込み・編集セッション・競合検出** |
| 値の由来 | 取得困難 | `GetDetailsAsync` で**完全に追跡可能** |
| 既定値の扱い | 暗黙的 | **「未設定」と「既定値で存在」を区別** |
| ファイル保持 | コメント等消失 | **コメント・空白・形式を保持** |
| スキーマ移行 | 手動 | **属性ベースで自動変換** |

---

## 対象読者・トーン

- **読者**: .NET 開発者。設定管理に課題を感じている人
- **トーン**: 技術的で簡潔、誇張しない


---

# ===== opencode/nemotron-3.5-lightning-free =====

README.md を作成しました。context.md の内容を基に、Configlue の README 用日本語解説を以下の構成でまとめています。

1. **特徴** - ライブラリの概要と対象枠組み
2. **解決する課題** - 設定管理で直面する複数の要件
3. **基本アーキテクチャ** - 6つの概念(Resource→Codec→Source→Fragment→Options、Patch)
4. **主な機能** - 優先度マージ、読み取り専用ソース、プロジェクション/マウント、プリセット、スパース書き込み、編集セッション、マイグレーション、バックアップ、安全な書き込み、セクション、ZIP/HTTP/S3/Dapr、JSON Schema、Native AOT、リアクティブ/DI統合、プロファイル
5. **既知の制限** - アトミックでない書き込み、Source退役のスコープ、Source集合の固定
6. **パッケージ構成** - 主要パッケージの一覧
7. **Quick Start** - 公式コード例
8. **値の由来を調べる / スパース保存** - GetDetailsAsync と Unset() の使用法
9. **その他の API** - IReadOnlyOptions, SaveAsync, OpenEditSessionAsync など
10. **想定読者とトーン** - .NET開発者向けのトーン説明
11. **ライセンス** - Apache-2.0

ファイル: `C:\Users\arika\AppData\Local\Temp\opencode\configlue-readme-bench\README.md`



---

# ===== opencode/space-bunny-free =====

# Configlue

**Make easy configuration management.**

Configlue は .NET アプリケーションの設定管理（configuration management）を代行するライブラリです。
設定が散らばる複数の場所 ― グローバル設定、実行フォルダー、環境変数、コマンドライン、暗号化された資格情報、
甚至は社内ポリシー API ― を **1 つのモデルに結合（glue）** します。名前の由来は configuration + glue です。

- 対象: .NET 10 SDK 以降
- ライセンス: Apache-2.0
- 現状: 「アーキテクチャ上の土台」です。`Configuration.Writable` を完全に置き換えるものではありません

## インストール

```shell
dotnet add package Configlue
```

`Configlue` はユーザー向けのメタパッケージです（Core / DI / JSON provider / JSON Schema / HTTP resources /
common sources / environment source / generator analyzer を同梱。実装アセンブリ自体は持ちません）。
XML や YAML、リモートリソースなどが必要な場合は、該当する機能パッケージを追加してください。

## Why Configlue?

JSON ファイルを読み書きするだけなら数行で済みます。実際には次のような要件が積み重なります。

- 設定が複数箇所にある（グローバル設定、実行フォルダー、環境変数、コマンドライン引数、暗号化された資格情報、社内ポリシーや HTTP API などのリモート管理）
- 設定ファイルが書き換わったら再起動なしで反映したい（変更通知）
- 書き込み先を自動で選びたい。環境変数から読んだ値への書き込みはエラーにしたい
- 設定ファイルは人間が書く。コメントを消したくない、JSON Schema がほしい、壊れたファイルへの対処がほしい
- 既定値のままなら書き出したくない（ただしユーザーが明示した `null` は尊重する）
- 設定ファイルのバージョンアップ 때、旧形式から新形式へ自動変換したい
- バックアップと自動整理
- 書き込みの安全性: アトミック性（クラッシュしても壊れない）、他プロセスとの競合検出・自動マージ、自動リトライ

これらを自前実装するのは面倒です。Configlue はその共通部分をランタイムとジェネレーターに閉じ込めています。

## Quick Start

`example.cs` として保存し、.NET 10 以降で `dotnet run example.cs` を実行してください。

```csharp
#!/usr/bin/env dotnet
#:package Configlue@*

using Configlue;
using Configlue.Source.Presets;

// 1. 設定モデルを宣言する。ジェネレーターが Fragment / Patch のサポートを生成する。
[ConfiglueModel("SampleSetting", Version = 1)]
public partial class SampleSetting
{
    public string Name { get; set; } = "World";
    public int RunCount { get; set; }
    public bool DefaultValue { get; set; } = true;
}

// 2. プリセットの層を宣言する。ここで列挙したソースだけが有効になる。
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);

// 3. Options インスタンス経由で読み書きする。
var options = context.GetOptions<SampleSetting>();
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// スパース編集: 変更したフィールドだけが対象層に保存される。
await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue は変更していないので対象層には書き込まれない。
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

## アーキテクチャ

依存関係は直線的で、学習順も同じです。

```text
Resource (location) → Codec (conversion) → Source (contribution) → Fragment (diff) → Options (facade)
                                                        ↘ Patch (edit fragment)
```

| 概念 | 一言で | 例 |
| --- | --- | --- |
| Resource | バイトがどこにあるか | ファイル、ZIPエントリ、HTTP応答、メモリ |
| Codec | バイト↔値の変換 | JSON / XML / YAML の読み書き |
| Source | 論理的な寄与（どのフィールドをどの優先度で） | 「ユーザー設定ファイルの Server 部分」 |
| Fragment | 存在を記憶する差分 | 「Port だけ」を持つ状態 |
| Patch | 単一フィールドの編集 | 「Port を 9000 にする」 |
| Options | アプリが見るファサード | 読み・保存・監視・説明・診断 |

**読み込み**: 各 Source が Resource からバイトを取得し、Codec が Fragment に変換します。ランタイムは優先度順に
「存在する」フィールドだけを 1 つのモデルへ重ねます。

**書き込み**: 逆向きです。アプリは普通のモデル値を編集し、内部では変更が Fragment 差分になります。
`WriteRoute` / `WritePlan` が指す Source にだけ届き、無関係な Source は変更されません。

- Fragment は「メンバーが存在しない」と「null / 既定値で存在する」を区別します。層の合成で「未設定」が
  「既定値に設定」を上書きすることはありません。
- Patch は生成される `TModel.Patch`（単一フィールドの編集フラグメント）です。`Unset()` は書き込み先 Source の
  寄与だけを取り消し、下位優先度の値を再び見せます。
- `[ConfiglueMerge]` でメンバーごとのマージ挙動を変更できます（組み込み: `Append` / `Deep` / `Replace` /
  `SetUnion`、カスタム戦略も可）。コレクションの層合成と順序はこの指定で決まります。

## 主な機能

- **複数ソースの優先度マージ** — `Priority` が大きい Source が勝ちます。`GetDetailsAsync` で
  「どの値がどこ由来か」を検査できます。
- **読み取り専用ソース** — 環境変数・コマンドライン・既定の HTTP ソースは読み取り専用です。読み取り専用の値への
  書き込みは黙って無視されず、競合エラーになります。
- **プロジェクション / マウント** — 既存 Source を別モデルに整形（projection）したり、ネストしたパスに別の
  Source を接続（mount、`AddMounted`）できます。
- **プリセット** — `UseCommonSources` が global / local / environment などの標準的な層構成を組み立てます。
- **スパース書き込み** — 変更したフィールドだけを対象層に保存します。既定値のままのフィールドは書かれません。
- **編集セッション** — `OpenEditSessionAsync` で複数変更をまとめて適用し、`CommitAsync` までインメモリです。
  競合時は既定で失敗し、`WriteConflictResolution.LastWriteWins` も選べます。
- **スキーマ移行 / ストレージ移行** — `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` による
  旧バージョン設定の自動変換。既存ファイルを Source として登録できます。
- **バックアップと復元** — `FileResource` はアトミック書き込みとバックアップ世代管理を提供します。既定で `.bak`
  1 世代、`RestoreLatestBackupAsync` で復元します。
- **安全な書き込み** — アトミック性、競合検出、リトライ。
- **セクション** — `JsonSectionResource`、XML 要素、YAML マッピングで、ファイルの一部を独立した Resource として
  扱えます。書き込み時にコメント・空白・引用・スカラー形式を保持し、同じファイル内の独立セクションは 1 回の
  物理書き込みにバッチされます。
- **ZIP / HTTP / S3 / Dapr** — `ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込み・ポーリング）、
  `Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **JSON Schema 生成** — `Configlue.JsonSchema`。人間が設定ファイルを書くためのサポートです。
- **Native AOT 対応** — ソース生成の `JsonSerializerContext` を渡すとトリミング / AOT に強くなります。
- **リアクティブ統合（任意）** — `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と
  `Configlue.Extensions.R3`（R3 1.3.1）。`ObserveChanges()` / `ObserveValues()` / `ObserveReloadFailures()` /
  `ObserveActiveValues()` / `ObserveActiveProfileNames()` が使えます。
- **DI 統合** — `Configlue.Extensions.DI`。Microsoft の options アダプターが `Configlue.Extensions.MSOptions` です
  （`IOptions<T>` など）。同期ゲッターは非同期ソースの読み取り中にブロックするため、非同期フローでは
  `GetValueAsync` の利用を推奨します。
- **プロファイル / 動的オプション** — 名前付きオプションや永続プロファイルを、ランタイム単位で作成・削除できます。

## 値の由来を調べる / スパース保存

マージ後の値を取得するだけでなく、各フィールドがどのソース由来かを確認できます。

```csharp
var options = context.GetOptions<AppSettings>();

// 1. 現在の値（全ソースをマージしたもの）を取得
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 2. 各値がどこから来たかを調べる
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

指定したメンバーだけを更新するパッチを保存します。`Unset()` はその Source の寄与を外し、下位優先度の
Source が値を提供できるようにします。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

### その他の API

- `IReadOnlyOptions<T>` — 日常の読み取り面は `GetValueAsync` と `OnChange`。
- `SaveAsync(patch => ...)` — 生成 Patch によるスパース保存。
- `OpenEditSessionAsync()` — 変更をまとめて編集し、`CommitAsync` で確定。
- `ApplyPatchesAsync` + `StateSourcePatch` — 明示的なソース別マルチ書き込み。
- `StateWritePlan.For<T>().Route(...)` — 書き込みルーティング。
- `SourceKey<TModel>` と `options.Source(key)` — ソース単位の操作。

## Microsoft.Extensions.Configuration との違い

`IConfiguration` は読み取りを中心とした<Key,Value> ベースの抽象化です。対して Configlue は、
独立したソースの合成・値の来歴の検査・スパース保存を前提に設計されています。
どこから来たかを説明でき、書き込む先を安全に決められることが、Configlue を選ぶ理由になります。

## パッケージ構成

| パッケージ | 役割 |
| --- | --- |
| `Configlue` | ユーザー向けメタパッケージ |
| `Configlue.Abstraction` | 契約（provider / codec / resource / generated-model） |
| `Configlue.Core` | 解決と永続化のランタイム |
| `Configlue.Extensibility` | プロバイダー SDK |
| `Configlue.Extensions.DI` | 依存性注入への統合 |
| `Configlue.Extensions.MSOptions` | Microsoft options アダプター（`IOptions<T>` など） |
| `Configlue.Extensions.R3` | R3 連携 |
| `Configlue.Extensions.Reactive` | System.Reactive 連携 |
| `Configlue.Generator` | Roslyn アナライザー（スパースなモデルサポートの生成） |
| `Configlue.Testing` | インメモリのテストダブル |
| `Configlue.Provider.Json` / `.Xml` / `.Yaml` | 各形式の Codec・セクションリソース・ファイル登録 |
| `Configlue.JsonSchema` | JSON Schema の生成とエクスポート |
| `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml` | ソースの追加機能 |
| `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip` | リモートおよびアーカイブリソース |
| `Configlue.Transformer.AES` | Resource と Codec の間のバイトを AES-GCM で暗号化・認証 |

## 既知の制限

- 異なる Resource 間の書き込みはアトミックではありません。
- Source の退役は現在の options インスタンスに閉じるだけで、実データは残ります。
- Source 集合は options ランタイムで固定です。

## ビルドについて

リポジトリは preview 設定でビルドされます。ソースジェネレーター的支持が必要なため、`LangVersion` を
preview 相当に設定してください。



