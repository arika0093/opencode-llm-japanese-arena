# Configlue README 日本語 - 全モデル出力

---

# ===== opencode-go/deepseek-v4.1-flash =====

# Configlue

## 概要

Configlue は、アプリケーションの設定管理を代行する .NET ライブラリです。キャッチコピーは "Make easy configuration management."。複数の場所に散らばった設定を 1 つのモデルに**結合（glue）**することを中心的な考え方としており、名前も configuration + glue に由来します。

JSON ファイルの読み書きだけなら数行で済みますが、実際のアプリケーションでは次のような要件が積み重なります。

- 設定が複数箇所にある: グローバル設定、実行フォルダー設定、環境変数、コマンドライン引数、暗号化された資格情報、社内ポリシーや HTTP API などのリモート管理
- 設定ファイルが書き換わったら再起動なしで反映したい（変更通知）
- 書き込み先を自動で選びたい。環境変数から読んだ値への書き込みはエラーにしたい
- 設定ファイルは人間が書くため、コメントを消さない、JSON Schema がほしい、壊れたファイルへの対処が必要
- 既定値のままなら書き出さない（ただしユーザーが明示した `null` は尊重する）
- 設定ファイルのバージョンアップ（旧形式から新形式への自動変換）
- バックアップと自動整理
- 書き込みの安全性: アトミック性（クラッシュしても壊れない）、他プロセスとの競合検出・自動マージ、自動リトライ

これらを自前で実装するのは面倒、というのが Configlue の動機です。

対象は .NET 10 SDK 以降で、C# を使用します（`LangVersion` はソースジェネレーター対応が必要で、リポジトリは preview でビルドしています）。ライセンスは Apache-2.0。現状は「アーキテクチャ上の土台」であり、`Configuration.Writable` を完全に置き換えるものではありません。

### 基本アーキテクチャ

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

**読み込み**では、各 Source が Resource からバイトを取得し、Codec が Fragment に変換します。ランタイムが優先度順に「存在する」フィールドだけを 1 つのモデルへ重ねます。

**書き込み**は逆向きです。アプリは普通のモデル値を編集します。内部では変更が Fragment 差分になり、`WriteRoute` / `WritePlan` が指す Source にだけ届きます。無関係な Source は変更されません。

- Fragment は「メンバーが存在しない」と「null / 既定値で存在する」を区別します。層の合成で「未設定」が「既定値に設定」を上書きすることはありません。
- Patch は生成される `TModel.Patch`（単一フィールドの編集フラグメント）です。`Unset()` は書き込み先 Source の寄与だけを取り消し、下位優先度の値を再び見せます。
- `[ConfiglueMerge]` でメンバーごとのマージ挙動を変更できます（組み込み: `Append`, `Deep`, `Replace`, `SetUnion`、カスタム戦略も可）。コレクションの層合成・順序はここで決まります。

## 主な特徴

- **複数ソースの優先度マージ**: `Priority` が大きい Source が勝ちます。`GetDetailsAsync` で「どの値がどこ由来か」を検査できます。
- **読み取り専用ソース**: 環境変数・コマンドライン・既定の HTTP ソースは読み取り専用です。読み取り専用の値への書き込みは黙って無視せず競合エラーになります。
- **プロジェクション / マウント**: 既存 Source を別モデルに整形（projection）したり、ネストしたパスに別 Source を接続（mount, `AddMounted`）できます。
- **プリセット**: `UseCommonSources` が標準的な層構成（global / local / environment など）を組み立てます。
- **スパース書き込み**: 変更したフィールドだけを対象層に保存します。既定値のままのフィールドは書かれません。
- **編集セッション**: `OpenEditSessionAsync` で複数の変更をまとめて適用できます。`CommitAsync` までインメモリで、競合時は既定で失敗し、`WriteConflictResolution.LastWriteWins` も選べます。
- **スキーマ移行 / ストレージ移行**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` による旧バージョン設定の自動変換。既存ファイルを Source として登録できます。
- **バックアップと復元**: `FileResource` はアトミック書き込みとバックアップ世代管理を行います。既定で `.bak` 1 世代、`RestoreLatestBackupAsync` で復元できます。
- **安全な書き込み**: アトミック性、競合検出、リトライを備えます。
- **セクション**: `JsonSectionResource` / XML 要素 / YAML マッピングで、ファイルの一部を独立した Resource として扱えます。書き込み時はコメント・空白・引用・スカラー形式を保持し、同じファイル内の独立セクションは 1 回の物理書き込みにバッチされます。
- **ZIP / HTTP / S3 / Dapr**: `ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込み・ポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **JSON Schema 生成**: `Configlue.JsonSchema`。人間が設定を書くために利用します。
- **Native AOT 対応**: ソース生成の `JsonSerializerContext` を渡すとトリミング / AOT に強くなります。
- **リアクティブ統合（任意）**: `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）。`ObserveChanges()`, `ObserveValues()`, `ObserveReloadFailures()`, `ObserveActiveValues()`, `ObserveActiveProfileNames()` を提供します。
- **DI 統合**: `Configlue.Extensions.DI`。Microsoft の options アダプター `Configlue.Extensions.MSOptions`（`IOptions<T>` など。同期ゲッターは非同期ソース読み取り中ブロックするため、非同期フローでは `GetValueAsync` 推奨）。
- **プロファイル / 動的オプション**: 名前付きオプションや永続プロファイルで、ランタイムを単位に作成・削除できます。
- **既知の制限**: 異なる Resource 間の書き込みはアトミックではありません。Source の退役は現在の options インスタンスに閉じ、実データは残ります。Source 集合は options ランタイムで固定です。

### パッケージ構成（主要なもの）

- `Configlue` … ユーザー向けメタパッケージ（Core / DI / JSON provider / JSON Schema / HTTP resources / common sources / environment source / generator analyzer を同梱。実装アセンブリは持ちません）。
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

インストールは `dotnet add package Configlue` から始め、必要な機能パッケージを追加します。

## 基本的な使い方

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

### 値の由来を調べる

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

### スパース保存

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

既存の `Microsoft.Extensions.Configuration` との違いとして、`IConfiguration` は読み取り中心である一方、Configlue は独立した Source の合成・来歴の検査・スパース保存に向いています。

---

# ===== opencode-go/glm-5.3 =====

# Configlue

Make easy configuration management.

## 概要

Configlue は、アプリケーションの設定管理（configuration management）を代行する .NET ライブラリです。グローバル設定、実行フォルダーの設定、環境変数、コマンドライン引数、暗号化された資格情報、社内ポリシーや HTTP API によるリモート管理など、複数の場所に散らばった設定を 1 つのモデルへ結合（glue）します。ライブラリ名も configuration + glue に由来します。

JSON ファイルの読み書きだけなら数行で済みますが、実際の設定管理には次のような要件が積み重なります。

- 設定が複数箇所にある
- 設定ファイルが書き換わったら再起動なしで反映したい（変更通知）
- 書き込み先を自動で選びたい。環境変数から読んだ値への書き込みはエラーにしたい
- 設定ファイルは人間が書くもの。コメントを消さない、JSON Schema がほしい、壊れたファイルへの対処
- 既定値のままなら書き出さない（ただしユーザーが明示した `null` は尊重する）
- 設定ファイルのバージョンアップ（旧形式から新形式への自動変換）
- バックアップと自動整理
- 書き込みの安全性: アトミック性（クラッシュしても壊れない）、他プロセスとの競合検出・自動マージ、自動リトライ

これらを自前で実装するのは面倒です。Configlue は、この部分を引き受ける土台を提供します。

`Microsoft.Extensions.Configuration` の `IConfiguration` が読み取り中心の API であるのに対し、Configlue は独立したソースの合成、値の来歴の検査、スパースな保存（変更したフィールドだけを書き込む）に向いています。なお現状はアーキテクチャ上の土台であり、`Configuration.Writable` を完全に置き換えるものではありません。

- 対象: .NET 10 SDK 以降
- ライセンス: Apache-2.0

## 主な特徴

### アーキテクチャ

内部は 6 つの概念で構成され、依存関係は直線的で、学習順も同じです。

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

- **読み込み**: 各 Source が Resource からバイトを取得し、Codec が Fragment に変換します。ランタイムが優先度順に「存在する」フィールドだけを 1 つのモデルへ重ね合わせます。
- **書き込み**: 逆向きです。アプリは普通のモデル値を編集します。内部では変更が Fragment 差分になり、`WriteRoute` / `WritePlan` が指す Source にだけ届きます。無関係な Source は変更されません。
- Fragment は「メンバーが存在しない」と「null/既定値で存在する」を区別します。層の合成で「未設定」が「既定値に設定」を上書きすることはありません。
- Patch の `Unset()` は、書き込み先 Source の寄与だけを取り消し、下位優先度の Source が再び値を提供できるようにします。
- `[ConfiglueMerge]` でメンバーごとのマージ挙動を変更できます（組み込み: `Append`, `Deep`, `Replace`, `SetUnion`。カスタム戦略も可）。コレクションの層合成・順序はここで決まります。

### 機能一覧

- **複数ソースの優先度マージ**: `Priority` が大きい Source が勝ちます。`GetDetailsAsync` で「どの値がどこ由来か」を検査できます。
- **読み取り専用ソース**: 環境変数・コマンドライン・既定の HTTP ソースは読み取り専用です。読み取り専用の値への書き込みは黙って無視せず競合エラーになります。
- **プリセット**: `UseCommonSources` が標準的な層構成（global/local/environment など）を組み立てます。
- **スパース書き込み**: 変更したフィールドだけを対象層に保存します。既定値のままのフィールドは書かれません。
- **編集セッション**: `OpenEditSessionAsync` で複数変更をまとめて適用できます。`CommitAsync` まではインメモリです。競合時は既定で失敗し、`WriteConflictResolution.LastWriteWins` も選べます。
- **プロジェクション / マウント**: 既存 Source を別モデルに整形（projection）したり、ネストしたパスに別 Source を接続（mount, `AddMounted`）できます。
- **スキーマ移行 / ストレージ移行**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` により、旧バージョン設定を新形式へ自動変換できます。既存ファイルを Source として登録できます。
- **バックアップと復元**: `FileResource` はアトミック書き込みとバックアップ世代管理（既定で `.bak` 1 世代）を行い、`RestoreLatestBackupAsync` で復元できます。
- **安全な書き込み**: アトミック性、競合検出、リトライ。
- **セクション**: `JsonSectionResource` / XML 要素 / YAML マッピングで、ファイルの一部を独立した Resource として扱えます。書き込み時はコメント・空白・引用・スカラー形式を保持します。同じファイル内の独立セクションは 1 回の物理書き込みにバッチされます。
- **さまざまな Resource**: `ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込み・ポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **JSON Schema 生成**: `Configlue.JsonSchema` で、人間が設定を書くためのスキーマを生成・エクスポートできます。
- **Native AOT 対応**: ソース生成の `JsonSerializerContext` を渡すと、トリミング/AOT に強くなります。
- **リアクティブ統合（任意）**: `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）。`ObserveChanges()`, `ObserveValues()`, `ObserveReloadFailures()`, `ObserveActiveValues()`, `ObserveActiveProfileNames()` が使えます。
- **DI 統合**: `Configlue.Extensions.DI`。Microsoft の options アダプター `Configlue.Extensions.MSOptions`（`IOptions<T>` など）も利用できます。同期ゲッターは非同期ソース読み取り中ブロックするため、非同期フローでは `GetValueAsync` を推奨します。
- **プロファイル / 動的オプション**: 名前付きオプションや永続プロファイルを、ランタイム単位で作成・削除できます。

### 既知の制限

- 異なる Resource 間の書き込みはアトミックではありません。
- Source の退役は現在の options インスタンスに閉じ、実データは残ります。
- Source 集合は options ランタイムで固定されます。

## 基本的な使い方

### インストール

```
dotnet add package Configlue
```

`Configlue` はユーザー向けメタパッケージで、Core / DI / JSON provider / JSON Schema / HTTP resources / common sources / environment source / generator analyzer を同梱します（実装アセンブリは持ちません）。必要に応じて、次のような機能パッケージを追加します。

| パッケージ | 内容 |
| --- | --- |
| `Configlue.Abstraction` | 契約（provider/codec/resource/generated-model） |
| `Configlue.Core` | 解決と永続化のランタイム |
| `Configlue.Extensibility` | プロバイダー SDK |
| `Configlue.Generator` | Roslyn アナライザー（スパースなモデルサポート生成） |
| `Configlue.Testing` | インメモリのテストダブル |
| `Configlue.Provider.Json` / `.Xml` / `.Yaml` | 各形式の Codec・セクションリソース・ファイル登録 |
| `Configlue.JsonSchema` | JSON Schema 生成・エクスポート |
| `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml` | 環境変数・コマンドライン・プリセットソース |
| `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip` | HTTP / Dapr / S3 / ZIP リソース |
| `Configlue.Extensions.DI` / `.MSOptions` / `.R3` / `.Reactive` | DI・Microsoft options・リアクティブ統合 |
| `Configlue.Transformer.AES` | Resource と Codec の間のバイトを AES-GCM で暗号化・認証 |

### クイックスタート

次のコードを `example.cs` に保存し、`dotnet run example.cs` で実行できます（.NET 10 以降）。

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

### 値の由来を調べる

`GetDetailsAsync` で、各値がどこから来たか、書き込み可能かを調べられます。

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

### スパース保存と Unset

指定したメンバーだけを更新するパッチを保存できます。`Unset()` はその Source の寄与を外し、下位優先度の Source が値を提供できるようにします。

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

# ===== opencode-go/glm-5.3-flash =====

# Configlue

**Make easy configuration management.**

Configlue は、アプリケーションの設定管理（configuration management）を代行する .NET ライブラリです。複数の場所に散らばった設定を 1 つのモデルに**結合（glue）**するのが中心的な考え方で、名前も configuration + glue に由来します。

## 概要

JSON ファイルの読み書きだけなら数行で済みます。しかし実際のアプリケーションでは、次のような要件が積み重なります:

- 設定が複数箇所にある: グローバル設定、実行フォルダー設定、環境変数、コマンドライン引数、暗号化された資格情報、社内ポリシーや HTTP API などのリモート管理。
- 設定ファイルが書き換わったら、再起動なしで反映したい（変更通知）。
- 書き込み先を自動で選びたい。環境変数から読んだ値への書き込みはエラーにしたい。
- 設定ファイルは人間が書く: コメントを消さない、JSON Schema がほしい、壊れたファイルへの対処。
- 既定値のままなら書き出さない（ただしユーザーが明示した `null` は尊重する）。
- 設定ファイルのバージョンアップ（旧形式→新形式への自動変換）。
- バックアップと自動整理。
- 書き込みの安全性: アトミック性（クラッシュしても壊れない）、他プロセスとの競合検出・自動マージ、自動リトライ。

これらを自前実装するのは面倒です。Configlue はこの一連の課題を引き受けます。既存の `Microsoft.Extensions.Configuration` との違いを一言でいえば、`IConfiguration` が読み取り中心であるのに対し、Configlue は独立したソースの合成、値の来歴の検査、スパース保存に向いています。

対象は .NET 10 SDK 以降の C# です（`LangVersion` はソースジェネレーター対応が必要で、リポジトリは preview でビルドされています）。ライセンスは Apache-2.0。Configlue は現状「アーキテクチャ上の土台」であり、`Configuration.Writable` を完全に置き換えるものではありません。

### 基本アーキテクチャ

内部構成の基本は 6 つの概念で、依存関係は直線的です。学習する順番も同じです:

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

**読み込み**では、各 Source が Resource からバイトを取得し、Codec が Fragment に変換します。ランタイムは優先度順に「存在する」フィールドだけを 1 つのモデルへ重ねます。

**書き込み**はこの逆です。アプリは普通のモデル値を編集するだけ。内部では変更が Fragment 差分になり、`WriteRoute` / `WritePlan` が指す Source にだけ届きます。無関係な Source は変更されません。

この層構造を支える仕組み:

- Fragment は「メンバーが存在しない」ことと「null / 既定値で存在する」ことを区別します。層を合成しても、「未設定」が「既定値に設定」を上書きすることはありません。
- Patch は生成される `TModel.Patch`（単一フィールドの編集フラグメント）です。`Unset()` を呼ぶと書き込み先 Source の寄与だけが取り消され、下位優先度の値が再び見えるようになります。
- `[ConfiglueMerge]` でメンバーごとのマージ挙動を変更できます（組み込み: `Append` / `Deep` / `Replace` / `SetUnion`、カスタム戦略も可）。コレクションの層合成・順序はここで決まります。

## 主な特徴

- **複数ソースの優先度マージ** — `Priority` が大きい Source が勝ちます。`GetDetailsAsync` で「どの値がどこ由来か」を検査できます。
- **読み取り専用ソース** — 環境変数・コマンドライン・既定の HTTP ソースは読み取り専用です。読み取り専用の値への書き込みは黙って無視されず、競合エラーになります。
- **プロジェクション / マウント** — 既存 Source を別モデルに整形（projection）したり、ネストしたパスに別 Source を接続（mount、`AddMounted`）できます。
- **プリセット** — `UseCommonSources` が標準的な層構成（global / local / environment など）を組み立てます。
- **スパース書き込み** — 変更したフィールドだけを対象層に保存します。既定値のままのフィールドは書かれません。
- **編集セッション** — `OpenEditSessionAsync` で複数の変更をまとめて適用し、`CommitAsync` まではインメモリです。競合時は既定で失敗します（`WriteConflictResolution.LastWriteWins` も選択できます）。
- **スキーマ移行 / ストレージ移行** — `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` による旧バージョン設定の自動変換。既存ファイルを Source として登録することもできます。
- **バックアップと復元** — `FileResource` はアトミック書き込みとバックアップ世代管理を行います。既定で `.bak` 1 世代を保持し、`RestoreLatestBackupAsync` で復元できます。
- **安全な書き込み** — アトミック性、競合検出、リトライ。
- **セクション** — `JsonSectionResource` / XML 要素 / YAML マッピングで、ファイルの一部を独立した Resource として扱えます。書き込み時はコメント・空白・引用・スカラー形式を保持し、同じファイル内の独立セクションは 1 回の物理書き込みにバッチされます。
- **ZIP / HTTP / S3 / Dapr** — `ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込み・ポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **JSON Schema 生成** — `Configlue.JsonSchema` による生成・エクスポート。人間が設定を書くためのスキーマです。
- **Native AOT 対応** — ソース生成の `JsonSerializerContext` を渡すと、トリミング / Native AOT に強くなります。
- **リアクティブ統合（任意）** — `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）。`ObserveChanges()`、`ObserveValues()`、`ObserveReloadFailures()`、`ObserveActiveValues()`、`ObserveActiveProfileNames()` を提供します。
- **DI 統合** — `Configlue.Extensions.DI`。Microsoft の options アダプター `Configlue.Extensions.MSOptions`（`IOptions<T>` など）は、同期ゲッターが非同期ソース読み取り中にブロックするため、非同期フローでは `GetValueAsync` の利用を推奨します。
- **プロファイル / 動的オプション** — 名前付きオプションや永続プロファイルを、ランタイムを単位に作成・削除できます。
- **既知の制限** — 異なる Resource 間の書き込みはアトミックではありません。Source の退役は現在の options インスタンスに閉じており、実データは残ります。Source 集合は options ランタイムで固定です。

