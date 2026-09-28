# Configlue

> Make easy configuration management.

Configlue は、アプリケーションの設定管理を引き受ける .NET ライブラリです。あちこちに散在する設定を一つのモデルに **glue**（接着）することが中心のアイデアで、名前は configuration + glue に由来します。

- 要件: .NET 10 SDK 以降（ソースジェネレーターが使える `LangVersion` が必要。リポジトリは `preview` でビルド）
- ライセンス: Apache-2.0
- 現状は「アーキテクチャの基盤」であり、`Configuration.Writable` の完全な代替ではありません

## Why Configlue?

JSON ファイルを読み書きするだけなら数行で書けます。しかし実際の要件はこのように積み上がります:

- 設定が複数の場所に存在する: グローバル設定、実行フォルダごとの設定、環境変数、コマンドライン引数、暗号化された資格情報、企業ポリシーや HTTP API による遠隔管理
- 設定ファイルが書き換えられたら、アプリを再起動せずに反映したい（変更通知）
- 書き込み先を自動的に選び分けたい。環境変数から読み込んだ値への書き込みはエラーにしたい
- 設定ファイルは人間が書く: コメントを消したくない、JSON Schema が欲しい、壊れたファイルを扱いたい
- デフォルト値のままの項目は書き出したくない（ただしユーザーが明示的に設定した `null` は尊重する）
- 設定ファイルのバージョンアップ（旧形式から新形式への自動変換）
- バックアップと自動クリーンアップ
- 書き込みの安全性: 原子的性（クラッシュで破損しない）、他プロセスとの競合検出と自動マージ、自動リトライ

これらを全部自分で実装するのは面倒、というのが動機です。

### Microsoft.Extensions.Configuration との違い

`IConfiguration` は読み取り志向です。Configlue は、独立したソースの合成・値の出所の検査・稀疏（sparse）保存に向いています。

## 中核アーキテクチャ（6 つの概念）

依存関係は一直線になり、これが学習順序もそのままです:

```text
Resource (場所) → Codec (変換) → Source (寄与) → Fragment (差分) → Options (ファサード)
                                              ↘ Patch (一項目の編集)
```

| 概念 | 一言で | 例 |
| --- | --- | --- |
| Resource | バイト列がどこにあるか | ファイル、ZIP エントリ、HTTP レスポンス、メモリ |
| Codec | バイト列と値の変換 | JSON / XML / YAML の読み書き |
| Source | 論理的な寄与（どの項目をどの優先度で出すか） | 「ユーザー設定ファイルの `Server` の部分」 |
| Fragment | 存在を覚えている差分 | 「`Port` だけ持っている」状態 |
| Patch | 一項目の編集 | 「`Port` を 9000 にする」 |
| Options | アプリが見るファサード | 読み取り、保存、監視、説明、診断 |

**読み取り**: 各 Source が Resource からバイト列を取り、Codec が Fragment に変換します。ランタイムは「存在する」項目だけを優先度順に重ね合わせて、一つのモデルにします。

**書き込み**: 逆方向です。アプリは普通のモデル値を編集します。内部的には変更は Fragment の差分になり、`WriteRoute` / `WritePlan` が指定する Source にだけ届きます。無関係な Source は変更されません。

- Fragment は「メンバーが存在しない」と「null/デフォルトとして存在する」を区別します。レイヤー合成で「未設定」が「デフォルトに設定済み」を上書きすることは決してありません。
- Patch は生成される `TModel.Patch`（一項目の編集フラグメント）です。`Unset()` は書き込み先 Source の寄与だけを退避し、優先度の低い値を再び露出させます。
- `[ConfiglueMerge]` はメンバーごとのマージ挙動を変えます（組み込み: `Append`、`Deep`、`Replace`、`SetUnion`。カスタム戦略も可）。コレクションのレイヤー合成と順序はここで決まります。

## 主な機能

