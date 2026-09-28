# Configlue

**Make easy configuration management.**

Configlue は、.NET アプリケーションの設定管理を引き受けるライブラリです。複数の場所に散らばった設定を「糊（グルー）」のように一つのモデルにまとめ上げます。名前のとおり、configuration + glue に由来します。

## 必要なもの

- .NET 10 SDK 以降
- C#（ソースジェネレーターをサポートする `LangVersion`。リポジトリは `preview` でビルド）
- ライセンス: Apache-2.0

## なぜ Configlue なのか

JSON ファイルの読み書きは数行で書けます。しかし実際には、次のような要求が積み上がります。

- 設定が複数の場所に存在する: グローバル設定、実行時フォルダごとの設定、環境変数、コマンドライン引数、暗号化された認証情報、企業ポリシーや HTTP API などのリモート管理
- 設定ファイルの書き換えをアプリの再起動なしに反映したい（変更通知）
- 書き込み先を自動的に選びたい。環境変数から読んだ値への書き込みはエラーにすべき
- 設定ファイルは人間が書く: コメントを消さない、JSON Schema のサポート、壊れたファイルの処理
- 値がデフォルトのままなら書き出さない（ただしユーザーが明示的に設定した `null` は尊重する）
- 設定ファイルのバージョンアップ（旧フォーマットからの自動変換）
- バックアップと自動クリーンアップ
- 書き込みの安全性: アトミック性（クラッシュ時の破損防止）、他プロセスとの競合検出と自動マージ、自動リトライ

これらをすべて自分で実装するのは退屈な作業です。Configlue がその負担を軽減します。

## コアアーキテクチャ（6 つの概念）

依存関係は一直線をなし、学習順序も同じです。

```text
Resource（場所） → Codec（変換） → Source（寄与） → Fragment（差分） → Options（ファサード）
                                                        ↘ Patch（編集フラグメント）
```

| 概念 | 一言で | 例 |
| --- | --- | --- |
| Resource | バイトが存在する場所 | ファイル、ZIP エントリ、HTTP レスポンス、メモリ |
| Codec | バイトと値の変換 | JSON / XML / YAML の読み書き |
| Source | 論理的な寄与（どのフィールドをどの優先度で） | 「ユーザー設定ファイルの `Server` 部分」 |
| Fragment | 存在を記憶する差分 | 「`Port` のみ」という状態 |
| Patch | 単一フィールドの編集 | 「`Port` を 9000 に設定」 |
| Options | アプリが見るファサード | 読取、保存、監視、説明、診断 |

**読み取り**: 各 Source が Resource からバイトを取得し、Codec が Fragment に変換します。ランタイムは「存在する」フィールドのみを優先順位順に重ね、一つのモデルに合成します。

**書き込み**: 逆方向です。アプリは通常のモデル値を編集します。内部的には変更が Fragment 差分となり、`WriteRoute` / `WritePlan` が指定する Source のみに到達します。無関係な Source は変更されません。

- Fragment は「メンバーが存在しない」ことと「null/デフォルトとして存在すること」を区別します。レイヤー合成では「未設定」が「デフォルト設定済み」を上書きすることはありません。
- Patch は生成された `TModel.Patch`（単一フィールド編集フラグメント）です。`Unset()` は書き込み先 Source の寄与を取り消し、優先度の低い値が再び見えるようにします。
- `[ConfiglueMerge]` でメンバーごとのマージ動作を変更できます（組み込み: `Append`、`Deep`、`Replace`、`SetUnion`、カスタム戦略も可能）。コレクションレイヤーの合成と順序はここで決まります。

## 主な機能

