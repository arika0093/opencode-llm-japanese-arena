# Configlue

設定管理を引き受ける .NET 向けライブラリです。合言葉は「Make easy configuration management.」です。

アプリケーションの設定は、全体設定ファイル、実行フォルダーごとのファイル、環境変数、コマンドライン引数、暗号化された credential、HTTP API や社内ポリシーによる遠隔管理など、複数の場所に散らばりがちです。Configlue はこれらを貼り合わせて、ひとつのモデルとして扱います。名前は configuration と glue に由来します。JSON ファイルを数行で読み書きするだけなら簡単ですが、実運用で積み上がる細かな要求を自前で実装する手間を省くためのライブラリです。

`Microsoft.Extensions.Configuration` の `IConfiguration` が読み取り中心であるのに対し、Configlue は独立した提供元を組み合わせること、値の由来を確認できること、変更した分だけを書き戻せることに向いています。現在の位置づけは土台となる実装であり、`Configuration.Writable` を完全に置き換えるものではありません。

動作条件は .NET 10 SDK 以降です。C# はソースジェネレーターを利用できる `LangVersion` が必要であり、リポジトリは `preview` でビルドしています。ライセンスは Apache-2.0 です。

## まずは動かす

`example.cs` に保存して `dotnet run example.cs` で実行できます（.NET 10 以降）。

```csharp
#!/usr/bin/env dotnet
#:package Configlue@*

using Configlue;
using Configlue.Source.Presets;

// 1. 設定モデルを宣言する。Fragment と Patch の対応はジェネレーターが作る。
[ConfiglueModel("SampleSetting", Version = 1)]
public partial class SampleSetting
{
    public string Name { get; set; } = "World";
    public int RunCount { get; set; }
    public bool DefaultValue { get; set; } = true;
}

// 2. 使う層を宣言する。ここに挙げた提供元だけが有効になる。
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);

// 3. options 経由で読み書きする。
var options = context.GetOptions<SampleSetting>();
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 変更した項目だけが対象層に保存される。
await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue に触れていないため、対象層には書き出されない。
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

導入は `dotnet add package Configlue` から始めます。必要に応じて機能ごとのパッケージを追加します。`Configlue` は利用者向けの取りまとめパッケージであり、Core や DI、JSON 提供元、JSON Schema、HTTP リソース、共通提供元、環境変数提供元、ジェネレーターなどを束ねています。自前の実装 assembly は持ちません。

## 読み書きの考え方を六つの言葉で整理する

依存関係は一直線に並び、学ぶ順番も同じです。

```text
Resource (場所) → Codec (変換) → Source (寄与) → Fragment (差分) → Options (窓口)
                                                        ↘ Patch (1項目の編集)
```

| 言葉 | 意味 | 例 |
| --- | --- | --- |
| Resource | バイト列の置き場所 | ファイル、ZIP 内項目、HTTP 応答、メモリー |
| Codec | バイト列と値の変換 | JSON、XML、YAML の読み書き |
| Source | どの項目をどの優先度で受け持つかという論理的な寄与 | 使用者設定ファイルの `Server` 部分 |
| Fragment | 有無を覚えている差分 | `Port` だけを持っている状態 |
| Patch | 1項目分の編集 | `Port` を 9000 にする |
| Options | アプリケーションが触る窓口 | 読み取り、保存、監視、説明、診断 |

読み取りでは、各 Source が Resource からバイト列を取り寄せ、Codec が Fragment に変換します。実行時は「存在する」項目だけを優先度順に重ねて、ひとつのモデルにします。

書き込みは逆向きです。アプリケーションは普段どおりのモデル値を編集します。内部では変更が Fragment の差分になり、`WriteRoute` や `WritePlan` で指名された Source にだけ届きます。関係のない Source には触れません。

この重ね合わせを支える約束は三つあります。

まず、Fragment は「項目がない」ことと「null や既定値として存在する」ことを区別します。そのため、未設定が既定値として設定済みの値を上書きすることはありません。利用者が明示した null は尊重されます。

次に、Patch は生成される `TModel.Patch` であり、1項目単位の編集用差分です。`Unset()` は書き込み先 Source の寄与だけを取り下げ、下位の優先度の値を再び見えるようにします。

さらに、項目ごとの重ね方は `[ConfiglueMerge]` で変えられます。組み込みは `Append`、`Deep`、`Replace`、`SetUnion` であり、自作の方式も使えます。コレクションの重ね方や順序はここで決まります。

## 値の由来を確かめて必要な分だけ書き戻す

日常の読み取りは `IReadOnlyOptions<T>` の `GetValueAsync` と `OnChange` を使います。ファイルが書き換えられたら再起動なしで反映し、変更通知で知ることができます。

各値がどこから来たかは `GetDetailsAsync` で調べられます。

```csharp
var options = context.GetOptions<AppSettings>();
// 現在値を読む。すべての提供元の重ね合わせ結果である。
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 値の由来を調べる。
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

