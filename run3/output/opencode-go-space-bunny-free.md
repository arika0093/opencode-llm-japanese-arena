# Configlue

**Make easy configuration management.**

.NET のアプリケーションの設定管理をまるごと引き受けるライブラリです。
`Configlue` という名前は **configuration** と **glue**（接着する糊）から来ています。
複数の場所に散らばった設定を、1つのモデルに接着してまとめることが中心の考え方です。

- 必要環境: .NET 10 SDK 以降（C#。ソースジェネレーターを使うため `LangVersion` の指定が必要です）
- ライセンス: Apache-2.0

> 現時点では「アーキテクチャの土台」としての位置づけです。`Configuration.Writable` の完全な置き換えを意図したものではなく、既存の設定管理をまるごと代替するものではありません。

---

## なぜ Configlue なのか

JSON ファイルを読み書きするだけなら数行で済みます。しかし実用段階では、要求は単純に積み上がります。

- **設定の置き場所が複数ある。** グローバル設定、実行ディレクトリごとの設定、環境変数、コマンドライン引数、暗号化された資格情報、企業ポリシーや HTTP API といったリモート管理。
- **設定ファイルが書き換わったことを、再起動なしで反映したい。** （変更通知）
- **書き込み先を自動的に決めたい。** 環境変数から読んだ値への書き込みは、エラーにしたい。
- **設定ファイルは人間が書く。** コメントを消したくない。JSON Schema による補完が欲しい。壊れたファイルの扱いを決めたい。
- **デフォルト値のままの項目は書き出したくない。** （ただし利用者が明示した `null` は尊重したい）
- **設定ファイルにバージョンを設けたい。** 古い形式から新しい形式へ自動変換したい。
- **バックアップとその後始末。**
- **書き込みの安全性。** アトミックな書き込み（クラッシュで壊れない）、他プロセスとの競合検出と自動マージ、自動リトライ。

これらを自前で実装するのは面倒です。

---

## コアの考え方（6つの概念）

依存関係は一続きになっています。学ぶ順番も同じです。

```text
Resource（置き場所）→ Codec（変換）→ Source（寄与）→ Fragment（差分）→ Options（窓口）
                                                              ↘ Patch（編集用の差分）
```

| 概念 | 一言で言うと | 例 |
| --- | --- | --- |
| Resource | バイト列がどこにあるか | ファイル、ZIP エントリ、HTTP レスポンス、メモリ |
| Codec | バイト列と値の相互変換 | JSON / XML / YAML の読み書き |
| Source | 論理的な寄与（どのフィールドを、どの優先度で） | 「ユーザー設定ファイルの `Server` の部分」 |
| Fragment | 「存在」を覚えておく差分 | 「`Port` だけを持つ状態」 |
| Patch | 単一フィールドの編集 | 「`Port` を 9000 にする」 |
| Options | アプリケーションが見る窓口 | 読む・保存・監視・説明・診断 |

**読み取り**: 各 Source が Resource からバイト列を取り出し、Codec がそれを Fragment に変換します。
ランタイムは「存在している」フィールドだけを優先度順に重ね合わせて、1つのモデルにまとめます。

**書き込み**: 逆方向です。アプリケーションは普通のモデルの値を編集します。
内部ではその変更が Fragment の差分になり、`WriteRoute` / `WritePlan` で指定された Source にだけ届きます。
無関係な Source は変更されません。

- Fragment は「メンバー不在」と「`null`／既定値として存在する」を区別します。レイヤーの合成で「未設定」が「既定値として設定済み」を上書きすることはありません。
- Patch は生成される `TModel.Patch`（単一フィールドの編集用 Fragment）です。`Unset()` を呼ぶと、**書き込み先 Source の寄与だけ**を引っ込め、下位優先度の値が再び見えるようになります。
- `[ConfiglueMerge]` はメンバーごとのマージ動作を変えます（built-in: `Append` / `Deep` / `Replace` / `SetUnion`。独自戦略も可）。コレクションのレイヤー合成と順序はここで決まります。

---

## 主な機能

