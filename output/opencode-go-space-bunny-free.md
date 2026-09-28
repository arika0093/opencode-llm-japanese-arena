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
