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