- **複数 Source の優先度マージ** — `Priority` が大きい Source が勝ちます。`GetDetailsAsync` で「どの値はどこから来たか」を調べられます。
- **読み取り専用 Source** — 環境変数、コマンドライン、デフォルトの HTTP Source は読み取り専用です。読み取り専用の値への書き込みは黙って無視されず、競合エラーになります。
- **プロジェクション / マウント** — 既存の Source を別のモデルへ読み替える（projection）ほか、ネストしたパスに別の Source をぶら下げる（マウント、`AddMounted`）ことができます。
- **プリセット** — `UseCommonSources` で標準的なレイヤ構成（global / local / environment など）をまとめて組み立てられます。
- **疎な書き込み（sparse write）** — 変更したフィールドだけを対象レイヤに保存します。既定値のままのフィールドは書き込まれません。
- **編集セッション** — `OpenEditSessionAsync` で複数の変更をまとめて適用します。`CommitAsync` までメモリ上です。競合時は既定で失敗しますが、`WriteConflictResolution.LastWriteWins` も選べます。
- **スキーマ移行 / ストレージ移行** — `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` により、旧バージョンの設定を自動変換します。既存ファイルを Source として登録することもできます。
- **バックアップと復元** — `FileResource` がアトミックな書き込みとバックアップ世代の管理を提供します。`.bak` は既定で 1 世代。`RestoreLatestBackupAsync` で復元できます。
- **安全な書き込み** — アトミック性、競合検出、リトライ。
- **セクション** — `JsonSectionResource`、XML 要素、YAML マッピングを使って、ファイルの一部を独立した Resource として扱えます。書き込み時にコメント・空白・クォート・スカラルのスタイルは保持されます。同じファイル内の独立したセクションは、1回の物理書き込みにまとめられます。
- **ZIP / HTTP / S3 / Dapr** — `ZipEntryResource`、`Configlue.Resource.Http`（ETag による条件付き書き込みとポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **JSON Schema 生成** — 設定は人間が書くので、`Configlue.JsonSchema`。
- **Native AOT 対応** — ソース生成された `JsonSerializerContext` を渡すと、トリミング／AOT への耐性が上がります。
- **リアクティブ連携（任意）** — `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）。`ObserveChanges()`、`ObserveValues()`、`ObserveReloadFailures()`、`ObserveActiveValues()`、`ObserveActiveProfileNames()`。
- **DI 連携** — `Configlue.Extensions.DI`。Microsoft オプションのアダプターは `Configlue.Extensions.MSOptions`（`IOptions<T>` など。同期ゲッターは非同期 Source の読み取り中にブロックするため、非同期フローでは `GetValueAsync` の利用を推奨）。
- **プロファイル / 動的オプション** — 名前付きオプションと永続プロファイルにより、ランタイムをまとめて作成・破棄できます。
- **既知の制限** — 異なる Resource にまたがる書き込みはアトミックではありません。Source の廃止は現在の Options インスタンスの範囲に限られ、基盤データはそのまま残ります。Source 集合は Options ランタイムごとに固定です。

---

## インストール

```bash
dotnet add package Configlue
```

必要に応じて機能を追加するパッケージをインストールします。

### 主なパッケージ構成

| パッケージ | 役割 |
| --- | --- |
| `Configlue` | ユーザー向けのメタパッケージ（Core / DI / JSON provider / JSON Schema / HTTP resources / common sources / environment source / generator analyzer をまとめて取り込む。実装アセンブリ自体は持たない） |
| `Configlue.Abstraction` | 契約（provider / codec / resource / 生成モデル） |
| `Configlue.Core` | 値の解決（解決・合成）と永続化のランタイム |
| `Configlue.Extensibility` | provider SDK |
| `Configlue.Extensions.DI` / `.MSOptions` / `.R3` / `.Reactive` | 各連携 |
| `Configlue.Generator` | 疎なモデルサポートを生成する Roslyn アナライザー |
| `Configlue.Testing` | インメモリのテストダブル |
| `Configlue.Provider.Json` / `.Xml` / `.Yaml` | 各形式の codec・セクション Resource・ファイル登録 |
| `Configlue.JsonSchema` | JSON Schema の生成とエクスポート |
| `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml` | 設定ソース |
| `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip` | 設定の置き場所 |
| `Configlue.Transformer.AES` | Resource と Codec の間でバイト列に AES-GCM 暗号化と認証を適用 |

---

## クイックスタート

以下を `example.cs` として保存し、.NET 10 以降で `dotnet run example.cs` を実行してください。

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

## 値の由来を調べる / 疎な保存

```csharp
var options = context.GetOptions<AppSettings>();
// 1. Get the current value (merged from all sources)
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 2. Inspect where each value came from
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

指定したメンバーだけを更新する Patch を保存します。`Unset()` はその Source の寄与を取り除き、下位優先度の Source が値を提供できるようにします。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

### その他の API

- `IReadOnlyOptions<T>` — 日常的に読むための面。`GetValueAsync` と `OnChange`。
- `SaveAsync(patch => ...)` — 生成された Patch による疎な保存。
- `OpenEditSessionAsync()` — 複数をまとめて編集し、後で `CommitAsync`。
- `ApplyPatchesAsync` + `StateSourcePatch` — Source 単位の複数書き込みを明示的に行う。
- `StateWritePlan.For<T>().Route(...)` — 書き込み先ルーティング。
- `SourceKey<TModel>` と `options.Source(key)` — Source 単位の操作。

---

## Microsoft.Extensions.Configuration との違い

`IConfiguration` は読み取り中心の設計です。それに対し Configlue は次のような用途に向いています。

- 独立した Source の合成（グローバル／ローカル／環境変数／コマンドライン／リモートなど）
- 出所（provenance）の調査
- 疎な保存（変更した項目だけを書き戻す）

---

## 対象読者

設定管理で苦労している .NET 開発者を想定しています。特に、設定が複数の場所に分散し、書き込みの制御や出所の追跡が課題になっている方に向けています。

