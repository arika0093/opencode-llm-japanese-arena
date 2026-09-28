# Configlue

> Make easy configuration management.

Configlue は、アプリケーションの設定管理を引き受ける **.NET ライブラリ** です。名前は **config**uration + **glue** に由来し、複数の場所に散らばった設定を単一のモデルに「glue（接着）」することを目的としています。

- 要件: .NET 10 SDK 以降（ソースジェネレーターを使うため `LangVersion` は `preview`）
- ライセンス: Apache-2.0
- 現状は「アーキテクチャ上の土台」であり、`Configuration.Writable` の完全な代替ではありません

```text
Resource (所在) → Codec (変換) → Source (寄与) → Fragment (差分) → Options (外観)
                                                ↘ Patch (編集断片)
```

## 目次

- [なぜ Configlue なのか](#なぜ-configlue-なのか)
- [コアアーキテクチャ（6 つの概念）](#コアアーキテクチャ6-つの概念)
- [主な機能](#主な機能)
- [インストール](#インストール)
- [クイックスタート](#クイックスタート)
- [値の出所の確認とスパース保存](#値の出所の確認とスパース保存)
- [主要 API](#主要-api)
- [Microsoft.Extensions.Configuration との違い](#microsoftextensionsconfiguration-との違い)
- [既知の制限](#既知の制限)

## なぜ Configlue なのか

JSON ファイルを読み書きするだけなら数行で済みます。しかし実務では、要求が積み上がっていきます。

- **設定が複数の場所に存在する**: グローバル設定、実行フォルダーごとの設定、環境変数、コマンドライン引数、暗号化された認証情報、社内ポリシーや HTTP API といったリモート管理。
- **再起動なしの変更通知**: 設定ファイルが書き換えられたら、アプリを再起動せずに反映したい。
- **書き込み先の自動選択**: 環境変数から読んだ値への書き込みはエラーにしたい（黙って無視しない）。
- **人間が書く設定ファイル**: コメントを消さない、JSON Schema を欲しい、壊れたファイルにも対応したい。
- **デフォルト値は書き出したくない**: まだデフォルトのままなら保存しない（ただし、ユーザーが明示的に設定した `null` は尊重する）。
- **設定ファイルのバージョンアップ**: 旧形式から新形式への自動変換。
- **バックアップと自動クリーンアップ**。
- **書き込みの安全さ**: 原子性（クラッシュによる破損防止）、他プロセスとの競合検知と自動マージ、自動リトライ。

これらを自分で実装するのは面倒です。その動機が Configlue の出発点です。

## コアアーキテクチャ（6 つの概念）

依存は一直線に並んでおり、学習順序も同じです。

| 概念 | ひとことで | 例 |
| --- | --- | --- |
| **Resource** | バイトがどこにあるか | ファイル、ZIP エントリ、HTTP レスポンス、メモリ |
| **Codec** | バイトと値の変換 | JSON / XML / YAML の読み書き |
| **Source** | 論理的な寄与（どのフィールドをどの優先度で） | 「ユーザ設定ファイルの `Server` 部分」 |
| **Fragment** | 有無を記憶する差分 | 「`Port` だけがある」状態 |
| **Patch** | 1 フィールドの編集 | 「`Port` を 9000 にする」 |
| **Options** | アプリが見る外観 | 読み取り、保存、監視、説明、診断 |

**読み取り**: 各 Source が Resource からバイトを取り込み、Codec がそれを Fragment に変換します。ランタイムは「存在する」フィールドだけを優先度順に、単一のモデルへ重ね合わせます。

**書き込み**: その逆方向です。アプリは普通のモデル値を編集し、内部でそれが Fragment 差分に変換されて、`WriteRoute` / `WritePlan` が指名した Source だけに届きます。無関係な Source は変更されません。

- Fragment は「メンバーが無い」ことと「`null` / デフォルトとして存在する」ことを区別します。「未設定」が「デフォルトに設定済み」を上書きすることは、レイヤー合成でも起きません。
- Patch は生成される `TModel.Patch`（1 フィールドの編集断片）です。`Unset()` は書き込み先の Source の寄与だけを取り下げ、下優先の Source の値を再び露出させます。
- `[ConfiglueMerge]` でメンバーごとの合成挙動を変更できます（組み込み: `Append` / `Deep` / `Replace` / `SetUnion`、カスタム戦略も可）。コレクションのレイヤー合成と順序はここで決まります。

## 主な機能

- **複数ソースの優先度マージ**: `Priority` が大きい Source が勝ちます。`GetDetailsAsync` で「どの値がどこから来たか」を調べられます。
- **読み取り専用ソース**: 環境変数、コマンドライン、既定の HTTP ソースは読み取り専用です。読み取り専用の値への書き込みは黙って無視されず、競合エラーを送出します。
- **投影 / マウント**: 既存の Source を別のモデルに再整形（投影）したり、ネストしたパスに別 Source を取り付けたりできます（マウント、`AddMounted`）。
- **プリセット**: `UseCommonSources` が標準的なレイヤー構成（グローバル / ローカル / 環境変数など）を組み立てます。
- **スパース書き込み**: 変更したフィールドだけが対象レイヤーに保存されます。デフォルトのままのフィールドは書き出されません。
- **編集セッション**: `OpenEditSessionAsync` で複数の変更をまとめて適用し、`CommitAsync` までメモリ上に保持します。競合時は既定で失敗し、`WriteConflictResolution.LastWriteWins` も選べます。
- **スキーママイグレーション / ストレージマイグレーション**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` で旧バージョンの設定を自動変換します。既存ファイルをそのまま Source として登録できます。
- **バックアップと復元**: `FileResource` が原子的な書き込みとバックアップ世代管理を提供します。既定で `.bak` を 1 世代残し、`RestoreLatestBackupAsync` で復元します。
- **安全な書き込み**: 原子性、競合検知、リトライ。
- **セクション**: `JsonSectionResource` / XML 要素 / YAML マッピングにより、ファイルの一部分を独立した Resource として扱えます。書き込み時はコメント、空白、引用符、スカラー スタイルを保持します。同じファイル内の独立したセクションは 1 回の物理書き込みにまとめられます。
- **ZIP / HTTP / S3 / Dapr**: `ZipEntryResource`、`Configlue.Resource.Http`（ETag による条件付き書き込みとポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **JSON Schema 生成**: 設定は人間が書くものなので、`Configlue.JsonSchema` を用意しています。
- **Native AOT 対応**: ソースジェネレーターで生成した `JsonSerializerContext` を渡すと、トリミング / AOT 耐性が向上します。
- **リアクティブ統合（任意）**: `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）。`ObserveChanges()`、`ObserveValues()`、`ObserveReloadFailures()`、`ObserveActiveValues()`、`ObserveActiveProfileNames()`。
- **DI 統合**: `Configlue.Extensions.DI`。Microsoft options アダプターは `Configlue.Extensions.MSOptions`（`IOptions<T>` など）。同期 getter は非同期ソースの読み込み中にブロックするため、非同期のフローでは `GetValueAsync` を推奨します。
- **プロファイル / 動的 options**: 名前付き options と永続プロファイルにより、ランタイムを単位として作成・削除できます。

## インストール

```bash
dotnet add package Configlue
```

必要な機能のパッケージを追加します。

### パッケージ構成（主なもの）

- `Configlue` … ユーザー向けメタパッケージ（Core / DI / JSON プロバイダー / JSON Schema / HTTP リソース / 共通ソース / 環境変数ソース / ジェネレーター アナライザーを同梱。独自の実装アセンブリはありません）
- `Configlue.Abstraction` … 契約（provider / codec / resource / generated-model）
- `Configlue.Core` … 解決と永続化のランタイム
- `Configlue.Extensibility` … プロバイダー SDK
- `Configlue.Extensions.DI` / `Configlue.Extensions.MSOptions` / `Configlue.Extensions.R3` / `Configlue.Extensions.Reactive`
- `Configlue.Generator` … Roslyn アナライザー（スパースモデル対応を生成）
- `Configlue.Testing` … インメモリのテスト用ダブル
- `Configlue.Provider.Json` / `.Xml` / `.Yaml` … 各形式の codec、セクション resource、ファイル登録
- `Configlue.JsonSchema` … JSON Schema の生成とエクスポート
- `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml`
- `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip`
- `Configlue.Transformer.AES` … Resource と Codec の間のバイトを AES-GCM で暗号化・認証

## クイックスタート

以下を `example.cs` として保存し、.NET 10 以降で `dotnet run example.cs` を実行します。

```csharp
#!/usr/bin/env dotnet
#:package Configlue@*

using Configlue;
using Configlue.Source.Presets;

// 1. 設定モデルを宣言する。ジェネレーターが Fragment / Patch 対応を生成する。
[ConfiglueModel("SampleSetting", Version = 1)]
public partial class SampleSetting
{
    public string Name { get; set; } = "World";
    public int RunCount { get; set; }
    public bool DefaultValue { get; set; } = true;
}

// 2. プリセットのレイヤーを宣言する。ここに挙げたソースだけが有効になる。
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);

// 3. options インスタンス経由で読み書きする。
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

## 値の出所の確認とスパース保存

```csharp
var options = context.GetOptions<AppSettings>();
// 1. 現在の値を取得する（すべてのソースからマージ済み）
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

指定したメンバーだけを更新するパッチを保存できます。`Unset()` はその Source の寄与を取り下げ、下優先の Source に値を委ねます。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

## 主要 API

- `IReadOnlyOptions<T>` … 日常の読み取り面は `GetValueAsync` と `OnChange`
- `SaveAsync(patch => ...)` … 生成された Patch によるスパース保存
- `OpenEditSessionAsync()` … 複数をまとめて編集し、`CommitAsync`
- `ApplyPatchesAsync` + `StateSourcePatch` … ソース単位の明示的な複数書き込み
- `StateWritePlan.For<T>().Route(...)` … 書き込みルーティング
- `SourceKey<TModel>` と `options.Source(key)` … ソース単位の操作

## Microsoft.Extensions.Configuration との違い

`IConfiguration` は読み取り中心の API です。一方 Configlue は、独立したソースの合成、出所（provenance）の調査、そしてスパース保存に向いています。複数レイヤーを優先度で重ね、どの値がどこから来たかを問い、変更したフィールドだけを書き戻すといった用途では Configlue のモデルが合います。

## 既知の制限

- 異なる Resource をまたぐ書き込みは原子的ではありません。
- ソースの退役は現在の options インスタンスの範囲に限定され、裏側のデータは残ります。
- ソース集合は options ランタイムに対して固定です。

## ライセンス

Apache-2.0
