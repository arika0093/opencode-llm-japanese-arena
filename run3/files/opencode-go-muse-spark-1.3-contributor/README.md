# Configlue

**Make easy configuration management.**

Configlue は、アプリケーションの構成管理を引き受ける .NET ライブラリです。複数の場所に散らばった構成をひとつのモデルに **glue（貼り合わせ）** するのが中心思想で、名前は configuration + glue に由来します。

- 要件: .NET 10 SDK 以降。C# の `LangVersion` はソースジェネレーターをサポートすること（リポジトリは `preview` でビルド）。
- ライセンス: Apache-2.0。
- 現状は「アーキテクチャの基盤」であり、`Configuration.Writable` の完全な置き換えではありません。

## なぜ Configlue か

JSON ファイルをひとつ読み書きするだけなら数行で済みます。しかし実際には、次のような要件が積み重なります。

- 構成は複数の場所に存在する: グローバル設定、ランタイムフォルダーごとの設定、環境変数、コマンドライン引数、暗号化されたクレデンシャル、企業ポリシーや HTTP API のようなリモート管理。
- 構成ファイルが書き換えられたら、アプリを再起動せずに反映したい（変更通知）。
- 書き込み先を自動で選びたい。環境変数から読んだ値への書き込みはエラーにすべき。
- 構成ファイルは人間が書く: コメントを消さない、JSON Schema が欲しい、壊れたファイルへの対応。
- デフォルト値のままの値は書き出さない（ただしユーザーが明示的に設定した `null` は尊重する）。
- 構成ファイルのバージョンアップ（旧形式から新形式への自動変換）。
- バックアップと自動クリーンアップ。
- 書き込みの安全性: 原子性（クラッシュしても壊れない）、他プロセスとの競合検出と自動マージ、自動リトライ。

これらをすべて自前で実装するのは手間のかかる仕事です。

## コアアーキテクチャ（6 つの概念）

依存関係は一直線で、学ぶ順序も同じです。

```text
Resource (場所) → Codec (変換) → Source (提供) → Fragment (差分) → Options (ファサード)
                                                        ↘ Patch (編集フラグメント)
```

| 概念 | 一言でいうと | 例 |
| --- | --- | --- |
| Resource | バイトが存在する場所 | ファイル、ZIP エントリ、HTTP レスポンス、メモリ |
| Codec | バイトと値の相互変換 | JSON / XML / YAML の読み書き |
| Source | 論理的な提供（どのフィールドをどの優先度で） | 「ユーザー設定ファイルの `Server` 部分」 |
| Fragment | 存在を覚えている差分 | 「`Port` だけを持つ状態」 |
| Patch | 単一フィールドへの編集 | 「`Port` を 9000 にする」 |
| Options | アプリが触るファサード | 読み取り、保存、監視、説明、診断 |

**読み取り**: 各 Source が Resource からバイトを取得し、Codec がそれを Fragment に変換します。ランタイムは「存在する」フィールドだけを優先度順にオーバーレイして、ひとつのモデルに合成します。

**書き込み**: 逆方向です。アプリは通常のモデル値を編集します。内部ではその変更が Fragment の差分になり、`WriteRoute` / `WritePlan` で指定された Source だけに届きます。関係のない Source は変更されません。

- Fragment は「メンバーが存在しない」と「null / デフォルトとして存在する」を区別します。レイヤー合成で「未設定」が「デフォルト設定」を上書きすることはありません。
- Patch は生成された `TModel.Patch`（単一フィールド編集フラグメント）です。`Unset()` は書き込み先 Source の提供だけを取り下げ、より優先度の低い値を再び見えるようにします。
- `[ConfiglueMerge]` でメンバーごとのマージ動作を変更できます（組み込み: `Append`、`Deep`、`Replace`、`SetUnion`。カスタム戦略も可）。コレクションのレイヤー合成と順序付けはここで決まります。

## 主な機能

