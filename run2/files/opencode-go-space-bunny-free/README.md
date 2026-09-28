# Configlue

**Make easy configuration management.**

Configlue は .NET アプリケーションの設定管理（configuration management）を代行するライブラリです。グローバル設定、実行フォルダーの設定、環境変数、コマンドライン引数、社内ポリシーや HTTP API などのリモート管理といった、ばらばかれた設定を 1 つのモデルに**結合（glue）**します。名前も configuration + glue から来ています。

- 対象: .NET 10 SDK 以降 / C#（ソースジェネレーター対応の `LangVersion` が必要）
- ライセンス: Apache-2.0
- 現状: アーキテクチャ上の土台。`Microsoft.Extensions.Configuration` の `Configuration.Writable` を完全に置き換えるものではありません

---

## なぜ Configlue なのか

JSON ファイルを読み書きするだけなら数行で書けます。しかし実用的な設定管理では、その周辺に次のような要件が積み重なります。

- **設定が複数箇所にある。** グローバル設定、実行フォルダーの設定、環境変数、コマンドライン引数、暗号化された資格情報、社内ポリシーや HTTP API などのリモート管理。
- **ファイルが書き換わったら再起動なしで反映したい。** 変更通知で実行中のモデルを更新する。
- **書き込み先を自動で選びたい。** 環境変数から読んだ値への書き込みは、無視ではなくエラーにしたい。
- **設定ファイルは人間が書く。** コメントを消さない、JSON Schema を配る、壊れたファイルへ対処する。
- **既定値のままなら書き出さない。** ただしユーザーが明示した `null` は尊重する。
- **設定ファイルのバージョンアップ。** 旧形式から新形式へ自動変換する。
- **バックアップと自動整理。**
- **書き込みの安全性。** アトミック性、他プロセスとの競合検出と自動マージ、自動リトライ。

これらを毎回自前実装するのは面倒です。Configlue はその層をライブラリとして提供します。

---

## Quick Start

`example.cs` に保存し、`dotnet run example.cs` で実行できます（.NET 10 以降）。

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

---

## 基本アーキテクチャ

依存関係は直線的で、この順で読めば全体が掴めます。

```text
Resource (location) → Codec (conversion) → Source (contribution) → Fragment (diff) → Options (facade)
                                                        ↘ Patch (edit fragment)
```

| 概念 | 一言で | 例 |
| --- | --- | --- |
| **Resource** | バイトがどこにあるか | ファイル、ZIP エントリ、HTTP 応答、メモリ |
| **Codec** | バイトと値の相互変換 | JSON / XML / YAML の読み書き |
| **Source** | 論理的な寄与（どのフィールドをどの優先度で） | 「ユーザー設定ファイルの Server 部分」 |
| **Fragment** | 存在を記憶する差分 | 「Port だけ」を持つ状態 |
| **Patch** | 単一フィールドの編集 | 「Port を 9000 にする」 |
| **Options** | アプリが見るファサード | 読み・保存・監視・説明・診断 |

**読み込み** — 各 Source が Resource からバイトを取得し、Codec が Fragment に変換します。ランタイムは優先度順に、**存在する**フィールドだけを 1 つのモデルへ重ねます。

**書き込み** — 逆方向です。アプリは普通のモデル値を編集し、内部ではその変更が Fragment の差分になります。`WriteRoute` / `WritePlan` が指す Source にだけ届き、無関係な Source は変更されません。

この非対称性がポイントです。たとえば「環境変数から読んだ `Port` を、ユーザーが UI で 9000 に変えた」場合、書き込み先は管理可能なファイル Source に決まります。読み取り専用の値への書き込みは黙って無視されず、競合エラーになります。

### 存在と差分

Fragment は「メンバーが存在しない」と「`null` や既定値で存在する」を区別します。層を合成しても「未設定」が「既定値に設定」を上書きすることはありません。逆に、ユーザーが明示した `null` は尊重されます。

`Patch` はソースジェネレーターが生成する `TModel.Patch` で、単一フィールドの編集を表します。`Unset()` を呼ぶと、書き込み先 Source の寄与だけを取り除き、下位優先度の Source の値を再び見せます。

### マージ戦略

`[ConfiglueMerge]` でメンバーごとにマージ挙動を変更できます。組み込みは `Append`、`Deep`、`Replace`、`SetUnion` で、カスタム戦略も指定可能です。コレクションが層をどう合成され、どの順序になるかはここで決まります。

---

## 主な機能

**複数ソースの優先度マージ**
`Priority` が大きい Source が勝ちます。どの値も `GetDetailsAsync` で「どこから来たか」を検査できます。

**読み取り専用ソース**
環境変数、コマンドライン、既定の HTTP ソースは読み取り専用です。

**プロジェクション / マウント**
既存の Source を別モデルへ整形（projection）したり、ネストしたパスに別 Source を接続（mount、`AddMounted`）したりできます。

**プリセット**
`UseCommonSources` が global / local / environment といった標準的な層構成を組み立てます。列挙した Source だけが有効になります。

**スパース書き込み**
変更したフィールドだけを対象層へ保存します。既定値のままのフィールドはファイルに現れません。

**編集セッション**
`OpenEditSessionAsync` で複数の変更をまとめ、`CommitAsync` までインメモリで保持します。競合時は既定で失敗し、`WriteConflictResolution.LastWriteWins` を選ぶこともできます。

