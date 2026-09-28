# Configlue

Make easy configuration management.

## 概要

Configlue は、アプリケーションの設定管理（configuration management）を代行する .NET ライブラリです。グローバル設定、実行フォルダーの設定、環境変数、コマンドライン引数、暗号化された資格情報、社内ポリシーや HTTP API によるリモート管理など、複数の場所に散らばった設定を 1 つのモデルへ結合（glue）します。ライブラリ名も configuration + glue に由来します。

JSON ファイルの読み書きだけなら数行で済みますが、実際の設定管理には次のような要件が積み重なります。

- 設定が複数箇所にある
- 設定ファイルが書き換わったら再起動なしで反映したい（変更通知）
- 書き込み先を自動で選びたい。環境変数から読んだ値への書き込みはエラーにしたい
- 設定ファイルは人間が書くもの。コメントを消さない、JSON Schema がほしい、壊れたファイルへの対処
- 既定値のままなら書き出さない（ただしユーザーが明示した `null` は尊重する）
- 設定ファイルのバージョンアップ（旧形式から新形式への自動変換）
- バックアップと自動整理
- 書き込みの安全性: アトミック性（クラッシュしても壊れない）、他プロセスとの競合検出・自動マージ、自動リトライ

これらを自前で実装するのは面倒です。Configlue は、この部分を引き受ける土台を提供します。

`Microsoft.Extensions.Configuration` の `IConfiguration` が読み取り中心の API であるのに対し、Configlue は独立したソースの合成、値の来歴の検査、スパースな保存（変更したフィールドだけを書き込む）に向いています。なお現状はアーキテクチャ上の土台であり、`Configuration.Writable` を完全に置き換えるものではありません。

- 対象: .NET 10 SDK 以降
- ライセンス: Apache-2.0

## 主な特徴

### アーキテクチャ

内部は 6 つの概念で構成され、依存関係は直線的で、学習順も同じです。

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

- **読み込み**: 各 Source が Resource からバイトを取得し、Codec が Fragment に変換します。ランタイムが優先度順に「存在する」フィールドだけを 1 つのモデルへ重ね合わせます。
- **書き込み**: 逆向きです。アプリは普通のモデル値を編集します。内部では変更が Fragment 差分になり、`WriteRoute` / `WritePlan` が指す Source にだけ届きます。無関係な Source は変更されません。
- Fragment は「メンバーが存在しない」と「null/既定値で存在する」を区別します。層の合成で「未設定」が「既定値に設定」を上書きすることはありません。
- Patch の `Unset()` は、書き込み先 Source の寄与だけを取り消し、下位優先度の Source が再び値を提供できるようにします。
- `[ConfiglueMerge]` でメンバーごとのマージ挙動を変更できます（組み込み: `Append`, `Deep`, `Replace`, `SetUnion`。カスタム戦略も可）。コレクションの層合成・順序はここで決まります。

### 機能一覧