- **複数ソース間の優先度マージ**: `Priority` の大きい Source が勝ちます。`GetDetailsAsync` で「どの値がどこから来たか」を調べられます。
- **読み取り専用ソース**: 環境変数、コマンドライン、デフォルトの HTTP ソースは読み取り専用です。読み取り専用の値への書き込みは黙って無視されず、競合エラーになります。
- **プロジェクション / マウント**: 既存の Source を別のモデルに組み替える（プロジェクション）ことや、別の Source をネストしたパスに取り付ける（マウント、`AddMounted`）ことができます。
- **プリセット**: `UseCommonSources` が標準的なレイヤー構成（グローバル / ローカル / 環境変数など）を組み立てます。
- **疎な書き込み**: 変更したフィールドだけが対象レイヤーに保存されます。デフォルト値のままのフィールドは書き出されません。
- **編集セッション**: `OpenEditSessionAsync` で複数の変更をまとめて適用します。`CommitAsync` まではメモリ上です。競合時はデフォルトで失敗しますが、`WriteConflictResolution.LastWriteWins` も選べます。
- **スキーマ移行 / ストレージ移行**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` で旧バージョンの構成を自動変換します。既存のファイルも Source として登録できます。
- **バックアップと復元**: `FileResource` がアトミックな書き込みとバックアップ世代管理を提供します。デフォルトで `.bak` を 1 世代。`RestoreLatestBackupAsync` で復元します。
- **安全な書き込み**: 原子性、競合検出、リトライ。
- **セクション**: `JsonSectionResource` / XML 要素 / YAML マッピングで、ファイルの一部を独立した Resource として扱えます。書き込み時にはコメント、空白、クォート、スカラーのスタイルが保持されます。同じファイル内の独立したセクションは 1 回の物理書き込みにまとめられます。
- **ZIP / HTTP / S3 / Dapr**: `ZipEntryResource`、`Configlue.Resource.Http`（ETag による条件付き書き込みとポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **JSON Schema 生成**: `Configlue.JsonSchema`。構成ファイルは人間が書くものだからです。
- **Native AOT 対応**: ソース生成された `JsonSerializerContext` を渡すと、トリミング / AOT 耐性が向上します。
- **Reactive 統合（任意）**: `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）。`ObserveChanges()`、`ObserveValues()`、`ObserveReloadFailures()`、`ObserveActiveValues()`、`ObserveActiveProfileNames()`。
- **DI 統合**: `Configlue.Extensions.DI`。Microsoft オプションのアダプターは `Configlue.Extensions.MSOptions`（`IOptions<T>` など。同期ゲッターは非同期ソースの読み取り中にブロックするため、非同期フローでは `GetValueAsync` を推奨）。
- **プロファイル / 動的オプション**: 名前付きオプションと永続プロファイルで、ランタイムをまとめて作成・削除できます。

### `Microsoft.Extensions.Configuration` との違い

`IConfiguration` は読み取り中心なのに対し、Configlue は独立したソースの合成、値の出所の確認、疎な保存に向いています。

### 既知の制限事項

- 異なる Resource にまたがる書き込みはアトミックではありません。
- Source の引退（retirement）は現在のオプションインスタンスに範囲が限定され、背後のデータはそのまま残ります。
- オプションランタイムのソース構成は固定です。

## クイックスタート

`example.cs` として保存し、`dotnet run example.cs` で実行します（.NET 10 以降）。

```csharp
#!/usr/bin/env dotnet
#:package Configlue@*

using Configlue;
using Configlue.Source.Presets;

// 1. 設定モデルを宣言。ジェネレーターが Fragment/Patch サポートを生成します。
[ConfiglueModel("SampleSetting", Version = 1)]
public partial class SampleSetting
{
    public string Name { get; set; } = "World";
    public int RunCount { get; set; }
    public bool DefaultValue { get; set; } = true;
}

// 2. プリセットのレイヤーを宣言。ここに列挙したソースだけが有効になります。
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);

// 3. オプション経由で読み書きします。
var options = context.GetOptions<SampleSetting>();
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 疎な編集: 変更したフィールドだけが対象レイヤーに保存されます。
await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue は変更していないので、対象レイヤーには保存されません。
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

## 値の出所を確認する・疎な保存

```csharp
var options = context.GetOptions<AppSettings>();
// 1. 現在値を取得（すべてのソースからマージされた値）
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 2. それぞれの値がどこから来たのかを確認
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

指定したメンバーだけを更新するパッチを保存します。`Unset()` はその Source の提供を取り除き、より優先度の低い Source に値を任せます。

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
- `OpenEditSessionAsync()` … 複数の編集をまとめて行い、`CommitAsync` で確定。
- `ApplyPatchesAsync` + `StateSourcePatch` … ソース単位を明示した複数書き込み。
- `StateWritePlan.For<T>().Route(...)` … 書き込みルーティング。
- `SourceKey<TModel>` と `options.Source(key)` … ソース単位の操作。

## パッケージ構成

インストールは `dotnet add package Configlue` から始め、必要な機能パッケージを追加します。

| パッケージ | 役割 |
| --- | --- |
| `Configlue` | ユーザー向けメタパッケージ（Core / DI / JSON プロバイダー / JSON Schema / HTTP リソース / 共通ソース / 環境変数ソース / ジェネレーター analyzer を同梱。実装アセンブリは持たない） |
| `Configlue.Abstraction` | 契約（provider / codec / resource / generated-model） |
| `Configlue.Core` | 解決と永続化のランタイム |
| `Configlue.Extensibility` | プロバイダー SDK |
| `Configlue.Extensions.DI` / `.MSOptions` / `.R3` / `.Reactive` | DI・オプション・Reactive 統合 |
| `Configlue.Generator` | Roslyn analyzer（疎なモデルサポートを生成） |
| `Configlue.Testing` | メモリ上のテストダブル |
| `Configlue.Provider.Json` / `.Xml` / `.Yaml` | 各形式のコーデック、セクションリソース、ファイル登録 |
| `Configlue.JsonSchema` | JSON Schema の生成とエクスポート |
| `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml` | 各種ソースとプリセット |
| `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip` | 各種リソース |
| `Configlue.Transformer.AES` | Resource と Codec の間のバイトを AES-GCM で暗号化・認証 |
