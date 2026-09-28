# Configlue

**Make easy configuration management.**

Configlue は、アプリケーションの設定管理（configuration management）を代行する .NET ライブラリです。複数の場所に散らばった設定を 1 つのモデルに**結合（glue）**することを中心的な考え方としており、名前も configuration + glue に由来します。

- **対象**: .NET 10 SDK 以降（C#。ソースジェネレーター対応の `LangVersion` が必要。リポジトリは preview でビルド）
- **ライセンス**: Apache-2.0

> **現状について**: Configlue は現時点で「アーキテクチャ上の土台」であり、`Configuration.Writable` を完全に置き換えるものではありません。

## Why Configlue?

JSON ファイルの読み書きだけなら数行で済みます。しかし実際のアプリケーションでは、次のような要件が積み重なっていきます。

- **設定が複数箇所にある**: グローバル設定、実行フォルダー設定、環境変数、コマンドライン引数、暗号化された資格情報、社内ポリシーや HTTP API などのリモート管理。
- **変更通知**: 設定ファイルが書き換わったら、再起動なしで反映したい。
- **書き込み先の自動選択**: 環境変数から読んだ値への書き込みはエラーにしたい。
- **人間が書く設定ファイル**: コメントを消さない、JSON Schema がほしい、壊れたファイルへの対処。
- **スパースな保存**: 既定値のままなら書き出さない（ただしユーザーが明示した `null` は尊重する）。
- **設定ファイルのバージョンアップ**: 旧形式から新形式への自動変換。
- **バックアップと自動整理**。
- **書き込みの安全性**: アトミック性（クラッシュしても壊れない）、他プロセスとの競合検出・自動マージ、自動リトライ。

これらを自前で実装するのは面倒です。Configlue はこの「面倒」を引き受けます。

## インストール

```console
dotnet add package Configlue
```

