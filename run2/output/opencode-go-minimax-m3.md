# Configlue

**設定管理を、簡単にする。**

Configlue は、.NET アプリケーション向けの設定管理ライブラリです。ファイル、環境変数、コマンドライン引数、リモート API など複数箇所に散らばった設定を、1 つのモデルに**結合（glue）**します。ライブラリ名は configuration + glue に由来します。

> **注意**: 現状は「アーキテクチャ上の土台」段階であり、`Microsoft.Extensions.Configuration.Writable` をそのまま置き換える完成品ではありません。

- **対象**: .NET 10 SDK 以降
- **言語**: C#（ソースジェネレーター対応版が必要、リポジトリは preview でビルド）
- **ライセンス**: Apache-2.0

---

## Configlue が解決する課題

JSON ファイルの読み書きは数行で済みます。しかし実運用では、次のような要件が積み重なります。

- **散在する設定**: グローバル設定、実行フォルダー設定、環境変数、コマンドライン、暗号化された資格情報、社内ポリシー、HTTP API などのリモート管理。
- **変更通知**: 設定ファイルが書き換わったら再起動なしで反映したい。
- **書き込み先の自動選択**: 環境変数から読んだ値への書き込みはエラーにしたい。
- **人が書く設定ファイル**: コメントを消さない、JSON Schema がほしい、壊れたファイルへの対処。
- **スパース保存**: 既定値のままなら書き出さない（明示的な `null` は尊重）。
- **スキーマ移行**: 旧形式から新形式への自動変換。
- **バックアップと世代管理**: 自動で整理したい。
- **安全な書き込み**: アトミック性（クラッシュしても壊れない）、他プロセスとの競合検出・自動マージ、自動リトライ。

これらを毎回自前で実装するのは面倒、というのが Configlue の動機です。

---

## 基本アーキテクチャ

依存関係は直線的で、学習もこの順です。

```
Resource (location) → Codec (conversion) → Source (contribution) → Fragment (diff) → Options (facade)
                                                          ↘ Patch (edit fragment)
```

| 概念 | 一言で | 例 |
| --- | --- | --- |
| **Resource** | バイトがどこにあるか | ファイル、ZIP エントリ、HTTP 応答、メモリ |
| **Codec** | バイト ↔ 値の変換 | JSON / XML / YAML の読み書き |
| **Source** | 論理的な寄与（どのフィールドをどの優先度で） | 「ユーザー設定ファイルの Server 部分」 |
| **Fragment** | 「存在」を記憶する差分 | 「Port だけ」を持つ状態 |
| **Patch** | 単一フィールドの編集 | 「Port を 9000 にする」 |
| **Options** | アプリが見るファサード | 読み・保存・監視・説明・診断 |

**読み込み**: 各 Source が Resource からバイトを取得し、Codec が Fragment に変換します。ランタイムが優先度順に「存在する」フィールドだけを 1 つのモデルへ重ねます。

**書き込み**: 逆向きです。アプリはモデル値を編集するだけ。内部では変更が Fragment 差分になり、`WriteRoute` / `WritePlan` が指す Source にだけ届きます。無関係な Source は変更されません。

- **Fragment** は「メンバーが存在しない」と「null/既定値で存在する」を区別します。層の合成で「未設定」が「既定値に設定」を上書きすることはありません。
- **Patch** はソースジェネレーターが生成する `TModel.Patch`（単一フィールドの編集フラグメント）。`Unset()` を呼ぶと、書き込み先 Source の寄与だけが取り消され、下位優先度の値が再び見えるようになります。
- **`[ConfiglueMerge]`** でメンバーごとのマージ挙動を変更可能（組み込み: `Append`, `Deep`, `Replace`, `SetUnion`、カスタム戦略も定義可）。

---

## 主な機能

