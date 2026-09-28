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