**スキーマ移行 / ストレージ移行**
`[ConfigluePreviousVersion]` と `Fragment.FromPrevious` により、旧バージョンの設定を自動変換します。既存ファイルをそのまま Source として登録することもできます。

**バックアップと復元**
`FileResource` はアトミック書き込みとバックアップ世代管理を行います。既定で `.bak` 1 世代を保持し、`RestoreLatestBackupAsync` で復元できます。

**安全な書き込み**
アトミック性、競合検出、リトライを扱います。他プロセスと競合した場合は検出・自動マージします。

**セクション**
`JsonSectionResource`、XML 要素、YAML マッピングで、ファイルの一部を独立した Resource として扱えます。書き込み時にコメント・空白・引用・スカラー形式を保持し、同じファイル内の独立セクションは 1 回の物理書き込みにバッチされます。

**ZIP / HTTP / S3 / Dapr**
`ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込み・ポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。

**JSON Schema 生成**
`Configlue.JsonSchema` がスキーマの生成とエクスポートを提供します。設定ファイルを人が手で書くことを前提にしています。

**Native AOT 対応**
ソース生成の `JsonSerializerContext` を渡すと、トリミング／AOT に対して強くなります。

**リアクティブ統合（任意）**
`Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）で `ObserveChanges()`、`ObserveValues()`、`ObserveReloadFailures()`、`ObserveActiveValues()`、`ObserveActiveProfileNames()` が使えます。

**DI 統合**
`Configlue.Extensions.DI`、および Microsoft の options アダプター `Configlue.Extensions.MSOptions`（`IOptions<T>` など）を用意しています。なお同期ゲッターは非同期ソースの読み取り中にブロックするため、非同期フローでは `GetValueAsync` の利用を推奨します。

**プロファイル / 動的オプション**
名前付きオプションや永続プロファイルで、ランタイム単位で options を作成・削除できます。

---

## 値の由来を調べる

マージされた値がどこから来たのかも取得できます。

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

診断画面や「設定が効かない」という問い合わせへの回答に、そのまま使えます。

---

## スパース保存

更新したいメンバーだけをパッチで指定します。`Unset()` はその Source の寄与を外し、下位優先度の Source が値を提供できるようにします。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

その他の主な API:

| API | 用途 |
| --- | --- |
| `IReadOnlyOptions<T>` | 日常の読み取り面。`GetValueAsync` と `OnChange` |
| `SaveAsync(patch => ...)` | 生成 Patch によるスパース保存 |
| `OpenEditSessionAsync()` / `CommitAsync()` | 複数変更をまとめて適用 |
| `ApplyPatchesAsync` + `StateSourcePatch` | 明示的なソース別のマルチ書き込み |
| `StateWritePlan.For<T>().Route(...)` | 書き込みルーティング |
| `SourceKey<TModel>` / `options.Source(key)` | ソース単位の操作 |

---

## 既存の設定管理との違い

`Microsoft.Extensions.Configuration` の `IConfiguration` は読み取りを中心に設計されています。provider を並べて合成し、値を引くことに特化した API です。

Configlue が軸に置くのは次の点です。

- 独立した複数ソースの合成と、値ごとの来歴（`GetDetailsAsync`）の検査
- スパース保存と、書き込み先の安全な解決
- 人間向けの設定ファイル（コメント保持、JSON Schema）
- バックアップ、アトミック書き込み、競合処理

読み取り中心の構成だけなら `IConfiguration` のほうが軽量です。設定の**書き戻し**と**出典の可視化**が要件に入るなら Configlue の領域です。

---

## パッケージ

まずメタパッケージを入れ、必要な機能を足していきます。

```bash
dotnet add package Configlue
```

| パッケージ | 内容 |
| --- | --- |
| `Configlue` | ユーザー向けメタパッケージ（Core / DI / JSON provider / JSON Schema / HTTP resources / common sources / environment source / generator analyzer を同梱。実装アセンブリは持たない） |
| `Configlue.Abstraction` | 契約（provider / codec / resource / generated-model） |
| `Configlue.Core` | 解決と永続化のランタイム |
| `Configlue.Extensibility` | プロバイダー SDK |
| `Configlue.Generator` | Roslyn アナライザー（スパースなモデルサポート生成） |
| `Configlue.Extensions.DI` | DI 統合 |
| `Configlue.Extensions.MSOptions` | `IOptions<T>` などの Microsoft options アダプター |
| `Configlue.Extensions.R3` / `.Reactive` | リアクティブ統合 |
| `Configlue.Testing` | インメモリのテストダブル |
| `Configlue.Provider.Json` / `.Xml` / `.Yaml` | 各形式の Codec・セクションリソース・ファイル登録 |
| `Configlue.JsonSchema` | JSON Schema の生成・エクスポート |
| `Configlue.Source.Environment` / `.CommandLine` | 環境変数、コマンドライン引数のソース |
| `Configlue.Source.Presets` / `.Presets.Yaml` / `.Presets.Xml` | 標準的な層構成のプリセット |
| `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip` | 各種リソース |
| `Configlue.Transformer.AES` | Resource と Codec の間のバイトを AES-GCM で暗号化・認証 |

---

## 既知の制限

- 異なる Resource 間の書き込みはアトミックではありません。
- Source の退役は現在の options インスタンスに閉じており、実データは残ります。
- Source 集合は options ランタイムで固定です。

現時点ではアーキテクチャ上の土台であり、既存の設定管理をそのまま置き換えるものではありません。

---

## License

Apache-2.0