優先度は `Priority` の大きい Source が勝ちます。環境変数、コマンドライン、既定の HTTP 提供元は読み取り専用です。読み取り専用の値に書き込もうとしても黙って無視されるのではなく、競合の誤りとして報告されます。書き込み先は自動で選ばれます。

保存は `SaveAsync` に Patch を渡します。指定した項目だけを更新します。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

まとめ書きには `OpenEditSessionAsync` を使います。複数の変更を一括で扱い、`CommitAsync` まではメモリー上にとどまります。競合時は既定で失敗し、`WriteConflictResolution.LastWriteWins` も選べます。提供元を明示して複数書き込みする場合は `ApplyPatchesAsync` と `StateSourcePatch`、書き込み先の割り当ては `StateWritePlan.For<T>().Route(...)`、提供元ごとの操作は `SourceKey<TModel>` と `options.Source(key)` を使います。

既存の Source を別のモデルに作り替える投影と、入れ子になった経路に別の Source を取り付けるマウントもできます。マウントには `AddMounted` を使います。定型の層構成は `UseCommonSources` で組み立てます。

## 人が書くファイルを壊さないための仕組み

設定ファイルは人が書きます。Configlue は注釈や空白、引用の仕方、スカラーの書き方を書き込み時に保ちます。ファイルの一部を独立した Resource として扱う仕組みとして、`JsonSectionResource`、XML 要素、YAML マッピングがあります。同じファイル内の独立した区分への書き込みは、1回の物理書き込みにまとめられます。壊れたファイルへの対処や、人が書くための JSON Schema 対応も含まれます。Schema の生成と出力は `Configlue.JsonSchema` が受け持ちます。

古い形式の自動変換もできます。`[ConfigluePreviousVersion]` と `Fragment.FromPrevious` により、版つきの設定を移行します。既存のファイルは Source として登録できます。既定値のままの値は書き出さないため、ファイルが必要以上に膨らみません。

## 書き込みを安全に終えるための仕組み

`FileResource` は不可分な書き込みと世代つき予備複製の管理を行います。既定では `.bak` を1世代作ります。戻すときは `RestoreLatestBackupAsync` を使います。不可分性、他過程との競合検出と自動統合、自動再試行により、途中停止による破損を防ぎます。

ただし、異なる Resource にまたがる書き込みは不可分ではありません。また、Source の利用停止は現在の options 実体の中だけに閉じ、裏側の実データは残ります。options 実行ごとの提供元の集合は固定です。

## 置き場所と周辺連携の広げ方

置き場所として、ZIP 内項目は `ZipEntryResource`、HTTP は `Configlue.Resource.Http`（ETag による条件つき書き込みと定時確認）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr` があります。ASP.NET Core 側の受け口は `Configlue.Resource.Http.AspNetCore` です。

Resource と Codec の間でバイト列を暗号化・認証する場合は `Configlue.Transformer.AES` を使います。方式は AES-GCM です。

利用の広げ方は次のとおりです。

- 永続プロファイルと名前つき options により、実行環境を単位として作ったり消したりできます。
- JSON、XML、YAML ごとに Codec、区分 Resource、ファイル登録が用意されています。
- トリミングや Native AOT への耐性を高めるには、ソース生成済みの `JsonSerializerContext` を渡します。
- DI は `Configlue.Extensions.DI`、Microsoft の options への橋渡しは `Configlue.Extensions.MSOptions`（`IOptions<T>` など）です。同期取得は非同期提供元の読み取り待ちで止まるため、非同期の流れでは `GetValueAsync` の利用が勧められます。
- 反応型の連携は任意です。`Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）があり、`ObserveChanges()`、`ObserveValues()`、`ObserveReloadFailures()`、`ObserveActiveValues()`、`ObserveActiveProfileNames()` を使えます。
- 試験用のメモリー内二重体は `Configlue.Testing`、提供元を作る側の SDK は `Configlue.Extensibility`、契約は `Configlue.Abstraction`、解決と永続化の実行部は `Configlue.Core`、疎なモデル対応の生成は Roslyn による `Configlue.Generator` が受け持ちます。

形式別の共通層は `Configlue.Source.Presets` を基本に、`Configlue.Source.Presets.Yaml` と `Configlue.Source.Presets.Xml` を足します。環境変数は `Configlue.Source.Environment`、コマンドライン引数は `Configlue.Source.CommandLine` です。

