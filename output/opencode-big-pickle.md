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
