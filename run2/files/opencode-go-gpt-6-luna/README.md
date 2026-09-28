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