## 基本的な使い方

### インストール

まずメタパッケージを追加します:

```sh
dotnet add package Configlue
```

必要な機能に応じて、個別のパッケージを追加します。主なパッケージ:

| パッケージ | 内容 |
| --- | --- |
| `Configlue` | ユーザー向けメタパッケージ（Core / DI / JSON provider / JSON Schema / HTTP resources / common sources / environment source / generator analyzer を同梱。実装アセンブリは持たない） |
| `Configlue.Abstraction` | 契約（provider / codec / resource / generated-model） |
| `Configlue.Core` | 解決と永続化のランタイム |
| `Configlue.Extensibility` | プロバイダー SDK |
| `Configlue.Extensions.DI` / `.MSOptions` / `.R3` / `.Reactive` | DI 統合、Microsoft の options アダプター、R3 / System.Reactive 統合 |
| `Configlue.Generator` | Roslyn アナライザー（スパースなモデルサポート生成） |
| `Configlue.Testing` | インメモリのテストダブル |
| `Configlue.Provider.Json` / `.Xml` / `.Yaml` | 各形式の Codec・セクションリソース・ファイル登録 |
| `Configlue.JsonSchema` | JSON Schema 生成・エクスポート |
| `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml` | 環境変数・コマンドラインソースと `UseCommonSources` のプリセット |
| `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip` | HTTP / Dapr / S3 / ZIP エントリの Resource |
| `Configlue.Transformer.AES` | Resource と Codec の間のバイトを AES-GCM で暗号化・認証 |

### Quick Start

次のコードを `example.cs` に保存して `dotnet run example.cs` で実行します（.NET 10 以降）:

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

やっていることは次のとおりです:

1. `[ConfiglueModel]` を付けた `partial` クラスとして設定モデルを宣言します。ジェネレーターが Fragment / Patch サポートを生成します。
2. `ConfiglueApp.CreateContext` と `UseCommonSources` でプリセットの層構成を宣言します。ここに列挙した Source だけが有効になります。この例では global / local / environment の層を構成しています。
3. `GetOptions<T>()` で取得した options インスタンスを通じて読み書きします。`SaveAsync` のパッチ編集はスパースに動作し、未変更の `DefaultValue` は対象層に保存されません。

### 値の由来を調べる

各値がどの Source 由来か、書き込み可能かを調べるには `GetDetailsAsync` を使います:

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

### スパース保存と Unset()

パッチは指定したメンバーだけを更新して保存します。`Unset()` を呼ぶとその Source の寄与が外され、下位優先度の Source が値を提供できるようになります:

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

### その他の API

- `IReadOnlyOptions<T>` — 日常の読み取り面は `GetValueAsync` と `OnChange`。
- `options.SaveAsync(patch => ...)` — 生成された Patch によるスパース保存。
- `options.OpenEditSessionAsync()` — 複数の変更をまとめて編集し、`CommitAsync` で適用。
- `options.ApplyPatchesAsync` + `StateSourcePatch` — ソースを明示した複数 Source への書き込み。
- `StateWritePlan.For<T>().Route(...)` — 書き込みルーティング。
- `SourceKey<TModel>` と `options.Source(key)` — ソース単位の操作。

---

# ===== opencode-go/gpt-6-luna =====

# 概要

Configlue は、複数の場所に分散した設定をひとつのモデルに結合する .NET ライブラリです。名前は *configuration* と *glue* に由来し、「Make easy configuration management.」を掲げています。

グローバル設定やローカルファイル、環境変数、コマンドライン引数などを組み合わせ、設定の読み込み、変更、保存、監視を扱います。`Microsoft.Extensions.Configuration` が読み取り中心なのに対し、Configlue は独立したソースの合成、値の由来の確認、変更したフィールドだけの保存に向いています。

対象は .NET 10 SDK 以降で、ライセンスは Apache-2.0 です。現状はアーキテクチャ上の土台であり、`Configuration.Writable` を完全に置き換えるものではありません。

# 主な特徴

- **複数ソースの優先度マージ**: 優先度の高い Source の値を採用します。`GetDetailsAsync` で、値の由来や書き込み可否を確認できます。
- **スパースな読み書き**: Fragment は、メンバーが存在しない状態と、`null` や既定値で存在する状態を区別します。変更したフィールドだけを保存でき、`Unset()` で書き込み先 Source の寄与を外すと、下位の Source の値が再び見えるようになります。
- **柔軟なマージ**: `[ConfiglueMerge]` でメンバーごとのマージ方法を指定できます。組み込み戦略は `Append`、`Deep`、`Replace`、`SetUnion` で、カスタム戦略も利用できます。
- **Source に応じた書き込み**: 環境変数やコマンドラインなどの読み取り専用 Source への書き込みは、黙って無視されず競合エラーになります。書き込み先は `WriteRoute` / `WritePlan` で指定できます。
- **編集セッションと競合解決**: `OpenEditSessionAsync` で変更をまとめ、`CommitAsync` までインメモリで編集できます。競合時は既定で失敗し、`WriteConflictResolution.LastWriteWins` も選択できます。
- **設定ファイルの扱い**: `FileResource` はアトミック書き込みとバックアップ世代管理に対応し、既定では `.bak` を1世代保持します。JSON/XML/YAML のセクションを独立した Resource として扱う場合は、書き込み時にコメントや空白などの形式を保持できます。
- **拡張可能な構成**: プロジェクションやマウントで Source を別モデルやネストしたパスに接続できます。`UseCommonSources` では global/local/environment などの標準的な層を組み立てられます。
- **各種統合**: JSON Schema 生成、Native AOT を考慮したソース生成の `JsonSerializerContext`、DI や Microsoft options との統合、任意の Reactive / R3 統合を利用できます。Resource にはファイル、ZIP、HTTP、S3、Dapr などがあります。
- **制限事項**: 異なる Resource 間の書き込みはアトミックではありません。Source の集合は options ランタイムごとに固定されます。

インストールは次のコマンドから始められます。必要に応じて機能パッケージを追加してください。

```sh
dotnet add package Configlue
```

# 基本的な使い方

次の例は、設定モデルを宣言し、共通ソースのプリセットを構成して、値を読み書きする方法です。`.NET 10` 以降で `example.cs` に保存し、`dotnet run example.cs` で実行できます。

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

`GetDetailsAsync` を使うと、値がどの Source から提供されたか、編集可能かを調べられます。生成された Patch で指定したメンバーだけを更新でき、`Unset()` はその Source の寄与を外します。

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

await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

---

# ===== opencode-go/grok-4.7 =====

## 概要

Configlue は、アプリケーションの設定管理を担う .NET ライブラリです。キャッチコピーは "Make easy configuration management." です。

中心にあるのは、複数の場所に散らばった設定を 1 つのモデルへ結合（glue）するという考え方です。名前も configuration と glue を合わせたものです。

対象は .NET 10 SDK 以降です。言語は C# で、ソースジェネレーターが使える `LangVersion` が必要です。リポジトリは preview でビルドしています。ライセンスは Apache-2.0 です。

現状はアーキテクチャ上の土台であり、`Configuration.Writable` を完全に置き換えるものではありません。

`Microsoft.Extensions.Configuration` の `IConfiguration` は、読み取りが中心です。Configlue は、独立したソースの合成、値の来歴の検査、スパースな保存に向いています。

JSON ファイルの読み書きだけなら、数行で足ります。実際の設定管理では、次のような要件が積み重なります。

- 設定が複数箇所にある。グローバル設定、実行フォルダーの設定、環境変数、コマンドライン引数、暗号化された資格情報、社内ポリシーや HTTP API などのリモート管理。
- 設定ファイルが書き換わったら、再起動なしで反映したい（変更通知）。
- 書き込み先を自動で選びたい。環境変数から読んだ値への書き込みは、エラーにしたい。
- 設定ファイルは人間が書く。コメントを消さない、JSON Schema がほしい、壊れたファイルに対処する。
- 既定値のままなら書き出さない。ただし、ユーザーが明示した `null` は尊重する。
- 設定ファイルのバージョンアップ。旧形式から新形式へ自動変換する。
- バックアップと、その自動整理。
- 書き込みの安全性。アトミック性（クラッシュしても壊れない）、他プロセスとの競合検出と自動マージ、自動リトライ。

これらを自前で実装するのは面倒です。それが Configlue の動機です。

## 主な特徴

依存関係は直線的で、学習する順序も同じです。

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

**読み込み**では、各 Source が Resource からバイトを取得し、Codec がそれを Fragment に変換します。ランタイムは優先度順に、「存在する」フィールドだけを 1 つのモデルへ重ねます。

**書き込み**は逆向きです。アプリは普通のモデル値を編集します。内部では変更が Fragment の差分になり、`WriteRoute` / `WritePlan` が指す Source にだけ届きます。無関係な Source は変更されません。

Fragment は、「メンバーが存在しない」ことと、「null や既定値として存在する」ことを区別します。層を合成するとき、「未設定」が「既定値に設定されている」状態を上書きすることはありません。

Patch は、生成される `TModel.Patch` です。単一フィールドを編集するフラグメントで、`Unset()` は書き込み先 Source の寄与だけを取り消します。取り消すと、より優先度の低い値が再び見えるようになります。

`[ConfiglueMerge]` で、メンバーごとのマージ挙動を変えられます。組み込みの戦略は `Append`、`Deep`、`Replace`、`SetUnion` です。カスタム戦略も使えます。コレクションを層としてどう合成し、どの順序にするかは、ここで決まります。

**複数ソースの優先度マージ。** `Priority` が大きい Source が勝ちます。`GetDetailsAsync` で、どの値がどこから来たかを検査できます。

**読み取り専用ソース。** 環境変数、コマンドライン、既定の HTTP ソースは読み取り専用です。読み取り専用の値へ書き込もうとすると、黙って無視せず、競合エラーになります。

**プロジェクションとマウント。** 既存の Source を別のモデルへ整形できます（projection）。ネストしたパスへ、別の Source を接続することもできます（mount、`AddMounted`）。

**プリセット。** `UseCommonSources` が、global / local / environment などの標準的な層を組み立てます。ここで挙げたソースだけが有効になります。

**スパース書き込み。** 変更したフィールドだけを、対象の層へ保存します。既定値のままのフィールドは書かれません。

**編集セッション。** `OpenEditSessionAsync` で、複数の変更をまとめて適用できます。`CommitAsync` まではインメモリです。競合したときは、既定では失敗します。`WriteConflictResolution.LastWriteWins` も選べます。

**スキーマ移行とストレージ移行。** `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` により、旧バージョンの設定を自動変換します。既存のファイルを Source として登録できます。

**バックアップと復元。** `FileResource` は、アトミックな書き込みとバックアップの世代管理を行います。既定では `.bak` を 1 世代残し、`RestoreLatestBackupAsync` で復元できます。

**安全な書き込み。** アトミック性、競合検出、リトライに対応します。

**セクション。** `JsonSectionResource`、XML 要素、YAML マッピングにより、ファイルの一部を独立した Resource として扱えます。書き込み時は、コメント、空白、引用、スカラー形式を保持します。同じファイル内の独立したセクションは、1 回の物理書き込みにまとめられます。

**ZIP / HTTP / S3 / Dapr。** `ZipEntryResource`、`Configlue.Resource.Http`（ETag による条件付き書き込みとポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr` があります。

**JSON Schema。** `Configlue.JsonSchema` がスキーマを生成・エクスポートします。人間が設定を書くためのものです。

**Native AOT。** ソース生成した `JsonSerializerContext` を渡すと、トリミングと AOT に強くなります。

**リアクティブ統合（任意）。** `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）があります。`ObserveChanges()`、`ObserveValues()`、`ObserveReloadFailures()`、`ObserveActiveValues()`、`ObserveActiveProfileNames()` を使えます。

**DI 統合。** `Configlue.Extensions.DI` があります。Microsoft の options へのアダプターは `Configlue.Extensions.MSOptions` です（`IOptions<T>` など）。同期のゲッターは、非同期ソースの読み取り中にブロックします。非同期の流れでは `GetValueAsync` を使ってください。

**プロファイルと動的オプション。** 名前付きオプションや永続プロファイルにより、ランタイムを単位として作成・削除できます。

**既知の制限。**

- 異なる Resource のあいだの書き込みは、アトミックではありません。
- Source の退役は、現在の options インスタンスに閉じます。実データは残ります。
- Source の集合は、options のランタイムで固定です。

**パッケージ。** インストールは `dotnet add package Configlue` から始め、必要な機能のパッケージを追加します。

- `Configlue` は、ユーザー向けのメタパッケージです。Core、DI、JSON provider、JSON Schema、HTTP resources、common sources、environment source、generator analyzer を同梱します。実装アセンブリは持ちません。
- `Configlue.Abstraction` は契約です（provider、codec、resource、generated-model）。
- `Configlue.Core` は、解決と永続化のランタイムです。
- `Configlue.Extensibility` は、プロバイダー SDK です。
- `Configlue.Extensions.DI`、`Configlue.Extensions.MSOptions`、`Configlue.Extensions.R3`、`Configlue.Extensions.Reactive`
- `Configlue.Generator` は Roslyn アナライザーで、スパースなモデルサポートを生成します。
- `Configlue.Testing` は、インメモリのテストダブルです。
- `Configlue.Provider.Json`、`.Xml`、`.Yaml` は、各形式の Codec、セクションリソース、ファイル登録です。
- `Configlue.JsonSchema` は、JSON Schema の生成とエクスポートです。
- `Configlue.Source.Environment`、`.CommandLine`、`.Presets`、`.Presets.Yaml`、`.Presets.Xml`
- `Configlue.Resource.Http`、`.Http.AspNetCore`、`.Dapr`、`.S3`、`.Zip`
- `Configlue.Transformer.AES` は、Resource と Codec のあいだのバイトを AES-GCM で暗号化し、認証します。

## 基本的な使い方

次のコードを `example.cs` に保存し、.NET 10 以降で `dotnet run example.cs` を実行します。モデルに `[ConfiglueModel]` を付けると、ジェネレーターが Fragment と Patch のサポートを生成します。`UseCommonSources` では、ここに挙げた層だけが有効になります。`SaveAsync` はスパースな編集で、変更したフィールドだけを対象の層へ保存します。

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

値の由来は、`GetDetailsAsync` で調べられます。どの Source から来たか、書き込めるか、各寄与の状態を確認できます。

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

指定したメンバーだけを更新するパッチも保存できます。`Unset()` は、その Source の寄与を外し、より優先度の低い Source が値を出せるようにします。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

このほかに、次の API があります。

- `IReadOnlyOptions<T>` の日常的な読み取り面は、`GetValueAsync` と `OnChange` です。
- `SaveAsync(patch => ...)` は、生成された Patch によるスパース保存です。
- `OpenEditSessionAsync()` は、変更をまとめて編集し、`CommitAsync` で確定します。
- `ApplyPatchesAsync` と `StateSourcePatch` は、ソースを明示した複数箇所への書き込みです。
- `StateWritePlan.For<T>().Route(...)` は、書き込みのルーティングです。
- `SourceKey<TModel>` と `options.Source(key)` は、ソース単位の操作です。

---

# ===== opencode-go/hy4-preview =====

# Configlue

## 概要

Configlue は、アプリケーションの設定管理（configuration management）を代行する .NET ライブラリです。キャッチコピーは "Make easy configuration management."。複数の場所に散らばった設定を 1 つのモデルに結合（glue）するのが中心的な考え方で、名前も configuration + glue に由来します。

対象は .NET 10 SDK 以降（C#）。`LangVersion` はソースジェネレーターに対応した設定が必要で、リポジトリは preview でビルドされています。ライセンスは Apache-2.0 です。なお現時点では「アーキテクチャ上の土台」であり、`Configuration.Writable` を完全に置き換えるものではありません。

### なぜ Configlue なのか

JSON ファイルを読み書きするだけなら数行で済みます。しかし実際のアプリケーションでは、次のような要件が積み重なります。

- 設定が複数箇所にある（グローバル設定、実行フォルダーの設定、環境変数、コマンドライン引数、暗号化された資格情報、社内ポリシーや HTTP API などのリモート管理）
- 設定ファイルが書き換わったら、再起動なしで反映したい（変更通知）
- 書き込み先を自動で選びたい。環境変数から読んだ値への書き込みはエラーにしたい
- 設定ファイルは人間が書く（コメントを消さない、JSON Schema がほしい、壊れたファイルへの対処）
- 既定値のままなら書き出さない（ただしユーザーが明示した `null` は尊重する）
- 設定ファイルのバージョンアップ（旧形式から新形式への自動変換）
- バックアップと自動整理
- 書き込みの安全性（アトミック性、他プロセスとの競合検出・自動マージ、自動リトライ）

これらを自前で実装するのは面倒です。その手間を引き受けるのが Configlue の役割です。

### 基本アーキテクチャ

Configlue は 6 つの概念から成り、依存関係は直線的で、学習順も同じです。

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

**読み込み**では、各 Source が Resource からバイトを取得し、Codec がそれを Fragment に変換します。ランタイムは優先度順に「存在する」フィールドだけを 1 つのモデルへ重ねていきます。

**書き込み**は逆向きです。アプリケーションは普通のモデル値を編集します。内部では変更が Fragment の差分になり、`WriteRoute` / `WritePlan` が指す Source にだけ届きます。無関係な Source は変更されません。

- Fragment は「メンバーが存在しない」ことと「null または既定値で存在する」ことを区別します。そのため層の合成で「未設定」が「既定値に設定」を上書きしてしまうことはありません。
- Patch は生成される `TModel.Patch`（単一フィールドの編集フラグメント）です。`Unset()` は書き込み先 Source の寄与だけを取り消し、下位優先度の値をもう一度見せます。
- `[ConfiglueMerge]` でメンバーごとのマージ挙動を変更できます（組み込みは `Append`、`Deep`、`Replace`、`SetUnion`。カスタム戦略も可能）。コレクションの層合成と順序はここで決まります。

`Microsoft.Extensions.Configuration` の `IConfiguration` は読み取りが中心です。Configlue は、独立したソースの合成、値の来歴（provenance）の検査、そしてスパース保存に向いています。

## 主な特徴

**複数ソースの合成**

- **優先度マージ**: `Priority` が大きい Source が勝ちます。`GetDetailsAsync` で「どの値がどこ由来か」を検査できます。
- **読み取り専用ソース**: 環境変数、コマンドライン、既定の HTTP ソースは読み取り専用です。読み取り専用の値への書き込みは黙って無視されず、競合エラーになります。
- **プロジェクション / マウント**: 既存の Source を別モデルに整形（projection）したり、ネストしたパスに別の Source を接続（mount、`AddMounted`）できます。
- **プリセット**: `UseCommonSources` が標準的な層構成（global / local / environment など）を組み立てます。

**書き込み**

- **スパース書き込み**: 変更したフィールドだけを対象の層に保存します。既定値のままのフィールドは書き出されません。
- **編集セッション**: `OpenEditSessionAsync` で複数の変更をまとめて適用できます。`CommitAsync` まではインメモリです。競合時は既定で失敗し、`WriteConflictResolution.LastWriteWins` も選べます。
- **安全な書き込み**: アトミック性、競合検出、リトライに対応します。
- **バックアップと復元**: `FileResource` はアトミック書き込みとバックアップの世代管理を行います。既定は `.bak` 1 世代で、`RestoreLatestBackupAsync` で復元できます。

