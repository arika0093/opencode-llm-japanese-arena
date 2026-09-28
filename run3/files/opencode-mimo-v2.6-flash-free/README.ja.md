# Configlue

> Make easy configuration management.

Configlue は、アプリケーションの設定管理を引き受ける .NET ライブラリです。名前は **config**uration + **glue** に由来し、複数の場所に分散した設定を一つのモデルへ「グルー（接着）」して扱うことがコンセプトの中心です。

- 要件: .NET 10 SDK 以降（ソースジェネレーターを使うため `LangVersion` は `preview` でビルドしています）
- ライセンス: Apache-2.0
- 現状: 「アーキテクチャの土台」であり、`Configuration.Writable` の完全な置き換えではありません

## なぜ Configlue なのか

JSON ファイルを読み書きするだけなら数行で済みます。しかし実運用では、次の要求が積み上がっていきます。

- 設定が複数の場所に存在する：グローバル設定、ランタイムフォルダーごとの設定、環境変数、コマンドライン引数、暗号化された資格情報、社内ポリシーや HTTP API などのリモート管理。
- 設定ファイルの書き換えを、アプリ再起動なしで反映したい（変更通知）。
- 書き込み先を自動で選びたい。環境変数から読んだ値への書き込みはエラーにしたい。
- 設定ファイルは人間が書く：コメントを消さない、JSON Schema が欲しい、壊れたファイルにも対応したい。
- まだデフォルト値のままなら書き出したくない（ただし、ユーザーが明示した `null` は尊重したい）。
- 設定ファイルをバージョンアップしたい（旧形式から新形式への自動変換）。
- バックアップと自動クリーンアップ。
- 書き込みの安全性：アトミック性（クラッシュによる破壊がない）、他プロセスとの競合検知と自動マージ、自動リトライ。

これらを自分で実装するのは煩雑なので、Configlue はその面倒な部分を引き受けます。

`Microsoft.Extensions.Configuration`（`IConfiguration`）が読み取り志向なのに対し、Configlue は独立したソースの合成、出所（プロヴナンス）の調査、疎な保存に向いています。

## コアアーキテクチャ（6 つの概念）

依存は一直線で、学習順も同じです。

```text
Resource (場所) → Codec (変換) → Source (寄与) → Fragment (差分) → Options (外向け API)
                                                     ↘ Patch (編集フラグメント)
```

| 概念 | 一言で | 例 |
| --- | --- | --- |
| Resource | バイトが住む場所 | ファイル、ZIP エントリ、HTTP レスポンス、メモリ |
| Codec | バイトと値の変換 | JSON / XML / YAML の読み書き |
| Source | 論理的な寄与（どのフィールドをどの優先度で） | 「ユーザ設定ファイルの `Server` 部分」 |
| Fragment | 「存在」を覚える差分 | 「`Port` だけを持つ」状態 |
| Patch | 1 フィールドの編集 | 「`Port` を 9000 に設定」 |
| Options | アプリが見る外向け API | 読む、保存、監視、説明、診断 |

**読み取り**: 各 Source は Resource からバイトを取り込み、Codec がそれを Fragment に変換します。ランタイムは「存在する」フィールドだけを優先度順に重ねて、単一のモデルに合成します。

**書き込み**: その逆方向です。アプリはふつうのモデル値を編集します。内部ではその変更が Fragment の差分になり、`WriteRoute` / `WritePlan` が指名した Source にだけ届きます。無関係な Source は変更されません。

- Fragment は「メンバーが欠落している」と「null/デフォルトとして存在している」を区別します。レイヤー合成で「未設定」が「デフォルトで設定済み」を上書きすることはありません。
- Patch はジェネレーターが生成する `TModel.Patch`（1 フィールドの編集フラグメント）です。`Unset()` は書き込み先の Source からの寄与だけを取り下げ、より優先度の低い値を再び露出させます。
- `[ConfiglueMerge]` でメンバーごとのマージ挙動を変更できます（組み込み: `Append` / `Deep` / `Replace` / `SetUnion`、独自戦略も可）。コレクションのレイヤー合成と順序はここで決めます。

## 主な機能

