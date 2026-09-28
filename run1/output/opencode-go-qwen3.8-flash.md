## 概要

Configlue は、アプリケーションの設定管理を代行する .NET ライブラリです。キャッチコピーは "Make easy configuration management." で、複数の場所に散らばった設定を 1 つのモデルに**結合（glue）** することが中心的な考え方です。名前は configuration + glue に由来します。対象は .NET 10 SDK 以降、ライセンスは Apache-2.0 です。

JSON ファイルの読み書きだけなら数行で済みますが、実際には以下のような要件が積み重なります。

- 設定が複数箇所にある（グローバル設定、実行フォルダー設定、環境変数、コマンドライン引数、暗号化された資格情報、HTTP API などのリモート管理）
- ファイルが書き換わったら再起動なしで反映したい
- 書き込み先を自動で選びたい。環境変数から読んだ値への書き込みはエラーにしたい
- 人間が書くファイルなので、コメントを残したい、JSON Schema がほしい、壊れたファイルに対処したい
- 既定値のままなら書き出さない（ただし明示された `null` は尊重する）
- 設定ファイルのバージョンアップ、バックアップと自動整理
- 書き込みのアトミック性、他プロセスとの競合検出・自動マージ、自動リトライ

これらを自前実装するのは面倒だ、というのが Configlue の動機です。現状は「アーキテクチャ上の土台」であり、`Configuration.Writable` を完全に置き換えるものではありません。`Microsoft.Extensions.Configuration`（`IConfiguration`）が読み取り中心なのに対し、Configlue は独立ソースの合成・来歴の検査・スパース保存に向いています。

アーキテクチャは 6 つの概念からなり、依存関係は直線的です（学習順も同じ）。

| 概念 | 一言で | 例 |
| --- | --- | --- |
| Resource | バイトがどこにあるか | ファイル、ZIPエントリ、HTTP応答、メモリ |
| Codec | バイト↔値の変換 | JSON / XML / YAML の読み書き |
| Source | 論理的な寄与（どのフィールドをどの優先度で） | 「ユーザー設定ファイルの Server 部分」 |
| Fragment | 存在を記憶する差分 | 「Port だけ」を持つ状態 |
| Patch | 単一フィールドの編集 | 「Port を 9000 にする」 |
| Options | アプリが見るファサード | 読み・保存・監視・説明・診断 |

```text
Resource (location) → Codec (conversion) → Source (contribution) → Fragment (diff) → Options (facade)
                                                        ↘ Patch (edit fragment)
```

読み込み時は、各 Source が Resource からバイトを取得し、Codec が Fragment に変換します。ランタイムが優先度順に「存在する」フィールドだけを 1 つのモデルへ重ねます。書き込みはその逆向きで、アプリが普通のモデル値を編集すると、内部で Fragment 差分になり、`WriteRoute` / `WritePlan` が指す Source にだけ届きます。無関係な Source は変更されません。

Fragment は「メンバーが存在しない」と「null/既定値で存在する」を区別するため、層の合成で「未設定」が「既定値に設定」を上書きすることはありません。`[ConfiglueMerge]` を使うとメンバーごとのマージ挙動（組み込みは `Append` / `Deep` / `Replace` / `SetUnion`、カスタム戦略も可）も制御できます。

## 主な特徴