**移行と相互運用**

- **スキーマ移行 / ストレージ移行**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` により、旧バージョンの設定を自動変換できます。既存ファイルも Source として登録できます。
- **JSON Schema 生成**: `Configlue.JsonSchema` が人間向けの JSON Schema を生成・エクスポートします。
- **Native AOT 対応**: ソース生成の `JsonSerializerContext` を渡すと、トリミング / AOT に強くなります。

**保存先と統合**

- **セクション**: `JsonSectionResource` / XML 要素 / YAML マッピングにより、ファイルの一部を独立した Resource として扱えます。書き込み時はコメント・空白・引用・スカラー形式が保持され、同じファイル内の独立セクションは 1 回の物理書き込みにバッチされます。
- **ZIP / HTTP / S3 / Dapr**: `ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込みとポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **暗号化**: `Configlue.Transformer.AES` が Resource と Codec の間のバイトを AES-GCM で暗号化・認証します。
- **リアクティブ統合（任意）**: `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）。`ObserveChanges()`、`ObserveValues()`、`ObserveReloadFailures()`、`ObserveActiveValues()`、`ObserveActiveProfileNames()` を提供します。
- **DI 統合**: `Configlue.Extensions.DI`。Microsoft の options アダプターとして `Configlue.Extensions.MSOptions`（`IOptions<T>` など）。同期ゲッターは非同期ソースの読み取り中にブロックするため、非同期フローでは `GetValueAsync` が推奨されます。
- **プロファイル / 動的オプション**: 名前付きオプションや永続プロファイルで、ランタイムを単位として作成・削除できます。

**既知の制限**

- 異なる Resource をまたぐ書き込みはアトミックではありません。
- Source の退役（retire）は現在の options インスタンスに閉じ、実データは残ります。
- Source の集合は options ランタイム内で固定されます。

### パッケージ構成

まず `dotnet add package Configlue` を実行し、必要な機能パッケージを追加します。

- `Configlue` … ユーザー向けメタパッケージ（Core / DI / JSON provider / JSON Schema / HTTP resources / common sources / environment source / generator analyzer を同梱。実装アセンブリは持ちません）
- `Configlue.Abstraction` … 契約（provider / codec / resource / generated-model）
- `Configlue.Core` … 解決と永続化のランタイム
- `Configlue.Extensibility` … プロバイダー SDK
- `Configlue.Generator` … Roslyn アナライザー（スパースなモデルサポートを生成）
- `Configlue.Testing` … インメモリのテストダブル
- `Configlue.Provider.Json` / `.Xml` / `.Yaml` … 各形式の Codec、セクションリソース、ファイル登録
- `Configlue.JsonSchema` … JSON Schema の生成・エクスポート
- `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml`
- `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip`
- `Configlue.Transformer.AES`
- `Configlue.Extensions.DI` / `.MSOptions` / `.R3` / `.Reactive`

## 基本的な使い方

### Quick Start

以下のコードを `example.cs` に保存し、`dotnet run example.cs` で実行します（.NET 10 以降）。

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

手順は 3 つです。モデルを宣言する（ジェネレーターが Fragment / Patch のサポートを生成）、利用する層を宣言する（ここで列挙した Source だけが有効になる）、options インスタンス経由で読み書きする、という流れになります。

### 値の由来を調べる

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

### 指定したメンバーだけを保存する

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

`Unset()` はその Source の寄与だけを外し、下位優先度の Source が値を提供できるようにします。

### その他の API

- `IReadOnlyOptions<T>` … 日常の読み取り面は `GetValueAsync` と `OnChange`
- `SaveAsync(patch => ...)` … 生成された Patch によるスパース保存
- `OpenEditSessionAsync()` … まとめて編集し `CommitAsync` で適用
- `ApplyPatchesAsync` + `StateSourcePatch` … 明示的なソース別マルチ書き込み
- `StateWritePlan.For<T>().Route(...)` … 書き込みルーティング
- `SourceKey<TModel>` と `options.Source(key)` … ソース単位の操作

---

# ===== opencode-go/kimi-k3 =====

## 概要

Configlue は、アプリケーションの設定管理（configuration management）を代行する .NET ライブラリです。キャッチコピーは "Make easy configuration management."。名前のとおり、複数の場所に散らばった設定を 1 つのモデルへ結合（glue）することを中心に設計されています。対象は .NET 10 SDK 以降、ライセンスは Apache-2.0 です。

JSON ファイルの読み書きだけなら数行で済みますが、実際のアプリケーションでは要件が積み重なります。グローバル設定・実行フォルダー設定・環境変数・コマンドライン引数・暗号化された資格情報・HTTP API によるリモート管理など、設定が複数箇所に存在することは珍しくありません。さらに、変更通知による再起動なしの反映、書き込み先の自動選択、人間が編集するためのコメント保持や JSON Schema、既定値の書き出し抑制、旧形式からの自動変換、バックアップ、アトミックな書き込みや競合検出といった要件を自前で実装するのは面倒です。Configlue はこれらをライブラリとして引き受けます。

なお Configlue は現状「アーキテクチャ上の土台」であり、`Configuration.Writable` を完全に置き換えるものではありません。`Microsoft.Extensions.Configuration`（`IConfiguration`）が読み取り中心であるのに対し、Configlue は独立したソースの合成・値の来歴の検査・スパースな保存に向いた設計になっています。

### 基本アーキテクチャ

Configlue は直線的な依存関係を持つ 6 つの概念で構成されており、学習順もこの順番のままです。

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

**読み込み**では、各 Source が Resource からバイトを取得し、Codec が Fragment に変換します。ランタイムが優先度順に「存在する」フィールドだけを 1 つのモデルへ重ねます。Fragment は「メンバーが存在しない」と「null/既定値で存在する」を区別するため、層の合成で「未設定」が「既定値に設定」を上書きすることはありません。

**書き込み**は逆向きです。アプリは普通のモデル値を編集するだけで、内部では変更が Fragment 差分になり、`WriteRoute` / `WritePlan` が指す Source にだけ届きます。無関係な Source は変更されません。

## 主な特徴

- **複数ソースの優先度マージ**: `Priority` が大きい Source が勝ちます。`GetDetailsAsync` で「どの値がどこ由来か」を検査できます。
- **読み取り専用ソース**: 環境変数・コマンドライン・既定の HTTP ソースは読み取り専用です。読み取り専用の値への書き込みは黙って無視されず、競合エラーになります。
- **スパース書き込み**: 変更したフィールドだけを対象層に保存します。既定値のままのフィールドは書き出されません（ユーザーが明示した `null` は尊重されます）。
- **編集セッション**: `OpenEditSessionAsync` で複数の変更をまとめて適用できます。`CommitAsync` まではインメモリです。競合時は既定で失敗しますが、`WriteConflictResolution.LastWriteWins` も選択できます。
- **安全な書き込み**: アトミック書き込み、他プロセスとの競合検出・自動マージ、自動リトライに対応しています。`FileResource` はバックアップ世代管理を備え、既定で `.bak` を 1 世代保持し、`RestoreLatestBackupAsync` で復元できます。
- **プリセット**: `UseCommonSources` が標準的な層構成（global / local / environment など）を組み立てます。
- **プロジェクション / マウント**: 既存 Source を別モデルに整形（projection）したり、ネストしたパスに別 Source を接続（mount, `AddMounted`）したりできます。
- **マージ挙動のカスタマイズ**: `[ConfiglueMerge]` でメンバーごとのマージ挙動を変更できます（組み込み: `Append`, `Deep`, `Replace`, `SetUnion`。カスタム戦略も可能）。コレクションの層合成・順序はここで決まります。
- **スキーマ移行 / ストレージ移行**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` により、旧バージョンの設定を新形式へ自動変換できます。既存ファイルを Source として登録することも可能です。
- **セクション**: `JsonSectionResource` / XML 要素 / YAML マッピングで、ファイルの一部を独立した Resource として扱えます。書き込み時はコメント・空白・引用・スカラー形式を保持し、同じファイル内の独立セクションは 1 回の物理書き込みにバッチされます。
- **多様な Resource**: `ZipEntryResource`、HTTP（ETag 条件付き書き込み・ポーリング）、S3、Dapr などを利用できます。`Configlue.Transformer.AES` により、Resource と Codec の間のバイトを AES-GCM で暗号化・認証することもできます。
- **JSON Schema 生成**: `Configlue.JsonSchema` で、人間が設定ファイルを書くための JSON Schema を生成・エクスポートできます。
- **Native AOT 対応**: ソース生成の `JsonSerializerContext` を渡すとトリミング / AOT に強くなります。
- **DI / リアクティブ統合（任意）**: `Configlue.Extensions.DI` による DI 統合、`Configlue.Extensions.MSOptions` による `IOptions<T>` アダプター（同期ゲッターは非同期ソース読み取り中にブロックするため、非同期フローでは `GetValueAsync` を推奨）、`Configlue.Extensions.Reactive`（System.Reactive）と `Configlue.Extensions.R3` による `ObserveChanges()` / `ObserveValues()` / `ObserveReloadFailures()` などのリアクティブ統合が利用できます。
- **プロファイル / 動的オプション**: 名前付きオプションや永続プロファイルで、ランタイムを単位にオプションを作成・削除できます。

### 既知の制限

- 異なる Resource 間の書き込みはアトミックではありません。
- Source の退役は現在の options インスタンスに閉じ、実データは残ります。
- Source 集合は options ランタイムで固定です。

## 基本的な使い方

インストールは `dotnet add package Configlue` から始め、必要な機能パッケージを追加します。

次のコードを `example.cs` に保存し、`dotnet run example.cs` で実行できます（.NET 10 以降）。

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

### 値の由来を調べる

`GetDetailsAsync` を使うと、マージ後の各値がどの Source から来たのか、その Source が書き込み可能かどうかを検査できます。

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

### スパース保存と Unset

指定したメンバーだけを更新するパッチを保存できます。`Unset()` は書き込み先 Source の寄与だけを取り消し、下位優先度の Source が値を提供できるようにします。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

### その他の API

- `IReadOnlyOptions<T>` … 日常の読み取り面は `GetValueAsync` と `OnChange`。
- `SaveAsync(patch => ...)` … 生成される Patch でスパース保存。
- `OpenEditSessionAsync()` … まとめて編集し `CommitAsync` で確定。
- `ApplyPatchesAsync` + `StateSourcePatch` … 明示的なソース別マルチ書き込み。
- `StateWritePlan.For<T>().Route(...)` … 書き込みルーティング。
- `SourceKey<TModel>` と `options.Source(key)` … ソース単位の操作。

---

# ===== opencode-go/longcat-2.5-preview-free =====

# Configlue

## 概要

Configlue は、アプリケーションの設定管理を代行する .NET ライブラリです。キャッチコピーは "Make easy configuration management."。複数の場所に散らばった設定を 1 つのモデルに結合（glue）するのが中心的な考え方で、名前も configuration + glue に由来します。

JSON ファイルの読み書きだけなら数行で済みますが、実際にはグローバル設定・実行フォルダー設定・環境変数・コマンドライン引数・暗号化された資格情報・社内ポリシーや HTTP API など、設定が複数箇所に散らばっていることが普通です。さらに、設定ファイルが書き換わったら再起動なしで反映したい、書き込み先を自動で選びたい、環境変数から読んだ値への書き込みはエラーにしたい、設定ファイルは人間が書くのでコメントを消さないでほしい、既定値のままなら書き出さないでほしい、設定ファイルのバージョンアップを自動で行いたい、バックアップと自動整理がほしい、書き込みはアトミックで他プロセスとの競合を検出してほしい——これらを自前実装するのは面倒です。Configlue はその面倒を解決します。

対象は .NET 10 SDK 以降、C# です（`LangVersion` はソースジェネレーター対応が必要で、リポジトリは preview でビルドします）。ライセンスは Apache-2.0 です。

なお、Configlue は `Microsoft.Extensions.Configuration` の代替ではありません。`IConfiguration` は読み取り中心の API ですが、Configlue は独立したソースの合成・来歴の検査・スパース保存に向いています。

## 主な特徴

### 6 つの概念

Configlue のアーキテクチャは 6 つの概念で説明でき、依存関係は直線的で、学習順も同じです。

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

**読み込み**では、各 Source が Resource からバイトを取得し、Codec が Fragment に変換します。ランタイムが優先度順に「存在する」フィールドだけを 1 つのモデルへ重ねます。

**書き込み**はその逆向きです。アプリは普通のモデル値を編集します。内部では変更が Fragment 差分になり、`WriteRoute` / `WritePlan` が指す Source にだけ届きます。無関係な Source は変更されません。

Fragment は「メンバーが存在しない」と「null/既定値で存在する」を区別します。層の合成で「未設定」が「既定値に設定」を上書きすることはありません。Patch は生成される `TModel.Patch`（単一フィールドの編集フラグメント）で、`Unset()` は書き込み先 Source の寄与だけを取り消し、下位優先度の値を再び見せます。`[ConfiglueMerge]` でメンバーごとのマージ挙動を変更することも可能です（組み込み: `Append`, `Deep`, `Replace`, `SetUnion`、カスタム戦略も可）。コレクションの層合成・順序はここで決まります。

### 複数ソースの優先度マージ

`Priority` が大きい Source が勝ちます。`GetDetailsAsync` で「どの値がどこ由来か」を検査できます。

### 読み取り専用ソース

環境変数・コマンドライン・既定の HTTP ソースは読み取り専用です。読み取り専用の値への書き込みは黙って無視せず、競合エラーになります。

### スパース書き込み

変更したフィールドだけを対象層に保存します。既定値のままのフィールドは書かれません。

### 編集セッション

`OpenEditSessionAsync` で複数変更をまとめて適用できます。`CommitAsync` までインメモリです。競合時は既定で失敗し、`WriteConflictResolution.LastWriteWins` も選べます。

### スキーマ移行 / ストレージ移行

`[ConfigluePreviousVersion]` と `Fragment.FromPrevious` による旧バージョン設定の自動変換が可能です。既存ファイルを Source として登録できます。

### バックアップと復元

`FileResource` はアトミック書き込みとバックアップ世代管理を提供します。既定で `.bak` 1 世代、`RestoreLatestBackupAsync` で復元できます。

### 安全な書き込み

アトミック性、競合検出、リトライを備えています。

### セクション

`JsonSectionResource` / XML 要素 / YAML マッピングで、ファイルの一部を独立した Resource として扱えます。書き込み時はコメント・空白・引用・スカラー形式を保持します。同じファイル内の独立セクションは 1 回の物理書き込みにバッチされます。

### プロバイダー

ZIP / HTTP / S3 / Dapr に対応しています。`ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込み・ポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr` があります。

### JSON Schema 生成

`Configlue.JsonSchema` で JSON Schema を生成・エクスポートできます。人間が設定を書くための機能です。

### Native AOT 対応

ソース生成の `JsonSerializerContext` を渡すと、トリミング/AOT に強くなります。

### リアクティブ統合（任意）

`Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）を提供しています。`ObserveChanges()`, `ObserveValues()`, `ObserveReloadFailures()`, `ObserveActiveValues()`, `ObserveActiveProfileNames()` が利用できます。

### DI 統合

`Configlue.Extensions.DI` を提供しています。Microsoft の options アダプター `Configlue.Extensions.MSOptions`（`IOptions<T>` など）もあります。同期ゲッターは非同期ソース読み取り中ブロックするため、非同期フローでは `GetValueAsync` の利用が推奨されます。

### プロファイル / 動的オプション

名前付きオプションや永続プロファイルで、ランタイムを単位に作成・削除できます。

### 既知の制限

異なる Resource 間の書き込みはアトミックではありません。Source の退役は現在の options インスタンスに閉じ、実データは残ります。Source 集合は options ランタイムで固定されます。

## 基本的な使い方

### Quick Start

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

### 値の由来を調べる

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

### スパース保存

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

### インストール

```bash
dotnet add package Configlue
```

必要な機能パッケージを追加してください。

---

# ===== opencode-go/mimo-v2.6-flash =====

## 概要

Configlue は、アプリケーションの設定管理を代行する .NET ライブラリです。「Make easy configuration management.」を掲げ、複数の場所に散らばった設定を 1 つのモデルに結合（glue）することを中心的な考え方としています。名前も configuration と glue の造語です。

対象は .NET 10 SDK 以降、ライセンスは Apache-2.0 です。現状はアーキテクチャ上の土台という位置づけで、`Configuration.Writable` を完全に置き換えるものではありません。

JSON ファイルの読み書きだけなら数行で済みますが、実際の設定管理には次のような要件が積み重なります。

- 設定が複数箇所にある: グローバル設定、実行フォルダー設定、環境変数、コマンドライン引数、暗号化された資格情報、社内ポリシーや HTTP API などのリモート管理
- 設定ファイルが書き換わったら再起動なしで反映したい（変更通知）
- 書き込み先を自動で選びたい。環境変数から読んだ値への書き込みはエラーにしたい
- 設定ファイルは人間が書く: コメントを消さない、JSON Schema がほしい、壊れたファイルへの対処
- 既定値のままなら書き出さない（ただしユーザーが明示した `null` は尊重する）
- 設定ファイルのバージョンアップ（旧形式から新形式への自動変換）
- バックアップと自動整理
- 書き込みの安全性: アトミック性、他プロセスとの競合検出・自動マージ、自動リトライ

これらを自前実装するのは面倒、というのが Configlue の動機です。

内部は 6 つの概念で構成され、依存関係は直線的です。

```text
Resource (location) → Codec (conversion) → Source (contribution) → Fragment (diff) → Options (facade)
                                                        ↘ Patch (edit fragment)
