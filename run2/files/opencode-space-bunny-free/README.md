# Configlue

**Make easy configuration management.**

Configlue は .NET アプリケーションの設定管理（configuration management）を代行するライブラリです。
設定が散らばる複数の場所 ― グローバル設定、実行フォルダー、環境変数、コマンドライン、暗号化された資格情報、
甚至は社内ポリシー API ― を **1 つのモデルに結合（glue）** します。名前の由来は configuration + glue です。

- 対象: .NET 10 SDK 以降
- ライセンス: Apache-2.0
- 現状: 「アーキテクチャ上の土台」です。`Configuration.Writable` を完全に置き換えるものではありません

## インストール

```shell
dotnet add package Configlue
```

`Configlue` はユーザー向けのメタパッケージです（Core / DI / JSON provider / JSON Schema / HTTP resources /
common sources / environment source / generator analyzer を同梱。実装アセンブリ自体は持ちません）。
XML や YAML、リモートリソースなどが必要な場合は、該当する機能パッケージを追加してください。

## Why Configlue?

JSON ファイルを読み書きするだけなら数行で済みます。実際には次のような要件が積み重なります。

- 設定が複数箇所にある（グローバル設定、実行フォルダー、環境変数、コマンドライン引数、暗号化された資格情報、社内ポリシーや HTTP API などのリモート管理）
- 設定ファイルが書き換わったら再起動なしで反映したい（変更通知）
- 書き込み先を自動で選びたい。環境変数から読んだ値への書き込みはエラーにしたい
- 設定ファイルは人間が書く。コメントを消したくない、JSON Schema がほしい、壊れたファイルへの対処がほしい
- 既定値のままなら書き出したくない（ただしユーザーが明示した `null` は尊重する）
- 設定ファイルのバージョンアップ 때、旧形式から新形式へ自動変換したい
- バックアップと自動整理
- 書き込みの安全性: アトミック性（クラッシュしても壊れない）、他プロセスとの競合検出・自動マージ、自動リトライ

これらを自前実装するのは面倒です。Configlue はその共通部分をランタイムとジェネレーターに閉じ込めています。

## Quick Start

`example.cs` として保存し、.NET 10 以降で `dotnet run example.cs` を実行してください。

```csharp
#!/usr/bin/env dotnet
#:package Configlue@*

using Configlue;
using Configlue.Source.Presets;

// 1. 設定モデルを宣言する。ジェネレーターが Fragment / Patch のサポートを生成する。
[ConfiglueModel("SampleSetting", Version = 1)]
public partial class SampleSetting
{
    public string Name { get; set; } = "World";
    public int RunCount { get; set; }
    public bool DefaultValue { get; set; } = true;
}

// 2. プリセットの層を宣言する。ここで列挙したソースだけが有効になる。
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);

// 3. Options インスタンス経由で読み書きする。
var options = context.GetOptions<SampleSetting>();
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// スパース編集: 変更したフィールドだけが対象層に保存される。
await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue は変更していないので対象層には書き込まれない。
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

## アーキテクチャ

依存関係は直線的で、学習順も同じです。

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

**読み込み**: 各 Source が Resource からバイトを取得し、Codec が Fragment に変換します。ランタイムは優先度順に
「存在する」フィールドだけを 1 つのモデルへ重ねます。

**書き込み**: 逆向きです。アプリは普通のモデル値を編集し、内部では変更が Fragment 差分になります。
`WriteRoute` / `WritePlan` が指す Source にだけ届き、無関係な Source は変更されません。

- Fragment は「メンバーが存在しない」と「null / 既定値で存在する」を区別します。層の合成で「未設定」が
  「既定値に設定」を上書きすることはありません。
- Patch は生成される `TModel.Patch`（単一フィールドの編集フラグメント）です。`Unset()` は書き込み先 Source の
  寄与だけを取り消し、下位優先度の値を再び見せます。
- `[ConfiglueMerge]` でメンバーごとのマージ挙動を変更できます（組み込み: `Append` / `Deep` / `Replace` /
  `SetUnion`、カスタム戦略も可）。コレクションの層合成と順序はこの指定で決まります。

## 主な機能

- **複数ソースの優先度マージ** — `Priority` が大きい Source が勝ちます。`GetDetailsAsync` で
  「どの値がどこ由来か」を検査できます。
- **読み取り専用ソース** — 環境変数・コマンドライン・既定の HTTP ソースは読み取り専用です。読み取り専用の値への
  書き込みは黙って無視されず、競合エラーになります。
- **プロジェクション / マウント** — 既存 Source を別モデルに整形（projection）したり、ネストしたパスに別の
  Source を接続（mount、`AddMounted`）できます。
- **プリセット** — `UseCommonSources` が global / local / environment などの標準的な層構成を組み立てます。
- **スパース書き込み** — 変更したフィールドだけを対象層に保存します。既定値のままのフィールドは書かれません。
- **編集セッション** — `OpenEditSessionAsync` で複数変更をまとめて適用し、`CommitAsync` までインメモリです。
  競合時は既定で失敗し、`WriteConflictResolution.LastWriteWins` も選べます。
- **スキーマ移行 / ストレージ移行** — `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` による
  旧バージョン設定の自動変換。既存ファイルを Source として登録できます。
- **バックアップと復元** — `FileResource` はアトミック書き込みとバックアップ世代管理を提供します。既定で `.bak`
  1 世代、`RestoreLatestBackupAsync` で復元します。
- **安全な書き込み** — アトミック性、競合検出、リトライ。
- **セクション** — `JsonSectionResource`、XML 要素、YAML マッピングで、ファイルの一部を独立した Resource として
  扱えます。書き込み時にコメント・空白・引用・スカラー形式を保持し、同じファイル内の独立セクションは 1 回の
  物理書き込みにバッチされます。
- **ZIP / HTTP / S3 / Dapr** — `ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込み・ポーリング）、
  `Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **JSON Schema 生成** — `Configlue.JsonSchema`。人間が設定ファイルを書くためのサポートです。
- **Native AOT 対応** — ソース生成の `JsonSerializerContext` を渡すとトリミング / AOT に強くなります。
- **リアクティブ統合（任意）** — `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と
  `Configlue.Extensions.R3`（R3 1.3.1）。`ObserveChanges()` / `ObserveValues()` / `ObserveReloadFailures()` /
  `ObserveActiveValues()` / `ObserveActiveProfileNames()` が使えます。
