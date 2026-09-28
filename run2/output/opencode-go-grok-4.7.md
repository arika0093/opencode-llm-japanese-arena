# Configlue

**Make easy configuration management.**

Configlue は、アプリケーションの設定管理を代行する .NET ライブラリです。複数の場所に散らばった設定を、1 つのモデルに結合（glue）します。名前は configuration + glue です。

- 対象: .NET 10 SDK 以降。C#（`LangVersion` はソースジェネレーター対応が必要。リポジトリは preview でビルド）
- ライセンス: Apache-2.0
- 現状はアーキテクチャ上の土台であり、`Configuration.Writable` を完全に置き換えるものではない

`Microsoft.Extensions.Configuration` の `IConfiguration` は読み取りが中心です。Configlue は、独立したソースの合成、値の来歴の検査、変更したフィールドだけの保存に向きます。

## なぜ Configlue か

JSON ファイルの読み書きだけなら数行で済みます。実際には、次の要件が積み重なります。

- 設定が複数箇所にある。グローバル設定、実行フォルダー、環境変数、コマンドライン引数、暗号化された資格情報、社内ポリシーや HTTP API などのリモート管理
- ファイルが書き換わったら、再起動なしで反映したい（変更通知）
- 書き込み先を自動で選びたい。環境変数から読んだ値への書き込みはエラーにしたい
- 設定ファイルは人間が書く。コメントを消さない、JSON Schema がほしい、壊れたファイルに対処したい
- 既定値のままなら書き出さない。ただしユーザーが明示した `null` は尊重する
- 旧形式から新形式への自動変換
- バックアップと自動整理
- 書き込みの安全性。アトミック性（クラッシュしても壊れない）、他プロセスとの競合検出と自動マージ、自動リトライ

これらを自前で実装するのは面倒です。Configlue はその共通部分を引き受けます。

## アーキテクチャ

依存は直線的です。学習順も同じです。

```text
Resource (location) → Codec (conversion) → Source (contribution) → Fragment (diff) → Options (facade)
                                                        ↘ Patch (edit fragment)
```

| 概念 | 一言で | 例 |
| --- | --- | --- |
| Resource | バイトがどこにあるか | ファイル、ZIP エントリ、HTTP 応答、メモリ |
| Codec | バイトと値の変換 | JSON / XML / YAML の読み書き |
| Source | 論理的な寄与（どのフィールドをどの優先度で） | 「ユーザー設定ファイルの Server 部分」 |
| Fragment | 存在を記憶する差分 | 「Port だけ」を持つ状態 |
| Patch | 単一フィールドの編集 | 「Port を 9000 にする」 |
| Options | アプリが見るファサード | 読み・保存・監視・説明・診断 |

**読み込み。** 各 Source が Resource からバイトを取得し、Codec が Fragment に変換します。ランタイムは優先度順に、「存在する」フィールドだけを 1 つのモデルへ重ねます。

**書き込み。** 逆向きです。アプリは普通のモデル値を編集します。内部では変更が Fragment 差分になり、`WriteRoute` / `WritePlan` が指す Source にだけ届きます。無関係な Source は変わりません。

- Fragment は「メンバーが存在しない」と「null または既定値で存在する」を区別します。層の合成で、「未設定」が「既定値に設定」を上書きすることはありません。
- Patch は生成される `TModel.Patch`（単一フィールドの編集フラグメント）です。`Unset()` は書き込み先 Source の寄与だけを取り消し、下位優先度の値を再び見せます。
- `[ConfiglueMerge]` でメンバーごとのマージを変えられます。組み込みは `Append`、`Deep`、`Replace`、`SetUnion`。カスタム戦略も使えます。コレクションの層合成と順序はここで決まります。

## インストール

```sh
dotnet add package Configlue
```

`Configlue` はユーザー向けメタパッケージです。Core、DI、JSON provider、JSON Schema、HTTP resources、common sources、environment source、generator analyzer を同梱します。実装アセンブリは持ちません。XML、YAML、S3 など、必要な機能パッケージを追加します。

## Quick Start

`example.cs` に保存し、`dotnet run example.cs` で実行します（.NET 10 以降）。

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

モデルは `partial` にし、`[ConfiglueModel]` を付けます。ジェネレーターが Fragment / Patch を作ります。`UseCommonSources` は、ここで列挙した層だけを有効にします。`SaveAsync` は変更したフィールドだけを対象層へ書きます。

## 値の由来とスパース保存

`GetDetailsAsync` で、各値がどの Source から来たか、書き込めるかを調べられます。

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

指定したメンバーだけを更新するパッチを保存します。`Unset()` はその Source の寄与を外し、下位優先度の Source が値を提供できるようにします。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

