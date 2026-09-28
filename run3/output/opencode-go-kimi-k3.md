# Configlue

> Make easy configuration management.

**Configlue** は、アプリケーションの設定管理をまるごと引き受ける .NET ライブラリです。複数の場所に散らばった設定を 1 つのモデルに「接着 (glue)」することを中心思想としており、名前は configuration + glue に由来します。

- **要件**: .NET 10 SDK 以降。C# の `LangVersion` はソースジェネレーターに対応していること (リポジトリでは `preview` でビルドしています)。
- **ライセンス**: Apache-2.0
- **現状**: 現時点では「アーキテクチャの土台」であり、`Configuration.Writable` の完全な代替ではありません。

## なぜ Configlue?

JSON ファイルの読み書き自体は数行で書けます。しかし実際には、次のような要求が積み上がっていきます。

- 設定は複数の場所に存在する: グローバル設定、実行フォルダーごとの設定、環境変数、コマンドライン引数、暗号化された資格情報、社内ポリシーや HTTP API によるリモート管理。
- 設定ファイルが書き換えられたら、アプリを再起動せずに反映したい (変更通知)。
- 書き込み先を自動で選びたい。環境変数から読んだ値への書き込みはエラーにしたい。
- 設定ファイルは人間が書くもの: コメントを消さないでほしい、JSON Schema 対応がほしい、壊れたファイルをハンドリングしたい。
- 値が既定値のままなら書き出さないでほしい (ただしユーザーが明示的に設定した `null` は尊重する)。
- 設定ファイルをバージョンアップしたい (旧形式から新形式への自動変換)。
- バックアップと自動クリーンアップ。
- 書き込みの安全性: アトミック性 (クラッシュしても壊れない)、他プロセスとの競合検出と自動マージ、自動リトライ。

これらをすべて自分で実装するのは骨が折れます。Configlue はそのためにあります。

### Microsoft.Extensions.Configuration との違い

`IConfiguration` は読み取り中心の設計です。一方 Configlue は、独立したソースの合成、値の出所の検査、スパース保存 (変更したフィールドだけを保存) に適した設計になっています。

## インストール

```text
dotnet add package Configlue
```

`Configlue` はユーザー向けのメタパッケージです (Core / DI / JSON プロバイダー / JSON Schema / HTTP リソース / 共通ソース / 環境変数ソース / ジェネレーター アナライザーを束ねており、自身の実装アセンブリーは持ちません)。必要に応じて機能パッケージを追加してください (「パッケージ構成」を参照)。

## クイックスタート

以下を `example.cs` に保存し、`dotnet run example.cs` で実行できます (.NET 10 以降)。

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

// 2. プリセットのレイヤーを宣言します。ここに列挙したソースだけが有効になります。
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);

// 3. options インスタンスを通して読み書きします。
var options = context.GetOptions<SampleSetting>();
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// スパース編集: 変更したフィールドだけが対象レイヤーに保存されます。
await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue は変更していないため、対象レイヤーには保存されません。
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

## コアアーキテクチャ (6 つの概念)

依存関係は一直線で、学習順序も同じです。

```text
Resource (場所) → Codec (変換) → Source (寄与) → Fragment (差分) → Options (ファサード)
                                                      ↘ Patch (編集フラグメント)
```

| 概念 | 一言で言うと | 例 |
| --- | --- | --- |
| Resource | バイト列の置き場所 | ファイル、ZIP エントリー、HTTP レスポンス、メモリー |
| Codec | バイト列と値の相互変換 | JSON / XML / YAML の読み書き |
| Source | 論理的な「寄与」(どのフィールドをどの優先度で) | 「ユーザー設定ファイルの `Server` 部分」 |
| Fragment | 存在を記憶する差分 | 「`Port` だけを持つ」状態 |
| Patch | 1 フィールドの編集 | 「`Port` を 9000 に設定する」 |
| Options | アプリから見えるファサード | 読み取り、保存、監視、説明、診断 |

**読み取り**: 各 Source が Resource からバイト列を取得し、Codec がそれを Fragment に変換します。ランタイムは「存在する」フィールドだけを優先度順に重ねて、1 つのモデルに合成します。

**書き込み**: 逆方向です。アプリは普通のモデル値を編集します。内部的には変更が Fragment の差分となり、`WriteRoute` / `WritePlan` が指名した Source にだけ届きます。無関係な Source は変更されません。

- Fragment は「メンバーが存在しない」と「null / 既定値として存在する」を区別します。レイヤー合成で「未設定」が「既定値に設定済み」を上書きすることはありません。
- Patch は生成される `TModel.Patch` (単一フィールドの編集フラグメント) です。`Unset()` は書き込み先 Source の寄与だけを取り下げ、低優先度の値を再び表面に出します。
- `[ConfiglueMerge]` でメンバーごとのマージ動作を変更できます (組み込み: `Append`、`Deep`、`Replace`、`SetUnion`。カスタム戦略も可能)。コレクションのレイヤー合成や順序はここで決まります。

## 主な機能

