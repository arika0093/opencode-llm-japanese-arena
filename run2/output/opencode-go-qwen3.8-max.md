# Configlue

> Make easy configuration management.

Configlue は、アプリケーションの設定管理（configuration management）を代行する .NET ライブラリです。名前は **configuration + glue** に由来し、複数箇所に散らばった設定を **1 つのモデルに結合（glue）** することを中心的な考え方としています。

- 対象: **.NET 10 SDK 以降**（C#。ソースジェネレーターを使うため `LangVersion` には preview 相当が必要です。リポジトリは preview でビルドしています）
- ライセンス: **Apache-2.0**
- 位置づけ: 現時点では **アーキテクチャ上の土台** です。`Configuration.Writable` を完全に置き換えるものではありません。

---

## 目次

- [なぜ Configlue なのか](#なぜ-configlue-なのか)
- [インストール](#インストール)
- [Quick Start](#quick-start)
- [基本アーキテクチャ](#基本アーキテクチャ)
- [値の由来を調べる](#値の由来を調べる)
- [スパース保存と Unset](#スパース保存と-unset)
- [その他の API](#その他の-api)
- [主な機能](#主な機能)
- [Microsoft.Extensions.Configuration との違い](#microsoftextensionsconfiguration-との違い)
- [既知の制限](#既知の制限)
- [パッケージ構成](#パッケージ構成)

---

## なぜ Configlue なのか

JSON ファイルを読み書きするだけなら数行で済みます。しかし実際には、次のような要件が積み重なっていきます。

- **設定が複数箇所にある** — グローバル設定、実行フォルダー設定、環境変数、コマンドライン引数、暗号化された資格情報、社内ポリシーや HTTP API によるリモート管理。
- **変更を再起動なしで反映したい** — 設定ファイルが書き換わったときの変更通知。
- **書き込み先を自動で選びたい** — 環境変数から読んだ値への書き込みはエラーにしたい。
- **設定ファイルは人間が書く** — コメントを消したくない、JSON Schema がほしい、壊れたファイルへの対処がほしい。
- **既定値のままなら書き出したくない** — ただしユーザーが明示した `null` は尊重する。
- **設定ファイルのバージョンアップ** — 旧形式から新形式への自動変換。
- **バックアップと自動整理**。
- **書き込みの安全性** — アトミック性（クラッシュしても壊れない）、他プロセスとの競合検出と自動マージ、自動リトライ。

これらを自前実装するのは面倒です。Configlue はこの一式を、層（レイヤー）として宣言的に組み立てられるようにします。

## インストール

```bash
dotnet add package Configlue
```

`Configlue` はユーザー向けのメタパッケージです。XML / YAML や S3 など、必要に応じて機能パッケージを追加してください（後述の[パッケージ構成](#パッケージ構成)）。

## Quick Start

以下を `example.cs` に保存し、`dotnet run example.cs` で実行できます（.NET 10 以降）。

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

ポイントは 3 つです。

1. **モデルを宣言する** — `[ConfiglueModel]` を付けた `partial` クラスに対し、ジェネレーターが Fragment / Patch 用のサポートコードを生成します。
2. **層を宣言する** — `UseCommonSources` で global / local / environment などの標準的な層構成を組み立てます。**ここに列挙したソースだけが有効になります。**
3. **options 経由で読み書きする** — アプリ側は普通のモデル値を扱うだけで、差分の保存先は Configlue が選びます。

## 基本アーキテクチャ

Configlue は 6 つの概念から成ります。依存関係は直線的で、学習順も同じです。

```text
Resource (location) → Codec (conversion) → Source (contribution) → Fragment (diff) → Options (facade)
                                                        ↘ Patch (edit fragment)
```

| 概念 | 一言で | 例 |
| --- | --- | --- |
| **Resource** | バイトがどこにあるか | ファイル、ZIP エントリ、HTTP 応答、メモリ |
| **Codec** | バイト ↔ 値の変換 | JSON / XML / YAML の読み書き |
| **Source** | 論理的な寄与（どのフィールドをどの優先度で） | 「ユーザー設定ファイルの Server 部分」 |
| **Fragment** | 存在を記憶する差分 | 「Port だけ」を持つ状態 |
| **Patch** | 単一フィールドの編集 | 「Port を 9000 にする」 |
| **Options** | アプリが見るファサード | 読み・保存・監視・説明・診断 |

### 読み込み

各 Source が Resource からバイトを取得し、Codec がそれを Fragment に変換します。ランタイムは優先度順に、**「存在する」フィールドだけ**を 1 つのモデルへ重ね合わせます。

### 書き込み

逆向きです。アプリは普通のモデル値を編集するだけで、内部ではその変更が Fragment 差分になります。差分は `WriteRoute` / `WritePlan` が指す Source にだけ届き、無関係な Source は変更されません。

### Fragment と Patch

- Fragment は「メンバーが存在しない」と「null / 既定値で存在する」を区別します。この区別により、層の合成で **未設定が既定値を上書きしてしまう** ことが起きません。
- Patch はジェネレーターが生成する `TModel.Patch`（単一フィールドの編集フラグメント）です。`Unset()` は書き込み先 Source の寄与だけを取り消し、下位優先度の値を再び見えるようにします。
- `[ConfiglueMerge]` でメンバーごとのマージ挙動を変更できます。組み込み戦略は `Append` / `Deep` / `Replace` / `SetUnion` で、カスタム戦略も定義可能です。コレクションの層合成とその順序はここで決まります。

## 値の由来を調べる

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

`GetDetailsAsync` は、メンバーごとに「採用された値の由来（`Source`）」「書き込み可能か（`IsEditable`）」「各 Source の寄与と状態（`Sources`）」を返します。設定が意図した層から来ているかを診断できます。

## スパース保存と Unset

指定したメンバーだけを更新するパッチを保存します。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

- **スパース書き込み** — 変更したフィールドだけが対象層に保存されます。既定値のままのフィールドは書き込まれません。
- **`Unset()`** — その Source の寄与を外し、下位優先度の Source が値を提供できるようにします。

## その他の API

| API | 用途 |
| --- | --- |
| `IReadOnlyOptions<T>` | 日常の読み取り面。`GetValueAsync` と `OnChange` |
| `SaveAsync(patch => ...)` | 生成 Patch によるスパース保存 |
| `OpenEditSessionAsync()` | 複数の変更をまとめて適用し `CommitAsync` |
| `ApplyPatchesAsync` + `StateSourcePatch` | 明示的なソース別マルチ書き込み |
| `StateWritePlan.For<T>().Route(...)` | 書き込みルーティング |
| `SourceKey<TModel>` / `options.Source(key)` | ソース単位の操作 |

### 編集セッション

`OpenEditSessionAsync` を使うと、複数の変更を `CommitAsync` までインメモリでまとめて適用できます。競合が起きた場合は既定で失敗します。`WriteConflictResolution.LastWriteWins` を選ぶこともできます。

## 主な機能

### 優先度マージと読み取り専用ソース

- `Priority` が大きい Source が勝ちます。
- 環境変数・コマンドライン・既定の HTTP ソースは読み取り専用です。**読み取り専用の値への書き込みは黙って無視されず、競合エラーになります。**
- 既存 Source を別モデルへ整形する **projection**、ネストしたパスに別 Source を接続する **mount**（`AddMounted`）をサポートします。
- `UseCommonSources` が global / local / environment などの標準的な層構成を組み立てるプリセットです。

### 安全な書き込み

- **アトミック書き込み** — クラッシュしても設定ファイルが壊れません。
- **競合検出と自動マージ、自動リトライ** — 他プロセスとの同時編集に対応します。
- **バックアップと復元** — `FileResource` はアトミック書き込みとバックアップ世代管理を行います。既定で `.bak` を 1 世代保持し、`RestoreLatestBackupAsync` で復元できます。

### セクション

`JsonSectionResource`（および XML の要素、YAML のマッピング）により、ファイルの一部を独立した Resource として扱えます。

- 書き込み時も **コメント・空白・引用・スカラー形式を保持** します。人間が書いたファイルを機械が上書きする用途に向きます。
- 同じファイル内の独立したセクションは、**1 回の物理書き込みにバッチ** されます。

### リソースの種類

ZIP / HTTP / S3 / Dapr を利用できます。

- `ZipEntryResource` — ZIP アーカイブ内のエントリ
- `Configlue.Resource.Http` — ETag 条件付き書き込みとポーリング
- `Configlue.Resource.S3` / `Configlue.Resource.Dapr`

### スキーマ移行とストレージ移行

- `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` により、旧バージョンの設定を新形式へ自動変換できます。
- 既存のファイルを Source として登録できます。

### JSON Schema 生成

`Configlue.JsonSchema` がモデルから JSON Schema を生成・エクスポートします。設定ファイルを人間が書く前提のライブラリとして、エディター補完や検証に使えるスキーマを用意できます。

### 暗号化

`Configlue.Transformer.AES` は Resource と Codec の間で流れるバイトを **AES-GCM で暗号化・認証** します。資格情報のような機微な層に使えます。

### Native AOT

ソース生成の `JsonSerializerContext` を渡すと、トリミングや Native AOT に対して強くなります。

### リアクティブ統合（任意）

- `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）
- `Configlue.Extensions.R3`（R3 1.3.1）

`ObserveChanges()` / `ObserveValues()` / `ObserveReloadFailures()` / `ObserveActiveValues()` / `ObserveActiveProfileNames()` を利用できます。

### DI / Microsoft.Extensions.Options 統合

- `Configlue.Extensions.DI` — DI コンテナ統合。
- `Configlue.Extensions.MSOptions` — `IOptions<T>` など Microsoft の options へのアダプター。同期ゲッターは非同期ソースの読み取り中にブロックするため、**非同期フローでは `GetValueAsync` の使用を推奨** します。

### プロファイルと動的オプション

名前付きオプションや永続プロファイルを使い、ランタイムを単位に options を作成・削除できます。

## Microsoft.Extensions.Configuration との違い

`IConfiguration` は読み取り中心の設計です。Configlue はそれに加え、**独立した複数のソースを合成し、値の来歴を検査し、変更したフィールドだけを目的の層にスパース保存する** ことに特化しています。設定を読み込むだけでなく、アプリケーションから書き戻す必要がある場合に適しています。

## 既知の制限

- 異なる Resource 間の書き込みはアトミックではありません。
- Source の退役（retirement）は現在の options インスタンスに閉じており、実データは残ります。
- Source の集合は options ランタイムで固定されます。

## パッケージ構成

| パッケージ | 内容 |
| --- | --- |
| `Configlue` | ユーザー向けメタパッケージ。Core / DI / JSON provider / JSON Schema / HTTP resources / common sources / environment source / generator analyzer を同梱（実装アセンブリは持ちません） |
| `Configlue.Abstraction` | 契約（provider / codec / resource / generated-model） |
| `Configlue.Core` | 解決と永続化のランタイム |
| `Configlue.Extensibility` | プロバイダー SDK |
| `Configlue.Generator` | Roslyn アナライザー（スパースなモデルサポートの生成） |
| `Configlue.Testing` | インメモリのテストダブル |
| `Configlue.Provider.Json` / `.Xml` / `.Yaml` | 各形式の Codec、セクションリソース、ファイル登録 |
| `Configlue.JsonSchema` | JSON Schema の生成・エクスポート |
| `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml` | ソース実装とプリセット |
| `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip` | リソース実装 |
| `Configlue.Transformer.AES` | Resource と Codec の間のバイトを AES-GCM で暗号化・認証 |
| `Configlue.Extensions.DI` / `.MSOptions` / `.Reactive` / `.R3` | DI・options・リアクティブ統合 |

## ライセンス

Apache-2.0