日常的に使う面は次のとおりです。

- `IReadOnlyOptions<T>` … 読み取りは `GetValueAsync` と `OnChange`
- `SaveAsync(patch => ...)` … 生成 Patch によるスパース保存
- `OpenEditSessionAsync()` … まとめて編集し、`CommitAsync` までインメモリ
- `ApplyPatchesAsync` と `StateSourcePatch` … ソースを明示した複数書き込み
- `StateWritePlan.For<T>().Route(...)` … 書き込みルーティング
- `SourceKey<TModel>` と `options.Source(key)` … ソース単位の操作

## 主な機能

- **優先度マージ。** `Priority` が大きい Source が勝ちます。由来は `GetDetailsAsync` で検査できます。
- **読み取り専用ソース。** 環境変数、コマンドライン、既定の HTTP ソースは読み取り専用です。そこから来た値への書き込みは黙って無視せず、競合エラーになります。
- **プロジェクション / マウント。** 既存 Source を別モデルに整形（projection）できます。ネストしたパスへ別 Source を接続する（mount、`AddMounted`）こともできます。
- **プリセット。** `UseCommonSources` が global / local / environment などの標準的な層を組み立てます。
- **スパース書き込み。** 変更したフィールドだけを対象層に保存します。既定値のままのフィールドは書かれません。
- **編集セッション。** `OpenEditSessionAsync` で複数変更をまとめます。`CommitAsync` までインメモリです。競合時は既定で失敗します。`WriteConflictResolution.LastWriteWins` も選べます。
- **スキーマ移行 / ストレージ移行。** `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` で、旧バージョンを自動変換します。既存ファイルを Source として登録できます。
- **バックアップと復元。** `FileResource` はアトミック書き込みとバックアップ世代管理をします。既定は `.bak` 1 世代です。`RestoreLatestBackupAsync` で復元します。
- **安全な書き込み。** アトミック性、競合検出、リトライ。
- **セクション。** `JsonSectionResource`、XML 要素、YAML マッピングで、ファイルの一部を独立した Resource として扱えます。書き込み時はコメント、空白、引用、スカラー形式を保持します。同じファイル内の独立セクションは、1 回の物理書き込みにバッチされます。
- **ZIP / HTTP / S3 / Dapr。** `ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込みとポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **JSON Schema。** `Configlue.JsonSchema` で生成・エクスポートします。人間が設定を書くためです。
- **Native AOT。** ソース生成の `JsonSerializerContext` を渡すと、トリミングと AOT に強くなります。
- **リアクティブ（任意）。** `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）。`ObserveChanges()`、`ObserveValues()`、`ObserveReloadFailures()`、`ObserveActiveValues()`、`ObserveActiveProfileNames()`。
- **DI。** `Configlue.Extensions.DI`。Microsoft の options アダプターは `Configlue.Extensions.MSOptions`（`IOptions<T>` など）。同期ゲッターは非同期ソースの読み取り中にブロックするため、非同期フローでは `GetValueAsync` を使います。
- **プロファイル / 動的オプション。** 名前付きオプションや永続プロファイルで、ランタイムを単位に作成・削除できます。

## パッケージ

| パッケージ | 役割 |
| --- | --- |
| `Configlue` | ユーザー向けメタパッケージ。実装アセンブリは持たない |
| `Configlue.Abstraction` | 契約（provider / codec / resource / generated-model） |
| `Configlue.Core` | 解決と永続化のランタイム |
| `Configlue.Extensibility` | プロバイダー SDK |
| `Configlue.Extensions.DI` | DI 統合 |
| `Configlue.Extensions.MSOptions` | `IOptions<T>` などのアダプター |
| `Configlue.Extensions.Reactive` | System.Reactive 統合 |
| `Configlue.Extensions.R3` | R3 統合 |
| `Configlue.Generator` | Roslyn アナライザー（スパースなモデルサポートの生成） |
| `Configlue.Testing` | インメモリのテストダブル |
| `Configlue.Provider.Json` / `.Xml` / `.Yaml` | 各形式の Codec、セクションリソース、ファイル登録 |
| `Configlue.JsonSchema` | JSON Schema の生成・エクスポート |
| `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml` | 環境変数、コマンドライン、プリセット |
| `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip` | リモートおよびアーカイブの Resource |
| `Configlue.Transformer.AES` | Resource と Codec の間のバイトを AES-GCM で暗号化・認証 |

## 既知の制限

- 異なる Resource 間の書き込みはアトミックではない
- Source の退役は現在の options インスタンスに閉じる。実データは残る
- Source の集合は、options ランタイムで固定される

## ライセンス

Apache-2.0