- **複数ソースの優先度マージ**: `Priority` が大きい Source が勝つ。`GetDetailsAsync` で「どの値がどこ由来か」を検査できる
- **読み取り専用ソース**: 環境変数・コマンドライン・既定の HTTP ソースは読み取り専用で、読み取り専用の値への書き込みは黙って無視せず競合エラーになる
- **プリセット**: `UseCommonSources` が標準的な層構成（global / local / environment など）を組み立てる
- **プロジェクション / マウント**: 既存 Source を別モデルに整形したり、ネストしたパスに別 Source を接続（`AddMounted`）できる
- **スパース書き込み**: 変更したフィールドだけを対象層に保存し、既定値のままのフィールドは書かない
- **編集セッション**: `OpenEditSessionAsync` で複数変更をまとめて適用し、`CommitAsync` までインメモリ。競合時は既定で失敗、`WriteConflictResolution.LastWriteWins` も選べる
- **スキーマ移行 / ストレージ移行**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` により旧バージョン設定を自動変換。既存ファイルを Source として登録できる
- **バックアップと安全な書き込み**: `FileResource` はアトミック書き込みとバックアップ世代管理（既定で `.bak` 1 世代、`RestoreLatestBackupAsync` で復元）。競合検出とリトライも備える
- **セクション**: `JsonSectionResource` / XML 要素 / YAML マッピングでファイルの一部を独立した Resource として扱え、書き込み時にコメント・空白・引用・スカラー形式を保持する。同じファイル内の独立セクションは 1 回の物理書き込みにバッチされる
- **リモート / 圧縮リソース**: `ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込み・ポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`
- **JSON Schema 生成**: `Configlue.JsonSchema` により、人間が設定を書くためのスキーマを生成・エクスポートできる
- **Native AOT 対応**: ソース生成の `JsonSerializerContext` を渡すとトリミング/AOT に強くなる
- **リアクティブ統合（任意）**: `Configlue.Extensions.Reactive`（System.Reactive）と `Configlue.Extensions.R3` で `ObserveChanges()` / `ObserveValues()` / `ObserveReloadFailures()` などが使える
- **DI 統合**: `Configlue.Extensions.DI` と、Microsoft の options アダプター `Configlue.Extensions.MSOptions`（`IOptions<T>` など。同期ゲッターは非同期ソース読み取り中にブロックするため、非同期フローでは `GetValueAsync` 推奨）
- **プロファイル / 動的オプション**: 名前付きオプションや永続プロファイルをランタイム単位で作成・削除できる
- **暗号化**: `Configlue.Transformer.AES` が Resource と Codec の間のバイトを AES-GCM で暗号化・認証する

既知の制限として、異なる Resource 間の書き込みはアトミックではなく、Source の退役は現在の options インスタンスに閉じられ実データは残り、Source 集合は options ランタイムで固定されます。

パッケージは `Configlue`（ユーザー向けメタパッケージ）を中心に、契約の `Configlue.Abstraction`、ランタイムの `Configlue.Core`、プロバイダー SDK の `Configlue.Extensibility`、Roslyn アナライザーの `Configlue.Generator`、テスト用の `Configlue.Testing`、各形式の `Configlue.Provider.Json` / `.Xml` / `.Yaml` などに分かれています。まずはメタパッケージをインストールし、必要な機能パッケージを追加するのが基本です。

## 基本的な使い方

インストールは `dotnet add package Configlue` から行います。以下は公式 README の Quick Start で、`example.cs` に保存して `dotnet run example.cs` で実行できます（.NET 10 以降）。

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

流れは 3 段階です。`[ConfiglueModel]` を付けた partial クラスで設定モデルを宣言すると、ジェネレーターが Fragment / Patch サポートを生成します。`UseCommonSources` で有効にする層（グローバル、ローカル、環境変数）を宣言し、アプリは `GetOptions<T>()` で得た options インスタンスを通して読み書きします。`SaveAsync` はパッチ形式で、変更したメンバーだけを対象層に保存します。

各値がどこから来たかを調べるには `GetDetailsAsync` を使います。

```csharp
var options = context.GetOptions<AppSettings>();
// 1. 現在の値（全ソースをマージしたもの）を取得
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

`Unset()` を使うと、書き込み先 Source の寄与だけを取り消し、下位優先度の値を再び見せることができます。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

そのほか、日常の読み取り面は `IReadOnlyOptions<T>` の `GetValueAsync` と `OnChange`、複数変更のまとめて適用は `OpenEditSessionAsync()` と `CommitAsync`、明示的なソース別マルチ書き込みは `ApplyPatchesAsync` + `StateSourcePatch`、書き込みルーティングは `StateWritePlan.For<T>().Route(...)`、ソース単位の操作は `SourceKey<TModel>` と `options.Source(key)` で行えます。
