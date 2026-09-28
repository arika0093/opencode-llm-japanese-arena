# Configlue

> Make easy configuration management.

Configlue は、アプリケーション内の複数の場所に分散した設定をひとつのモデルへまとめ、読み取り・変更・保存を扱う .NET ライブラリです。名前は *configuration* と *glue* に由来します。

グローバル設定、実行フォルダーごとの設定、環境変数、コマンドライン引数、リモート設定などを組み合わせ、値の出どころを調べながら、変更した項目だけを適切な保存先へ書き込めます。

## なぜ Configlue?

JSON ファイルの読み書き自体は簡単でも、実際のアプリケーションでは次のような要件が加わります。

- 複数の設定元を優先度に応じて合成したい
- ファイルの変更を再起動なしで反映したい
- 環境変数など読み取り専用の値への書き込みをエラーにしたい
- コメントなど人が編集した設定ファイルの書式を保ちたい
- 変更した項目だけを保存し、未変更の既定値は書き出したくない
- 設定形式の移行、バックアップ、復元を扱いたい
- クラッシュや複数プロセスからの更新に備えて安全に書き込みたい

こうした処理を個別に実装する手間を減らすことが Configlue の目的です。

`Microsoft.Extensions.Configuration` の `IConfiguration` が読み取りを中心とするのに対し、Configlue は独立した設定元の合成、値の出どころの確認、変更箇所だけの保存を扱うための仕組みを提供します。

## 基本のしくみ

Configlue の概念は、データの流れに沿って理解できます。

```text
Resource（保存場所）→ Codec（変換）→ Source（設定の寄与）→ Fragment（差分）→ Options（アプリ向け API）
                                                              ↘ Patch（差分の編集）
```

| 概念 | 役割 | 例 |
| --- | --- | --- |
| `Resource` | バイト列がある場所 | ファイル、ZIP エントリー、HTTP レスポンス、メモリ |
| `Codec` | バイト列と値の相互変換 | JSON、XML、YAML |
| `Source` | 優先度を持つ設定の寄与 | ユーザー設定ファイルの `Server` 部分 |
| `Fragment` | 値の有無を保持する差分 | `Port` だけを含む状態 |
| `Patch` | 項目単位の編集 | `Port` を 9000 に設定 |
| `Options` | アプリケーションから使う窓口 | 読み取り、保存、監視、調査 |

読み取り時は、各 `Source` が `Resource` からデータを取得し、`Codec` が `Fragment` に変換します。ランタイムは値が設定されている項目だけを優先度順に重ね、ひとつのモデルを構成します。

書き込み時は、通常のモデルへの変更を `Fragment` の差分に変換し、`WriteRoute` / `WritePlan` で指定した `Source` に反映します。関係のない `Source` は変更しません。`Fragment` は「項目が存在しない」状態と「`null` や既定値として存在する」状態を区別します。

## 主な機能

- **複数ソースの優先度付き合成** — 優先度の高い `Source` の値を採用します。`GetDetailsAsync` で値の出どころや書き込み可否を調べられます。
- **読み取り専用ソースの保護** — 環境変数、コマンドライン、既定の HTTP ソースへの書き込みは黙って無視せず、競合エラーになります。
- **スパースな保存** — 指定した項目だけを保存し、未変更の項目を保存先に書き出しません。
- **項目ごとのマージ方法** — `[ConfiglueMerge]` で `Append`、`Deep`、`Replace`、`SetUnion` などを指定できます。カスタム戦略も利用できます。
- **ソースの投影とマウント** — 既存の `Source` を別モデルに投影したり、`AddMounted` でモデル内のパスに別の `Source` を接続したりできます。
- **プリセット** — `UseCommonSources` でグローバル、ローカル、環境変数などの標準的な構成を組み立てられます。
- **編集セッション** — `OpenEditSessionAsync` で複数の変更をメモリ上にまとめ、`CommitAsync` で確定できます。競合時は既定で失敗し、`WriteConflictResolution.LastWriteWins` も選べます。
- **スキーマ・ストレージ移行** — `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` による旧バージョンからの変換や、既存ファイルの `Source` 登録に対応します。
- **安全なファイル書き込みとバックアップ** — `FileResource` はアトミックな書き込みとバックアップ世代の管理を行います。既定では `.bak` を 1 世代保持し、`RestoreLatestBackupAsync` で復元できます。
- **ファイルの一部分を独立したリソースとして扱う** — JSON セクション、XML 要素、YAML マッピングを扱えます。書き込み時にコメント、空白、引用符、スカラーのスタイルを保持し、同じファイル内の独立したセクションは物理書き込みをまとめます。
- **さまざまな保存先** — ZIP、HTTP（ETag による条件付き書き込みとポーリング）、S3、Dapr に対応するリソースがあります。
- **JSON Schema と Native AOT** — JSON Schema の生成・出力に対応します。ソース生成された `JsonSerializerContext` を渡すことで、トリミングや AOT への対応を高められます。
- **DI・Options・リアクティブ連携** — DI、`IOptions<T>` などの Microsoft Options アダプター、System.Reactive / R3 向けの任意パッケージを提供します。
- **プロファイルと動的 Options** — 名前付き Options や永続プロファイルを使い、ランタイムを単位として作成・削除できます。