```

| 概念 | 一言で | 例 |
| --- | --- | --- |
| Resource | バイトがどこにあるか | ファイル、ZIPエントリ、HTTP応答、メモリ |
| Codec | バイトと値の変換 | JSON / XML / YAML の読み書き |
| Source | 論理的な寄与（どのフィールドをどの優先度で） | 「ユーザー設定ファイルの Server 部分」 |
| Fragment | 存在を記憶する差分 | 「Port だけ」を持つ状態 |
| Patch | 単一フィールドの編集 | 「Port を 9000 にする」 |
| Options | アプリが見るファサード | 読み・保存・監視・説明・診断 |

読み込みでは、各 Source が Resource からバイトを取得し、Codec が Fragment に変換します。ランタイムが優先度順に「存在する」フィールドだけを 1 つのモデルへ重ね合わせます。書き込みはその逆で、アプリは普通のモデル値を編集し、内部で変更が Fragment 差分になって `WriteRoute` / `WritePlan` が指す Source にだけ届きます。無関係な Source は変更されません。

なお、`IConfiguration` が読み取り中心なのに対し、Configlue は独立したソースの合成、値の来歴の検査、スパース保存に向いた設計です。

## 主な特徴

- **複数ソースの優先度マージ**: `Priority` が大きい Source が勝ちます。`GetDetailsAsync` で「どの値がどこ由来か」を検査できます。
- **読み取り専用ソース**: 環境変数・コマンドライン・既定の HTTP ソースは読み取り専用です。読み取り専用の値への書き込みは黙って無視されず、競合エラーになります。
- **プロジェクション / マウント**: 既存の Source を別モデルに整形（projection）したり、ネストしたパスに別の Source を接続（mount、`AddMounted`）できます。
- **プリセット**: `UseCommonSources` が standard な層構成（global / local / environment など）を組み立てます。
- **スパース書き込み**: 変更したフィールドだけを対象層に保存し、既定値のままのフィールドは書きません。
- **編集セッション**: `OpenEditSessionAsync` で複数変更をまとめて適用し、`CommitAsync` までインメモリで保持します。競合時は既定で失敗し、`WriteConflictResolution.LastWriteWins` も選べます。
- **スキーマ移行 / ストレージ移行**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` による旧バージョン設定の自動変換。既存ファイルを Source として登録できます。
- **バックアップと復元**: `FileResource` はアトミック書き込みとバックアップ世代管理を持ち、既定で `.bak` を 1 世代残し、`RestoreLatestBackupAsync` で復元できます。
- **安全な書き込み**: アトミック性、競合検出、リトライ。
- **セクション**: `JsonSectionResource` / XML 要素 / YAML マッピングで、ファイルの一部を独立した Resource として扱えます。書き込み時はコメント・空白・引用・スカラー形式を保持し、同じファイル内の独立セクションは 1 回の物理書き込みにバッチされます。
- **ZIP / HTTP / S3 / Dapr**: `ZipEntryResource`、`Configlue.Resource.Http`（ETag による条件付き書き込み・ポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **JSON Schema 生成**: `Configlue.JsonSchema` により、人間が設定を書きやすい形を用意できます。
- **Native AOT 対応**: ソース生成の `JsonSerializerContext` を渡すと、トリミング / AOT に強くなります。
- **リアクティブ統合（任意）**: `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）で、`ObserveChanges()`、`ObserveValues()`、`ObserveReloadFailures()`、`ObserveActiveValues()`、`ObserveActiveProfileNames()` などが使えます。
- **DI 統合**: `Configlue.Extensions.DI`。Microsoft の options アダプターとして `Configlue.Extensions.MSOptions`（`IOptions<T>` など）もあります。同期ゲッターは非同期ソースの読み取り中にブロックするため、非同期フローでは `GetValueAsync` を推奨します。
- **プロファイル / 動的オプション**: 名前付きオプションや永続プロファイルで、ランタイムを単位に作成・削除できます。
- **既知の制限**: 異なる Resource 間の書き込みはアトミックではありません。Source の退役は現在の options インスタンスに閉じ、実データは残ります。Source の集合は options ランタイムで固定です。

パッケージは `Configlue` メタパッケージ（Core / DI / JSON provider / JSON Schema / HTTP resources / common sources / environment source / generator analyzer を同梱）を起点に、必要な機能パッケージを追加して使います。形式別の `Configlue.Provider.Json` / `.Xml` / `.Yaml`、リモート系の `Configlue.Resource.Http` / `.S3` / `.Dapr` / `.Zip`、暗号化用の `Configlue.Transformer.AES`（Resource と Codec の間のバイトを AES-GCM で暗号化・認証）などがあります。

## 基本的な使い方

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

設定モデルには `[ConfiglueModel]` を付けて `partial class` とし、ジェネレーターが Fragment / Patch の対応を生成します。`UseCommonSources` で有効にする層を宣言すると、書き込み先の自動選択やスパース保存がこの宣言に基づいて行われます。`SaveAsync` のパッチで触れたフィールドだけが対象層に保存され、触れなかったフィールドは書き出されません。

値の由来を調べることもできます。

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

指定したメンバーだけを更新するパッチを保存できます。`Unset()` はその Source の寄与だけを外し、下位優先度の Source が値を提供できるようにします。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

その他の主な API は次のとおりです。

- `IReadOnlyOptions<T>` … 日常の読み取り面は `GetValueAsync` と `OnChange`
- `SaveAsync(patch => ...)` … 生成 Patch によるスパース保存
- `OpenEditSessionAsync()` … まとめて編集し `CommitAsync`
- `ApplyPatchesAsync` + `StateSourcePatch` … 明示的なソース別マルチ書き込み
- `StateWritePlan.For<T>().Route(...)` … 書き込みルーティング
- `SourceKey<TModel>` と `options.Source(key)` … ソース単位の操作

---

# ===== opencode-go/mimo-v2.6-pro =====

# 概要

Configlue は、アプリケーションの設定管理（configuration management）を代行する .NET ライブラリです。キャッチコピーは "Make easy configuration management."。

設定値はグローバル設定ファイル、実行フォルダーの設定、環境変数、コマンドライン引数など、複数の場所に散らばりがちです。Configlue はこれらを優先度つきで 1 つのモデルに結合（glue）します。名前は configuration + glue に由来します。

対象は .NET 10 SDK 以降の C# で、ソースジェネレーターによるモデルサポート生成を前提とします。ライセンスは Apache-2.0。現状は「アーキテクチャ上の土台」であり、`Configuration.Writable` を完全に置き換えるものではない点に注意してください。

## なぜ Configlue なのか

JSON ファイルの読み書きだけなら数行で済みます。しかし実際の運用では、次のような要件が積み重なります。

- 設定が複数箇所にある: グローバル設定、実行フォルダー設定、環境変数、コマンドライン引数、暗号化された資格情報、社内ポリシーや HTTP API などのリモート管理
- 設定ファイルが書き換わったら再起動なしで反映したい（変更通知）
- 書き込み先を自動で選びたい。環境変数から読んだ値への書き込みはエラーにしたい
- 設定ファイルは人間が書く: コメントを消さない、JSON Schema がほしい、壊れたファイルへの対処
- 既定値のままなら書き出さない（ただしユーザーが明示した `null` は尊重する）
- 設定ファイルのバージョンアップ（旧形式から新形式への自動変換）
- バックアップと自動整理
- 書き込みの安全性: アトミック性（クラッシュしても壊れない）、他プロセスとの競合検出・自動マージ、自動リトライ

これらを自前実装するのは面倒です。Configlue はこの受け皿を提供します。

## 基本アーキテクチャ

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

**書き込み**: 逆向きです。アプリは普通のモデル値を編集し、内部では変更が Fragment 差分になります。`WriteRoute` / `WritePlan` が指す Source にだけ届き、無関係な Source は変更されません。

Fragment は「メンバーが存在しない」と「null / 既定値で存在する」を区別します。これにより層の合成で「未設定」が「既定値に設定」を上書きすることはありません。Patch は生成される `TModel.Patch`（単一フィールドの編集フラグメント）で、`Unset()` は書き込み先 Source の寄与だけを取り消し、下位優先度の値を再び見せます。また `[ConfiglueMerge]` でメンバーごとのマージ挙動を変更でき（組み込み: `Append`, `Deep`, `Replace`, `SetUnion`、カスタム戦略も可）、コレクションの層合成・順序はここで決まります。

## Microsoft.Extensions.Configuration との違い

`IConfiguration` は読み取り中心の構成です。Configlue は独立したソースの合成、値の来歴の検査、スパース保存といった書き込みを含むライフサイクルに向いています。

# 主な特徴

- **複数ソースの優先度マージ**: `Priority` が大きい Source が勝ちます。`GetDetailsAsync` で「どの値がどこ由来か」を検査できます。
- **読み取り専用ソース**: 環境変数・コマンドライン・既定の HTTP ソースは読み取り専用です。読み取り専用の値への書き込みは黙って無視せず競合エラーになります。
- **プロジェクション / マウント**: 既存 Source を別モデルに整形（projection）したり、ネストしたパスに別 Source を接続（mount, `AddMounted`）できます。
- **プリセット**: `UseCommonSources` が標準的な層構成（global / local / environment など）を組み立てます。
- **スパース書き込み**: 変更したフィールドだけを対象層に保存します。既定値のままのフィールドは書かれません。
- **編集セッション**: `OpenEditSessionAsync` で複数変更をまとめて適用します。`CommitAsync` までインメモリで、競合時は既定で失敗、`WriteConflictResolution.LastWriteWins` も選べます。
- **スキーマ移行 / ストレージ移行**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` により旧バージョン設定を自動変換します。既存ファイルを Source として登録できます。
- **バックアップと復元**: `FileResource` はアトミック書き込みとバックアップ世代管理を持ちます。既定で `.bak` 1 世代、`RestoreLatestBackupAsync` で復元します。
- **安全な書き込み**: アトミック性、競合検出、リトライに対応します。
- **セクション**: `JsonSectionResource` / XML 要素 / YAML マッピングで、ファイルの一部を独立した Resource として扱えます。書き込み時はコメント・空白・引用・スカラー形式を保持し、同じファイル内の独立セクションは 1 回の物理書き込みにバッチされます。
- **ZIP / HTTP / S3 / Dapr**: `ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込み・ポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **JSON Schema 生成**: `Configlue.JsonSchema` が設定の JSON Schema を生成・エクスポートします。人間が設定を書くための仕組みです。
- **Native AOT 対応**: ソース生成の `JsonSerializerContext` を渡すとトリミング / AOT に強くなります。
- **リアクティブ統合（任意）**: `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）。`ObserveChanges()`, `ObserveValues()`, `ObserveReloadFailures()`, `ObserveActiveValues()`, `ObserveActiveProfileNames()` を提供します。
- **DI 統合**: `Configlue.Extensions.DI`。Microsoft の options アダプター `Configlue.Extensions.MSOptions`（`IOptions<T>` など）も提供します。同期ゲッターは非同期ソース読み取り中ブロックするため、非同期フローでは `GetValueAsync` の利用を推奨します。
- **プロファイル / 動的オプション**: 名前付きオプションや永続プロファイルでランタイムを単位に作成・削除できます。
- **既知の制限**: 異なる Resource 間の書き込みはアトミックではありません。Source の退役は現在の options インスタンスに閉じ、実データは残ります。Source 集合は options ランタイムで固定です。

## パッケージ構成

インストールは `dotnet add package Configlue` から。必要に応じて機能パッケージを追加します。

- `Configlue` … ユーザー向けメタパッケージ（Core / DI / JSON provider / JSON Schema / HTTP resources / common sources / environment source / generator analyzer を同梱。実装アセンブリは持たない）
- `Configlue.Abstraction` … 契約（provider / codec / resource / generated-model）
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

# 基本的な使い方

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

`GetDetailsAsync` を使うと、各値がどの Source から来たか、書き込み可能かを確認できます。

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

## その他の API

- `IReadOnlyOptions<T>` … 日常の読み取り面は `GetValueAsync` と `OnChange`。
- `SaveAsync(patch => ...)` … 生成 Patch でスパース保存。
- `OpenEditSessionAsync()` … まとめて編集し `CommitAsync`。
- `ApplyPatchesAsync` + `StateSourcePatch` … 明示的なソース別マルチ書き込み。
- `StateWritePlan.For<T>().Route(...)` … 書き込みルーティング。
- `SourceKey<TModel>` と `options.Source(key)` … ソース単位の操作。

---

# ===== opencode-go/minimax-m3 =====

# Configlue

## 概要

Configlue は、アプリケーションの **設定管理（configuration management）** を代行する .NET ライブラリです。キャッチコピーは "Make easy configuration management."。

名前のとおり、**複数の場所に散らばった設定を 1 つのモデルに「糊付け（glue）」する** のが中心的な考え方です。グローバル設定・実行フォルダー設定・環境変数・コマンドライン引数・暗号化された資格情報・リモートの社内ポリシーや HTTP API など、由来も形式もばらばらの設定を、優先度に従って 1 つのモデルに合成します。

- 対象: .NET 10 SDK 以降。C# は `LangVersion` がソースジェネレーター対応版である必要があり、リポジトリは preview でビルドされます。
- ライセンス: Apache-2.0。
- 位置付け: 現状は「アーキテクチャ上の土台」であり、`Microsoft.Extensions.Configuration.Writable` を完全に置き換えるものではありません。`IConfiguration` が読み取り中心であるのに対し、Configlue は独立した複数ソースの合成・値の来歴の検査・スパースな書き戻しに向きます。

## 主な特徴

### 6つの基本概念

依存関係は直線で、学習順も同じです。

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

**書き込み**: 逆向きです。アプリは普通のモデル値を編集し、内部では変更が Fragment 差分になり、`WriteRoute` / `WritePlan` が指す Source にだけ届きます。無関係な Source は変更されません。

Fragment は「メンバーが存在しない」と「null / 既定値で存在する」を区別します。層の合成で「未設定」が「既定値に設定」を上書きすることはありません。Patch はソースジェネレータが生成する `TModel.Patch`（単一フィールドの編集フラグメント）で、`Unset()` を呼ぶと書き込み先 Source の寄与だけが取り消され、下位優先度の Source の値が再び見えるようになります。`[ConfiglueMerge]` でメンバーごとのマージ挙動を切り替えられ、組み込みで `Append` / `Deep` / `Replace` / `SetUnion`、カスタム戦略も定義可能です。コレクションの層合成や順序もこの仕組みで決まります。

### コア機能

- **複数ソースの優先度マージ**: `Priority` が大きい Source が勝ちます。`GetDetailsAsync` で「どの値がどこ由来か」を検査できます。
- **読み取り専用ソース**: 環境変数・コマンドライン・既定の HTTP ソースは読み取り専用です。読み取り専用の値への書き込みは黙って無視されず、競合エラーになります。
- **プロジェクション / マウント**: 既存 Source を別モデルに整形（projection）したり、ネストしたパスに別 Source を接続（mount, `AddMounted`）したりできます。
- **プリセット**: `UseCommonSources` が標準的な層構成（global / local / environment など）を組み立てます。
- **スパース書き込み**: 変更したフィールドだけを対象層に保存します。既定値のままのフィールドは書き出されず、ユーザーが明示した `null` のみ尊重されます。
- **編集セッション**: `OpenEditSessionAsync` で複数変更をまとめて適用し、`CommitAsync` までインメモリで保持します。競合時は既定で失敗し、`WriteConflictResolution.LastWriteWins` を選べば後勝ちで上書きできます。
- **スキーマ移行 / ストレージ移行**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` により旧バージョン設定を自動変換します。既存ファイルを Source として登録できます。
- **バックアップと復元**: `FileResource` はアトミック書き込みとバックアップ世代管理を提供し、既定で `.bak` 1 世代を保持します。`RestoreLatestBackupAsync` で復元できます。
- **安全な書き込み**: アトミック性、他プロセスとの競合検出、自動リトライを備えます。
- **セクション**: `JsonSectionResource` / XML 要素 / YAML マッピングで、ファイルの一部を独立した Resource として扱えます。書き込み時はコメント・空白・引用・スカラー形式を保持し、同じファイル内の独立セクションは 1 回の物理書き込みにバッチされます。
- **ZIP / HTTP / S3 / Dapr**: `ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込み・ポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr` を利用できます。
- **JSON Schema 生成**: `Configlue.JsonSchema` が人間が手で設定を書くためのスキーマを出力します。
- **Native AOT 対応**: ソース生成の `JsonSerializerContext` を渡すとトリミング / AOT に強くなります。
- **リアクティブ統合（任意）**: `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）で `ObserveChanges()` / `ObserveValues()` / `ObserveReloadFailures()` / `ObserveActiveValues()` / `ObserveActiveProfileNames()` などが使えます。
- **DI 統合**: `Configlue.Extensions.DI`、および Microsoft の options アダプター `Configlue.Extensions.MSOptions`（`IOptions<T>` など）を提供します。同期ゲッターは非同期ソース読み取り中ブロックするため、非同期フローでは `GetValueAsync` が推奨されます。
- **プロファイル / 動的オプション**: 名前付きオプションや永続プロファイルをランタイム単位で作成・削除できます。
- **既知の制限**: 異なる Resource 間の書き込みはアトミックではありません。Source の退役は現在の options インスタンスに閉じ、実データは残ります。Source 集合は options ランタイムで固定です。

### パッケージ構成

インストールは `dotnet add package Configlue` から開始し、必要な機能パッケージを追加します。

- `Configlue` — ユーザー向けメタパッケージ。Core / DI / JSON provider / JSON Schema / HTTP resources / common sources / environment source / generator analyzer を同梱します（実装アセンブリは持ちません）。
- `Configlue.Abstraction` — 契約（provider / codec / resource / generated-model）。
- `Configlue.Core` — 解決と永続化のランタイム。
- `Configlue.Extensibility` — プロバイダー SDK。
- `Configlue.Extensions.DI` / `.MSOptions` / `.R3` / `.Reactive`
- `Configlue.Generator` — Roslyn アナライザー（スパースなモデルサポート生成）。
- `Configlue.Testing` — インメモリのテストダブル。
- `Configlue.Provider.Json` / `.Xml` / `.Yaml` — 各形式の Codec・セクションリソース・ファイル登録。
- `Configlue.JsonSchema` — JSON Schema 生成・エクスポート。
- `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml`
- `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip`
- `Configlue.Transformer.AES` — Resource と Codec の間のバイトを AES-GCM で暗号化・認証します。

## 基本的な使い方

以下の例は `example.cs` に保存し、`dotnet run example.cs` で実行できます（.NET 10 以降）。

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

### 値の由来を調べる

ある値がどの Source から来たのか、書き込み可能かどうかは `GetDetailsAsync` で診断できます。

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

### スパースに保存する / 値を外す

`SaveAsync` には変更したいメンバーだけを代入した Patch を渡します。`Unset()` を呼ぶと、その Source の寄与だけが取り消され、下位優先度の Source が値を提供します。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

### その他の API

- `IReadOnlyOptions<T>` — 日常の読み取り面は `GetValueAsync` と `OnChange`。
- `SaveAsync(patch => ...)` — 生成 Patch でのスパース保存。
- `OpenEditSessionAsync()` — まとめて編集し `CommitAsync`。
- `ApplyPatchesAsync` + `StateSourcePatch` — 明示的なソース別マルチ書き込み。
- `StateWritePlan.For<T>().Route(...)` — 書き込みルーティング。
- `SourceKey<TModel>` と `options.Source(key)` — ソース単位の操作。

---

# ===== opencode-go/muse-spark-1.3-contributor =====

## 概要

Configlue は、アプリケーションの設定管理を代行する .NET ライブラリです。キャッチコピーは "Make easy configuration management." で、名前の通り configuration を glue すること、すなわち複数の場所に散らばった設定を 1 つのモデルに結合することが中心的な考え方です。

対象は .NET 10 SDK 以降で、C# の `LangVersion` はソースジェネレーター対応が必要です。ライセンスは Apache-2.0 です。現状はアーキテクチャ上の土台であり、`Configuration.Writable` を完全に置き換えるものではありません。

`Microsoft.Extensions.Configuration` の `IConfiguration` が読み取り中心であるのに対し、Configlue は独立した Source の合成、値の来歴の検査、スパース保存に向いています。JSON ファイルの読み書きだけなら数行で済みますが、実際には次のような要件が積み重なることを解決しようとしています。

