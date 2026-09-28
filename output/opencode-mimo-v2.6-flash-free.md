## 概要

Configlue は、アプリケーションの設定管理を代行する .NET ライブラリです。「Make easy configuration management.」を掲げ、複数の場所に散らばった設定を 1 つのモデルに結合（glue）することを目的としています（名前も configuration + glue に由来します）。

対象は .NET 10 SDK 以降、ライセンスは Apache-2.0 です。

JSON ファイルの読み書きだけなら数行で済みます。しかし実際の設定管理には、次のような要件が積み重なります。

- 設定が複数箇所にある（グローバル設定、実行フォルダー、環境変数、コマンドライン引数、暗号化された資格情報、社内ポリシーや HTTP API などのリモート管理）
- ファイルが書き換わったら再起動なしで反映したい
- 書き込み先を自動で選びたい（環境変数から読んだ値への書き込みはエラーにしたい）
- 人間が設定ファイルを書く前提で、コメントを消さず JSON Schema もほしい
- 既定値のままなら書き出さない
- 設定ファイルのバージョンアップ（旧形式→新形式への自動変換）
- バックアップと自動整理
- 書き込みの安全性（アトミック性、他プロセスとの競合検出・自動マージ、自動リトライ）

これらを自前実装するのは面倒です。Configlue はそのためのアーキテクチャ上の土台として設計されています。現状は `Configuration.Writable` を完全に置き換えるものではありません。

なお、既存の `Microsoft.Extensions.Configuration` との違いとしては、`IConfiguration` が読み取り中心なのに対し、Configlue は独立したソースの合成、値の来歴の検査、スパース保存に向いています。

## 主な特徴

**基本アーキテクチャ**

設定は 6 つの概念で構成され、依存関係と学習順は直線的です。

```text
Resource (location) → Codec (conversion) → Source (contribution) → Fragment (diff) → Options (facade)
                                                        ↘ Patch (edit fragment)
```

| 概念 | 一言で | 例 |
| --- | --- | --- |
| Resource | バイトがどこにあるか | ファイル、ZIPエントリ、HTTP応答、メモリ |
| Codec | バイト↔値の変換 | JSON / XML / YAML の読み書き |
| Source | 論理的な寄与（どのフィールドをどの優先度で） | 「ユーザー設定ファイルの Server 部分」 |
| Fragment | 存在を記憶する差分 | 「Port だけ」を持つ状態 |
| Patch | 単一フィールドの編集 | 「Port を 9000 にする」 |
| Options | アプリが見るファサード | 読み・保存・監視・説明・診断 |

読み込みでは、各 Source が Resource からバイトを取得し、Codec が Fragment に変換します。ランタイムが優先度順に「存在する」フィールドだけを 1 つのモデルへ重ねます。書き込みはその逆で、アプリは普通のモデル値を編集するだけで、内部の変更が Fragment 差分になり、書き込み先の Source にだけ届きます。無関係な Source は変更されません。

Fragment は「メンバーが存在しない」と「null/既定値で存在する」を区別するため、層の合成で「未設定」が「既定値に設定」を上書きすることはありません。

**主な機能**

- **複数ソースの優先度マージ**: `Priority` が大きい Source が勝ち、`GetDetailsAsync` で「どの値がどこ由来か」を検査できます。
- **読み取り専用ソース**: 環境変数・コマンドライン・既定の HTTP ソースは読み取り専用。読み取り専用の値への書き込みは黙って無視せず、競合エラーになります。
- **スパース書き込み**: 変更したフィールドだけを対象層に保存し、既定値のままのフィールドは書きません。
- **編集セッション**: `OpenEditSessionAsync` で複数変更をまとめて適用し、`CommitAsync` までインメモリで保持します。
- **スキーマ移行 / ストレージ移行**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` による旧バージョン設定の自動変換。
- **バックアップと安全な書き込み**: `FileResource` がアトミック書き込みとバックアップ世代管理（既定で `.bak` 1 世代、`RestoreLatestBackupAsync` で復元）を担い、競合検出・リトライも備えます。
- **セクション**: `JsonSectionResource` / XML 要素 / YAML マッピングで、ファイルの一部を独立した Resource として扱えます。書き込み時はコメント・空白・引用・スカラー形式を保持し、同一ファイル内の独立セクションは 1 回の物理書き込みにバッチされます。
- **プロジェクション / マウント**: 既存 Source を別モデルに整形したり、ネストしたパスに別 Source を接続（`AddMounted`）できます。
- **プリセット**: `UseCommonSources` が global / local / environment などの標準的な層構成を組み立てます。
- **JSON Schema 生成**: `Configlue.JsonSchema` により、人間が設定を書きやすい形を用意できます。
- **Native AOT 対応**: ソース生成の `JsonSerializerContext` を渡すと、トリミング / AOT に強くなります。
- **リアクティブ統合（任意）**: `Configlue.Extensions.Reactive`（System.Reactive）と `Configlue.Extensions.R3` で、変更や値のストリームを購読できます。
- **DI 統合**: `Configlue.Extensions.DI` と、Microsoft の options アダプターである `Configlue.Extensions.MSOptions`（`IOptions<T>` など）を提供します。同期ゲッターは非同期ソースの読み取り中にブロックするため、非同期フローでは `GetValueAsync` の利用を推奨します。
- **暗号化**: `Configlue.Transformer.AES` で、Resource と Codec の間のバイトを AES-GCM により暗号化・認証できます。

パッケージは `dotnet add package Configlue` から導入でき、`Configlue` は Core / DI / JSON provider / JSON Schema / HTTP resources / common sources / environment source / generator analyzer を同梱するメタパッケージです。用途に応じて `Configlue.Provider.Xml` / `.Yaml`、`Configlue.Resource.S3` / `.Dapr` / `.Zip`、`Configlue.Extensions.R3` などの機能パッケージを追加します。

**既知の制限**

- 異なる Resource 間の書き込みはアトミックではありません。
- Source の退役は現在の options インスタンスに閉じており、実データは残ります。
- Source 集合は options ランタイムで固定されます。

## 基本的な使い方

`example.cs` に保存し、.NET 10 以降で `dotnet run example.cs` として実行できます。

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

設定モデルに `[ConfiglueModel]` を付けて `partial class` として宣言すると、ジェネレーターが Fragment / Patch の対応を生成します。`UseCommonSources` で有効にする層を列挙し、`GetOptions<T>()` で得た options インスタンスから読み書きします。保存は `SaveAsync` のパッチで行うため、変更したフィールドだけが対象層に書き込まれます。

**値の由来を調べる**

現在の値がどこから来ているか、またどこに書き込めるかを確認できます。

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

`Unset()` を使うと、その Source の寄与だけを取り消して下位優先度の Source が値を提供できるようにできます。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

**その他の主な API**

- `IReadOnlyOptions<T>` … 日常の読み取り面は `GetValueAsync` と `OnChange`
- `SaveAsync(patch => ...)` … 生成 Patch によるスパース保存
- `OpenEditSessionAsync()` … まとめて編集し `CommitAsync`
- `ApplyPatchesAsync` + `StateSourcePatch` … 明示的なソース別マルチ書き込み
- `StateWritePlan.For<T>().Route(...)` … 書き込みルーティング
- `SourceKey<TModel>` と `options.Source(key)` … ソース単位の操作
