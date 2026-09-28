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