- グローバル設定、実行フォルダー設定、環境変数、コマンドライン引数、暗号化された資格情報、社内ポリシーや HTTP API などのリモート管理といった、複数箇所にある設定の統合
- 設定ファイルが書き換わったら再起動なしで反映したいという変更通知
- 書き込み先の自動選択と、環境変数から読んだ値への書き込みはエラーにすること
- 人間が書く設定ファイルへの配慮として、コメントを消さないこと、JSON Schema、壊れたファイルへの対処
- 既定値のままなら書き出さないこと。ただしユーザーが明示した `null` は尊重すること
- 設定ファイルのバージョンアップとして、旧形式から新形式への自動変換
- バックアップと自動整理
- 書き込みの安全性として、アトミック性、他プロセスとの競合検出・自動マージ、自動リトライ

基本アーキテクチャは 6 つの概念からなり、依存関係は直線的です。

```text
Resource (location) → Codec (conversion) → Source (contribution) → Fragment (diff) → Options (facade)
                                                        ↘ Patch (edit fragment)
```

| 概念 | 一言で | 例 |
| --- | --- | --- |
| Resource | バイトがどこにあるか | ファイル、ZIP エントリ、HTTP 応答、メモリ |
| Codec | バイトと値の変換 | JSON / XML / YAML の読み書き |
| Source | 論理的な寄与 | 「ユーザー設定ファイルの Server 部分」 |
| Fragment | 存在を記憶する差分 | 「Port だけ」を持つ状態 |
| Patch | 単一フィールドの編集 | 「Port を 9000 にする」 |
| Options | アプリが見るファサード | 読み・保存・監視・説明・診断 |

読み込みでは、各 Source が Resource からバイトを取得し、Codec が Fragment に変換します。ランタイムが優先度順に「存在する」フィールドだけを 1 つのモデルへ重ねます。書き込みでは逆向きで、アプリは普通のモデル値を編集します。内部では変更が Fragment 差分になり、`WriteRoute` / `WritePlan` が指す Source にだけ届きます。無関係な Source は変更されません。

Fragment は「メンバーが存在しない」と「null / 既定値で存在する」を区別します。そのため層の合成で「未設定」が「既定値に設定」を上書きすることはありません。Patch は生成される `TModel.Patch` で、`Unset()` は書き込み先 Source の寄与だけを取り消し、下位優先度の値を再び見せます。`[ConfiglueMerge]` でメンバーごとのマージ挙動を変更でき、組み込みは `Append`、`Deep`、`Replace`、`SetUnion` で、カスタム戦略も可能です。

## 主な特徴

- **複数ソースの優先度マージ**: `Priority` が大きい Source が勝ちます。`GetDetailsAsync` で「どの値がどこ由来か」を検査できます。
- **読み取り専用ソース**: 環境変数・コマンドライン・既定の HTTP ソースは読み取り専用です。読み取り専用の値への書き込みは黙って無視せず競合エラーになります。
- **プロジェクション / マウント**: 既存 Source を別モデルに整形したり、ネストしたパスに別 Source を接続できます。マウントには `AddMounted` を使います。
- **プリセット**: `UseCommonSources` が global / local / environment などの標準的な層構成を組み立てます。
- **スパース書き込み**: 変更したフィールドだけを対象層に保存します。既定値のままのフィールドは書かれません。
- **編集セッション**: `OpenEditSessionAsync` で複数変更をまとめて適用します。`CommitAsync` までインメモリで、競合時は既定で失敗し、`WriteConflictResolution.LastWriteWins` も選べます。
- **スキーマ移行 / ストレージ移行**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` による旧バージョン設定の自動変換ができます。既存ファイルを Source として登録できます。
- **バックアップと復元**: `FileResource` はアトミック書き込みとバックアップ世代管理を行います。既定で `.bak` 1 世代で、`RestoreLatestBackupAsync` で復元できます。
- **安全な書き込み**: アトミック性、競合検出、リトライに対応します。
- **セクション**: `JsonSectionResource` / XML 要素 / YAML マッピングで、ファイルの一部を独立した Resource として扱えます。書き込み時はコメント・空白・引用・スカラー形式を保持します。同じファイル内の独立セクションは 1 回の物理書き込みにバッチされます。
- **ZIP / HTTP / S3 / Dapr**: `ZipEntryResource`、`Configlue.Resource.Http`、`Configlue.Resource.S3`、`Configlue.Resource.Dapr` があります。HTTP は ETag 条件付き書き込み・ポーリングに対応します。
- **JSON Schema 生成**: `Configlue.JsonSchema` により、人間が設定を書くためのスキーマを生成・エクスポートできます。
- **Native AOT 対応**: ソース生成の `JsonSerializerContext` を渡すとトリミング / AOT に強くなります。
- **リアクティブ統合（任意）**: `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）があります。`ObserveChanges()`、`ObserveValues()`、`ObserveReloadFailures()`、`ObserveActiveValues()`、`ObserveActiveProfileNames()` が使えます。
- **DI 統合**: `Configlue.Extensions.DI` と、Microsoft の options アダプターである `Configlue.Extensions.MSOptions`（`IOptions<T>` など）があります。同期ゲッターは非同期ソース読み取り中ブロックするので、非同期フローでは `GetValueAsync` が推奨されます。
- **プロファイル / 動的オプション**: 名前付きオプションや永続プロファイルでランタイムを単位に作成・削除できます。
- **既知の制限**: 異なる Resource 間の書き込みはアトミックではありません。Source の退役は現在の options インスタンスに閉じ、実データは残ります。Source 集合は options ランタイムで固定です。

パッケージは `dotnet add package Configlue` から導入します。`Configlue` はユーザー向けメタパッケージで、Core / DI / JSON provider / JSON Schema / HTTP resources / common sources / environment source / generator analyzer を同梱し、実装アセンブリは持ちません。その他に `Configlue.Abstraction`、`Configlue.Core`、`Configlue.Extensibility`、`Configlue.Generator`、`Configlue.Testing`、`Configlue.Provider.Json` / `.Xml` / `.Yaml`、`Configlue.JsonSchema`、`Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml`、`Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip`、`Configlue.Transformer.AES` などがあり、必要な機能パッケージを追加します。`Configlue.Transformer.AES` は Resource と Codec の間のバイトを AES-GCM で暗号化・認証します。

## 基本的な使い方

`example.cs` に保存し `dotnet run example.cs` で実行できます（.NET 10 以降）。

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

現在の値と値の由来の調べ方は次の通りです。`GetValueAsync` は全ソースをマージしたものを取得し、`GetDetailsAsync` は各値がどこから来たかを示します。日常の読み取り面は `IReadOnlyOptions<T>` の `GetValueAsync` と `OnChange` が担います。

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

その他の API として、`SaveAsync(patch => ...)` による生成 Patch でのスパース保存、`OpenEditSessionAsync()` でまとめて編集し `CommitAsync` すること、`ApplyPatchesAsync` と `StateSourcePatch` による明示的なソース別マルチ書き込み、`StateWritePlan.For<T>().Route(...)` による書き込みルーティング、`SourceKey<TModel>` と `options.Source(key)` によるソース単位の操作があります。


---

# ===== opencode-go/qwen3.8-flash =====

## 概要

Configlue は、アプリケーションの設定管理を代行する .NET ライブラリです。キャッチコピーは "Make easy configuration management." で、複数の場所に散らばった設定を 1 つのモデルに**結合（glue）** することが中心的な考え方です。名前は configuration + glue に由来します。対象は .NET 10 SDK 以降、ライセンスは Apache-2.0 です。

JSON ファイルの読み書きだけなら数行で済みますが、実際には以下のような要件が積み重なります。

- 設定が複数箇所にある（グローバル設定、実行フォルダー設定、環境変数、コマンドライン引数、暗号化された資格情報、HTTP API などのリモート管理）
- ファイルが書き換わったら再起動なしで反映したい
- 書き込み先を自動で選びたい。環境変数から読んだ値への書き込みはエラーにしたい
- 人間が書くファイルなので、コメントを残したい、JSON Schema がほしい、壊れたファイルに対処したい
- 既定値のままなら書き出さない（ただし明示された `null` は尊重する）
- 設定ファイルのバージョンアップ、バックアップと自動整理
- 書き込みのアトミック性、他プロセスとの競合検出・自動マージ、自動リトライ

これらを自前実装するのは面倒だ、というのが Configlue の動機です。現状は「アーキテクチャ上の土台」であり、`Configuration.Writable` を完全に置き換えるものではありません。`Microsoft.Extensions.Configuration`（`IConfiguration`）が読み取り中心なのに対し、Configlue は独立ソースの合成・来歴の検査・スパース保存に向いています。

アーキテクチャは 6 つの概念からなり、依存関係は直線的です（学習順も同じ）。

| 概念 | 一言で | 例 |
| --- | --- | --- |
| Resource | バイトがどこにあるか | ファイル、ZIPエントリ、HTTP応答、メモリ |
| Codec | バイト↔値の変換 | JSON / XML / YAML の読み書き |
| Source | 論理的な寄与（どのフィールドをどの優先度で） | 「ユーザー設定ファイルの Server 部分」 |
| Fragment | 存在を記憶する差分 | 「Port だけ」を持つ状態 |
| Patch | 単一フィールドの編集 | 「Port を 9000 にする」 |
| Options | アプリが見るファサード | 読み・保存・監視・説明・診断 |

```text
Resource (location) → Codec (conversion) → Source (contribution) → Fragment (diff) → Options (facade)
                                                        ↘ Patch (edit fragment)
```

読み込み時は、各 Source が Resource からバイトを取得し、Codec が Fragment に変換します。ランタイムが優先度順に「存在する」フィールドだけを 1 つのモデルへ重ねます。書き込みはその逆向きで、アプリが普通のモデル値を編集すると、内部で Fragment 差分になり、`WriteRoute` / `WritePlan` が指す Source にだけ届きます。無関係な Source は変更されません。

Fragment は「メンバーが存在しない」と「null/既定値で存在する」を区別するため、層の合成で「未設定」が「既定値に設定」を上書きすることはありません。`[ConfiglueMerge]` を使うとメンバーごとのマージ挙動（組み込みは `Append` / `Deep` / `Replace` / `SetUnion`、カスタム戦略も可）も制御できます。

## 主な特徴

