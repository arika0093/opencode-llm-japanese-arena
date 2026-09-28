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
