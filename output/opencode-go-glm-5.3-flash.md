# Configlue

**Make easy configuration management.**

Configlue は、アプリケーションの設定管理（configuration management）を代行する .NET ライブラリです。複数の場所に散らばった設定を 1 つのモデルに**結合（glue）**するのが中心的な考え方で、名前も configuration + glue に由来します。

## 概要

JSON ファイルの読み書きだけなら数行で済みます。しかし実際のアプリケーションでは、次のような要件が積み重なります:

- 設定が複数箇所にある: グローバル設定、実行フォルダー設定、環境変数、コマンドライン引数、暗号化された資格情報、社内ポリシーや HTTP API などのリモート管理。
- 設定ファイルが書き換わったら、再起動なしで反映したい（変更通知）。
- 書き込み先を自動で選びたい。環境変数から読んだ値への書き込みはエラーにしたい。
- 設定ファイルは人間が書く: コメントを消さない、JSON Schema がほしい、壊れたファイルへの対処。
- 既定値のままなら書き出さない（ただしユーザーが明示した `null` は尊重する）。
- 設定ファイルのバージョンアップ（旧形式→新形式への自動変換）。
- バックアップと自動整理。
- 書き込みの安全性: アトミック性（クラッシュしても壊れない）、他プロセスとの競合検出・自動マージ、自動リトライ。

これらを自前実装するのは面倒です。Configlue はこの一連の課題を引き受けます。既存の `Microsoft.Extensions.Configuration` との違いを一言でいえば、`IConfiguration` が読み取り中心であるのに対し、Configlue は独立したソースの合成、値の来歴の検査、スパース保存に向いています。

対象は .NET 10 SDK 以降の C# です（`LangVersion` はソースジェネレーター対応が必要で、リポジトリは preview でビルドされています）。ライセンスは Apache-2.0。Configlue は現状「アーキテクチャ上の土台」であり、`Configuration.Writable` を完全に置き換えるものではありません。

### 基本アーキテクチャ

内部構成の基本は 6 つの概念で、依存関係は直線的です。学習する順番も同じです:

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

**読み込み**では、各 Source が Resource からバイトを取得し、Codec が Fragment に変換します。ランタイムは優先度順に「存在する」フィールドだけを 1 つのモデルへ重ねます。

**書き込み**はこの逆です。アプリは普通のモデル値を編集するだけ。内部では変更が Fragment 差分になり、`WriteRoute` / `WritePlan` が指す Source にだけ届きます。無関係な Source は変更されません。

この層構造を支える仕組み:

- Fragment は「メンバーが存在しない」ことと「null / 既定値で存在する」ことを区別します。層を合成しても、「未設定」が「既定値に設定」を上書きすることはありません。
- Patch は生成される `TModel.Patch`（単一フィールドの編集フラグメント）です。`Unset()` を呼ぶと書き込み先 Source の寄与だけが取り消され、下位優先度の値が再び見えるようになります。
- `[ConfiglueMerge]` でメンバーごとのマージ挙動を変更できます（組み込み: `Append` / `Deep` / `Replace` / `SetUnion`、カスタム戦略も可）。コレクションの層合成・順序はここで決まります。

## 主な特徴

- **複数ソースの優先度マージ** — `Priority` が大きい Source が勝ちます。`GetDetailsAsync` で「どの値がどこ由来か」を検査できます。
- **読み取り専用ソース** — 環境変数・コマンドライン・既定の HTTP ソースは読み取り専用です。読み取り専用の値への書き込みは黙って無視されず、競合エラーになります。
- **プロジェクション / マウント** — 既存 Source を別モデルに整形（projection）したり、ネストしたパスに別 Source を接続（mount、`AddMounted`）できます。
- **プリセット** — `UseCommonSources` が標準的な層構成（global / local / environment など）を組み立てます。
- **スパース書き込み** — 変更したフィールドだけを対象層に保存します。既定値のままのフィールドは書かれません。
- **編集セッション** — `OpenEditSessionAsync` で複数の変更をまとめて適用し、`CommitAsync` まではインメモリです。競合時は既定で失敗します（`WriteConflictResolution.LastWriteWins` も選択できます）。
- **スキーマ移行 / ストレージ移行** — `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` による旧バージョン設定の自動変換。既存ファイルを Source として登録することもできます。
- **バックアップと復元** — `FileResource` はアトミック書き込みとバックアップ世代管理を行います。既定で `.bak` 1 世代を保持し、`RestoreLatestBackupAsync` で復元できます。
- **安全な書き込み** — アトミック性、競合検出、リトライ。
- **セクション** — `JsonSectionResource` / XML 要素 / YAML マッピングで、ファイルの一部を独立した Resource として扱えます。書き込み時はコメント・空白・引用・スカラー形式を保持し、同じファイル内の独立セクションは 1 回の物理書き込みにバッチされます。
- **ZIP / HTTP / S3 / Dapr** — `ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込み・ポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **JSON Schema 生成** — `Configlue.JsonSchema` による生成・エクスポート。人間が設定を書くためのスキーマです。
- **Native AOT 対応** — ソース生成の `JsonSerializerContext` を渡すと、トリミング / Native AOT に強くなります。
- **リアクティブ統合（任意）** — `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）。`ObserveChanges()`、`ObserveValues()`、`ObserveReloadFailures()`、`ObserveActiveValues()`、`ObserveActiveProfileNames()` を提供します。
- **DI 統合** — `Configlue.Extensions.DI`。Microsoft の options アダプター `Configlue.Extensions.MSOptions`（`IOptions<T>` など）は、同期ゲッターが非同期ソース読み取り中にブロックするため、非同期フローでは `GetValueAsync` の利用を推奨します。
- **プロファイル / 動的オプション** — 名前付きオプションや永続プロファイルを、ランタイムを単位に作成・削除できます。
- **既知の制限** — 異なる Resource 間の書き込みはアトミックではありません。Source の退役は現在の options インスタンスに閉じており、実データは残ります。Source 集合は options ランタイムで固定です。