`Configlue` はユーザー向けのメタパッケージで、Core / DI / JSON provider / JSON Schema / HTTP resources / common sources / environment source / generator analyzer を同梱します（実装アセンブリは持ちません）。必要に応じて機能パッケージを追加してください（[パッケージ構成](#パッケージ構成)を参照）。

## Quick Start

以下の内容を `example.cs` に保存し、`dotnet run example.cs` で実行できます（.NET 10 以降）。

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

ポイント:

1. **モデルの宣言**: `[ConfiglueModel]` を付けると、ジェネレーターが Fragment / Patch のサポートコードを生成します。
2. **層の宣言**: `UseCommonSources` が標準的な層構成（global / local / environment など）を組み立てます。ここに列挙した Source だけが有効になります。
3. **読み書き**: `GetValueAsync` で全ソースをマージした現在値を取得し、`SaveAsync` で変更したフィールドだけを対象層へスパース保存します。

## 基本アーキテクチャ（6 つの概念）

依存関係は直線的で、学習順も同じです。

```text
Resource (location) → Codec (conversion) → Source (contribution) → Fragment (diff) → Options (facade)
                                                        ↘ Patch (edit fragment)
```

| 概念 | 一言で | 例 |
| --- | --- | --- |
| Resource | バイトがどこにあるか | ファイル、ZIP エントリ、HTTP 応答、メモリ |
| Codec | バイト↔値の変換 | JSON / XML / YAML の読み書き |
| Source | 論理的な寄与（どのフィールドをどの優先度で） | 「ユーザー設定ファイルの Server 部分」 |
| Fragment | 存在を記憶する差分 | 「Port だけ」を持つ状態 |
| Patch | 単一フィールドの編集 | 「Port を 9000 にする」 |
| Options | アプリが見るファサード | 読み・保存・監視・説明・診断 |

**読み込み**: 各 Source が Resource からバイトを取得し、Codec が Fragment に変換します。ランタイムが優先度順に「存在する」フィールドだけを 1 つのモデルへ重ねます。

**書き込み**: 逆向きです。アプリは普通のモデル値を編集します。内部では変更が Fragment 差分になり、`WriteRoute` / `WritePlan` が指す Source にだけ届きます。無関係な Source は変更されません。

重要な性質:

- **Fragment は「存在」を記憶する**: 「メンバーが存在しない」と「null / 既定値で存在する」を区別します。層の合成で「未設定」が「既定値に設定」を上書きすることはありません。
- **Patch と `Unset()`**: Patch は生成される `TModel.Patch`（単一フィールドの編集フラグメント）です。`Unset()` は書き込み先 Source の寄与だけを取り消し、下位優先度の値を再び見せます。
- **マージ戦略**: `[ConfiglueMerge]` でメンバーごとのマージ挙動を変更できます（組み込み: `Append`, `Deep`, `Replace`, `SetUnion`。カスタム戦略も可能）。コレクションの層合成・順序はここで決まります。

## 主な機能

- **複数ソースの優先度マージ**: `Priority` が大きい Source が勝ちます。`GetDetailsAsync` で「どの値がどこ由来か」を検査できます。
- **読み取り専用ソース**: 環境変数・コマンドライン・既定の HTTP ソースは読み取り専用です。読み取り専用の値への書き込みは黙って無視されず、競合エラーになります。
- **プロジェクション / マウント**: 既存 Source を別モデルに整形（projection）したり、ネストしたパスに別 Source を接続（mount、`AddMounted`）したりできます。
- **プリセット**: `UseCommonSources` が標準的な層構成（global / local / environment など）を組み立てます。
- **スパース書き込み**: 変更したフィールドだけを対象層に保存します。既定値のままのフィールドは書かれません。
- **編集セッション**: `OpenEditSessionAsync` で複数変更をまとめて適用します。`CommitAsync` まではインメモリです。競合時は既定で失敗し、`WriteConflictResolution.LastWriteWins` も選べます。
- **スキーマ移行 / ストレージ移行**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` により、旧バージョン設定を自動変換します。既存ファイルを Source として登録できます。
- **バックアップと復元**: `FileResource` はアトミック書き込みとバックアップ世代管理を備えます。既定で `.bak` を 1 世代保持し、`RestoreLatestBackupAsync` で復元できます。
- **安全な書き込み**: アトミック性、競合検出、リトライ。
- **セクション**: `JsonSectionResource` / XML 要素 / YAML マッピングで、ファイルの一部を独立した Resource として扱えます。書き込み時はコメント・空白・引用・スカラー形式を保持します。同じファイル内の独立セクションは 1 回の物理書き込みにバッチされます。
- **ZIP / HTTP / S3 / Dapr**: `ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込み・ポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **JSON Schema 生成**: `Configlue.JsonSchema`。人間が設定を書くための支援です。
- **Native AOT 対応**: ソース生成の `JsonSerializerContext` を渡すと、トリミング / AOT に強くなります。
- **リアクティブ統合（任意）**: `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）。`ObserveChanges()`、`ObserveValues()`、`ObserveReloadFailures()`、`ObserveActiveValues()`、`ObserveActiveProfileNames()` を提供します。
- **DI 統合**: `Configlue.Extensions.DI`。Microsoft の options アダプター `Configlue.Extensions.MSOptions`（`IOptions<T>` など）もあります。同期ゲッターは非同期ソース読み取り中にブロックするため、非同期フローでは `GetValueAsync` を推奨します。
- **プロファイル / 動的オプション**: 名前付きオプションや永続プロファイルで、ランタイムを単位として作成・削除できます。

## 値の由来を調べる / スパース保存

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

指定したメンバーだけを更新するパッチを保存できます。`Unset()` はその Source の寄与を外し、下位優先度の Source が値を提供できるようにします。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

### その他の API

- `IReadOnlyOptions<T>` … 日常の読み取り面は `GetValueAsync` と `OnChange`。
- `SaveAsync(patch => ...)` … 生成 Patch でスパース保存。
- `OpenEditSessionAsync()` … まとめて編集し `CommitAsync`。
- `ApplyPatchesAsync` + `StateSourcePatch` … 明示的なソース別マルチ書き込み。
- `StateWritePlan.For<T>().Route(...)` … 書き込みルーティング。
- `SourceKey<TModel>` と `options.Source(key)` … ソース単位の操作。

## パッケージ構成

| パッケージ | 役割 |
| --- | --- |
| `Configlue` | ユーザー向けメタパッケージ（Core / DI / JSON provider / JSON Schema / HTTP resources / common sources / environment source / generator analyzer を同梱。実装アセンブリは持たない） |
| `Configlue.Abstraction` | 契約（provider / codec / resource / generated-model） |
| `Configlue.Core` | 解決と永続化のランタイム |
| `Configlue.Extensibility` | プロバイダー SDK |
| `Configlue.Extensions.DI` | DI 統合 |
| `Configlue.Extensions.MSOptions` | Microsoft の options アダプター（`IOptions<T>` など） |
| `Configlue.Extensions.R3` / `Configlue.Extensions.Reactive` | リアクティブ統合 |
| `Configlue.Generator` | Roslyn アナライザー（スパースなモデルサポート生成） |
| `Configlue.Testing` | インメモリのテストダブル |
| `Configlue.Provider.Json` / `.Xml` / `.Yaml` | 各形式の Codec・セクションリソース・ファイル登録 |
| `Configlue.JsonSchema` | JSON Schema 生成・エクスポート |
| `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml` | 各種 Source とプリセット |
| `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip` | 各種 Resource |
| `Configlue.Transformer.AES` | Resource と Codec の間のバイトを AES-GCM 暗号化・認証 |

## 既知の制限

- 異なる Resource 間の書き込みはアトミックではありません。
- Source の退役は現在の options インスタンスに閉じ、実データは残ります。
- Source 集合は options ランタイムで固定です。

## Microsoft.Extensions.Configuration との違い

`IConfiguration` は読み取り中心の設計です。Configlue は、独立したソースの合成・値の来歴の検査・スパース保存に向いた設計になっています。設定を「読むだけ」でなく「どこから来た値かを把握し、安全に書き戻す」必要がある場合に適しています。

## ライセンス

Apache-2.0
