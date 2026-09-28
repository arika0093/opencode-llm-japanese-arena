# Configlue

> Make easy configuration management.

Configlue は、アプリケーションの設定管理を引き受ける .NET ライブラリです。
グローバル設定・実行フォルダーごとの設定・環境変数・コマンドライン引数・暗号化された資格情報・HTTP API など、**複数の場所に散らばった設定をひとつのモデルに糊付け（glue）する**ことを中心思想としており、ライブラリ名は configuration + glue に由来します。

現在は「アーキテクチャ基盤」の段階であり、`Configuration.Writable` の完全な置き換えではありません。

## 目次

- [なぜ Configlue なのか](#なぜ-configlue-なのか)
- [コアアーキテクチャ（6 つの概念）](#コアアーキテクチャ6-つの概念)
- [主な機能](#主な機能)
- [インストールとパッケージ構成](#インストールとパッケージ構成)
- [クイックスタート](#クイックスタート)
- [値の出所の確認とスパース保存](#値の出所の確認とスパース保存)
- [その他の API](#その他の-api)
- [Microsoft.Extensions.Configuration との違い](#microsoftextensionsconfiguration-との違い)
- [既知の制限](#既知の制限)
- [動作環境とライセンス](#動作環境とライセンス)

## なぜ Configlue なのか

JSON ファイルを 1 つ読み書きするだけなら数行で済みます。しかし実際の運用では、要件が次のように積み上がっていきます。

- 設定が複数の場所に存在する（グローバル設定、実行フォルダーごとの設定、環境変数、コマンドライン引数、暗号化された資格情報、企業ポリシーや HTTP API によるリモート管理）
- 設定ファイルが書き換えられたら、アプリケーションを再起動せずに反映したい（変更通知）
- 書き込み先を自動的に選びたい。環境変数から読み取った値への書き込みはエラーにしたい
- 設定ファイルは人間が書くものである。コメントを消したくない、JSON Schema に対応したい、壊れたファイルを扱いたい
- 既定値のままの項目は書き出したくない（ただしユーザーが明示的に設定した `null` は尊重したい）
- 設定ファイルをバージョンアップしたい（旧形式から新形式への自動変換）
- バックアップと自動クリーンアップ
- 書き込みの安全性。原子性（クラッシュしても壊れない）、他プロセスとの競合検出と自動マージ、自動リトライ

これらをすべて自前で実装するのは骨が折れます。Configlue はその面倒を引き受けます。

## コアアーキテクチャ（6 つの概念）

依存関係は一直線で、学習順序も同じです。

```text
Resource (location) → Codec (conversion) → Source (contribution) → Fragment (diff) → Options (facade)
                                                        ↘ Patch (edit fragment)
```

| 概念 | ひとことで言うと | 例 |
| --- | --- | --- |
| Resource | バイト列がどこにあるか | ファイル、ZIP エントリ、HTTP レスポンス、メモリ |
| Codec | バイト列と値の変換 | JSON / XML / YAML の読み書き |
| Source | 論理的な寄与（どのフィールドをどの優先度で供給するか） | 「ユーザー設定ファイルの `Server` 部分」 |
| Fragment | 存在を記憶する差分 | 「`Port` だけを持っている」状態 |
| Patch | 単一フィールドの編集 | 「`Port` を 9000 にする」 |
| Options | アプリケーションから見えるファサード | 読み取り、保存、監視、説明、診断 |

**読み取り** では、各 Source が Resource からバイト列を取得し、Codec が Fragment に変換します。ランタイムは「存在する」フィールドだけを優先度順に重ね合わせ、ひとつのモデルに合成します。

**書き込み** はその逆方向です。アプリケーションはごく普通のモデル値を編集します。内部的にはその変更が Fragment の差分となり、`WriteRoute` / `WritePlan` で指名された Source にのみ到達します。関係のない Source は変更されません。

- Fragment は「メンバーが存在しない」ことと「`null` や既定値として存在する」ことを区別します。レイヤー合成で「未設定」が「既定値に設定済み」を上書きすることはありません。
- Patch は生成される `TModel.Patch`（単一フィールド編集用の Fragment）です。`Unset()` は書き込み先 Source の寄与だけを取り下げ、下位優先度の値を再び表出させます。
- `[ConfiglueMerge]` でメンバーごとのマージ挙動を変更できます（組み込みは `Append`、`Deep`、`Replace`、`SetUnion`。カスタム戦略も可能）。コレクションのレイヤー合成と順序はここで決まります。

## 主な機能

- **複数ソースの優先度マージ** — `Priority` の大きい Source が勝ちます。`GetDetailsAsync` で「どの値がどこから来たか」を検査できます。
- **読み取り専用ソース** — 環境変数、コマンドライン、既定の HTTP ソースは読み取り専用です。読み取り専用値への書き込みは黙って無視されるのではなく、競合エラーになります。
- **射影 / マウント** — 既存の Source を別のモデルに再構成（射影）したり、入れ子のパスに別の Source を取り付け（マウント、`AddMounted`）たりできます。
- **プリセット** — `UseCommonSources` が標準的なレイヤー構成（グローバル／ローカル／環境変数など）を組み立てます。
- **スパース書き込み** — 変更したフィールドだけが対象レイヤーに保存されます。既定値のままのフィールドは書き込まれません。
- **編集セッション** — `OpenEditSessionAsync` で複数の変更をまとめて適用します。`CommitAsync` まではメモリ内です。競合時は既定で失敗します。`WriteConflictResolution.LastWriteWins` も利用できます。
- **スキーマ移行 / ストレージ移行** — `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` により、旧バージョン設定の自動変換を行います。既存ファイルを Source として登録できます。
- **バックアップと復元** — `FileResource` が原子書き込みとバックアップ世代管理を提供します。既定では `.bak` を 1 世代保持し、`RestoreLatestBackupAsync` で復元します。
- **安全な書き込み** — 原子性、競合検出、リトライ。
- **セクション** — `JsonSectionResource` / XML 要素 / YAML マッピングにより、ファイルの一部を独立した Resource として扱えます。書き込み時にコメント、空白、クォート、スカラー形式を保持します。同一ファイル内の独立したセクションは 1 回の物理書き込みにまとめられます。
- **ZIP / HTTP / S3 / Dapr** — `ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込みとポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **JSON Schema 生成** — 設定を書くのは人間なので、`Configlue.JsonSchema` を用意しています。
- **Native AOT 対応** — ソース生成した `JsonSerializerContext` を渡すと、トリミングや AOT に対する耐性が向上します。
- **リアクティブ統合（オプション）** — `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）。`ObserveChanges()`、`ObserveValues()`、`ObserveReloadFailures()`、`ObserveActiveValues()`、`ObserveActiveProfileNames()`。
- **DI 統合** — `Configlue.Extensions.DI`。Microsoft オプションアダプターは `Configlue.Extensions.MSOptions`（`IOptions<T>` など）にあります。同期 getter は非同期ソースの読み込み中にブロックするため、非同期フローでは `GetValueAsync` を推奨します。
- **プロファイル / 動的オプション** — 名前付きオプションと永続プロファイルにより、ランタイムを一単位として作成・削除できます。

## インストールとパッケージ構成

```bash
dotnet add package Configlue
```

`Configlue` から始め、必要な機能パッケージを追加してください。

| パッケージ | 内容 |
| --- | --- |
| `Configlue` | 利用者を想定したメタパッケージ（Core / DI / JSON プロバイダー / JSON Schema / HTTP リソース / 共通ソース / 環境変数ソース / ジェネレーター分析器を同梱。実装アセンブリ自体は持ちません） |
| `Configlue.Abstraction` | 契約（プロバイダー／コーデック／リソース／生成モデル） |
| `Configlue.Core` | 解決と永続化のランタイム |
| `Configlue.Extensibility` | プロバイダー SDK |
| `Configlue.Extensions.DI` / `.MSOptions` / `.R3` / `.Reactive` | DI・Microsoft オプション・リアクティブ統合 |
| `Configlue.Generator` | Roslyn 分析器（スパースモデル支援を生成） |
| `Configlue.Testing` | インメモリのテストダブル |
| `Configlue.Provider.Json` / `.Xml` / `.Yaml` | 各形式のコーデック、セクションリソース、ファイル登録 |
| `Configlue.JsonSchema` | JSON Schema の生成とエクスポート |
| `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml` | 環境変数・コマンドライン・プリセット |
| `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip` | リモート・アーカイブ系リソース |
| `Configlue.Transformer.AES` | Resource と Codec の間でバイト列に対する AES-GCM の暗号化と認証 |

## クイックスタート

次のコードを `example.cs` として保存し、`dotnet run example.cs` で実行できます（.NET 10 以降）。

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

手順は次の 3 つです。

1. `[ConfiglueModel]` を付けた設定モデルを宣言します。ジェネレーターが Fragment / Patch 支援を生成します。
2. `ConfiglueApp.CreateContext` と `UseCommonSources` でレイヤーを宣言します。ここに挙げたソースだけが有効になります。
3. オプションインスタンス経由で読み書きします。`SaveAsync` に渡したパッチのうち、変更したフィールドだけが対象レイヤーに保存されます。

## 値の出所の確認とスパース保存

```csharp
var options = context.GetOptions<AppSettings>();
// 1. Get the current value (merged from all sources)
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 2. Inspect where each value came from
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

指定したメンバーだけを反映するパッチを保存できます。`Unset()` はその Source の寄与を削除し、下位優先度の Source が値を供給できるようにします。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

## その他の API

| API | 役割 |
| --- | --- |
| `IReadOnlyOptions<T>` | 日常の読み取り面。`GetValueAsync` と `OnChange` |
| `SaveAsync(patch => ...)` | 生成された Patch によるスパース保存 |
| `OpenEditSessionAsync()` | 複数変更をまとめて編集し、`CommitAsync` で確定 |
| `ApplyPatchesAsync` + `StateSourcePatch` | ソースを明示した複数書き込み |
| `StateWritePlan.For<T>().Route(...)` | 書き込みルーティング |
| `SourceKey<TModel>` と `options.Source(key)` | ソース単位の操作 |

## Microsoft.Extensions.Configuration との違い

`IConfiguration` は読み取り志向です。一方 Configlue は、独立したソースの合成、値の出所（来歴）の検査、スパース保存に向いています。設定を書き戻し、その書き込み先を意識する必要がある場面が Configlue の対象です。

## 既知の制限

- 異なる Resource をまたぐ書き込みは原子的ではありません。
- Source の退役は現在のオプションインスタンスの範囲に限られ、背後のデータはそのまま残ります。
- オプションランタイムのソース集合は固定です。

## 動作環境とライセンス

- **.NET 10 SDK 以降**
- C#（`LangVersion` はソースジェネレーターをサポートする必要があります。リポジトリは `preview` でビルドしています）
- License: **Apache-2.0**