- **複数ソースの優先度マージ**: `Priority` が大きい Source が勝ちます。`GetDetailsAsync` で「どの値がどこ由来か」を検査できます。
- **読み取り専用ソース**: 環境変数・コマンドライン・既定の HTTP ソースは読み取り専用です。読み取り専用の値への書き込みは黙って無視せず競合エラーになります。
- **プリセット**: `UseCommonSources` が標準的な層構成（global/local/environment など）を組み立てます。
- **スパース書き込み**: 変更したフィールドだけを対象層に保存します。既定値のままのフィールドは書かれません。
- **編集セッション**: `OpenEditSessionAsync` で複数変更をまとめて適用できます。`CommitAsync` まではインメモリです。競合時は既定で失敗し、`WriteConflictResolution.LastWriteWins` も選べます。
- **プロジェクション / マウント**: 既存 Source を別モデルに整形（projection）したり、ネストしたパスに別 Source を接続（mount, `AddMounted`）できます。
- **スキーマ移行 / ストレージ移行**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` により、旧バージョン設定を新形式へ自動変換できます。既存ファイルを Source として登録できます。
- **バックアップと復元**: `FileResource` はアトミック書き込みとバックアップ世代管理（既定で `.bak` 1 世代）を行い、`RestoreLatestBackupAsync` で復元できます。
- **安全な書き込み**: アトミック性、競合検出、リトライ。
- **セクション**: `JsonSectionResource` / XML 要素 / YAML マッピングで、ファイルの一部を独立した Resource として扱えます。書き込み時はコメント・空白・引用・スカラー形式を保持します。同じファイル内の独立セクションは 1 回の物理書き込みにバッチされます。
- **さまざまな Resource**: `ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込み・ポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **JSON Schema 生成**: `Configlue.JsonSchema` で、人間が設定を書くためのスキーマを生成・エクスポートできます。
- **Native AOT 対応**: ソース生成の `JsonSerializerContext` を渡すと、トリミング/AOT に強くなります。
- **リアクティブ統合（任意）**: `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）。`ObserveChanges()`, `ObserveValues()`, `ObserveReloadFailures()`, `ObserveActiveValues()`, `ObserveActiveProfileNames()` が使えます。
- **DI 統合**: `Configlue.Extensions.DI`。Microsoft の options アダプター `Configlue.Extensions.MSOptions`（`IOptions<T>` など）も利用できます。同期ゲッターは非同期ソース読み取り中ブロックするため、非同期フローでは `GetValueAsync` を推奨します。
- **プロファイル / 動的オプション**: 名前付きオプションや永続プロファイルを、ランタイム単位で作成・削除できます。

### 既知の制限

- 異なる Resource 間の書き込みはアトミックではありません。
- Source の退役は現在の options インスタンスに閉じ、実データは残ります。
- Source 集合は options ランタイムで固定されます。

## 基本的な使い方

### インストール

```
dotnet add package Configlue
```

`Configlue` はユーザー向けメタパッケージで、Core / DI / JSON provider / JSON Schema / HTTP resources / common sources / environment source / generator analyzer を同梱します（実装アセンブリは持ちません）。必要に応じて、次のような機能パッケージを追加します。

| パッケージ | 内容 |
| --- | --- |
| `Configlue.Abstraction` | 契約（provider/codec/resource/generated-model） |
| `Configlue.Core` | 解決と永続化のランタイム |
| `Configlue.Extensibility` | プロバイダー SDK |
| `Configlue.Generator` | Roslyn アナライザー（スパースなモデルサポート生成） |
| `Configlue.Testing` | インメモリのテストダブル |
| `Configlue.Provider.Json` / `.Xml` / `.Yaml` | 各形式の Codec・セクションリソース・ファイル登録 |
| `Configlue.JsonSchema` | JSON Schema 生成・エクスポート |
| `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml` | 環境変数・コマンドライン・プリセットソース |
| `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip` | HTTP / Dapr / S3 / ZIP リソース |
| `Configlue.Extensions.DI` / `.MSOptions` / `.R3` / `.Reactive` | DI・Microsoft options・リアクティブ統合 |
| `Configlue.Transformer.AES` | Resource と Codec の間のバイトを AES-GCM で暗号化・認証 |

### クイックスタート

次のコードを `example.cs` に保存し、`dotnet run example.cs` で実行できます（.NET 10 以降）。

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

### 値の由来を調べる

`GetDetailsAsync` で、各値がどこから来たか、書き込み可能かを調べられます。

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

### スパース保存と Unset

指定したメンバーだけを更新するパッチを保存できます。`Unset()` はその Source の寄与を外し、下位優先度の Source が値を提供できるようにします。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

### その他の API

- `IReadOnlyOptions<T>` … 日常の読み取り面は `GetValueAsync` と `OnChange`
- `SaveAsync(patch => ...)` … 生成 Patch でスパース保存
- `OpenEditSessionAsync()` … まとめて編集し `CommitAsync`
- `ApplyPatchesAsync` + `StateSourcePatch` … 明示的なソース別マルチ書き込み
- `StateWritePlan.For<T>().Route(...)` … 書き込みルーティング
- `SourceKey<TModel>` と `options.Source(key)` … ソース単位の操作