- **複数ソースの優先度マージ**: `Priority` が大きい Source が勝ちます。`GetDetailsAsync` で「どの値がどこから来たか」を調査できます。
- **読み取り専用ソース**: 環境変数、コマンドライン、既定の HTTP ソースは読み取り専用です。読み取り専用の値への書き込みは黙って無視されず、競合エラーを送出します。
- **投影 / マウント**: 既存の Source を別のモデルへ整形し直して（投影して）扱えます。また、ネストしたパスに別の Source を取り付けられます（マウント、`AddMounted`）。
- **プリセット**: `UseCommonSources` が標準的なレイヤー構成（グローバル / ローカル / 環境変数など）を組み立てます。
- **疎な書き込み**: 変更したフィールドだけが対象レイヤーに保存されます。デフォルトのまま残したフィールドは書き出されません。
- **編集セッション**: `OpenEditSessionAsync` で複数の変更をまとめて適用し、`CommitAsync` までメモリ上に保持します。競合時は既定で失敗し、`WriteConflictResolution.LastWriteWins` も選べます。
- **スキーマ移行 / ストレージ移行**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` により旧バージョンの設定を自動変換します。既存ファイルを Source として登録できます。
- **バックアップと復元**: `FileResource` がアトミック書き込みとバックアップ世代管理を提供します。既定で `.bak` は 1 世代、`RestoreLatestBackupAsync` で復元します。
- **安全な書き込み**: アトミック性、競合検知、リトライ。
- **セクション**: `JsonSectionResource` / XML 要素 / YAML マッピングで、ファイルの一部を独立した Resource として扱えます。書き込み時はコメント、空白、クォート、スカルースタイルを保持します。同じファイル内の独立セクションは 1 回の物理書き込みにまとめられます。
- **ZIP / HTTP / S3 / Dapr**: `ZipEntryResource`、`Configlue.Resource.Http`（ETag による条件付き書き込みとポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **JSON Schema 生成**: 設定は人間が書くものなので、`Configlue.JsonSchema` を用意しています。
- **Native AOT 対応**: ソースジェネレーター出力の `JsonSerializerContext` を渡すと、トリミング / AOT に強くなります。
- **リアクティブ統合（任意）**: `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）。`ObserveChanges()`、`ObserveValues()`、`ObserveReloadFailures()`、`ObserveActiveValues()`、`ObserveActiveProfileNames()`。
- **DI 統合**: `Configlue.Extensions.DI`。Microsoft options アダプタは `Configlue.Extensions.MSOptions`（`IOptions<T>` など）。同期のゲッターは非同期ソースの読み込み中にブロックするため、非同期フローでは `GetValueAsync` を推奨します。
- **プロファイル / 動的オプション**: 名前付きオプションと永続プロファイルにより、ランタイムを単位として生成・削除できます。
- **既知の制限**: 異なる Resource 間の書き込みはアトミックではありません。Source の退役は現在のオプションインスタンスにスコープされ、裏のデータは残ります。ソース集合はオプションのランタイムに対して固定です。

## パッケージ構成（主なもの）

- `Configlue` … ユーザー向けメタパッケージ（Core / DI / JSON プロバイダー / JSON Schema / HTTP リソース / 共通ソース / 環境変数ソース / ジェネレーター解析器を同梱。独自の実装アセンブリはありません）
- `Configlue.Abstraction` … 契約（provider / codec / resource / 生成モデル）
- `Configlue.Core` … 解決と永続化のランタイム
- `Configlue.Extensibility` … プロバイダー SDK
- `Configlue.Extensions.DI` / `Configlue.Extensions.MSOptions` / `Configlue.Extensions.R3` / `Configlue.Extensions.Reactive`
- `Configlue.Generator` … Roslyn アナライザー（疎なモデル対応を生成）
- `Configlue.Testing` … インメモリのテスト用替身
- `Configlue.Provider.Json` / `.Xml` / `.Yaml` … 各形式のコーデック、セクションリソース、ファイル登録
- `Configlue.JsonSchema` … JSON Schema の生成とエクスポート
- `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml`
- `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip`
- `Configlue.Transformer.AES` … Resource と Codec の間のバイトを AES-GCM で暗号化・認証

インストールは `dotnet add package Configlue` から。必要な機能パッケージを追加してください。

## クイックスタート

次を `example.cs` に保存し、`dotnet run example.cs` で実行します（.NET 10 以降）。

```csharp
#!/usr/bin/env dotnet
#:package Configlue@*

using Configlue;
using Configlue.Source.Presets;

// 1. 設定モデルを宣言する。ジェネレーターが Fragment/Patch 対応を生成する。
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

// 3. オプションインスタンス経由で読み書きする。
var options = context.GetOptions<SampleSetting>();
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 疎な編集：変更したフィールドだけが対象レイヤーに保存される。
await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue は変更していないので対象レイヤーに保存されない。
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

## 値の出所を調べる / 疎な保存

```csharp
var options = context.GetOptions<AppSettings>();
// 1. 現在の値（全ソースのマージ結果）を取得する
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

指定したメンバーだけを更新するパッチを保存できます。`Unset()` はその Source の寄与を取り下げ、より優先度の低い Source に値を委ねます。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

その他の API:

- `IReadOnlyOptions<T>` … 日常の読み取り面は `GetValueAsync` と `OnChange`。
- `SaveAsync(patch => ...)` … 生成された Patch による疎な保存。
- `OpenEditSessionAsync()` … 複数をまとめて編集し、`CommitAsync` する。
- `ApplyPatchesAsync` + `StateSourcePatch` … ソースごとの明示的な複数書き込み。
- `StateWritePlan.For<T>().Route(...)` … 書き込みルーティング。
- `SourceKey<TModel>` と `options.Source(key)` … ソースごとの操作。
