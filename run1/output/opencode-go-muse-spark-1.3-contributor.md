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