- **複数ソースの優先度マージ**: `Priority` が大きい Source が勝つ。`GetDetailsAsync` で各値の**由来（プロvenance）**を検査できます。
- **読み取り専用ソース**: 環境変数・コマンドライン・既定の HTTP ソースは読み取り専用。読み取り専用 Source の値への書き込みは黙って無視されず、**競合エラー**として報告されます。
- **プロジェクション / マウント**: 既存 Source を別モデルへ整形（projection）したり、ネストしたパスに別 Source を接続（mount, `AddMounted`）できます。
- **プリセット**: `UseCommonSources` が global / local / environment などの標準的な層構成を組み立てます。
- **スパース書き込み**: 変更したフィールドだけを対象層に保存。既定値のままのフィールドは書き出されません。
- **編集セッション**: `OpenEditSessionAsync` で複数変更をまとめて適用し、`CommitAsync` で確定するまでインメモリで保持。競合時は既定で失敗、`WriteConflictResolution.LastWriteWins` も選べます。
- **スキーマ移行 / ストレージ移行**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` で旧バージョン設定を自動変換。既存ファイルを Source として登録できます。
- **バックアップと復元**: `FileResource` はアトミック書き込みとバックアップ世代管理（既定で `.bak` 1 世代）。`RestoreLatestBackupAsync` で復元。
- **安全な書き込み**: アトミック性、競合検出、自動リトライ。
- **セクション**: `JsonSectionResource` / XML 要素 / YAML マッピングで、ファイルの一部を独立した Resource として扱えます。書き込み時はコメント・空白・引用符・スカラー形式を保持。同じファイル内の独立セクションは 1 回の物理書き込みにバッチされます。
- **多彩なストレージ**: `ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込み・ポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **JSON Schema 生成**: `Configlue.JsonSchema`。人が設定を書くためのスキーマを出力。
- **Native AOT 対応**: ソース生成の `JsonSerializerContext` を渡すことでトリミング/AOT に強くなります。
- **リアクティブ統合**（任意）: `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）。`ObserveChanges()`, `ObserveValues()`, `ObserveReloadFailures()`, `ObserveActiveValues()`, `ObserveActiveProfileNames()` を提供。
- **DI 統合**: `Configlue.Extensions.DI` と、Microsoft の options アダプター `Configlue.Extensions.MSOptions`（`IOptions<T>` など）。同期ゲッターは非同期ソース読み取り中にブロックするため、非同期フローでは `GetValueAsync` の利用を推奨します。
- **プロファイル / 動的オプション**: 名前付きオプションや永続プロファイルをランタイム単位で作成・削除できます。

### 既知の制限

- 異なる Resource 間での書き込みはアトミックではありません。
- Source の退役は現在の options インスタンスに閉じた操作で、実データは残ります。
- Source 集合は options ランタイムで固定されます。

---

## インストール

```bash
dotnet add package Configlue
```

必要に応じて機能別パッケージを追加します。

### 主なパッケージ

| パッケージ | 役割 |
| --- | --- |
| `Configlue` | ユーザー向けメタパッケージ（Core / DI / JSON provider / JSON Schema / HTTP resources / common sources / environment source / generator analyzer を同梱。実装アセンブリは持たない）。 |
| `Configlue.Abstraction` | 契約（provider / codec / resource / generated-model）。 |
| `Configlue.Core` | 解決と永続化のランタイム。 |
| `Configlue.Extensibility` | プロバイダー SDK。 |
| `Configlue.Extensions.DI` / `.MSOptions` / `.R3` / `.Reactive` | DI、Microsoft.Extensions.Options 連携、リアクティブ統合。 |
| `Configlue.Generator` | Roslyn アナライザー。スパースなモデルサポートを生成。 |
| `Configlue.Testing` | インメモリテストダブル。 |
| `Configlue.Provider.Json` / `.Xml` / `.Yaml` | 各形式の Codec・セクションリソース・ファイル登録。 |
| `Configlue.JsonSchema` | JSON Schema 生成・エクスポート。 |
| `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml` | 各種 Source 実装。 |
| `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip` | 各種 Resource 実装。 |
| `Configlue.Transformer.AES` | Resource と Codec の間のバイトを AES-GCM で暗号化・認証。 |

---

## Quick Start

`example.cs` に保存し、.NET 10 以降で `dotnet run example.cs` で実行:

```csharp
#!/usr/bin/env dotnet
#:package Configlue@*

using Configlue;
using Configlue.Source.Presets;

// 1. 設定モデルを宣言。ジェネレーターが Fragment / Patch サポートを生成する。
[ConfiglueModel("SampleSetting", Version = 1)]
public partial class SampleSetting
{
    public string Name { get; set; } = "World";
    public int RunCount { get; set; }
    public bool DefaultValue { get; set; } = true;
}

// 2. プリセット層を宣言。ここで列挙した Source だけが有効になる。
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);

// 3. Options インスタンス越しに読み書きする。
var options = context.GetOptions<SampleSetting>();
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// スパース編集: 変更したフィールドだけが対象層に保存される。
await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue は変更していないので対象層には書き出されない。
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

---

## 値の由来を調べる / スパース保存

各フィールドがどの Source から来たかを確認できます。

```csharp
var options = context.GetOptions<AppSettings>();

// 1. 現在の値（全 Source をマージした結果）を取得
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 2. 各値の由来を調べる
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

---

## その他の API

- `IReadOnlyOptions<T>` — 日常の読み取り面は `GetValueAsync` と `OnChange`。
- `SaveAsync(patch => ...)` — 生成 Patch でスパース保存。
- `OpenEditSessionAsync()` — 複数変更をまとめて適用し、`CommitAsync` で確定。
- `ApplyPatchesAsync` + `StateSourcePatch` — 明示的なソース別マルチ書き込み。
- `StateWritePlan.For<T>().Route(...)` — 書き込みルーティング。
- `SourceKey<TModel>` と `options.Source(key)` — ソース単位の操作。

---

## `Microsoft.Extensions.Configuration` との関係

`IConfiguration` を主役とする `Microsoft.Extensions.Configuration` は主に**読み取り中心**の合成に向いています。Configlue は独立した Source を**対等な寄与**として扱い、

- 値の由来（プロvenance）の検査
- 読み取り専用 Source への書き込みを競合として検出
- スパース保存（変更箇所のみを対象層へ）
- アトミック書き込みとバックアップ世代管理

といった、書き込みを伴う「設定管理」に向きます。両者は対立するものではなく、用途や好みに応じて選び分けられます。設定の読み取りだけを軽く行いたい場面では `IConfiguration` の素朴さが有利です。一方、複数 Source を跨いで「どこ由来か」「ここは書き換えてはいけない」を扱いたいなら Configlue の方が素直に表現できます。

---

## ステータス

Configlue はまだアーキテクチャ上の土台段階です。`Microsoft.Extensions.Configuration.Writable` を完全に置き換える完成品ではなく、API は今後変更される可能性があります。フィードバックとコントリビューションを歓迎します。

