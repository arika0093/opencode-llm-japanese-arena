# Configlue

> Make easy configuration management.

Configlue は、アプリケーションの設定管理を一手に引き受ける .NET ライブラリです。
名前は **config**uration + g**lue**。複数の場所に散らばった設定を、ひとつのモデルに「貼り合わせる（glue）」ことを中心概念にしています。

- 対象: .NET 10 SDK 以降 / C#（ソースジェネレーターを利用するため、それをサポートする `LangVersion` が必要です。リポジトリは `preview` でビルドしています）
- ライセンス: Apache-2.0
- 現状は「アーキテクチャの基盤」であり、`Configuration.Writable` の完全な代替ではありません

---

## 目次

- [なぜ Configlue なのか](#なぜ-configlue-なのか)
- [インストール](#インストール)
- [クイックスタート](#クイックスタート)
- [コアアーキテクチャ（6つの概念）](#コアアーキテクチャ6つの概念)
- [主な機能](#主な機能)
- [値の出所を調べる / 疎な保存](#値の出所を調べる--疎な保存)
- [パッケージ構成](#パッケージ構成)
- [Microsoft.Extensions.Configuration との違い](#microsoftextensionsconfiguration-との違い)
- [既知の制限](#既知の制限)

---

## なぜ Configlue なのか

JSON ファイルを1つ読み書きするだけなら、数行で書けます。しかし実際のアプリケーションでは、要求が次のように積み上がっていきます。

| 要求 | 内容 |
| --- | --- |
| 設定が複数箇所にある | グローバル設定、ランタイムフォルダごとの設定、環境変数、コマンドライン引数、暗号化された資格情報、さらに企業ポリシーや HTTP API といったリモート管理 |
| 変更通知 | 設定ファイルが書き換えられたら、アプリを再起動せずに反映したい |
| 書き込み先の自動選択 | 書き込み先は自動で選びたい。環境変数から読んだ値への書き込みはエラーにしたい |
| 人間が書くファイル | コメントを消したくない。JSON Schema が欲しい。壊れたファイルも扱いたい |
| 既定値の扱い | まだ既定値のままの項目は書き出したくない（ただしユーザーが明示した `null` は尊重したい） |
| バージョンアップ | 設定ファイルを旧形式から新形式へ自動変換したい |
| バックアップ | 世代管理と自動掃除 |
| 書き込み安全性 | 原子性（クラッシュ時に壊さない）、他プロセスとの衝突検出と自動マージ、自動リトライ |

これらをすべて自前で実装するのは退屈です。Configlue は、この「設定管理のあるある」を構造として引き受けることを目的にしています。

---

## インストール

まずはメタパッケージを追加します。

```bash
dotnet add package Configlue
```

そのうえで、必要な機能パッケージ（HTTP / S3 / XML / YAML / Reactive など）を追加してください。
パッケージ構成は [パッケージ構成](#パッケージ構成) を参照してください。

---

## クイックスタート

以下を `example.cs` に保存し、`dotnet run example.cs` で実行できます（.NET 10 以降）。

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

// 2. プリセットのレイヤー構成を宣言します。ここに列挙したソースだけが有効になります。
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);

// 3. options インスタンス経由で読み書きします。
var options = context.GetOptions<SampleSetting>();
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 疎（sparse）な編集: 変更したフィールドだけが対象レイヤーに保存されます。
await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue は変更していないため、対象レイヤーには保存されません。
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

ポイントは3つです。

1. **モデルを宣言する** — `[ConfiglueModel]` を付けた `partial class` に、ソースジェネレーターが Fragment / Patch のコードを生成します。
2. **レイヤーを宣言する** — `UseCommonSources` で「どの場所から、どの優先度で読むか」を組み立てます。
3. **モデルとして読み書きする** — アプリケーションが触るのは普通のモデル値だけです。保存先の選択や差分計算は内部で行われます。

---

## コアアーキテクチャ（6つの概念）

依存関係は一直線に並んでおり、学習する順序も同じです。

```text
Resource (場所) → Codec (変換) → Source (寄与) → Fragment (差分) → Options (ファサード)
                                                        ↘ Patch (編集差分)
```

| 概念 | 一言で | 例 |
| --- | --- | --- |
| Resource | バイト列が置かれている場所 | ファイル、ZIP エントリ、HTTP レスポンス、メモリ |
| Codec | バイト列と値の間の変換 | JSON / XML / YAML の読み書き |
| Source | 論理的な寄与（どのフィールドをどの優先度で） | 「ユーザー設定ファイルのうち `Server` の部分」 |
| Fragment | 「存在」を覚えている差分 | 「`Port` だけがある」状態 |
| Patch | 単一フィールドの編集 | 「`Port` を 9000 にする」 |
| Options | アプリケーションが見るファサード | 読む、保存する、監視する、説明する、診断する |

### 読み取り

各 Source が Resource からバイト列を取得し、Codec がそれを Fragment に変換します。
ランタイムは **「存在する」フィールドだけ**を、優先度の順に、ひとつのモデルへ重ね合わせます。

### 書き込み

読み取りの逆方向です。アプリケーションは普通のモデル値を編集します。
内部的にはその変更が Fragment の差分になり、`WriteRoute` / `WritePlan` が指定した Source にだけ届きます。無関係な Source は変更されません。

### Fragment と Patch

- **Fragment** は「メンバーが存在しない」ことと「`null` / 既定値として存在する」ことを区別します。
  そのため、レイヤー合成時に「未設定」が「既定値に設定済み」を上書きしてしまうことがありません。
- **Patch** は生成される `TModel.Patch`（単一フィールドの編集差分）です。
  `Unset()` は書き込み先 Source の寄与だけを取り下げ、より優先度の低い Source の値を再び表に出します。
- **`[ConfiglueMerge]`** でメンバーごとのマージ挙動を変更できます。
  組み込みは `Append` / `Deep` / `Replace` / `SetUnion`。独自ストラテジも定義可能です。
  コレクションのレイヤー合成や順序はここで決まります。

---

## 主な機能

### 複数ソースの優先度マージ

`Priority` の大きい Source が優先されます。`GetDetailsAsync` で「どの値がどこから来たか」を検査できます。

### 読み取り専用ソース

環境変数、コマンドライン、既定の HTTP ソースは読み取り専用です。
読み取り専用の値への書き込みは、**暗黙に無視されず、衝突エラーになります**。

### 投影（Projection）とマウント（Mount）

既存の Source を別のモデルに作り替える（投影）ことや、別の Source をネストしたパスに取り付ける（マウント、`AddMounted`）ことができます。

### プリセット

`UseCommonSources` が、標準的なレイヤー構成（グローバル / ローカル / 環境変数など）を組み立てます。

### 疎な書き込み（Sparse writes）

変更したフィールドだけが対象レイヤーに保存されます。既定値のままのフィールドは書き出されません。

### 編集セッション

`OpenEditSessionAsync` で複数の変更をまとめて適用します。`CommitAsync` まではメモリ上の変更です。
衝突時は既定で失敗し、`WriteConflictResolution.LastWriteWins` も選択できます。

### スキーマ移行 / 保存形式の移行

`[ConfigluePreviousVersion]` と `Fragment.FromPrevious` により、旧バージョンの設定を自動変換できます。
既存ファイルを Source として登録することも可能です。

### バックアップとリストア

`FileResource` が原子書き込みとバックアップ世代管理を提供します。既定では `.bak` を1世代保持し、
`RestoreLatestBackupAsync` で復元できます。

### 安全な書き込み

原子性、衝突検出、リトライを備えます。

### セクション

`JsonSectionResource` / XML 要素 / YAML マッピングにより、ファイルの一部を独立した Resource として扱えます。
書き込み時は**コメント、空白、クォート、スカラースタイルが保持されます**。
同一ファイル内の独立したセクションは、1回の物理書き込みにまとめられます。

### ZIP / HTTP / S3 / Dapr

`ZipEntryResource`、`Configlue.Resource.Http`（ETag による条件付き書き込みとポーリング）、
`Configlue.Resource.S3`、`Configlue.Resource.Dapr` を利用できます。

### JSON Schema 生成

設定は人間が書くものなので、`Configlue.JsonSchema` が JSON Schema の生成と出力を提供します。

### ネイティブ AOT 対応

ソース生成した `JsonSerializerContext` を渡すことで、トリミング / AOT 耐性が向上します。

### リアクティブ統合（オプション）

`Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）を提供します。
`ObserveChanges()`、`ObserveValues()`、`ObserveReloadFailures()`、`ObserveActiveValues()`、`ObserveActiveProfileNames()` が利用できます。

### DI 統合 / Microsoft.Extensions.Options

`Configlue.Extensions.DI` で DI に統合できます。
`Configlue.Extensions.MSOptions` が Microsoft のオプションアダプター（`IOptions<T>` など）を提供します。
同期のゲッターは非同期ソースの読み取り中にブロックするため、非同期フローでは `GetValueAsync` を推奨します。

### プロファイル / 動的オプション

名前付きオプションと永続プロファイルにより、ランタイムをまとめて作成・削除できます。

---

## 値の出所を調べる / 疎な保存

```csharp
var options = context.GetOptions<AppSettings>();

// 1. 現在の値を取得します（全ソースのマージ結果）
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 2. 各値がどこから来たかを調べます
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

Patch を保存すると、指定したメンバーだけが更新されます。
`Unset()` はその Source の寄与を取り除き、より優先度の低い Source に値を提供させます。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

### その他の API

| API | 用途 |
| --- | --- |
| `IReadOnlyOptions<T>` | 日常的な読み取り面。`GetValueAsync` と `OnChange` |
| `SaveAsync(patch => ...)` | 生成された Patch による疎な保存 |
| `OpenEditSessionAsync()` | 複数の変更をまとめて編集し、`CommitAsync` で確定 |
| `ApplyPatchesAsync` + `StateSourcePatch` | ソース単位の明示的な複数書き込み |
| `StateWritePlan.For<T>().Route(...)` | 書き込みのルーティング |
| `SourceKey<TModel>` / `options.Source(key)` | ソース単位の操作 |

---

## パッケージ構成

| パッケージ | 役割 |
| --- | --- |
| `Configlue` | ユーザー向けメタパッケージ（Core / DI / JSON プロバイダー / JSON Schema / HTTP リソース / 共通ソース / 環境変数ソース / ジェネレーターアナライザーを同梱。自身の実装アセンブリは持ちません） |
| `Configlue.Abstraction` | コントラクト（プロバイダー / コーデック / リソース / 生成モデル） |
| `Configlue.Core` | 解決と永続化のランタイム |
| `Configlue.Extensibility` | プロバイダー SDK |
| `Configlue.Extensions.DI` | DI 統合 |
| `Configlue.Extensions.MSOptions` | `IOptions<T>` などのアダプター |
| `Configlue.Extensions.R3` / `.Reactive` | リアクティブ統合 |
| `Configlue.Generator` | Roslyn アナライザー（疎なモデルのサポートを生成） |
| `Configlue.Testing` | インメモリのテストダブル |
| `Configlue.Provider.Json` / `.Xml` / `.Yaml` | 各形式のコーデック、セクションリソース、ファイル登録 |
| `Configlue.JsonSchema` | JSON Schema の生成と出力 |
| `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml` | 各種ソースとプリセット |
| `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip` | 各種リソース実装 |
| `Configlue.Transformer.AES` | Resource と Codec の間のバイト列に対する AES-GCM 暗号化と認証 |

---

## Microsoft.Extensions.Configuration との違い

`IConfiguration` は読み取り志向です。フラットなキー/値として設定を公開しますが、値がどのソース由来かを検査したり、
特定のソースだけに差分を書き戻したりする仕組みは持ちません。

Configlue は、独立したソースの合成・由来の検査・疎な保存に適しています。
「設定を書く」「設定の出所を説明する」「複数レイヤーを安全に重ねる」必要がある場面に選択してください。

---

## 既知の制限

- 異なる Resource をまたぐ書き込みは原子的ではありません。
- Source の退役（retire）は現在の options インスタンスに scoped であり、背後のデータはそのまま残ります。
- Source の集合は 1 つの options ランタイム内では固定です。

---

Copyright (c) Configlue contributors. Licensed under the Apache License, Version 2.0.