- **複数ソースの優先度マージ**: `Priority` が大きい Source が勝ちます。`GetDetailsAsync` で「どの値がどこから来たか」を検査できます。
- **読み取り専用ソース**: 環境変数、コマンドライン、既定の HTTP ソースは読み取り専用です。読み取り専用の値への書き込みは暗黙に無視されず、競合エラーになります。
- **プロジェクション / マウント**: 既存の Source を別のモデルに整形 (プロジェクション) したり、ネストしたパスに別の Source を取り付け (マウント、`AddMounted`) たりできます。
- **プリセット**: `UseCommonSources` が標準的なレイヤー構成 (グローバル / ローカル / 環境変数など) を組み立てます。
- **スパース書き込み**: 変更したフィールドだけが対象レイヤーに保存されます。既定値のままのフィールドは書き込まれません。
- **編集セッション**: `OpenEditSessionAsync` で複数の変更をまとめて適用できます。`CommitAsync` まではメモリー上の変更です。競合時は既定で失敗します。`WriteConflictResolution.LastWriteWins` も利用可能です。
- **スキーマ移行 / ストレージ移行**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` による旧バージョン設定の自動変換。既存ファイルを Source として登録できます。
- **バックアップと復元**: `FileResource` はアトミックな書き込みとバックアップ世代管理を提供します。既定で `.bak` を 1 世代保持し、`RestoreLatestBackupAsync` で復元できます。
- **安全な書き込み**: アトミック性、競合検出、リトライ。
- **セクション**: `JsonSectionResource` / XML 要素 / YAML マッピングにより、ファイルの一部を独立した Resource として扱えます。書き込み時にコメント、空白、引用符、スカラースタイルが保持されます。同一ファイル内の独立したセクションは 1 回の物理書き込みにバッチ処理されます。
- **ZIP / HTTP / S3 / Dapr**: `ZipEntryResource`、`Configlue.Resource.Http` (ETag 条件付き書き込みとポーリング)、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **JSON Schema 生成**: `Configlue.JsonSchema`。人間が設定を書くからこそ。
- **Native AOT 対応**: ソース生成された `JsonSerializerContext` を渡すことで、トリミング / AOT 耐性が向上します。
- **リアクティブ連携 (オプション)**: `Configlue.Extensions.Reactive` (System.Reactive 7.0.0) と `Configlue.Extensions.R3` (R3 1.3.1)。`ObserveChanges()`、`ObserveValues()`、`ObserveReloadFailures()`、`ObserveActiveValues()`、`ObserveActiveProfileNames()`。
- **DI 連携**: `Configlue.Extensions.DI`。Microsoft オプションアダプターは `Configlue.Extensions.MSOptions` (`IOptions<T>` など。同期ゲッターは非同期ソースの読み取り中にブロックするため、非同期フローでは `GetValueAsync` を推奨)。
- **プロファイル / 動的オプション**: 名前付きオプションと永続化プロファイルにより、ランタイムを単位として作成・削除できます。

### 既知の制限

- 異なる Resource にまたがる書き込みはアトミックではありません。
- Source の退避 (retirement) は現在の options インスタンスにスコープされ、背後のデータはそのまま残ります。
- ソース集合は options ランタイムごとに固定です。

## 値の出所の検査とスパース保存

```csharp
var options = context.GetOptions<AppSettings>();
// 1. 現在の値を取得 (全ソースをマージしたもの)
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 2. 各値の出所を検査
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

指定したメンバーだけを更新するパッチを保存できます。`Unset()` はその Source の寄与を取り除くため、より低い優先度の Source が値を提供できるようになります。

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
- `OpenEditSessionAsync()` … 複数の変更をまとめて編集し、`CommitAsync`。
- `ApplyPatchesAsync` + `StateSourcePatch` … ソースごとの明示的な複数書き込み。
- `StateWritePlan.For<T>().Route(...)` … 書き込みルーティング。
- `SourceKey<TModel>` と `options.Source(key)` … ソースごとの操作。

## パッケージ構成 (主なもの)

- `Configlue` … ユーザー向けメタパッケージ (Core / DI / JSON プロバイダー / JSON Schema / HTTP リソース / 共通ソース / 環境変数ソース / ジェネレーター アナライザーを束ねる。自身の実装アセンブリーは持たない)。
- `Configlue.Abstraction` … コントラクト (プロバイダー / コーデック / リソース / 生成モデル)。
- `Configlue.Core` … 解決と永続化のランタイム。
- `Configlue.Extensibility` … プロバイダー SDK。
- `Configlue.Extensions.DI` / `Configlue.Extensions.MSOptions` / `Configlue.Extensions.R3` / `Configlue.Extensions.Reactive`
- `Configlue.Generator` … Roslyn アナライザー (スパースモデルサポートを生成)。
- `Configlue.Testing` … インメモリーのテストダブル。
- `Configlue.Provider.Json` / `.Xml` / `.Yaml` … 各形式のコーデック、セクションリソース、ファイル登録。
- `Configlue.JsonSchema` … JSON Schema の生成とエクスポート。
- `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml`
- `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip`
- `Configlue.Transformer.AES` … Resource と Codec の間のバイト列に対する AES-GCM 暗号化と認証。

## ライセンス

Apache-2.0