- **複数ソースの優先度マージ**: `Priority` が大きい Source が勝つ。`GetDetailsAsync` で「どの値がどこ由来か」を検査できる
- **読み取り専用ソース**: 環境変数・コマンドライン・既定の HTTP ソースは読み取り専用で、読み取り専用の値への書き込みは黙って無視せず競合エラーになる
- **プリセット**: `UseCommonSources` が標準的な層構成（global / local / environment など）を組み立てる
- **プロジェクション / マウント**: 既存 Source を別モデルに整形したり、ネストしたパスに別 Source を接続（`AddMounted`）できる
- **スパース書き込み**: 変更したフィールドだけを対象層に保存し、既定値のままのフィールドは書かない
- **編集セッション**: `OpenEditSessionAsync` で複数変更をまとめて適用し、`CommitAsync` までインメモリ。競合時は既定で失敗、`WriteConflictResolution.LastWriteWins` も選べる
- **スキーマ移行 / ストレージ移行**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` により旧バージョン設定を自動変換。既存ファイルを Source として登録できる
- **バックアップと安全な書き込み**: `FileResource` はアトミック書き込みとバックアップ世代管理（既定で `.bak` 1 世代、`RestoreLatestBackupAsync` で復元）。競合検出とリトライも備える
- **セクション**: `JsonSectionResource` / XML 要素 / YAML マッピングでファイルの一部を独立した Resource として扱え、書き込み時にコメント・空白・引用・スカラー形式を保持する。同じファイル内の独立セクションは 1 回の物理書き込みにバッチされる
- **リモート / 圧縮リソース**: `ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込み・ポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`
- **JSON Schema 生成**: `Configlue.JsonSchema` により、人間が設定を書くためのスキーマを生成・エクスポートできる
- **Native AOT 対応**: ソース生成の `JsonSerializerContext` を渡すとトリミング/AOT に強くなる
- **リアクティブ統合（任意）**: `Configlue.Extensions.Reactive`（System.Reactive）と `Configlue.Extensions.R3` で `ObserveChanges()` / `ObserveValues()` / `ObserveReloadFailures()` などが使える
- **DI 統合**: `Configlue.Extensions.DI` と、Microsoft の options アダプター `Configlue.Extensions.MSOptions`（`IOptions<T>` など。同期ゲッターは非同期ソース読み取り中にブロックするため、非同期フローでは `GetValueAsync` 推奨）
- **プロファイル / 動的オプション**: 名前付きオプションや永続プロファイルをランタイム単位で作成・削除できる
- **暗号化**: `Configlue.Transformer.AES` が Resource と Codec の間のバイトを AES-GCM で暗号化・認証する

既知の制限として、異なる Resource 間の書き込みはアトミックではなく、Source の退役は現在の options インスタンスに閉じられ実データは残り、Source 集合は options ランタイムで固定されます。

パッケージは `Configlue`（ユーザー向けメタパッケージ）を中心に、契約の `Configlue.Abstraction`、ランタイムの `Configlue.Core`、プロバイダー SDK の `Configlue.Extensibility`、Roslyn アナライザーの `Configlue.Generator`、テスト用の `Configlue.Testing`、各形式の `Configlue.Provider.Json` / `.Xml` / `.Yaml` などに分かれています。まずはメタパッケージをインストールし、必要な機能パッケージを追加するのが基本です。

## 基本的な使い方

インストールは `dotnet add package Configlue` から行います。以下は公式 README の Quick Start で、`example.cs` に保存して `dotnet run example.cs` で実行できます（.NET 10 以降）。

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

流れは 3 段階です。`[ConfiglueModel]` を付けた partial クラスで設定モデルを宣言すると、ジェネレーターが Fragment / Patch サポートを生成します。`UseCommonSources` で有効にする層（グローバル、ローカル、環境変数）を宣言し、アプリは `GetOptions<T>()` で得た options インスタンスを通して読み書きします。`SaveAsync` はパッチ形式で、変更したメンバーだけを対象層に保存します。

各値がどこから来たかを調べるには `GetDetailsAsync` を使います。

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

`Unset()` を使うと、書き込み先 Source の寄与だけを取り消し、下位優先度の値を再び見せることができます。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

そのほか、日常の読み取り面は `IReadOnlyOptions<T>` の `GetValueAsync` と `OnChange`、複数変更のまとめて適用は `OpenEditSessionAsync()` と `CommitAsync`、明示的なソース別マルチ書き込みは `ApplyPatchesAsync` + `StateSourcePatch`、書き込みルーティングは `StateWritePlan.For<T>().Route(...)`、ソース単位の操作は `SourceKey<TModel>` と `options.Source(key)` で行えます。

---

# ===== opencode-go/qwen3.8-max =====

# Configlue

## 概要

Configlue は、アプリケーションの設定管理を代行する .NET ライブラリです。キャッチコピーは "Make easy configuration management."。

複数の場所に散らばった設定を 1 つのモデルに **結合（glue）** するのが中心的な考え方で、名前も configuration + glue に由来します。

- 対象: .NET 10 SDK 以降、C#（ソースジェネレーターを利用するため対応する `LangVersion` が必要。リポジトリは preview でビルドしています）
- ライセンス: Apache-2.0
- 現状は「アーキテクチャ上の土台」であり、`Configuration.Writable` を完全に置き換えるものではありません

`Microsoft.Extensions.Configuration` との違いとしては、`IConfiguration` が読み取り中心なのに対し、Configlue は独立した複数のソースの合成、値の来歴の検査、スパースな保存といった用途に向いています。

### なぜ Configlue が必要か

JSON ファイルの読み書きだけなら数行で済みます。しかし実際には、次のような要件が積み重なっていきます。

- 設定が複数箇所にある: グローバル設定、実行フォルダー設定、環境変数、コマンドライン引数、暗号化された資格情報、社内ポリシーや HTTP API などのリモート管理
- 設定ファイルが書き換わったら、再起動なしで反映したい（変更通知）
- 書き込み先を自動で選びたい。環境変数から読んだ値への書き込みはエラーにしたい
- 設定ファイルは人間が書く: コメントを消さない、JSON Schema がほしい、壊れたファイルへの対処が必要
- 既定値のままなら書き出さない（ただしユーザーが明示した `null` は尊重する）
- 設定ファイルのバージョンアップ（旧形式 → 新形式への自動変換）
- バックアップと自動整理
- 書き込みの安全性: アトミック性（クラッシュしても壊れない）、他プロセスとの競合検出・自動マージ、自動リトライ

これらを自前で実装するのは面倒です。Configlue はこの部分を担います。

### 基本アーキテクチャ

Configlue は 6 つの概念で構成されます。依存関係は直線的で、学習順も同じです。

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

**読み込み**は、各 Source が Resource からバイトを取得し、Codec が Fragment に変換します。ランタイムが優先度順に「存在する」フィールドだけを 1 つのモデルへ重ねます。

**書き込み**はその逆向きです。アプリは普通のモデル値を編集するだけで、内部では変更が Fragment 差分になり、`WriteRoute` / `WritePlan` が指す Source にだけ届きます。無関係な Source は変更されません。

- Fragment は「メンバーが存在しない」ことと「null / 既定値で存在する」ことを区別します。層の合成で「未設定」が「既定値に設定」を上書きすることはありません。
- Patch は生成される `TModel.Patch`（単一フィールドの編集フラグメント）です。`Unset()` は書き込み先 Source の寄与だけを取り消し、下位優先度の値を再び見えるようにします。
- `[ConfiglueMerge]` でメンバーごとのマージ挙動を変更できます（組み込みは `Append`、`Deep`、`Replace`、`SetUnion`。カスタム戦略も可能）。コレクションの層合成と順序はここで決まります。

## 主な特徴

- **複数ソースの優先度マージ**: `Priority` が大きい Source が勝ちます。`GetDetailsAsync` で「どの値がどこ由来か」を検査できます。
- **読み取り専用ソース**: 環境変数・コマンドライン・既定の HTTP ソースは読み取り専用です。読み取り専用の値への書き込みは、黙って無視されず競合エラーになります。
- **プロジェクション / マウント**: 既存の Source を別モデルに整形（projection）したり、ネストしたパスに別の Source を接続（mount、`AddMounted`）できます。
- **プリセット**: `UseCommonSources` が標準的な層構成（global / local / environment など）を組み立てます。
- **スパース書き込み**: 変更したフィールドだけを対象層に保存します。既定値のままのフィールドは書き込まれません。
- **編集セッション**: `OpenEditSessionAsync` で複数の変更をまとめて適用し、`CommitAsync` までインメモリで保持します。競合時は既定で失敗しますが、`WriteConflictResolution.LastWriteWins` も選べます。
- **スキーマ移行 / ストレージ移行**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` により、旧バージョンの設定を自動変換します。既存ファイルを Source として登録することもできます。
- **バックアップと復元**: `FileResource` はアトミックな書き込みとバックアップ世代管理を行います。既定では `.bak` を 1 世代保持し、`RestoreLatestBackupAsync` で復元します。
- **安全な書き込み**: アトミック性、競合検出、リトライを備えます。
- **セクション**: `JsonSectionResource` / XML 要素 / YAML マッピングにより、ファイルの一部を独立した Resource として扱えます。書き込み時はコメント・空白・引用・スカラー形式を保持します。同じファイル内の独立したセクションは、1 回の物理書き込みにバッチされます。
- **ZIP / HTTP / S3 / Dapr**: `ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込み・ポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr` を提供します。
- **JSON Schema 生成**: `Configlue.JsonSchema`。人間が設定ファイルを書くための支援です。
- **Native AOT 対応**: ソース生成の `JsonSerializerContext` を渡すと、トリミングや AOT に強くなります。
- **リアクティブ統合（任意）**: `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）。`ObserveChanges()`、`ObserveValues()`、`ObserveReloadFailures()`、`ObserveActiveValues()`、`ObserveActiveProfileNames()` が利用できます。
- **DI 統合**: `Configlue.Extensions.DI`。Microsoft の options アダプターとして `Configlue.Extensions.MSOptions`（`IOptions<T>` など）も用意しています。同期ゲッターは非同期ソースの読み取り中はブロックするため、非同期フローでは `GetValueAsync` の利用を推奨します。
- **プロファイル / 動的オプション**: 名前付きオプションや永続プロファイルを、ランタイムを単位に作成・削除できます。

### 既知の制限

- 異なる Resource 間の書き込みはアトミックではありません。
- Source の退役は現在の options インスタンスに閉じており、実データは残ります。
- Source の集合は options ランタイムで固定されます。

## 基本的な使い方

### パッケージ構成

| パッケージ | 内容 |
| --- | --- |
| `Configlue` | ユーザー向けメタパッケージ。Core / DI / JSON provider / JSON Schema / HTTP resources / common sources / environment source / generator analyzer を同梱し、実装アセンブリは持ちません |
| `Configlue.Abstraction` | 契約（provider / codec / resource / generated-model） |
| `Configlue.Core` | 解決と永続化のランタイム |
| `Configlue.Extensibility` | プロバイダー SDK |
| `Configlue.Extensions.DI` / `.MSOptions` / `.R3` / `.Reactive` | DI・options アダプター・リアクティブ統合 |
| `Configlue.Generator` | Roslyn アナライザー（スパースなモデルサポートの生成） |
| `Configlue.Testing` | インメモリのテストダブル |
| `Configlue.Provider.Json` / `.Xml` / `.Yaml` | 各形式の Codec、セクションリソース、ファイル登録 |
| `Configlue.JsonSchema` | JSON Schema の生成・エクスポート |
| `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml` | ソース実装とプリセット |
| `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip` | リソース実装 |
| `Configlue.Transformer.AES` | Resource と Codec の間のバイトを AES-GCM で暗号化・認証 |

インストールは次のコマンドから行い、必要な機能パッケージを追加していきます。

```bash
dotnet add package Configlue
```

### Quick Start

次のコードを `example.cs` に保存し、`dotnet run example.cs` で実行できます（.NET 10 以降）。

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

### 値の由来を調べる

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

### スパース保存

指定したメンバーだけを更新するパッチを保存します。`Unset()` はその Source の寄与を外し、下位優先度の Source が値を提供できるようにします。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

### その他の API

- `IReadOnlyOptions<T>` … 日常の読み取り面は `GetValueAsync` と `OnChange`
- `SaveAsync(patch => ...)` … 生成された Patch によるスパース保存
- `OpenEditSessionAsync()` … まとめて編集し `CommitAsync`
- `ApplyPatchesAsync` + `StateSourcePatch` … 明示的なソース別マルチ書き込み
- `StateWritePlan.For<T>().Route(...)` … 書き込みルーティング
- `SourceKey<TModel>` と `options.Source(key)` … ソース単位の操作

---

# ===== opencode-go/space-bunny-free =====

# Configlue

Make easy configuration management.

Configlue は .NET アプリケーションの設定管理を代行するライブラリです。グローバル設定、実行フォルダーの設定、環境変数、コマンドライン引数、リモート管理など、设立了まま散らばった設定を一つのモデルに**結合（glue）** します。

- 対象: .NET 10 SDK 以降
- ライセンス: Apache-2.0
- インストール: `dotnet add package Configlue`（必要に応じて機能パッケージを追加）

# 主な特徴

## 6 つの概念

依存関係は直線的で、この順で学習できます。

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

読み込みは、各 Source が Resource からバイトを取得し、Codec が Fragment に変換、ランタイムが優先度順に「存在する」フィールドだけを 1 つのモデルへ重ねる流れです。書き込みは逆向きで、アプリが通常のモデル値を編集すると、内部では Fragment 差分になり、`WriteRoute` / `WritePlan` が指す Source にだけ届きます。無関係な Source は変更されません。

Fragment は「メンバーが存在しない」と「null や既定値で存在する」を区別します。そのため層の合成で「未設定」が「既定値に設定」を上書きすることはありません。`Unset()` は書き込み先 Source の寄与だけを取り消し、下位優先度の値を再び見せます。メンバーごとのマージ挙動は `[ConfiglueMerge]` で指定でき、組み込みの `Append` / `Deep` / `Replace` / `SetUnion` に加えてカスタム戦略も使えます。

## 優先度マージと来歴の検査

`Priority` が大きい Source が勝ちます。`GetDetailsAsync` で「どの値がどこから来たか」を調べられます。読み取り専用の Source（環境変数、コマンドライン、既定の HTTP ソース）への書き込みは黙って無視されず、競合エラーになります。

## 人間が書く設定ファイルへの配慮

設定ファイルは人間が書くものです。`JsonSectionResource` / XML 要素 / YAML マッピングを使えば、ファイルの一部を独立した Resource として扱えます。書き込み時にコメント・空白・引用・スカラー形式が保持され、同じファイル内の独立セクションは 1 回の物理書き込みにバッチされます。`Configlue.JsonSchema` で JSON Schema も生成できます。壊れたファイルの扱いも扱いの対象です。

## スパース書き込み

変更したフィールドだけが対象層に保存されます。既定値のままのフィールドは書き出されません（ユーザーが明示した `null` は尊重されます）。スパースなモデルサポートは `Configlue.Generator`（Roslyn アナライザー）が生成します。

## 変更通知と編集セッション

設定ファイルが書き換わったら再起動なしで反映されます。複数変更をまとめたい場合は `OpenEditSessionAsync` で編集セッションを開き、`CommitAsync` までインメモリで扱います。競合時は既定で失敗し、`WriteConflictResolution.LastWriteWins` も選べます。R3（`Configlue.Extensions.R3`）と System.Reactive（`Configlue.Extensions.Reactive`）向けの拡張もあり、`ObserveChanges()` / `ObserveValues()` / `ObserveReloadFailures()` / `ObserveActiveValues()` / `ObserveActiveProfileNames()` が使えます。

## 安全な書き込みとバックアップ

書き込みはアトミックで、他プロセスとの競合検出と自動リトライを行います。`FileResource` はアトミック書き込みとバックアップ世代管理を扱い、既定で `.bak` 1 世代を保持し、`RestoreLatestBackupAsync` で復元できます。

## バージョン移行とストレージの多様性

`[ConfigluePreviousVersion]` と `Fragment.FromPrevious` により、旧バージョンの設定を新形式へ自動変換できます。既存ファイルを Source として登録することもできます。

Resource は ZIP（`ZipEntryResource`）、HTTP（`Configlue.Resource.Http`。ETag 条件付き書き込み・ポーリングに対応）、S3（`Configlue.Resource.S3`）、Dapr（`Configlue.Resource.Dapr`）.Left に.extends。`Configlue.Transformer.AES` は Resource と Codec の間のバイトを AES-GCM で暗号化・認証します。

## プロジェクション・マウント・プリセット

既存 Source を別モデルに整形する projection や、ネストしたパスに別 Source を接続する mount（`AddMounted`）ができます。`UseCommonSources` は global / local / environment などの標準的な層構成を組み立てるプリセットです。

## DI 連携とプロファイル

`Configlue.Extensions.DI` で DI に統合できます。Microsoft の options アダプターが `Configlue.Extensions.MSOptions` で提供されており、`IOptions<T>` などを利用できます。同期ゲッターは非同期ソースの読み取り中にブロックするため、非同期フローでは `GetValueAsync` の利用を推奨します。名前付きオプションや永続プロファイルにより、ランタイム単位で options を作成・削除できます。

Native AOT に対応しており、ソース生成の `JsonSerializerContext` を渡すとトリミング / AOT に強くなります。

## `Microsoft.Extensions.Configuration` との違い

`IConfiguration` は読み取りを中心に設計されています。Configlue は独立した複数ソースの合成、来歴の検査、スパース保存に向いています。現状はアーキテクチャ上の土台であり、`Configuration.Writable` を完全に置き換えるものではありません。

## パッケージ構成

| パッケージ | 役割 |
| --- | --- |
| `Configlue` | ユーザー向けメタパッケージ（Core / DI / JSON provider / JSON Schema / HTTP resources / common sources / environment source / generator analyzer を同梱。実装アセンブリは持たない） |
| `Configlue.Abstraction` | 契約（provider / codec / resource / generated model） |
| `Configlue.Core` | 解決と永続化のランタイム |
| `Configlue.Extensibility` | プロバイダー SDK |
| `Configlue.Generator` | スパースなモデルサポートを生成する Roslyn アナライザー |
| `Configlue.Testing` | インメモリのテストダブル |
| `Configlue.Provider.Json` / `.Xml` / `.Yaml` | 各形式の Codec・セクションリソース・ファイル登録 |
| `Configlue.JsonSchema` | JSON Schema の生成・エクスポート |
| `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml` | 各種の Source・プリセット |
| `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip` | 各種の Resource |
| `Configlue.Transformer.AES` | AES-GCM によるバイト列の暗号化・認証 |
| `Configlue.Extensions.DI` / `.MSOptions` / `.R3` / `.Reactive` | 各-framework 連携 |

## 既知の制限

- 異なる Resource 間の書き込みはアトミックではありません。
- Source の退役は現在の options インスタンスに閉じるだけで、実データは残ります。
- Source 集合は options ランタイムで固定です。

# 基本的な使い方

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

## 値の由来を調べる

`GetValueAsync` は全ソースをマージした現在値を返します。`GetDetailsAsync` を使うと、各値がどの Source から来たかと書き換え可能かどうかを調べられます。

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

## その他の API

- `IReadOnlyOptions<T>` … 日常的な読み取り面は `GetValueAsync` と `OnChange`。
- `SaveAsync(patch => ...)` … 生成された Patch によるスパース保存。
- `OpenEditSessionAsync()` … 変更をまとめて編集し、`CommitAsync` で適用。
- `ApplyPatchesAsync` + `StateSourcePatch` … 明示的なソース別のマルチ書き込み。
- `StateWritePlan.For<T>().Route(...)` … 書き込みルーティング。
- `SourceKey<TModel>` と `options.Source(key)` … ソース単位の操作。

---

# ===== opencode/big-pickle =====

# Configlue

**Make easy configuration management.**

Configlue は、アプリケーションの設定管理を代行する .NET ライブラリです。グローバル設定、実行フォルダーの設定、環境変数、コマンドライン引数、暗号化された資格情報、そして社内ポリシーや HTTP API のようなリモート管理まで——_settings が あちこちに散らばっている_ 状況を、1 つのモデルに**結合（glue）** します。名前の由来も configuration + glue です。

JSON ファイルを読み書きするだけなら数行で済みます。しかし実用的な設定管理では、その裏に「設定ファイルが書き換わったら再起動なしで反映したい」「書き込み先は自動で選びたい、環境変数から読んだ値への書き込みはエラーにしたい」「設定ファイルは人間が書くのでコメントを消したくない、JSON Schema .transfer ほしい」「既定値のままなら書き出したくない」「旧形式から新形式へ自動移行したい」「バックアップとアトミック書き込み、競合検出とリトライが必要」といった要件が積み重なります。Configlue はそれらを自前実装せずに済ませられるよう、アーキテクチャの土台を提供します。

- 対象: .NET 10 SDK 以降
- ライセンス: Apache-2.0
- 現状はアーキテクチャ上の土台であり、`Configuration.Writable` を完全に置き換えるものではありません

## 主な特徴

### 独立した 6 つの概念

設定の流れは直線的で、このまま学習順になっています。

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

**読み込み**は、各 Source が Resource からバイトを取得し、Codec が Fragment に変換します。ランタイムは優先度順に「存在する」フィールドだけを 1 つのモデルへ重ねます。

**書き込み**は逆向きです。アプリは普通のモデル値を編集し、内部では変更が Fragment の差分になり、`WriteRoute` / `WritePlan` が指す Source にだけ届きます。無関係な Source は変更されません。

Fragment は「メンバーが存在しない」と「null や既定値で存在する」を区別します。そのため層の合成で「未設定」が「既定値に設定」を上書きすることはありません。生成される `TModel.Patch` は単一フィールドの編集フラグメントで、`Unset()` を呼ぶと書き込み先 Source の寄与だけを取り消し、下位優先度の値を再び見せられます。`[ConfiglueMerge]` でメンバーごとのマージ挙動を変更でき、組み込みの戦略は `Append`, `Deep`, `Replace`, `SetUnion` です（カスタム戦略も可）。コレクションの層合成と順序はここで決まります。

### 複数ソースの優先度マージと来歴の検査

`Priority` が大きい Source が勝ちます。`GetDetailsAsync` を使えば、「どの値がどこから来たのか」を検査できます。読み取り専用ソース（環境変数・コマンドライン・既定の HTTP ソース）への書き込みは黙って無視されず、競合エラーになります。

### スパース書き込みと編集セッション

変更したフィールドだけが対象層に保存されます。既定値のままのフィールドは書かれません（ユーザーが明示した `null` は尊重されます）。`OpenEditSessionAsync` を使えば、複数変更をまとめて，`CommitAsync` までインメモリで扱えます。競合時は既定で失敗しますが、`WriteConflictResolution.LastWriteWins` も選べます。

### 人間のために設計された設定ファイル

`JsonSectionResource` / XML 要素 / YAML マッピングを使うと、ファイルの一部を独立した Resource として扱えます。書き込み時にコメント・空白・引用・スカラー形式を保持し、同じファイル内の独立セクションは 1 回の物理書き込みにバッチされます。`Configlue.JsonSchema` で JSON Schema を生成でき、`[ConfigluePreviousVersion]` と `Fragment.FromPrevious` による旧バージョン設定の自動変換や、既存ファイルの Source 登録anstieg major玩法にも VPNs.. [correcting]…

### バックアップと安全な書き込み

`FileResource` はアトミック書き込みとバックアップ世代管理を備え、既定で `.bak` 1 世代を保持します。`RestoreLatestBackupAsync` で復元できます。書き込みはアトミック性・競合検出・リトライで保護されます。

### プロジェクション、マウント、プリセット

既存 Source を別モデルに整形する projection や、ネストしたパスに別 Source を接続する mount（`AddMounted`）が可能です。`UseCommonSources` は global / local / environment などの標準的な層構成を組み立てます。断面として有効なのは、ここに挙げたソースだけです。

### リモートと暗号化リソース

`ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込み・ポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr` が利用できます。`Configlue.Transformer.AES` は Resource と Codec の間のバイトを AES-GCM で暗号化・認証します。

### 統合とパイプライン

- **Native AOT**: ソース生成の `JsonSerializerContext` を渡すとトリミング/AOT に強くなります
- **リアクティブ（任意）**: `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）、`Configlue.Extensions.R3`（R3 1.3.1）。`ObserveChanges()`, `ObserveValues()`, `ObserveReloadFailures()`, `ObserveActiveValues()`, `ObserveActiveProfileNames()`
- **DI**: `Configlue.Extensions.DI`、および Microsoft の options アダプター `Configlue.Extensions.MSOptions`（`IOptions<T>` など）。同期ゲッターは非同期ソース読み取り中にブロックするため、非同期フローでは `GetValueAsync` を推奨します
- **プロファイル / 動的オプション**: 名前付きオプションや永続プロファイルで、ランタイムを単位に作成・削除できます
- **テスト**: `Configlue.Testing` にインメモリのテストダブルがあります

### 既知の制限

異なる Resource 間の書き込みはアトミックではありません。Source の退役は現在の options インスタンスに閉じ、実データは残ります。Source 集合は options ランタイムで固定です。

### `Microsoft.Extensions.Configuration` との違い

`IConfiguration` は読み取りを中心にした API です。Configlue は、独立したソースの合成・来歴の検査・スパース保存，面向しています。

### パッケージ構成

まず `dotnet add package Configlue` でユーザー向けメタパッケージを入れ、必要な機能パッケージを追加します（メタパッケージは実装アセンブリを持ちません）。

- `Configlue` … メタパッケージ。Core / DI / JSON provider / JSON Schema / HTTP resources / common sources / environment source / generator analyzer を同梱
- `Configlue.Abstraction` … 契約（provider / codec / resource / generated-model）
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

## 基本的な使い方

`example.cs` に保存し、`dotnet run example.cs` で実行してください（.NET 10 以降）。

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

### 値の由来を調べる

`GetValueAsync` で全ソースをマージした現在値を取得し、`GetDetailsAsync` で各値の由来を調べられます。

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

### スパース保存

指定したメンバーだけを更新するパッチを保存します。`Unset()` はその Source の寄与を外し、下位優先度の Source が値を提供できるようにします。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

### 主な API

- `IReadOnlyOptions<T>` … 日常の読み取り面は `GetValueAsync` と `OnChange`
- `SaveAsync(patch => ...)` … 生成 Patch でスパース保存
- `OpenEditSessionAsync()` … まとめて編集し `CommitAsync`
- `ApplyPatchesAsync` + `StateSourcePatch` … 明示的なソース別マルチ書き込み
- `StateWritePlan.For<T>().Route(...)` … 書き込みルーティング
- `SourceKey<TModel>` と `options.Source(key)` … ソース単位の操作

---

# ===== opencode/ling-3.0-flash-fin-free =====

# Configlue

**Make easy configuration management.**

Configlue は、アプリケーションの設定管理を代行する .NET ライブラリです。複数の場所に散らばった設定を 1 つのモデルにまとめる（glue する）のが中心的な考え方であり、名前も configuration + glue に由来します。.NET 10 SDK 以降を対象とし、Apache-2.0 ライセンスの下で公開されています。

# 主な特徴

## 複数ソースの優先度マージ

設定はグローバルファイル、実行フォルダー、環境変数、コマンドライン引数、リモート HTTP API など複数の場所に存在しえます。各 Source には優先度（Priority）があり、大きいほうが勝ちます。`GetDetailsAsync` を呼べば、「どの値がどこ由来か」を検査できます。

## 読み取り専用ソースと書き込み保護

環境変数・コマンドライン・既定の HTTP ソースは読み取り専用です。読み取り専用の値への書き込みは黙って無視されるのではなく、競合エラーとして通知されます。環境変数から読んだ値への書き込みが原因で設定が意図せず上書きされることを防ぎます。

## スパース書き込み

変更したフィールドだけを対象層に保存します。既定値のままのフィールドは書き出されず、ユーザーが明示的に `null` を指定した場合は尊重されます。これにより、不要な設定の破壊を防ぎます。

## 編集セッションと安全な書き込み