- **DI 統合** — `Configlue.Extensions.DI`。Microsoft の options アダプターが `Configlue.Extensions.MSOptions` です
  （`IOptions<T>` など）。同期ゲッターは非同期ソースの読み取り中にブロックするため、非同期フローでは
  `GetValueAsync` の利用を推奨します。
- **プロファイル / 動的オプション** — 名前付きオプションや永続プロファイルを、ランタイム単位で作成・削除できます。

## 値の由来を調べる / スパース保存

マージ後の値を取得するだけでなく、各フィールドがどのソース由来かを確認できます。

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

指定したメンバーだけを更新するパッチを保存します。`Unset()` はその Source の寄与を外し、下位優先度の
Source が値を提供できるようにします。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

### その他の API

- `IReadOnlyOptions<T>` — 日常の読み取り面は `GetValueAsync` と `OnChange`。
- `SaveAsync(patch => ...)` — 生成 Patch によるスパース保存。
- `OpenEditSessionAsync()` — 変更をまとめて編集し、`CommitAsync` で確定。
- `ApplyPatchesAsync` + `StateSourcePatch` — 明示的なソース別マルチ書き込み。
- `StateWritePlan.For<T>().Route(...)` — 書き込みルーティング。
- `SourceKey<TModel>` と `options.Source(key)` — ソース単位の操作。

## Microsoft.Extensions.Configuration との違い

`IConfiguration` は読み取りを中心とした<Key,Value> ベースの抽象化です。対して Configlue は、
独立したソースの合成・値の来歴の検査・スパース保存を前提に設計されています。
どこから来たかを説明でき、書き込む先を安全に決められることが、Configlue を選ぶ理由になります。

## パッケージ構成

| パッケージ | 役割 |
| --- | --- |
| `Configlue` | ユーザー向けメタパッケージ |
| `Configlue.Abstraction` | 契約（provider / codec / resource / generated-model） |
| `Configlue.Core` | 解決と永続化のランタイム |
| `Configlue.Extensibility` | プロバイダー SDK |
| `Configlue.Extensions.DI` | 依存性注入への統合 |
| `Configlue.Extensions.MSOptions` | Microsoft options アダプター（`IOptions<T>` など） |
| `Configlue.Extensions.R3` | R3 連携 |
| `Configlue.Extensions.Reactive` | System.Reactive 連携 |
| `Configlue.Generator` | Roslyn アナライザー（スパースなモデルサポートの生成） |
| `Configlue.Testing` | インメモリのテストダブル |
| `Configlue.Provider.Json` / `.Xml` / `.Yaml` | 各形式の Codec・セクションリソース・ファイル登録 |
| `Configlue.JsonSchema` | JSON Schema の生成とエクスポート |
| `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml` | ソースの追加機能 |
| `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip` | リモートおよびアーカイブリソース |
| `Configlue.Transformer.AES` | Resource と Codec の間のバイトを AES-GCM で暗号化・認証 |

## 既知の制限

- 異なる Resource 間の書き込みはアトミックではありません。
- Source の退役は現在の options インスタンスに閉じるだけで、実データは残ります。
- Source 集合は options ランタイムで固定です。

## ビルドについて

リポジトリは preview 設定でビルドされます。ソースジェネレーター的支持が必要なため、`LangVersion` を
preview 相当に設定してください。
