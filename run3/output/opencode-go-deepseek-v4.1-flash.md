# Configlue

**Make easy configuration management.**

Configlue は、アプリケーションの構成管理を引き受ける .NET ライブラリです。
複数の場所に散らばった構成を 1 つのモデルに **glue（接着）** することを中心的な考え方としており、名前は configuration + glue に由来します。

- 要件: .NET 10 SDK 以降。C#（`LangVersion` がソースジェネレーターをサポートしていること。リポジトリでは `preview` でビルド）
- ライセンス: Apache-2.0
- 現状は「アーキテクチャの土台」であり、`Configuration.Writable` を完全に置き換えるものではありません。

## なぜ Configlue か

JSON ファイルを読み書きするだけなら数行で済みます。しかし実際には、次のような要件が積み重なっていきます。

- 構成が複数の場所にある: グローバル設定、実行フォルダーごとの設定、環境変数、コマンドライン引数、暗号化された資格情報、社内ポリシーや HTTP API などのリモート管理。
- 構成ファイルが書き換えられたら、アプリを再起動せずに反映したい（変更通知）。
- 書き込み先を自動で選びたい。環境変数から読んだ値への書き込みはエラーにしたい。
- 構成ファイルは人間が書くものなので、コメントを消したくない、JSON Schema が欲しい、壊れたファイルも扱いたい。
- 値が既定のままなら書き出したくない（ただし、ユーザーが明示的に設定した `null` は尊重したい）。
- 構成ファイルをバージョンアップしたい（旧形式から新形式への自動変換）。
- バックアップと自動クリーンアップ。
- 書き込みの安全性: アトミック性（クラッシュしても壊れない）、他プロセスとの競合検出と自動マージ、自動リトライ。

これらをすべて自分で実装するのは面倒です。Configlue はそこを引き受けます。

## コアアーキテクチャ（6 つの概念）

依存関係は一直線で、学習順も同じです。

```text
Resource (場所) → Codec (変換) → Source (寄与) → Fragment (差分) → Options (ファサード)
                                                    ↘ Patch (編集フラグメント)
```

| 概念 | ひとことで | 例 |
| --- | --- | --- |
| Resource | バイトが存在する場所 | ファイル、ZIP エントリ、HTTP レスポンス、メモリ |
| Codec | バイトと値の相互変換 | JSON / XML / YAML の読み書き |
| Source | 論理的な寄与（どのフィールドをどの優先度で） | 「ユーザー設定ファイルの `Server` の部分」 |
| Fragment | 存在を覚えている差分 | 「`Port` だけ」を持っている状態 |
| Patch | 単一フィールドの編集 | 「`Port` を 9000 に設定」 |
| Options | アプリが見るファサード | 読み取り、保存、監視、説明、診断 |

**読み取り**: 各 Source が Resource からバイトを取得し、Codec がそれを Fragment に変換します。ランタイムは「存在する」フィールドだけを優先度順に重ね合わせ、1 つのモデルにします。

**書き込み**: 逆方向です。アプリは普通のモデル値を編集します。内部的には変更が Fragment の差分になり、`WriteRoute` / `WritePlan` が指定した Source にだけ届きます。無関係な Source は変更されません。

- Fragment は「メンバーが欠落している」ことと「null / 既定値として存在する」ことを区別します。レイヤーの合成で「未設定」が「既定値に設定」を上書きすることはありません。
- Patch は生成される `TModel.Patch`（単一フィールドの編集フラグメント）です。`Unset()` は書き込み先 Source の寄与だけを撤回し、下位優先度の値を再び露出させます。
- `[ConfiglueMerge]` はメンバーごとのマージ動作を変更します（組み込み: `Append`、`Deep`、`Replace`、`SetUnion`。カスタム戦略も可）。コレクションのレイヤー合成と順序はここで決まります。

## 主な機能

