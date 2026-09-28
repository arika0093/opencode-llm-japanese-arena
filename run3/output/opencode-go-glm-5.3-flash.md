# Configlue

**Make easy configuration management.**

Configlue は、アプリケーションの設定管理を担う .NET ライブラリです。名前は configuration + glue に由来し、複数の場所に散らばった設定を 1 つのモデルへ **glue(接着)** するという発想が中心にあります。

> [!NOTE]
> 現在は「アーキテクチャの基盤」であり、`Configuration.Writable` の完全な置き換えではありません。

- **要件**: .NET 10 SDK 以降。C# の `LangVersion` がソース ジェネレーターを利用できる必要があります(リポジトリは `preview` でビルドしています)。
- **ライセンス**: Apache-2.0

## なぜ Configlue なのか

JSON ファイルの読み書き自体は数行で済みます。しかし現実には、要求は次のように積み上がります。

- 設定は複数の場所に存在します。グローバル設定、ランタイム フォルダーごとの設定、環境変数、コマンドライン引数、暗号化された資格情報、企業ポリシーや HTTP API によるリモート管理。
- 設定ファイルが書き換えられたら、アプリを再起動せずに反映してほしい(変更通知)。
- 書き込み先を自動的に選びたい。環境変数から読み取った値への書き込みはエラーにしてほしい。
- 設定ファイルは人間が書くものです。コメントを消したくない、JSON Schema をサポートしてほしい、壊れたファイルも扱いたい。
- 既定値のままの値は書き出したくない(ただしユーザーが明示的に設定した `null` は尊重する)。
- 設定ファイルをバージョンアップしたい(旧形式から新形式への自動変換)。
- バックアップと自動クリーンアップ。
- 書き込みの安全性。原子性(クラッシュしても破損しない)、他プロセスとの競合検出と自動マージ、自動リトライ。

これらをすべて自前で実装するのは面倒です。Configlue はその受け皿です。

`Microsoft.Extensions.Configuration`(`IConfiguration`)は読み取り専用に寄った設計です。Configlue は、独立した複数ソースの構成、値の由来(provenance)の調査、スパース書き込みに適しています。

## コア アーキテクチャ(6 つの概念)

依存関係は一直線であり、学習順序も同じです。

```text
Resource (場所) → Codec (変換) → Source (寄与) → Fragment (差分) → Options (facade)
                                                        ↘ Patch (編集フラグメント)
```

| 概念 | 一言で言うと | 例 |
| --- | --- | --- |
| Resource | バイトがどこに存在するか | ファイル、ZIP エントリ、HTTP レスポンス、メモリ |
| Codec | バイトと値の相互変換 | JSON / XML / YAML の読み書き |
| Source | 論理的な寄与(どのフィールドをどの優先度で) | 「ユーザー設定ファイルの `Server` 部分」 |
| Fragment | 存在を記憶する差分 | 「`Port` だけを持つ」状態 |
| Patch | 1 フィールドの編集 | 「`Port` を 9000 に設定する」 |
| Options | アプリから見える外観 | 読み取り、保存、監視、説明、診断 |

**読み取り**: 各 Source が Resource からバイトを取得し、Codec が Fragment に変換します。ランタイムは「存在する(present)」フィールドだけを優先度順にオーバーレイし、1 つのモデルへ合成します。

**書き込み**: その逆方向です。アプリは普通のモデル値を編集します。内部ではその変更が Fragment の差分となり、`WriteRoute` / `WritePlan` が名指した Source にだけ届きます。無関係な Source は変更されません。

- Fragment は「メンバーが欠落している」ことと「null / 既定値として存在する」ことを区別します。レイヤー合成では「未設定」が「既定値の設定」を上書きすることはありません。
- Patch は生成される `TModel.Patch`(1 フィールドの編集フラグメント)です。`Unset()` は書き込み先 Source の寄与だけを引き上げ、下位の優先度の値を再び表に出します。
- `[ConfiglueMerge]` でメンバーごとのマージ挙動を変更できます(組み込みは `Append`、`Deep`、`Replace`、`SetUnion`。カスタム戦略も許可)。コレクションのレイヤー合成と順序はここで決まります。

## クイックスタート

以下を `example.cs` に保存し、`dotnet run example.cs` で実行します(.NET 10 以降)。

```csharp
#!/usr/bin/env dotnet
#:package Configlue@*

using Configlue;
using Configlue.Source.Presets;

// 1. 設定モデルを宣言します。ジェネレーターが Fragment/Patch サポートを生成します。
[ConfiglueModel("SampleSetting", Version = 1)]
public partial class SampleSetting
{
    public string Name { get; set; } = "World";
    public int RunCount { get; set; }
    public bool DefaultValue { get; set; } = true;
}

// 2. プリセット レイヤーを宣言します。ここで列挙したソースだけが有効になります。
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);

// 3. options インスタンスを介して読み書きします。
var options = context.GetOptions<SampleSetting>();
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// スパース編集: 変更したフィールドだけがターゲット レイヤーに保存されます。
await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue は変更していないため、ターゲット レイヤーには保存されません。
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

## 値の由来の調査とスパース保存

```csharp
var options = context.GetOptions<AppSettings>();
// 1. 現在値を取得する(全ソースをマージした結果)
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 2. 各値がどこから来たのかを調べる
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

