# Configlue

Configlue は、複数の場所に分かれたアプリケーション設定を一つのモデルにまとめ、読み取りと書き戻しを扱う .NET ライブラリです。名前は configuration と glue を重ねたものです。プロジェクトの標語は "Make easy configuration management." です。

設定ファイルを一つ読むだけなら、数行で足ります。運用が進むと、置き場所が先に増えます。グローバルな設定、実行フォルダーごとの設定、環境変数、コマンドライン引数、暗号化した資格情報、社内ポリシーや HTTP API のような遠隔の設定が、同時に存在します。

置き場所が増えると、満たしたい条件も増えます。ファイルの変更は再起動せずに反映したい。書き込み先は選び、環境変数から読んだ値へ書いたら失敗させたい。人が残したコメントは消したくない。既定値のままの項目はファイルに出したくないが、明示した `null` は残したい。形式の移行、バックアップ、落ちても壊れない書き込みまでを、アプリケーションごとに実装するのは手間です。

`Microsoft.Extensions.Configuration` の `IConfiguration` は、読み取りが中心です。Configlue は、独立した設定源を重ねること、値の出所を調べること、変えた項目だけを保存することに向いています。

利用には .NET 10 SDK 以降が必要です。C# の言語バージョンはソースジェネレーターに対応している必要があり、このリポジトリは `preview` でビルドしています。ライセンスは Apache-2.0 です。現時点の Configlue は、設定管理の仕組みを組むための土台です。`Configuration.Writable` の完全な置き換えではありません。

## 存在する項目だけを、優先度順に一つのモデルへ重ねる

バイト列の置き場所、形式の変換、どの項目を渡すかは、別の役割です。読み書きの差分と、アプリから使う入口は、その後ろに続きます。依存はこの順に並び、学ぶ順序も同じです。

```text
Resource（置き場所）→ Codec（変換）→ Source（渡す項目）→ Fragment（差分）→ Options（読み書きの入口）
                                                      ↘ Patch（一つの項目の編集）
```

各名前の意味は、次のとおりです。

| 名前 | 意味 | 例 |
| --- | --- | --- |
| Resource | バイト列が置いてある場所 | ファイル、ZIP 内のエントリ、HTTP の応答、メモリ |
| Codec | バイト列と値の相互変換 | JSON、XML、YAML の読み書き |
| Source | どの項目を、どの優先度で渡すか | ユーザー設定ファイルのうち `Server` の部分 |
| Fragment | 項目の有無を覚えた差分 | `Port` だけを持っている状態 |
| Patch | 一つの項目に対する編集 | `Port` を 9000 にする |
| Options | アプリが読み、保存し、監視する入口 | 読み取り、保存、監視、説明、診断 |

読み取りでは、各 Source が Resource からバイト列を取り、Codec がそれを Fragment にします。実行時は、項目が存在する分だけを、優先度の高い順に一つのモデルへ重ねます。この重なりの一段を、層と呼びます。優先度を表す `Priority` が大きい Source の値が採用されます。

Fragment は、項目が無いことと、`null` や既定値として項目があることを区別します。層を重ねるとき、未設定が「既定値として設定済み」を上書きすることはありません。利用者が明示した `null` は、未設定とは別に残ります。

コレクションをどう重ねるかは、メンバーごとに指定できます。属性は `[ConfiglueMerge]` で、組み込みの戦略は `Append`、`Deep`、`Replace`、`SetUnion` です。独自の戦略も追加できます。層を重ねたときの中身と順序は、この指定で決まります。

既にある Source は、別のモデルの形に読み替えることも、入れ子のパスへ別の Source を載せることもできます。後者の登録メソッドは `AddMounted` です。`UseCommonSources` は、グローバル、ローカル、環境変数といったよくある層の組み合わせを組み立てます。ここに挙げた Source だけが有効になります。

## 変えた項目だけを、書ける層へ戻す

書き込みは、読み取りと逆向きに進みます。アプリが編集するのは、普段使うモデルの値です。内部ではその変更が差分になり、書き込み経路が指した Source にだけ届きます。経路は `WriteRoute` と `WritePlan` で表します。関係のない Source は変更されません。