- **複数ソース間の優先度マージ**: `Priority` が大きい Source が優先されます。`GetDetailsAsync` で「どの値がどこから来たか」を確認できます。
- **読み取り専用ソース**: 環境変数、コマンドライン、デフォルトの HTTP ソースは読み取り専用です。読み取り専用値への書き込みは無視せず、競合エラーを発生させます。
- **プロジェクション / マウント**: 既存の Source を別のモデルに変形させたり（プロジェクション）、ネストしたパスに別の Source をアタッチしたりできます（マウント、`AddMounted`）。
- **プリセット**: `UseCommonSources` が標準的なレイヤー構成（グローバル/ローカル/環境変数など）を組み立てます。
- **スパース書き込み**: 変更したフィールドのみがターゲットレイヤーに保存されます。デフォルトのままのフィールドは書き出されません。
- **編集セッション**: `OpenEditSessionAsync` で複数の変更をまとめて適用します。`CommitAsync` まではメモリ内で保持されます。競合時はデフォルトで失敗し、`WriteConflictResolution.LastWriteWins` も利用可能です。
- **スキーマ移行 / ストレージ移行**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` により、旧バージョンの設定を自動変換します。既存ファイルを Source として登録できます。
- **バックアップと復元**: `FileResource` はアトミック書き込みとバックアップ世代管理を提供します。デフォルトで 1 世代の `.bak` を保持し、`RestoreLatestBackupAsync` で復元できます。
- **安全な書き込み**: アトミック性、競合検出、リトライ。
- **セクション**: `JsonSectionResource` / XML 要素 / YAML マッピングにより、ファイルの一部を独立した Resource として扱えます。書き込み時、コメント、空白、引用符、スカラースタイルは保持されます。同一ファイル内の独立セクションは 1 回の物理書き込みにまとめられます。
- **ZIP / HTTP / S3 / Dapr**: `ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込みとポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **JSON Schema 生成**: `Configlue.JsonSchema`。設定は人間が書くものだからです。
- **Native AOT 対応**: ソース生成された `JsonSerializerContext` を渡すことで、トリミング/AOT 耐性が向上します。
- **リアクティブ統合（任意）**: `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）および `Configlue.Extensions.R3`（R3 1.3.1）。`ObserveChanges()`、`ObserveValues()`、`ObserveReloadFailures()`、`ObserveActiveValues()`、`ObserveActiveProfileNames()`。
- **DI 統合**: `Configlue.Extensions.DI`。Microsoft options アダプターは `Configlue.Extensions.MSOptions`（`IOptions<T>` など）。同期ゲッターは非同期ソースの読み取り中にブロックするため、非同期フローでは `GetValueAsync` を推奨します。
- **プロファイル / 動的オプション**: 名前付きオプションと永続プロファイルにより、実行時を単位として作成・削除できます。
- **既知の制限**: 異なる Resource を跨ぐ書き込みはアトミックではありません。Source の廃止は現在のオプションインスタンスに限定され、基盤データは残ります。ソースセットはオプションランタイムに対して固定されます。

## パッケージ構成（主なもの）

- `Configlue` … ユーザー向けメタパッケージ（Core / DI / JSON プロバイダー / JSON Schema / HTTP リソース / コモンソース / 環境変数ソース / ジェネレーターアナライザーを同梱。実装アセンブリは持たない）
- `Configlue.Abstraction` … コントラクト（プロバイダー/コーデック/リソース/生成モデル）
- `Configlue.Core` … 解決と永続化のランタイム
- `Configlue.Extensibility` … プロバイダー SDK
- `Configlue.Extensions.DI` / `Configlue.Extensions.MSOptions` / `Configlue.Extensions.R3` / `Configlue.Extensions.Reactive`
- `Configlue.Generator` … Roslyn アナライザー（スパースモデルサポートを生成）
- `Configlue.Testing` … インメモリテストダブル
- `Configlue.Provider.Json` / `.Xml` / `.Yaml` … 各フォーマットのコーデック、セクションモソース、ファイル登録
- `Configlue.JsonSchema` … JSON Schema 生成とエクスポート
- `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml`
- `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip`
- `Configlue.Transformer.AES` … Resource と Codec の間のバイト列に対する AES-GCM 暗号化と認証

インストールは `dotnet add package Configlue` から始めてください。必要な機能パッケージを追加してください。

## クイックスタート

`example.cs` として保存し、`dotnet run example.cs` で実行します（.NET 10 以降）:

```csharp
#!/usr/bin/env dotnet
#:package Configlue@*

using Configlue;
using Configlue.Source.Presets;

// 1. 設定モデルを宣言。ジェネレーターが Fragment/Patch サポートを生成。
[ConfiglueModel("SampleSetting", Version = 1)]
public partial class SampleSetting
{
    public string Name { get; set; } = "World";
    public int RunCount { get; set; }
    public bool DefaultValue { get; set; } = true;
}

// 2. プリセットレイヤーを宣言。ここにリストされたソースのみが有効。
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);

// 3. オプションインスタンス経由で読み書き。
var options = context.GetOptions<SampleSetting>();
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// スパース編集: 変更したフィールドのみがターゲットレイヤーに保存される。
await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue は変更していないので、ターゲットレイヤーには保存されない。
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

## 値の出所の確認 / スパース保存

```csharp
var options = context.GetOptions<AppSettings>();
// 1. 現在の値を取得（全ソースからマージ）
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 2. 各値の出所を確認
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

指定したメンバーのみを更新する Patch を保存します。`Unset()` はその Source の寄与を取り消し、優先度の低い Source が値を提供できるようにします:

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

その他の API:
- `IReadOnlyOptions<T>` … 日常的な読み取り画面は `GetValueAsync` と `OnChange`
- `SaveAsync(patch => ...)` … 生成された Patch によるスパース保存
- `OpenEditSessionAsync()` … 複数項目をまとめて編集し、`CommitAsync`
- `ApplyPatchesAsync` + `StateSourcePatch` … 明示的なソースごとの複数書き込み
- `StateWritePlan.For<T>().Route(...)` … 書き込みルーティング
- `SourceKey<TModel>` と `options.Source(key)` … ソースごとの操作

## 想定読者

設定管理に痛みを感じている .NET 開発者向け。`Microsoft.Extensions.Configuration` との違いとして、`IConfiguration` は読み取り指向であるのに対し、Configlue は独立したソースの合成、出所の確認、スパース保存に適しています。