## 基本的な使い方

### インストール

まずメタパッケージを追加します:

```sh
dotnet add package Configlue
```

必要な機能に応じて、個別のパッケージを追加します。主なパッケージ:

| パッケージ | 内容 |
| --- | --- |
| `Configlue` | ユーザー向けメタパッケージ（Core / DI / JSON provider / JSON Schema / HTTP resources / common sources / environment source / generator analyzer を同梱。実装アセンブリは持たない） |
| `Configlue.Abstraction` | 契約（provider / codec / resource / generated-model） |
| `Configlue.Core` | 解決と永続化のランタイム |
| `Configlue.Extensibility` | プロバイダー SDK |
| `Configlue.Extensions.DI` / `.MSOptions` / `.R3` / `.Reactive` | DI 統合、Microsoft の options アダプター、R3 / System.Reactive 統合 |
| `Configlue.Generator` | Roslyn アナライザー（スパースなモデルサポート生成） |
| `Configlue.Testing` | インメモリのテストダブル |
| `Configlue.Provider.Json` / `.Xml` / `.Yaml` | 各形式の Codec・セクションリソース・ファイル登録 |
| `Configlue.JsonSchema` | JSON Schema 生成・エクスポート |
| `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml` | 環境変数・コマンドラインソースと `UseCommonSources` のプリセット |
| `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip` | HTTP / Dapr / S3 / ZIP エントリの Resource |
| `Configlue.Transformer.AES` | Resource と Codec の間のバイトを AES-GCM で暗号化・認証 |

### Quick Start

次のコードを `example.cs` に保存して `dotnet run example.cs` で実行します（.NET 10 以降）:

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

やっていることは次のとおりです:

1. `[ConfiglueModel]` を付けた `partial` クラスとして設定モデルを宣言します。ジェネレーターが Fragment / Patch サポートを生成します。
2. `ConfiglueApp.CreateContext` と `UseCommonSources` でプリセットの層構成を宣言します。ここに列挙した Source だけが有効になります。この例では global / local / environment の層を構成しています。
3. `GetOptions<T>()` で取得した options インスタンスを通じて読み書きします。`SaveAsync` のパッチ編集はスパースに動作し、未変更の `DefaultValue` は対象層に保存されません。

### 値の由来を調べる

各値がどの Source 由来か、書き込み可能かを調べるには `GetDetailsAsync` を使います:

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

### スパース保存と Unset()

パッチは指定したメンバーだけを更新して保存します。`Unset()` を呼ぶとその Source の寄与が外され、下位優先度の Source が値を提供できるようになります:

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

### その他の API

- `IReadOnlyOptions<T>` — 日常の読み取り面は `GetValueAsync` と `OnChange`。
- `options.SaveAsync(patch => ...)` — 生成された Patch によるスパース保存。
- `options.OpenEditSessionAsync()` — 複数の変更をまとめて編集し、`CommitAsync` で適用。
- `options.ApplyPatchesAsync` + `StateSourcePatch` — ソースを明示した複数 Source への書き込み。
- `StateWritePlan.For<T>().Route(...)` — 書き込みルーティング。
- `SourceKey<TModel>` と `options.Source(key)` — ソース単位の操作。