- **複数 Source の優先度マージ**: `Priority` が大きい Source が勝ちます。`GetDetailsAsync` で「どの値がどこから来たか」を調べられます。
- **読み取り専用 Source**: 環境変数、コマンドライン、既定の HTTP Source は読み取り専用です。読み取り専用の値への書き込みは黙って無視されず、競合エラーになります。
- **射影 / マウント**: 既存の Source を別のモデルに整形（射影）したり、別の Source をネストしたパスに取り付けたり（マウント、`AddMounted`）できます。
- **プリセット**: `UseCommonSources` が標準的なレイヤー構成（グローバル / ローカル / 環境など）を組み立てます。
- **スパース書き込み**: 変更したフィールドだけが対象レイヤーに保存されます。既定のままのフィールドは書き出されません。
- **編集セッション**: `OpenEditSessionAsync` で複数の変更をまとめて適用します。`CommitAsync` まではメモリ上です。競合時は既定で失敗し、`WriteConflictResolution.LastWriteWins` も利用できます。
- **スキーマ移行 / ストレージ移行**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` による旧バージョン構成の自動変換。既存ファイルを Source として登録できます。
- **バックアップと復元**: `FileResource` がアトミック書き込みとバックアップ世代管理を提供します。既定で `.bak` を 1 世代保持し、`RestoreLatestBackupAsync` で復元できます。
- **安全な書き込み**: アトミック性、競合検出、リトライ。
- **セクション**: `JsonSectionResource` / XML 要素 / YAML マッピングにより、ファイルの一部を独立した Resource として扱えます。書き込み時にはコメント、空白、クォート、スカラースタイルが保持されます。同一ファイル内の独立したセクションは 1 回の物理書き込みにまとめられます。
- **ZIP / HTTP / S3 / Dapr**: `ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込みとポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **JSON Schema 生成**: 構成は人間が書くものなので `Configlue.JsonSchema` を用意しています。
- **Native AOT 対応**: ソース生成された `JsonSerializerContext` を渡すことでトリミング / AOT 耐性が向上します。
- **リアクティブ統合（任意）**: `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）。`ObserveChanges()`、`ObserveValues()`、`ObserveReloadFailures()`、`ObserveActiveValues()`、`ObserveActiveProfileNames()`。
- **DI 統合**: `Configlue.Extensions.DI`。Microsoft オプションのアダプターは `Configlue.Extensions.MSOptions`（`IOptions<T>` など。同期ゲッターは非同期 Source の読み取り中にブロックするため、非同期フローでは `GetValueAsync` を推奨）。
- **プロファイル / 動的オプション**: 名前付きオプションと永続プロファイルにより、ランタイムを単位として作成・削除できます。
- **既知の制限**: 異なる Resource にまたがる書き込みはアトミックではありません。Source の退役は現在のオプションインスタンスにスコープされ、背後のデータはそのまま残ります。Source の集合はオプションランタイムごとに固定です。

## パッケージ構成（主なもの）

- `Configlue` … ユーザー向けメタパッケージ（Core / DI / JSON プロバイダー / JSON Schema / HTTP リソース / 共通 Source / 環境 Source / ジェネレーターアナライザーを同梱。実装アセンブリは持ちません）。
- `Configlue.Abstraction` … コントラクト（provider / codec / resource / 生成モデル）。
- `Configlue.Core` … 解決と永続化のランタイム。
- `Configlue.Extensibility` … プロバイダー SDK。
- `Configlue.Extensions.DI` / `Configlue.Extensions.MSOptions` / `Configlue.Extensions.R3` / `Configlue.Extensions.Reactive`
- `Configlue.Generator` … Roslyn アナライザー（スパースモデルのサポートを生成）。
- `Configlue.Testing` … インメモリのテストダブル。
- `Configlue.Provider.Json` / `.Xml` / `.Yaml` … 各形式のコーデック、セクションリソース、ファイル登録。
- `Configlue.JsonSchema` … JSON Schema の生成とエクスポート。
- `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml`
- `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip`
- `Configlue.Transformer.AES` … Resource と Codec の間のバイトに対する AES-GCM 暗号化と認証。

インストールは `dotnet add package Configlue` から始めます。必要に応じて機能パッケージを追加してください。

## クイックスタート

次を `example.cs` に保存し、`dotnet run example.cs` で実行します（.NET 10 以降）。

```csharp
#!/usr/bin/env dotnet
#:package Configlue@*

using Configlue;
using Configlue.Source.Presets;

// 1. 設定モデルを宣言する。ジェネレーターが Fragment/Patch サポートを生成する。
[ConfiglueModel("SampleSetting", Version = 1)]
public partial class SampleSetting
{
    public string Name { get; set; } = "World";
    public int RunCount { get; set; }
    public bool DefaultValue { get; set; } = true;
}

// 2. プリセットレイヤーを宣言する。ここに列挙した Source だけが有効になる。
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);

// 3. options インスタンスを通して読み書きする。
var options = context.GetOptions<SampleSetting>();
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// スパース編集: 変更したフィールドだけが対象レイヤーに保存される。
await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue は変更していないので、対象レイヤーには保存されない。
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

## 値の出所を調べる / スパース保存

```csharp
var options = context.GetOptions<AppSettings>();
// 1. 現在の値（すべての Source からマージされたもの）を取得する
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

指定したメンバーだけを更新する Patch を保存します。`Unset()` はその Source の寄与を取り除き、下位優先度の Source が値を提供できるようにします。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

その他の API:

- `IReadOnlyOptions<T>` … 日常的な読み取り面は `GetValueAsync` と `OnChange`。
- `SaveAsync(patch => ...)` … 生成された Patch によるスパース保存。
- `OpenEditSessionAsync()` … 複数の変更をまとめて編集し、`CommitAsync` で確定。
- `ApplyPatchesAsync` + `StateSourcePatch` … Source 単位の明示的な複数書き込み。
- `StateWritePlan.For<T>().Route(...)` … 書き込みルーティング。
- `SourceKey<TModel>` と `options.Source(key)` … Source 単位の操作。

## 対象読者

.NET 開発者、とりわけ構成管理に悩みを感じている人向けです。
`Microsoft.Extensions.Configuration` との違いとしては、`IConfiguration` が読み取り志向であるのに対し、Configlue は独立した Source の合成、出所の調査、スパース保存に適している点が挙げられます。