`OpenEditSessionAsync` で複数の変更をまとめ、`CommitAsync` までインメモリで保持できます。競合が発生した場合は既定で失敗し、`WriteConflictResolution.LastWriteWins` を選択することも可能です。`FileResource` はアトミック書き込みとバックアップ世代管理を扱い、`.bak` ファイルによる復元（`RestoreLatestBackupAsync`）が可能です。

## スキーマ移行とセクション

`[ConfigluePreviousVersion]` と `Fragment.FromPrevious` により、旧形式の設定を自動的に新形式に変換できます。`JsonSectionResource`・XML 要素・YAML マッピングでは、ファイルの一部を独立した Resource として扱え、書き込み時にコメント・空白・引用・スカラー形式を保持します。

## プロジェクション、マウント、プロファイル

既存の Source を別モデルに整形（projection）したり、ネストしたパスに別 Source を接続（mount）できます。`UseCommonSources` により、global / local / environment などの標準的な層構成を組み立てられます。名前付きオプションや永続プロファイルで、ランタイムを単位にした作成・削除が可能です。

## JSON Schema と Native AOT 対応

`Configlue.JsonSchema` により、人間が設定ファイルを記述するための JSON Schema を生成できます。ソース生成の `JsonSerializerContext` を渡すことで、トリミングや Native AOT ビルドに強くなります。

## リアクティブ・DI 統合

`Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）により、`ObserveChanges()`、`ObserveValues()`、`ObserveReloadFailures()` などのリアクティブ API が利用できます。`Configlue.Extensions.DI` と `Configlue.Extensions.MSOptions` により、Microsoft の `IOptions<T>` アダプターで DI 統合が可能です。非同期フローでは `GetValueAsync` の使用を推奨します。

# 基本的な使い方

## インストール

```
dotnet add package Configlue
```

必要に応じて機能パッケージを追加してください。

## モデルの定義

ソースジェネレーターにより、モデルに Fragment / Patch のサポートを自動生成させます。

```csharp
[ConfiglueModel("SampleSetting", Version = 1)]
public partial class SampleSetting
{
    public string Name { get; set; } = "World";
    public int RunCount { get; set; }
    public bool DefaultValue { get; set; } = true;
}
```

## コンテキストとプリセットの構成

`UseCommonSources` で標準的な層構成を組み立てます。

```csharp
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);
```

## 読み取りと書き込み

`GetOptions<T>` で取得した `Options` インスタンスを通じて、読み取りと書き込みを行います。

```csharp
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

## 値の由来の確認とスパース保存

`GetDetailsAsync` で各値の由来や書き込み可否を検査できます。`Unset()` を使うと、特定の Source の寄与を取り消し、下位優先度の Source が値を提供できるようにします。

```csharp
var details = await options.GetDetailsAsync();
Console.WriteLine($"Name came from {details.Name.Source?.Locator}");
Console.WriteLine($"Can write Name? {details.Name.IsEditable}");

await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

---

# ===== opencode/longcat-2.5-preview-free =====

# Configlue

## 概要

Configlue は、アプリケーションの設定管理（configuration management）を代行する .NET ライブラリです。キャッチコピーは "Make easy configuration management."。

複数の場所に散らばった設定を 1 つのモデルに**結合（glue）**するのが中心的な考え方で、名前も configuration + glue に由来します。

JSON ファイルの読み書きだけなら数行で済みますが、実際には次のような要件が積み重なります。

- 設定が複数箇所にある: グローバル設定、実行フォルダー設定、環境変数、コマンドライン引数、暗号化された資格情報、社内ポリシーや HTTP API などのリモート管理
- 設定ファイルが書き換わったら再起動なしで反映したい（変更通知）
- 書き込み先を自動で選びたい。環境変数から読んだ値への書き込みはエラーにしたい
- 設定ファイルは人間が書く: コメントを消さない、JSON Schema がほしい、壊れたファイルへの対処
- 既定値のままなら書き出さない（ただしユーザーが明示した `null` は尊重する）
- 設定ファイルのバージョンアップ（旧形式→新形式への自動変換）
- バックアップと自動整理
- 書き込みの安全性: アトミック性（クラッシュしても壊れない）、他プロセスとの競合検出・自動マージ、自動リトライ

これらを自前実装するのは面倒、というのが Configlue の動機です。

対象は .NET 10 SDK 以降、ライセンスは Apache-2.0 です。

`Microsoft.Extensions.Configuration` の `IConfiguration` は読み取り中心の API ですが、Configlue は独立したソースの合成、値の来歴の検査、スパース保存に向いています。

## 主な特徴

### 6 つの基本概念

Configlue の依存関係は直線的で、学習順も同じです。

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

Fragment は「メンバーが存在しない」と「null/既定値で存在する」を区別します。層の合成で「未設定」が「既定値に設定」を上書きすることはありません。

Patch は生成される `TModel.Patch`（単一フィールドの編集フラグメント）です。`Unset()` は書き込み先 Source の寄与だけを取り消し、下位優先度の値を再び見せます。

`[ConfiglueMerge]` でメンバーごとのマージ挙動を変更できます（組み込み: `Append`, `Deep`, `Replace`, `SetUnion`、カスタム戦略も可）。コレクションの層合成・順序はここで決まります。

### 複数ソースの優先度マージ

`Priority` が大きい Source が勝ちます。`GetDetailsAsync` で「どの値がどこ由来か」を検査できます。

### 読み取り専用ソース

環境変数・コマンドライン・既定の HTTP ソースは読み取り専用です。読み取り専用の値への書き込みは黙って無視せず、競合エラーになります。

### スパース書き込み

変更したフィールドだけを対象層に保存します。既定値のままのフィールドは書かれません。

### 編集セッション

`OpenEditSessionAsync` で複数変更をまとめて適用できます。`CommitAsync` までインメモリです。競合時は既定で失敗し、`WriteConflictResolution.LastWriteWins` も選べます。

### セクション

`JsonSectionResource` / XML 要素 / YAML マッピングで、ファイルの一部を独立した Resource として扱えます。書き込み時はコメント・空白・引用・スカラー形式を保持します。同じファイル内の独立セクションは 1 回の物理書き込みにバッチされます。

### バックアップと復元

`FileResource` はアトミック書き込みとバックアップ世代管理を行います。既定で `.bak` 1 世代、`RestoreLatestBackupAsync` で復元できます。

### スキーマ移行 / ストレージ移行

`[ConfigluePreviousVersion]` と `Fragment.FromPrevious` による旧バージョン設定の自動変換が可能です。既存ファイルを Source として登録できます。

### プロジェクション / マウント

既存 Source を別モデルに整形（projection）したり、ネストしたパスに別 Source を接続（mount, `AddMounted`）できます。

### プリセット

`UseCommonSources` が標準的な層構成（global/local/environment など）を組み立てます。

### 多様なリソース

ZIP / HTTP / S3 / Dapr をサポートします。`ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込み・ポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr` があります。

### JSON Schema 生成

`Configlue.JsonSchema` で JSON Schema を生成・エクスポートできます。人間が設定を書くための機能です。

### Native AOT 対応

ソース生成の `JsonSerializerContext` を渡すと、トリミング/AOT に強くなります。

### リアクティブ統合（任意）

`Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）があります。`ObserveChanges()`, `ObserveValues()`, `ObserveReloadFailures()`, `ObserveActiveValues()`, `ObserveActiveProfileNames()` が利用できます。

### DI 統合

`Configlue.Extensions.DI` と、Microsoft の options アダプター `Configlue.Extensions.MSOptions`（`IOptions<T>` など）があります。同期ゲッターは非同期ソース読み取り中ブロックするため、非同期フローでは `GetValueAsync` の使用が推奨されます。

### プロファイル / 動的オプション

名前付きオプションや永続プロファイルで、ランタイムを単位に作成・削除できます。

### 既知の制限

- 異なる Resource 間の書き込みはアトミックではない
- Source の退役は現在の options インスタンスに閉じ、実データは残る
- Source 集合は options ランタイムで固定

### パッケージ構成

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

## 基本的な使い方

### Quick Start

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

### 値の由来を調べる

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

### スパース保存

指定したメンバーだけを更新するパッチを保存します。`Unset()` はその Source の寄与を外し、下位優先度の Source が値を提供できるようにします。

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

### インストール

```bash
dotnet add package Configlue
```

必要な機能パッケージを追加してください。

---

# ===== opencode/mimo-v2.6-flash-free =====

## 概要

Configlue は、アプリケーションの設定管理を代行する .NET ライブラリです。「Make easy configuration management.」を掲げ、複数の場所に散らばった設定を 1 つのモデルに結合（glue）することを目的としています（名前も configuration + glue に由来します）。

対象は .NET 10 SDK 以降、ライセンスは Apache-2.0 です。

JSON ファイルの読み書きだけなら数行で済みます。しかし実際の設定管理には、次のような要件が積み重なります。

- 設定が複数箇所にある（グローバル設定、実行フォルダー、環境変数、コマンドライン引数、暗号化された資格情報、社内ポリシーや HTTP API などのリモート管理）
- ファイルが書き換わったら再起動なしで反映したい
- 書き込み先を自動で選びたい（環境変数から読んだ値への書き込みはエラーにしたい）
- 人間が設定ファイルを書く前提で、コメントを消さず JSON Schema もほしい
- 既定値のままなら書き出さない
- 設定ファイルのバージョンアップ（旧形式→新形式への自動変換）
- バックアップと自動整理
- 書き込みの安全性（アトミック性、他プロセスとの競合検出・自動マージ、自動リトライ）

これらを自前実装するのは面倒です。Configlue はそのためのアーキテクチャ上の土台として設計されています。現状は `Configuration.Writable` を完全に置き換えるものではありません。

なお、既存の `Microsoft.Extensions.Configuration` との違いとしては、`IConfiguration` が読み取り中心なのに対し、Configlue は独立したソースの合成、値の来歴の検査、スパース保存に向いています。

## 主な特徴

**基本アーキテクチャ**

設定は 6 つの概念で構成され、依存関係と学習順は直線的です。

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

読み込みでは、各 Source が Resource からバイトを取得し、Codec が Fragment に変換します。ランタイムが優先度順に「存在する」フィールドだけを 1 つのモデルへ重ねます。書き込みはその逆で、アプリは普通のモデル値を編集するだけで、内部の変更が Fragment 差分になり、書き込み先の Source にだけ届きます。無関係な Source は変更されません。

Fragment は「メンバーが存在しない」と「null/既定値で存在する」を区別するため、層の合成で「未設定」が「既定値に設定」を上書きすることはありません。

**主な機能**

- **複数ソースの優先度マージ**: `Priority` が大きい Source が勝ち、`GetDetailsAsync` で「どの値がどこ由来か」を検査できます。
- **読み取り専用ソース**: 環境変数・コマンドライン・既定の HTTP ソースは読み取り専用。読み取り専用の値への書き込みは黙って無視せず、競合エラーになります。
- **スパース書き込み**: 変更したフィールドだけを対象層に保存し、既定値のままのフィールドは書きません。
- **編集セッション**: `OpenEditSessionAsync` で複数変更をまとめて適用し、`CommitAsync` までインメモリで保持します。
- **スキーマ移行 / ストレージ移行**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` による旧バージョン設定の自動変換。
- **バックアップと安全な書き込み**: `FileResource` がアトミック書き込みとバックアップ世代管理（既定で `.bak` 1 世代、`RestoreLatestBackupAsync` で復元）を担い、競合検出・リトライも備えます。
- **セクション**: `JsonSectionResource` / XML 要素 / YAML マッピングで、ファイルの一部を独立した Resource として扱えます。書き込み時はコメント・空白・引用・スカラー形式を保持し、同一ファイル内の独立セクションは 1 回の物理書き込みにバッチされます。
- **プロジェクション / マウント**: 既存 Source を別モデルに整形したり、ネストしたパスに別 Source を接続（`AddMounted`）できます。
- **プリセット**: `UseCommonSources` が global / local / environment などの標準的な層構成を組み立てます。
- **JSON Schema 生成**: `Configlue.JsonSchema` により、人間が設定を書きやすい形を用意できます。
- **Native AOT 対応**: ソース生成の `JsonSerializerContext` を渡すと、トリミング / AOT に強くなります。
- **リアクティブ統合（任意）**: `Configlue.Extensions.Reactive`（System.Reactive）と `Configlue.Extensions.R3` で、変更や値のストリームを購読できます。
- **DI 統合**: `Configlue.Extensions.DI` と、Microsoft の options アダプターである `Configlue.Extensions.MSOptions`（`IOptions<T>` など）を提供します。同期ゲッターは非同期ソースの読み取り中にブロックするため、非同期フローでは `GetValueAsync` の利用を推奨します。
- **暗号化**: `Configlue.Transformer.AES` で、Resource と Codec の間のバイトを AES-GCM により暗号化・認証できます。

パッケージは `dotnet add package Configlue` から導入でき、`Configlue` は Core / DI / JSON provider / JSON Schema / HTTP resources / common sources / environment source / generator analyzer を同梱するメタパッケージです。用途に応じて `Configlue.Provider.Xml` / `.Yaml`、`Configlue.Resource.S3` / `.Dapr` / `.Zip`、`Configlue.Extensions.R3` などの機能パッケージを追加します。

**既知の制限**

- 異なる Resource 間の書き込みはアトミックではありません。
- Source の退役は現在の options インスタンスに閉じており、実データは残ります。
- Source 集合は options ランタイムで固定されます。

## 基本的な使い方

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

設定モデルに `[ConfiglueModel]` を付けて `partial class` として宣言すると、ジェネレーターが Fragment / Patch の対応を生成します。`UseCommonSources` で有効にする層を列挙し、`GetOptions<T>()` で得た options インスタンスから読み書きします。保存は `SaveAsync` のパッチで行うため、変更したフィールドだけが対象層に書き込まれます。

**値の由来を調べる**

現在の値がどこから来ているか、またどこに書き込めるかを確認できます。

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

`Unset()` を使うと、その Source の寄与だけを取り消して下位優先度の Source が値を提供できるようにできます。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

**その他の主な API**

- `IReadOnlyOptions<T>` … 日常の読み取り面は `GetValueAsync` と `OnChange`
- `SaveAsync(patch => ...)` … 生成 Patch によるスパース保存
- `OpenEditSessionAsync()` … まとめて編集し `CommitAsync`
- `ApplyPatchesAsync` + `StateSourcePatch` … 明示的なソース別マルチ書き込み
- `StateWritePlan.For<T>().Route(...)` … 書き込みルーティング
- `SourceKey<TModel>` と `options.Source(key)` … ソース単位の操作

---

# ===== opencode/muse-spark-1.3-contributor-free =====

## 概要

Configlue は、アプリケーションの設定管理を代行する .NET ライブラリです。キャッチコピーは "Make easy configuration management." です。

中心的な考え方は、グローバル設定、実行フォルダーの設定、環境変数、コマンドライン引数、暗号化された資格情報、リモート管理など、複数の場所に散らばった設定を 1 つのモデルに結合（glue）することです。名前も configuration + glue に由来します。

対象は .NET 10 SDK 以降で、C# の `LangVersion` はソースジェネレーター対応が必要です。ライセンスは Apache-2.0 です。現状はアーキテクチャ上の土台であり、`Configuration.Writable` を完全に置き換えるものではありません。

`Microsoft.Extensions.Configuration` の `IConfiguration` が読み取り中心であるのに対し、Configlue は独立した Source の合成、値の来歴の検査、スパース保存に向いています。

基本アーキテクチャは、次の 6 つの概念からなります。依存関係は直線的で、学習順も同じです。

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

読み込みでは、各 Source が Resource からバイトを取得し、Codec が Fragment に変換します。ランタイムが優先度順に「存在する」フィールドだけを 1 つのモデルへ重ねます。

書き込みは逆向きです。アプリは普通のモデル値を編集し、内部では変更が Fragment 差分になり、`WriteRoute` / `WritePlan` が指す Source にだけ届きます。無関係な Source は変更されません。

Fragment は「メンバーが存在しない」と「null / 既定値で存在する」を区別します。層の合成で「未設定」が「既定値に設定」を上書きすることはありません。Patch は生成される `TModel.Patch` で、`Unset()` は書き込み先 Source の寄与だけを取り消し、下位優先度の値を再び見せます。`[ConfiglueMerge]` でメンバーごとのマージ挙動を変更でき、組み込みには `Append`、`Deep`、`Replace`、`SetUnion` があり、カスタム戦略も可能です。

## 主な特徴

- 複数ソースの優先度マージ: `Priority` が大きい Source が勝ちます。`GetDetailsAsync` でどの値がどこ由来かを検査できます。
- 読み取り専用ソース: 環境変数・コマンドライン・既定の HTTP ソースは読み取り専用です。読み取り専用の値への書き込みは黙って無視せず競合エラーになります。
- プロジェクション / マウント: 既存 Source を別モデルに整形したり、ネストしたパスに別 Source を接続（mount、`AddMounted`）できます。
- プリセット: `UseCommonSources` が global / local / environment などの標準的な層構成を組み立てます。
- スパース書き込み: 変更したフィールドだけを対象層に保存します。既定値のままのフィールドは書かれませんが、ユーザーが明示した `null` は尊重されます。
- 編集セッション: `OpenEditSessionAsync` で複数変更をまとめて適用し、`CommitAsync` までインメモリです。競合時は既定で失敗し、`WriteConflictResolution.LastWriteWins` も選べます。
- スキーマ移行 / ストレージ移行: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` による旧バージョン設定の自動変換ができます。既存ファイルを Source として登録できます。
- バックアップと復元: `FileResource` はアトミック書き込みとバックアップ世代管理を行います。既定で `.bak` 1 世代で、`RestoreLatestBackupAsync` で復元できます。
- 安全な書き込み: アトミック性、競合検出、リトライに対応します。
- セクション: `JsonSectionResource` / XML 要素 / YAML マッピングで、ファイルの一部を独立した Resource として扱えます。書き込み時はコメント・空白・引用・スカラー形式を保持し、同じファイル内の独立セクションは 1 回の物理書き込みにバッチされます。
- ZIP / HTTP / S3 / Dapr: `ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込み・ポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr` を利用できます。
- JSON Schema 生成: `Configlue.JsonSchema` で人間が設定を書くためのスキーマを生成できます。
- Native AOT 対応: ソース生成の `JsonSerializerContext` を渡すとトリミング / AOT に強くなります。
- リアクティブ統合（任意）: `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）があり、`ObserveChanges()`、`ObserveValues()`、`ObserveReloadFailures()`、`ObserveActiveValues()`、`ObserveActiveProfileNames()` を利用できます。
- DI 統合: `Configlue.Extensions.DI` と、Microsoft の options アダプター `Configlue.Extensions.MSOptions`（`IOptions<T>` など）があります。同期ゲッターは非同期ソース読み取り中ブロックするので、非同期フローでは `GetValueAsync` 推奨です。
- プロファイル / 動的オプション: 名前付きオプションや永続プロファイルでランタイムを単位に作成・削除できます。
- その他の要件への対応: 変更通知による再起動なしの反映、書き込み先の自動選択、壊れたファイルへの対処、バックアップと自動整理、他プロセスとの競合検出・自動マージを含みます。
- 既知の制限: 異なる Resource 間の書き込みはアトミックではありません。Source の退役は現在の options インスタンスに閉じ、実データは残ります。Source 集合は options ランタイムで固定です。
- パッケージ構成: ユーザー向けメタパッケージ `Configlue`（Core / DI / JSON provider / JSON Schema / HTTP resources / common sources / environment source / generator analyzer を同梱、実装アセンブリは持たない）を中心に、`Configlue.Abstraction`、`Configlue.Core`、`Configlue.Extensibility`、`Configlue.Extensions.DI` / `Configlue.Extensions.MSOptions` / `Configlue.Extensions.R3` / `Configlue.Extensions.Reactive`、`Configlue.Generator`、`Configlue.Testing`、`Configlue.Provider.Json` / `.Xml` / `.Yaml`、`Configlue.JsonSchema`、`Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml`、`Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip`、`Configlue.Transformer.AES`（Resource と Codec の間のバイトを AES-GCM 暗号化・認証）があります。インストールは `dotnet add package Configlue` から始め、必要な機能パッケージを追加します。

## 基本的な使い方

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

現在の値（全ソースをマージしたもの）を取得し、各値がどこから来たかを調べる例です:

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

その他の API として、`IReadOnlyOptions<T>`（日常の読み取り面は `GetValueAsync` と `OnChange`）、`SaveAsync(patch => ...)`（生成 Patch でスパース保存）、`OpenEditSessionAsync()`（まとめて編集し `CommitAsync`）、`ApplyPatchesAsync` + `StateSourcePatch`（明示的なソース別マルチ書き込み）、`StateWritePlan.For<T>().Route(...)`（書き込みルーティング）、`SourceKey<TModel>` と `options.Source(key)`（ソース単位の操作）があります。


---

# ===== opencode/nemotron-3-ultra-free =====

# Configlue

.NET アプリケーションのための設定管理ライブラリ。"Make easy configuration management."

複数の場所に散らばった設定（グローバル、ローカル、環境変数、コマンドライン、リモート API など）を 1 つのモデルに **結合（glue）** し、読み書き・変更通知・スキーマ移行・安全な保存までを一貫して扱えます。

- 対象: .NET 10 SDK 以降
- ライセンス: Apache-2.0
- インストール: `dotnet add package Configlue`

---

## 概要

JSON ファイルの読み書きだけなら数行で済みますが、実用的な設定管理には次のような要件が積み重なります。

- 設定が複数箇所にある（グローバル / ローカル / 環境変数 / コマンドライン / 暗号化資格情報 / HTTP API 等）
- ファイル変更を再起動なしで反映したい
- 書き込み先を自動で選びたい（環境変数由来の値への書き込みはエラーにしたい）
- 人間が編集する前提：コメントを残したい、JSON Schema がほしい、壊れたファイルに対処したい
- 既定値のままなら書き出さない（明示的な `null` は尊重する）
- 設定ファイルのバージョンアップ（旧形式 → 新形式の自動変換）
- バックアップと自動整理
- 書き込みの安全性：アトミック性、競合検出・自動マージ、自動リトライ

Configlue はこれらを **6 つの概念** で整理し、ランタイムが自動で解決します。

```text
Resource (場所) → Codec (変換) → Source (寄与) → Fragment (差分) → Options (ファサード)
                                                      ↘ Patch (編集)