保存されるのは、変更した項目だけです。既定値のまま触っていない項目は、対象の層へ書き出されません。書き込み先は、この経路に沿って決まります。

環境変数、コマンドライン、既定の HTTP ソースは読み取り専用です。読み取り専用の値へ書こうとすると、書き込みは黙って無視されず、競合エラーになります。HTTP の Resource 自体は、後述のとおり条件付きの書き込みに対応します。読み取り専用なのは、既定の HTTP ソースです。

Patch は、ソースジェネレーターがモデルごとに作る `TModel.Patch` です。`Unset()` は、書き込み先の Source が渡していた値だけを外します。外したあとは、より優先度の低い Source の値が再び読めるようになります。

いくつかの変更をまとめて確定するときは、`OpenEditSessionAsync` で編集セッションを開きます。`CommitAsync` まではメモリ上の変更です。競合したときは既定で失敗します。後から書いた値を残す場合は、`WriteConflictResolution.LastWriteWins` を指定します。

## 人が書いたファイルの形を残して更新する

設定ファイルは人が書く前提です。JSON のセクション、XML の要素、YAML のマッピングは、ファイルの一部を独立した Resource として扱えます。JSON の場合の型は `JsonSectionResource` です。書き戻しても、コメント、空白、引用符、数値や文字列の表記は残ります。同じファイル内の独立したセクションは、物理的な書き込み 1 回にまとめられます。JSON Schema の生成と書き出しは `Configlue.JsonSchema` で行います。壊れたファイルへの対処も、この受け取りに含まれます。

ファイルへの書き込みは、途中で落ちてもファイルが壊れない形で行います。他プロセスとの競合検出、自動のマージ、失敗時の再試行も、書き込みの安全性に含まれます。バックアップの世代管理は `FileResource` が行い、既定では `.bak` を 1 世代残します。最新の世代へ戻すメソッドは `RestoreLatestBackupAsync` です。

設定の版を上げるときは、`[ConfigluePreviousVersion]` と `Fragment.FromPrevious` で、古い形式から新しい形式へ自動変換します。既存のファイルは Source として登録できます。

## バイト列の置き場所を、ファイルの外に広げる

Resource はファイルだけではありません。ZIP 内のエントリは `ZipEntryResource`、HTTP は `Configlue.Resource.Http`、S3 は `Configlue.Resource.S3`、Dapr は `Configlue.Resource.Dapr` です。HTTP では、ETag による条件付き書き込みとポーリングが使えます。Resource と Codec の間では、`Configlue.Transformer.AES` がバイト列を AES-GCM で暗号化し、認証します。

## モデルを宣言して、共通の層で読み書きする

導入は次のコマンドから始めます。足りない能力は、後述のパッケージを追加します。

```text
dotnet add package Configlue
```

`Configlue` は利用者向けのメタパッケージです。実装のアセンブリは持たず、Core、依存性注入、JSON のプロバイダー、JSON Schema、HTTP の Resource、共通ソース、環境変数ソース、ジェネレーターのアナライザーを同梱します。

次のコードを `example.cs` に保存し、.NET 10 以降で `dotnet run example.cs` を実行します。モデルは `partial` クラスとして宣言し、`[ConfiglueModel]` に名前と版を付けます。ジェネレーターが Fragment と Patch を作ります。読み書きは、`GetOptions` で得たインスタンスに対して行います。

```csharp
#!/usr/bin/env dotnet
#:package Configlue@*

using Configlue;
using Configlue.Source.Presets;

// 設定モデルを宣言する。ジェネレーターが Fragment と Patch を作る。
[ConfiglueModel("SampleSetting", Version = 1)]
public partial class SampleSetting
{
    public string Name { get; set; } = "World";
    public int RunCount { get; set; }
    public bool DefaultValue { get; set; } = true;
}

// 使う層を宣言する。ここに挙げた Source だけが有効になる。
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);

// Options を通して読み書きする。
var options = context.GetOptions<SampleSetting>();
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 変えた項目だけが対象の層に保存される。
await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue は変更していないので、対象の層には保存されない。
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

この例では `Name` と `RunCount` だけを変えています。`DefaultValue` は触っていないので、対象の層には保存されません。

## 値の出所を見てから、その層が渡した値を外す

重ねた結果だけでなく、各項目がどの Source から来たかも調べられます。`GetDetailsAsync` は、採用された Source の位置、その項目を編集できるか、各 Source の状態を返します。次の `AppSettings` は、利用側が宣言したモデルの例です。

```csharp
var options = context.GetOptions<AppSettings>();
// すべての Source を重ねた現在の値を取得する。
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 各値がどこから来たかを調べる。
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