- **複数ソースの優先度マージ**: `Priority` が大きい Source が勝ります。`GetDetailsAsync` で「どの値がどこから来たか」を検査できます。
- **読み取り専用ソース**: 環境変数、コマンドライン、デフォルトの HTTP ソースは読み取り専用です。読み取り専用の値への書き込みは、黙って無視するのではなく競合エラーになります。
- **射影 / マウント**: 既存の Source を別のモデルに形変換できます（射影）。別の Source を入れ子のパスに取り付けられます（マウント、`AddMounted`）。
- **プリセット**: `UseCommonSources` が標準的なレイヤー構成（グローバル/ローカル/環境など）を組み立てます。
- **稀疏書き込み**: 変更した項目だけがターゲットレイヤーに保存されます。デフォルトのままの項目は書かれません。
- **編集セッション**: `OpenEditSessionAsync` で複数の変更をまとめて適用します。`CommitAsync` までメモリ内に留まります。競合時はデフォルトで失敗し、`WriteConflictResolution.LastWriteWins` も選べます。
- **スキーママイグレーション / ストレージマイグレーション**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` により旧バージョンの設定を自動変換します。既存のファイルを Source として登録できます。
- **バックアップと復元**: `FileResource` は原子的書き込みとバックアップ世代管理を提供します。デフォルトは `.bak` 一代で、`RestoreLatestBackupAsync` で復元できます。
- **安全な書き込み**: 原子的性、競合検出、リトライ。
- **セクション**: `JsonSectionResource` / XML 要素 / YAML マッピングで、ファイルの一部を独立した Resource として扱えます。書き込み時はコメント、空白、引用、スカラースタイルが保持されます。同一ファイル内の独立セクションは一つの物理書き込みにまとめられます。
- **ZIP / HTTP / S3 / Dapr**: `ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込みとポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **JSON Schema 生成**: 人間が設定を書くものなので、`Configlue.JsonSchema` で生成・出力できます。
- **Native AOT 対応**: ソース生成された `JsonSerializerContext` を渡すと、トリミング/AOT 耐性が向上します。
- **リアクティブ統合（オプション）**: `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）。`ObserveChanges()`、`ObserveValues()`、`ObserveReloadFailures()`、`ObserveActiveValues()`、`ObserveActiveProfileNames()`。
- **DI 統合**: `Configlue.Extensions.DI`。Microsoft Options アダプターは `Configlue.Extensions.MSOptions` にあります（`IOptions<T>` など。同期ゲッターは非同期ソースの読み取り中にブロックするため、非同期フローでは `GetValueAsync` を推奨）。
- **プロファイル / 動的オプション**: 名前付きオプションと永続プロファイルにより、ランタイムを単位として作成・削除できます。

## インストール

```bash
dotnet add package Configlue
```

必要な能力に応じてパッケージを追加します。

### パッケージ構成（主要なもの）

| パッケージ | 役割 |
| --- | --- |
| `Configlue` | ユーザー向けメタパッケージ（Core / DI / JSON プロバイダー / JSON Schema / HTTP リソース / 共通ソース / 環境ソース / ジェネレーター・アナライザーを同梱。独自の実装アセンブリは持たない） |
| `Configlue.Abstraction` | 契約（プロバイダー/コーデック/リソース/生成モデル） |
| `Configlue.Core` | 解決と永続化のランタイム |
| `Configlue.Extensibility` | プロバイダー SDK |
| `Configlue.Extensions.DI` / `.MSOptions` / `.R3` / `.Reactive` | DI・MSOptions・リアクティブ統合 |
| `Configlue.Generator` | Roslyn アナライザー（稀疏モデルサポートを生成） |
| `Configlue.Testing` | インメモリ test double |
| `Configlue.Provider.Json` / `.Xml` / `.Yaml` | 各形式のコーデック、セクションリソース、ファイル登録 |
| `Configlue.JsonSchema` | JSON Schema 生成と出力 |
| `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml` | ソースとプリセット |
| `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip` | リソース |
| `Configlue.Transformer.AES` | Resource と Codec の間のバイト列に対する AES-GCM 暗号化と認証 |

## クイックスタート

`example.cs` に保存して `dotnet run example.cs` で実行できます（.NET 10 以降）:

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

// 2. プリセットレイヤーを宣言。ここに列挙したソースだけが有効になります。
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);

// 3. Options インスタンス経由で読み書き。
var options = context.GetOptions<SampleSetting>();
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 稀疏編集: 変更したフィールドだけがターゲットレイヤーに保存されます。
await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue は変更していないので、ターゲットレイヤーには保存されません。
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

## 値の出所の検査 / 稀疏保存

```csharp
var options = context.GetOptions<AppSettings>();
// 1. 現在の値（全ソースからマージ）を取得
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 2. 各値がどこから来たかを検査
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

指定したメンバーだけを更新する Patch を保存します。`Unset()` はその Source の寄与を取り除き、優先度の低い Source が値を提供できるようにします:

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

その他の API:

- `IReadOnlyOptions<T>` … 日常の読み取り面は `GetValueAsync` と `OnChange`
- `SaveAsync(patch => ...)` … 生成された Patch による稀疏保存
- `OpenEditSessionAsync()` … 複数箇所をまとめて編集し、`CommitAsync`
- `ApplyPatchesAsync` + `StateSourcePatch` … Source を明示した複数書き込み
- `StateWritePlan.For<T>().Route(...)` … 書き込みルーティング
- `SourceKey<TModel>` と `options.Source(key)` … Source 単位の操作

## 既知の制限

- 異なる Resource にまたがる書き込みは原子的ではありません
- Source の退役は現在の Options インスタンスのスコープであり、裏のデータはそのまま残ります
- ソースセットは Options ランタイムの間固定です

## ライセンス

Apache-2.0