```

| 概念 | 役割 |
|------|------|
| **Resource** | バイトがどこにあるか（ファイル、ZIP、HTTP、メモリ等） |
| **Codec** | バイト ↔ 値の相互変換（JSON / XML / YAML） |
| **Source** | 論理的な寄与（どのフィールドをどの優先度で提供するか） |
| **Fragment** | 「存在するフィールドだけ」を持つ差分状態 |
| **Patch** | 単一フィールドの編集操作 |
| **Options** | アプリが触るファサード（読み・保存・監視・診断） |

**読み込み**：各 Source が Resource からバイトを取得し、Codec で Fragment に変換。ランタイムが優先度順に「存在する」フィールドだけをモデルへ重ね合わせます。  
**書き込み**：逆方向。アプリは普通のモデル値を編集し、内部で Fragment 差分に変換され、`WriteRoute` / `WritePlan` が指す Source だけへ届きます。無関係な Source は変更されません。

- Fragment は「メンバーが存在しない」と「null/既定値で存在する」を区別します。層の合成で「未設定」が「既定値に設定」を上書きすることはありません。
- Patch は生成される `TModel.Patch`。`Unset()` は書き込み先 Source の寄与だけを取り消し、下位優先度の値を再び見せます。
- `[ConfiglueMerge]` でメンバーごとのマージ挙動を変更可能（組み込み: `Append`, `Deep`, `Replace`, `SetUnion`、カスタム戦略も可）。

---

## 主な特徴

- **複数ソースの優先度マージ**  
  `Priority` が大きい Source が勝つ。`GetDetailsAsync` で「どの値がどこ由来か」を検査可能。

- **読み取り専用ソース**  
  環境変数・コマンドライン・既定の HTTP ソースは読み取り専用。読み取り専用の値への書き込みは黙って無視せず競合エラーになる。

- **プロジェクション / マウント**  
  既存 Source を別モデルに整形（projection）したり、ネストしたパスに別 Source を接続（mount, `AddMounted`）できる。

- **プリセット**  
  `UseCommonSources` が標準的な層構成（global / local / environment 等）を組み立てる。

- **スパース書き込み**  
  変更したフィールドだけを対象層に保存。既定値のままのフィールドは書かれない。

- **編集セッション**  
  `OpenEditSessionAsync` で複数変更をまとめて適用。`CommitAsync` までインメモリ。競合時は既定で失敗、`WriteConflictResolution.LastWriteWins` も選択可能。

- **スキーマ移行 / ストレージ移行**  
  `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` による旧バージョン設定の自動変換。既存ファイルを Source として登録可能。

- **バックアップと復元**  
  `FileResource` はアトミック書き込みとバックアップ世代管理。既定で `.bak` 1 世代、`RestoreLatestBackupAsync` で復元。

- **安全な書き込み**  
  アトミック性、競合検出、自動リトライ。

- **セクション**  
  `JsonSectionResource` / XML 要素 / YAML マッピングで、ファイルの一部を独立した Resource として扱える。書き込み時はコメント・空白・引用・スカラー形式を保持。同じファイル内の独立セクションは 1 回の物理書き込みにバッチされる。

- **多様なリソース**  
  `ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込み・ポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。

- **JSON Schema 生成**  
  `Configlue.JsonSchema`。人間が設定を書くためのスキーマを出力。

- **Native AOT 対応**  
  ソース生成の `JsonSerializerContext` を渡すとトリミング / AOT に強くなる。

- **リアクティブ統合（任意）**  
  `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）。`ObserveChanges()`, `ObserveValues()`, `ObserveReloadFailures()`, `ObserveActiveValues()`, `ObserveActiveProfileNames()`。

- **DI 統合**  
  `Configlue.Extensions.DI`。Microsoft の options アダプター `Configlue.Extensions.MSOptions`（`IOptions<T>` 等。同期ゲッターは非同期ソース読み取り中ブロックするため、非同期フローでは `GetValueAsync` 推奨）。

- **プロファイル / 動的オプション**  
  名前付きオプションや永続プロファイルでランタイムを単位に作成・削除できる。

- **既知の制限**  
  異なる Resource 間の書き込みはアトミックでない。Source の退役は現在の options インスタンスに閉じ、実データは残る。Source 集合は options ランタイムで固定。

---

## 基本的な使い方

### クイックスタート

`example.cs` に保存し `dotnet run example.cs` で実行（.NET 10 以降）：

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

### 値の由来を調べる / スパース保存

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

指定したメンバーだけを更新するパッチを保存。`Unset()` はその Source の寄与を外し、下位優先度の Source が値を提供できるようにする：

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

### 主な API

- `IReadOnlyOptions<T>` … 日常の読み取り面は `GetValueAsync` と `OnChange`。
- `SaveAsync(patch => ...)` … 生成 Patch でスパース保存。
- `OpenEditSessionAsync()` … まとめて編集し `CommitAsync`。
- `ApplyPatchesAsync` + `StateSourcePatch` … 明示的なソース別マルチ書き込み。
- `StateWritePlan.For<T>().Route(...)` … 書き込みルーティング。
- `SourceKey<TModel>` と `options.Source(key)` … ソース単位の操作。

---

## Microsoft.Extensions.Configuration との違い

`IConfiguration` は読み取り中心のキーバリューストアですが、Configlue は **独立したソースの合成・来歴の検査・スパース保存** に特化しています。設定を「値の集合」ではなく「層を持つモデル」として扱いたい場合に適しています。

---

# ===== opencode/nemotron-3.5-lightning-free =====

# Configlue 日本語解説

## 概要

Configlue は、アプリケーションの設定管理を代行する .NET ライブラリです。キャッチコピーは "Make easy configuration management." です。

複数の場所に散らばった設定を 1 つのモデルに結合（glue）するのが中心的な考え方で、名前も configuration + glue になっています。対象は .NET 10 SDK 以降で、C# の利用にはソースジェネレーター対応の LangVersion が必要です。ライセンスは Apache-2.0 です。

現状はアーキテクチャ上の土台であり、`Configuration.Writable` を完全に置き換えるものではありません。

主な解決課題は以下の通りです。

- 設定がグローバル設定、実行フォルダー設定、環境変数、コマンドライン引数、暗号化された資格情報、社内ポリシーや HTTP API など複数箇所にある
- 設定ファイルが書き換わったら再起動なしで反映したい（変更通知）
- 書き込み先を自動で選びたい。環境変数から読んだ値への書き込みはエラーにしたい
- 設定ファイルは人間が書くため、コメントを残し、JSON Schema が欲しく、壊れたファイルへの対処が必要
- 既定値のままなら書き出さず、ユーザーが明示した `null` は尊重する
- 設定ファイルのバージョンアップ（旧形式→新形式への自動変換）
- バックアップと自動整理
- アトミック性、競合検出・自動マージ、自動リトライによる書き込みの安全性

これらを自前実装するのは面倒というのが動機です。

## 主な特徴

- **複数ソースの優先度マージ**: `Priority` が大きい Source が勝ち、`GetDetailsAsync` で「どの値がどこ由来か」を検査できます
- **読み取り専用ソース**: 環境変数・コマンドライン・既定の HTTP ソースは読み取り専用です。読み取り専用の値への書き込みは黙って無視せず競合エラーになります
- **プロジェクション / マウント**: 既存 Source を別モデルに整形（projection）したり、ネストしたパスに別 Source を接続（mount, `AddMounted`）できます
- **プリセット**: `UseCommonSources` が標準的な層構成（global/local/environment など）を組み立てます
- **スパース書き込み**: 変更したフィールドだけを対象層に保存。既定値のままのフィールドは書かれません
- **編集セッション**: `OpenEditSessionAsync` で複数変更をまとめて適用。`CommitAsync` までインメモリです。競合時は既定で失敗し、`WriteConflictResolution.LastWriteWins` も選べます
- **スキーマ移行 / ストレージ移行**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` による旧バージョン設定の自動変換。既存ファイルを Source として登録できます
- **バックアップと復元**: `FileResource` はアトミック書き込みとバックアップ世代管理。既定で `.bak` 1 世代、`RestoreLatestBackupAsync` で復元できます
- **安全な書き込み**: アトミック性、競合検出、リトライ
- **セクション**: `JsonSectionResource` / XML 要素 / YAML マッピングで、ファイルの一部を独立した Resource として扱えます。書き込み時はコメント・空白・引用・スカラー形式を保持し、同じファイル内の独立セクションは 1 回の物理書き込みにバッチされます
- **ZIP / HTTP / S3 / Dapr**: `ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込み・ポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`
- **JSON Schema 生成**: `Configlue.JsonSchema`。人間が設定を書くためです
- **Native AOT 対応**: ソース生成の `JsonSerializerContext` を渡すとトリミング/AOT に強くなります
- **リアクティブ統合（任意）**: `Configlue.Extensions.Reactive` と `Configlue.Extensions.R3`。`ObserveChanges()`, `ObserveValues()`, `ObserveReloadFailures()`, `ObserveActiveValues()`, `ObserveActiveProfileNames()` を使用できます
- **DI 統合**: `Configlue.Extensions.DI`。Microsoft の options アダプター `Configlue.Extensions.MSOptions`（`IOptions<T>` など。同期ゲッターは非同期ソース読み取り中ブロックするので非同期フローでは `GetValueAsync` 推奨）
- **プロファイル / 動的オプション**: 名前付きオプションや永続プロファイルでランタイムを単位に作成・削除できます
- **既知の制限**: 異なる Resource 間の書き込みはアトミックでなく、Source の退役は現在の options インスタンスに閉じ実データは残るほか、Source 集合は options ランタイムで固定されます

## 基本的な使い方

### クイックスタート

`example.cs` に保存し `dotnet run example.cs` で実行（.NET 10 以降）します。

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

### 値の由来を調べる / スパース保存

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

指定したメンバーだけを更新するパッチを保存。`Unset()` はその Source の寄与を外し、下位優先度の Source が値を提供できるようにします。

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

---

# ===== opencode/space-bunny-free =====

# Configlue

**Make easy configuration management.**

Configlue は .NET アプリケーションの設定管理を代行するライブラリです。グローバル設定、実行フォルダーの設定、環境変数、コマンドライン引数、リモートの管理 API —— :main: このような複数の場所に散らばった設定を、1 つのモデルに「接着（glue）」することを目的としています。名前は configuration と glue を組み合わせたものです。

JSON ファイルを読み書きするだけなら数行で済みます。しかし実運用では、変更通知、書き込み先の選択、コメントを保持した編集、バージョン移行、バックアップ、アトミック書き込みといった要件が積み重なります。Configlue はそれらを前提に設計されたアーキテクチャの土台です。

対象は .NET 10 SDK 以降、ライセンスは Apache-2.0 です。なお現状は `Configuration.Writable` を完全に置き換えるものではなく、アーキテクチャ上の土台として提供されています。

## 主な特徴

### 6 つの概念

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

**読み込み**は、各 Source が Resource からバイトを取得し、Codec が Fragment に変換し、ランタイムが優先度順に「存在する」フィールドだけを 1 つのモデルへ重ねる、という流れになります。

**書き込み**は逆向きです。アプリは普通のモデル値を編集し、内部では変更が Fragment 差分になり、`WriteRoute` / `WritePlan` が指す Source にだけ届きます。無関係な Source は変更されません。

Fragment は「メンバーが存在しない」と「null / 既定値で存在する」を区別します。そのため層の合成で「未設定」が「既定値に設定」を上書きすることはありません。Patch は生成される `TModel.Patch`（単一フィールドの編集フラグメント）で、`Unset()` を呼ぶと書き込み先 Source の寄与だけを取り消し、下位優先度の値を再び見せられます。メンバーごとのマージ挙動は `[ConfiglueMerge]` で変更でき、組み込みの `Append`、`Deep`、`Replace`、`SetUnion` に加えてカスタム戦略も使えます。コレクションの層合成と順序もここで決まります。

### 複数ソースの合成と来歴の検査

`Priority` が大きい Source が勝ちます。どの値がどこから来たのかは `GetDetailsAsync` で調べられます。環境変数・コマンドライン・既定の HTTP ソースは読み取り専用で、読み取り専用の値への書き込みは黙って無視されず競合エラーになります。

プロジェクションで既存 Source を別モデルに整形したり、マウント（`AddMounted`）でネストしたパスに別 Source を接続したりできます。プリセットの `UseCommonSources` は global / local / environment などの標準的な層構成を組み立てます。

### スパース書き込みと編集セッション

変更したフィールドだけが対象層に保存されます。既定値のままのフィールドは書かれません。`OpenEditSessionAsync` を使えば複数の変更をまとめて適用でき、`CommitAsync` までインメモリです。競合時は既定で失敗し、`WriteConflictResolution.LastWriteWins` も選べます。

### 安全な書き込みとストレージ移行

`FileResource` はアトミック書き込みとバックアップ世代管理を扱い、既定で `.bak` 1 世代を保持し、`RestoreLatestBackupAsync` で復元できます。書き込みはアトミック性・競合検出・リトライで保護されます。`[ConfigluePreviousVersion]` と `Fragment.FromPrevious` により旧バージョンの設定を自動変換でき、既存ファイルを Source として登録することもできます。

### セクションとリソース

`JsonSectionResource`、XML 要素、YAML マッピングで、ファイルの一部を独立した Resource として扱えます。書き込み時はコメント・空白・引用・スカラー形式が保持され、同じファイル内の独立セクションは 1 回の物理書き込みにバッチされます。

`ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込み・ポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr` も利用できます。`Configlue.Transformer.AES` は Resource と Codec の間のバイトを AES-GCM で暗号化・認証します。

### その他

- JSON Schema 生成（`Configlue.JsonSchema`）— 人間が設定ファイルを書けるようにするため
- Native AOT 対応 — ソース生成の `JsonSerializerContext` を渡すとトリミング / AOT に強くなる
- リアクティブ統合（任意）— `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）、`Configlue.Extensions.R3`（R3 1.3.1）。`ObserveChanges()`、`ObserveValues()`、`ObserveReloadFailures()`、`ObserveActiveValues()`、`ObserveActiveProfileNames()`
- DI 統合 — `Configlue.Extensions.DI`、および Microsoft の options アダプター `Configlue.Extensions.MSOptions`（`IOptions<T>` など）
- プロファイル / 動的オプション — 名前付きオプションや永続プロファイルでランタイムを単位に作成・削除

`Microsoft.Extensions.Configuration` の `IConfiguration` が読み取り中心であるのに対し、Configlue は独立したソースの合成、値の来歴の検査、スパース保存に向いています。

### パッケージ

インストールは `dotnet add package Configlue` からで、必要な機能パッケージを追加します。

- `Configlue` … ユーザー向けメタパッケージ（Core / DI / JSON provider / JSON Schema / HTTP resources / common sources / environment source / generator analyzer を同梱。実装アセンブリは持たない）
- `Configlue.Abstraction` … 契約（provider / codec / resource / generated-model）
- `Configlue.Core` … 解決と永続化のランタイム
- `Configlue.Extensibility` … プロバイダー SDK
- `Configlue.Extensions.DI` / `.MSOptions` / `.R3` / `.Reactive`
- `Configlue.Generator` … Roslyn アナライザー（スパースなモデルサポート生成）
- `Configlue.Testing` … インメモリのテストダブル
- `Configlue.Provider.Json` / `.Xml` / `.Yaml` … 各形式の Codec・セクションリソース・ファイル登録
- `Configlue.JsonSchema` … JSON Schema 生成・エクスポート
- `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml`
- `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip`
- `Configlue.Transformer.AES`

### 既知の制限

- 異なる Resource 間の書き込みはアトミックではありません
- Source の退役は現在の options インスタンスに閉じ、実データは残ります
- Source 集合は options ランタイムで固定です

## 基本的な使い方

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

### 値の由来を調べる

合成された現在値を取得したうえで、各値がどの Source 由来かを確認できます。

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

### スパース保存

指定したメンバーだけを更新します。`Unset()` はその Source の寄与を外し、下位優先度の Source が値を提供できるようにします。

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

`Configlue.Extensions.MSOptions` を使う場合、同期ゲッターは非同期ソースの読み取り中にブロックするため、非同期フローでは `GetValueAsync` の利用を推奨します。