## クイックスタート

.NET 10 以降で、以下を `example.cs` として保存し、`dotnet run example.cs` で実行できます。

```csharp
#!/usr/bin/env dotnet
#:package Configlue@*

using Configlue;
using Configlue.Source.Presets;

// 1. 設定モデルを宣言します。ジェネレーターが Fragment / Patch のサポートを生成します。
[ConfiglueModel("SampleSetting", Version = 1)]
public partial class SampleSetting
{
    public string Name { get; set; } = "World";
    public int RunCount { get; set; }
    public bool DefaultValue { get; set; } = true;
}

// 2. 使用するソースを指定します。
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);

// 3. Options 経由で読み取り、変更した項目を保存します。
var options = context.GetOptions<SampleSetting>();
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue は変更していないため、保存先には書き込まれません。
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

### 値の出どころを確認する

`GetDetailsAsync` では、各項目の値を提供したソースや書き込み可否を確認できます。

```csharp
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

`Patch` の `Unset()` は、書き込み先 `Source` の寄与だけを取り下げ、より低い優先度の `Source` が値を提供できるようにします。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

## インストール

基本パッケージを追加します。

```sh
dotnet add package Configlue
```

必要な機能に応じて、JSON / XML / YAML プロバイダー、リソース、拡張パッケージなどを追加してください。`Configlue` は主要パッケージをまとめたメタパッケージで、独自の実装アセンブリは持ちません。

## パッケージ構成

- `Configlue` — Core、DI、JSON プロバイダー、JSON Schema、HTTP リソース、共通ソース、環境変数ソース、ジェネレーターを含むメタパッケージ
- `Configlue.Abstraction`、`Configlue.Core`、`Configlue.Extensibility` — 契約、解決・永続化ランタイム、プロバイダー SDK
- `Configlue.Generator`、`Configlue.Testing` — スパースモデル対応を生成する Roslyn アナライザー、インメモリのテスト用ダブル
- `Configlue.Provider.Json` / `.Xml` / `.Yaml` — 各形式の Codec、セクションリソース、ファイル登録
- `Configlue.Source.Environment` / `.CommandLine` / `.Presets` — 環境変数、コマンドライン、プリセット
- `Configlue.Resource.Http` / `.Dapr` / `.S3` / `.Zip` — 各リソース実装
- `Configlue.Extensions.DI` / `.MSOptions` / `.Reactive` / `.R3` — DI、Microsoft Options、リアクティブ連携
- `Configlue.JsonSchema`、`Configlue.Transformer.AES` — JSON Schema 生成、Resource と Codec の間のバイト列に対する AES-GCM 暗号化・認証

## 制約

- .NET 10 SDK 以降が必要です。C# の `LangVersion` はソースジェネレーターをサポートする必要があり、このリポジトリは `preview` でビルドされます。
- 異なる `Resource` にまたがる書き込みはアトミックではありません。
- `Source` の退役は現在の Options インスタンス内に限られ、保存先のデータは残ります。
- Options ランタイムの開始後に `Source` の集合を変更することはできません。
- Configlue は設定管理のためのアーキテクチャ基盤であり、`Configuration.Writable` の完全な置き換えではありません。

## ライセンス

Apache-2.0