ループは、その項目に値を渡した Source を順に示します。種類、位置、書き込めるか、状態が分かります。

`SaveAsync` に渡す Patch は、指定した項目だけを更新します。次の例では `Name` を更新し、`RunCount` については書き込み先が渡していた値を外します。外した項目は、より優先度の低い Source の値に戻ります。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

普段の読み取りは `IReadOnlyOptions<T>` で行い、使うメソッドは `GetValueAsync` と `OnChange` です。ソースを指定して複数箇所へ書くときは `ApplyPatchesAsync` と `StateSourcePatch`、経路の定義は `StateWritePlan.For<T>().Route(...)` です。特定の Source だけを操作するときは、`SourceKey<TModel>` と `options.Source(key)` を使います。

## ファイルの変更を、再起動せずに受け取る

ファイルが書き換わったら、再起動せずに変更通知で反映できます。購読を Reactive で書く場合は、任意の拡張を追加します。`Configlue.Extensions.Reactive` は System.Reactive 7.0.0、`Configlue.Extensions.R3` は R3 1.3.1 を使います。購読できるのは、変更、値、再読み込みの失敗、有効な値、有効なプロファイル名です。メソッド名は `ObserveChanges`、`ObserveValues`、`ObserveReloadFailures`、`ObserveActiveValues`、`ObserveActiveProfileNames` です。

## 依存性の注入と、名前を付けた実行時

依存性の注入は `Configlue.Extensions.DI` です。`Configlue.Extensions.MSOptions` は `IOptions<T>` など、Microsoft のオプションへつなぎます。同期の取得は、非同期の Source を読んでいるあいだブロックします。非同期の処理では `GetValueAsync` を使ってください。

名前を付けたオプションと、保存しておくプロファイルを使うと、実行時の単位をまとめて追加したり外したりできます。ネイティブコードへ事前コンパイルする Native AOT では、ソース生成した `JsonSerializerContext` を渡すと、未使用コードの削除や AOT への耐性が上がります。

## 同梱されない能力は、パッケージを追加する

`Configlue` に同梱されない能力は、次のパッケージから必要なものだけを追加します。

| パッケージ | 役割 |
| --- | --- |
| `Configlue.Abstraction` | プロバイダー、Codec、Resource、生成モデルの契約 |
| `Configlue.Core` | 値の解決と保存を行う中核 |
| `Configlue.Extensibility` | 独自のプロバイダーを作るための SDK |
| `Configlue.Generator` | 差分モデルを生成する Roslyn アナライザー |
| `Configlue.Testing` | テスト用の、メモリ上の代用品 |
| `Configlue.Provider.Json` / `.Xml` / `.Yaml` | 各形式の Codec、セクション、ファイル登録 |
| `Configlue.JsonSchema` | JSON Schema の生成と書き出し |
| `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml` | 環境変数、コマンドライン、共通の層 |
| `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip` | HTTP、ASP.NET Core、Dapr、S3、ZIP |
| `Configlue.Extensions.DI` / `.MSOptions` / `.R3` / `.Reactive` | 依存性注入、Microsoft のオプション、購読 |
| `Configlue.Transformer.AES` | Resource と Codec の間の AES-GCM |

## 書き込みとソース集合に残る制約

異なる Resource への書き込みには、すべてが成功するか、すべてが失敗するかという保証はありません。

ソースを外しても、外れるのは今のオプションのインスタンスだけです。保存先のデータは残ります。

一つの実行時について、ソースの集合は固定されています。