保存は、指定したメンバーだけを更新するパッチで行います。`Unset()` を呼ぶと、その Source の寄与が引き上げられ、下位の優先度の Source が値を提供できるようになります。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

その他の API:

- `IReadOnlyOptions<T>` … 日常的な読み取りの表面は `GetValueAsync` と `OnChange`。
- `SaveAsync(patch => ...)` … 生成された Patch によるスパース保存。
- `OpenEditSessionAsync()` … 複数の変更をまとめて編集し、`CommitAsync` で確定する。
- `ApplyPatchesAsync` + `StateSourcePatch` … ソースごとの明示的な複数書き込み。
- `StateWritePlan.For<T>().Route(...)` … 書き込みルーティング。
- `SourceKey<TModel>` と `options.Source(key)` … ソースごとの操作。

## 主な機能

- **複数ソース間の優先度マージ**: `Priority` の大きい Source が勝ちます。`GetDetailsAsync` で「どの値がどこから来たか」を調べられます。
- **読み取り専用ソース**: 環境変数、コマンドライン、既定の HTTP ソースは読み取り専用です。読み取り専用の値への書き込みは黙って無視されるのではなく、競合エラーを発生させます。
- **プロジェクション / マウント**: 既存の Source を別のモデルへ整形する(プロジェクション)、またはネストされたパスに独立した Source を接続する(マウント、`AddMounted`)ことができます。
- **プリセット**: `UseCommonSources` が標準的なレイヤー構成(グローバル/ローカル/環境変数など)を組み立てます。
- **スパース書き込み**: 変更したフィールドだけがターゲット レイヤーに保存されます。既定値のままのフィールドは書き込まれません。
- **編集セッション**: `OpenEditSessionAsync` は複数の変更をまとめて適用します。`CommitAsync` までメモリ内に保持されます。競合時は既定で失敗します。`WriteConflictResolution.LastWriteWins` も利用できます。
- **スキーマ移行 / ストレージ移行**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` による旧バージョン設定の自動変換。既存のファイルを Source として登録することもできます。
- **バックアップと復元**: `FileResource` がアトミック書き込みとバックアップ世代管理を提供します。既定は 1 世代の `.bak`。`RestoreLatestBackupAsync` で復元します。
- **安全な書き込み**: 原子性、競合検出、リトライ。
- **セクション**: `JsonSectionResource` / XML 要素 / YAML マッピングにより、ファイルの一部を独立した Resource として扱えます。書き込み時、コメント・空白・引用符・スカラーのスタイルは保持されます。同一ファイル内の独立したセクションは 1 回の物理書き込みにまとめられます。
- **ZIP / HTTP / S3 / Dapr**: `ZipEntryResource`、`Configlue.Resource.Http`(ETag 条件付き書き込みとポーリング)、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **JSON Schema 生成**: `Configlue.JsonSchema`。設定は人間が書くものだからです。
- **Native AOT サポート**: ソース生成の `JsonSerializerContext` を渡すことで、トリミング/AOT への耐性が向上します。
- **リアクティブ統合(オプション)**: `Configlue.Extensions.Reactive`(System.Reactive 7.0.0)と `Configlue.Extensions.R3`(R3 1.3.1)。`ObserveChanges()`、`ObserveValues()`、`ObserveReloadFailures()`、`ObserveActiveValues()`、`ObserveActiveProfileNames()`。
- **DI 統合**: `Configlue.Extensions.DI`。Microsoft options アダプターは `Configlue.Extensions.MSOptions`(`IOptions<T>` など。同期 getter は非同期ソースの読み取り中にブロックするため、非同期フローでは `GetValueAsync` を推奨)。
- **プロファイル / 動的 options**: 名前付き options と永続プロファイルにより、ランタイムを単位として作成・削除できます。

## パッケージ構成(主要なもの)

- `Configlue` … ユーザー向けメタパッケージ(Core / DI / JSON プロバイダー / JSON Schema / HTTP リソース / common sources / 環境変数ソース / ジェネレーター アナライザーをバンドル。実装アセンブリは自前で持ちません)。
- `Configlue.Abstraction` … 契約(プロバイダー/コーデック/リソース/生成モデル)。
- `Configlue.Core` … 解決と永続化のランタイム。
- `Configlue.Extensibility` … プロバイダー SDK。
- `Configlue.Extensions.DI` / `Configlue.Extensions.MSOptions` / `Configlue.Extensions.R3` / `Configlue.Extensions.Reactive`
- `Configlue.Generator` … Roslyn アナライザー(スパース モデル サポートを生成)。
- `Configlue.Testing` … インメモリのテスト ダブル。
- `Configlue.Provider.Json` / `.Xml` / `.Yaml` … 各フォーマット向けのコーデック、セクション リソース、ファイル登録。
- `Configlue.JsonSchema` … JSON Schema の生成とエクスポート。
- `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml`
- `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip`
- `Configlue.Transformer.AES` … Resource と Codec の間のバイトに対する AES-GCM の暗号化と認証。

## インストール

`dotnet add package Configlue` から始め、必要な機能パッケージを追加してください。

## 既知の制限

- 異なる Resource 間にまたがる書き込みはアトミックではありません。
- Source の引退は現在の options インスタンスにスコープされ、バッキング データはそのまま残ります。
- ソース集合は options ランタイムに対して固定です。

## ライセンス

Apache-2.0
