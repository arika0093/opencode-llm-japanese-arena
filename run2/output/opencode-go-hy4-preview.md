# Configlue

**Make easy configuration management.**

Configlue は、アプリケーションの設定管理を代行する .NET ライブラリです。

複数の場所に散らばった設定（グローバル設定ファイル、実行フォルダーの設定、環境変数、コマンドライン引数、暗号化された資格情報、リモートの管理 API など）を、優先度付きの「層」として合成し、アプリケーションには 1 つのモデルとして見せます。読み取りだけでなく、**どこへ書き戻すか**まで面倒を見るのが特徴です。

- 対象: .NET 10 SDK 以降 / C#
- ライセンス: Apache-2.0

なお現時点の Configlue は「アーキテクチャ上の土台」であり、`Configuration.Writable` を完全に置き換えるものではありません。

---

## Why Configlue?

JSON ファイルを 1 つ読み書きするだけなら、数行のコードで済みます。しかし実際のアプリケーションでは、次のような要件が次々に積み重なります。

| 課題 | Configlue での扱い |
| --- | --- |
| 設定が複数箇所に散らばっている | Source ごとに優先度を付けて 1 つのモデルへ合成 |
| ファイルの変更を再起動なしで反映したい | 変更通知（`OnChange` / リアクティブ拡張） |
| 書き込み先を自動で選びたい | `WriteRoute` / `WritePlan` による書き込みルーティング |
| 読み取り専用の値（環境変数など）への書き込み | 黙って無視せず競合エラーにする |
| 設定ファイルは人間が書く | コメント・書式の保持、JSON Schema 生成、壊れたファイルの扱い |
| 既定値のままの項目は書き出したくない | スパース書き込み（ただしユーザーが明示した `null` は尊重） |
| 設定ファイルのバージョンアップ | `[ConfigluePreviousVersion]` による旧形式からの自動変換 |
| 書き込みで設定を壊したくない | アトミック書き込み、競合検出、自動リトライ、バックアップ |

これらを個別に自前実装するのは手間がかかります。Configlue はこの一連の処理を、後述する 6 つの概念に分解して提供します。

---

## インストール

```bash
dotnet add package Configlue
```

`Configlue` はユーザー向けのメタパッケージです（Core / DI / JSON provider / JSON Schema / HTTP resources / common sources / environment source / generator analyzer を同梱。実装アセンブリは持ちません）。ZIP・XML・YAML・S3・Dapr・リアクティブ統合などを使う場合は、後述のパッケージ一覧から必要なものを追加します。

---

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

1. `[ConfiglueModel]` を付けた `partial` クラスを宣言すると、ソースジェネレーターがスパースな読み書きに必要な `Fragment` / `Patch` のサポートを生成します。
2. `UseCommonSources` で「どの層を有効にするか」を明示します。ここに書いた Source だけが使われます。
3. アプリケーションは `GetOptions<T>()` が返すファサードに対して、モデルの読み取りと保存だけを行います。

---

## 基本アーキテクチャ（6 つの概念）

概念の依存関係は直線的で、学習順も同じです。

```text
Resource (location) → Codec (conversion) → Source (contribution) → Fragment (diff) → Options (facade)
                                                        ↘ Patch (edit fragment)
```

| 概念 | 一言で | 例 |
| --- | --- | --- |
| Resource | バイトがどこにあるか | ファイル、ZIP エントリ、HTTP 応答、メモリ |
| Codec | バイト ↔ 値の変換 | JSON / XML / YAML の読み書き |
| Source | 論理的な寄与（どのフィールドをどの優先度で） | 「ユーザー設定ファイルの Server 部分」 |
| Fragment | 存在を記憶する差分 | 「`Port` だけ」を持つ状態 |
| Patch | 単一フィールドの編集 | 「`Port` を 9000 にする」 |
| Options | アプリが見るファサード | 読み・保存・監視・説明・診断 |

### 読み込み

各 Source が Resource からバイトを取得し、Codec がそれを Fragment に変換します。ランタイムは優先度順に、**「存在する」フィールドだけ**を 1 つのモデルへ重ねていきます。

Fragment は「メンバーが存在しない」ことと、「`null` / 既定値で存在する」ことを区別します。そのため層の合成時に、「未設定」が下位優先度の「既定値に設定」を誤って上書きすることがありません。

### 書き込み

書き込みは逆向きです。アプリケーションは通常のモデル値を編集しますが、内部では変更が Fragment の差分になり、`WriteRoute` / `WritePlan` が指す Source にだけ届きます。無関係な Source は変更されません。

`Patch` はソースジェネレーターが生成する `TModel.Patch` 型です。`Unset()` を呼ぶと書き込み先 Source の寄与だけを取り消し、下位優先度の Source が再び値を提供できるようになります。

メンバーごとのマージ挙動は `[ConfiglueMerge]` で変更できます。組み込みの戦略は `Append` / `Deep` / `Replace` / `SetUnion` で、カスタム戦略も定義可能です。コレクションを層をまたいでどう合成し、どう並べるかはここで決まります。

---

## 主な機能

- **複数ソースの優先度マージ**: `Priority` が大きい Source が勝ちます。`GetDetailsAsync` で「どの値がどこ由来か」を検査できます。
- **読み取り専用ソース**: 環境変数・コマンドライン・既定の HTTP ソースは読み取り専用です。読み取り専用の値への書き込みは黙って無視されず、競合エラーになります。
- **プロジェクション / マウント**: 既存 Source を別モデルに整形（projection）したり、ネストしたパスに別 Source を接続（mount, `AddMounted`）できます。
- **プリセット**: `UseCommonSources` が標準的な層構成（global / local / environment など）を組み立てます。
- **スパース書き込み**: 変更されたフィールドだけが対象の層に保存されます。既定値のままのフィールドは書き出されません。
- **編集セッション**: `OpenEditSessionAsync()` で複数の変更をまとめて適用できます。`CommitAsync` まではインメモリです。競合時は既定で失敗し、`WriteConflictResolution.LastWriteWins` も選択できます。
- **スキーマ移行 / ストレージ移行**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` により、旧バージョンの設定を自動変換します。既存ファイルを Source としてそのまま登録できます。
- **バックアップと復元**: `FileResource` はアトミック書き込みとバックアップの世代管理を行います。既定は `.bak` 1 世代で、`RestoreLatestBackupAsync` で復元できます。
- **安全な書き込み**: アトミック性、競合検出、自動リトライ。
- **セクション**: `JsonSectionResource` / XML 要素 / YAML マッピングにより、ファイルの一部を独立した Resource として扱えます。書き込み時にコメント・空白・引用・スカラー形式は保持され、同一ファイル内の独立セクションは 1 回の物理書き込みにまとめられます。
- **ZIP / HTTP / S3 / Dapr**: `ZipEntryResource`、`Configlue.Resource.Http`（ETag による条件付き書き込みとポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **JSON Schema 生成**: `Configlue.JsonSchema`。人間が設定ファイルを書くためのスキーマを出力します。
- **Native AOT 対応**: ソース生成した `JsonSerializerContext` を渡すと、トリミング / AOT に強くなります。
- **リアクティブ統合（任意）**: `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）。`ObserveChanges()`, `ObserveValues()`, `ObserveReloadFailures()`, `ObserveActiveValues()`, `ObserveActiveProfileNames()` を提供します。
- **DI 統合**: `Configlue.Extensions.DI`。Microsoft の options アダプターとして `Configlue.Extensions.MSOptions`（`IOptions<T>` など）もあります。同期ゲッターは非同期ソースの読み取り中にブロックするため、非同期フローでは `GetValueAsync` を推奨します。
- **プロファイル / 動的オプション**: 名前付きオプションや永続プロファイルにより、ランタイムを単位として作成・削除できます。

### 既知の制限

- 異なる Resource をまたぐ書き込みはアトミックではありません。
- Source の退役は現在の options インスタンスに閉じ、実データは残ります。
- Source の集合は options ランタイム単位で固定されます。

---

## 値の由来を調べる / スパースに保存する

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

指定したメンバーだけを更新するパッチを保存できます。`Unset()` はその Source の寄与を外し、下位優先度の Source が値を提供できるようにします。

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
| `IReadOnlyOptions<T>` | 日常の読み取り面（`GetValueAsync` と `OnChange`） |
| `SaveAsync(patch => ...)` | 生成された Patch によるスパース保存 |
| `OpenEditSessionAsync()` | 複数変更をまとめて編集し `CommitAsync` |
| `ApplyPatchesAsync` + `StateSourcePatch` | 明示的なソース別マルチ書き込み |
| `StateWritePlan.For<T>().Route(...)` | 書き込みルーティングの指定 |
| `SourceKey<TModel>` と `options.Source(key)` | ソース単位の操作 |

---

## Microsoft.Extensions.Configuration との違い

`Microsoft.Extensions.Configuration` の `IConfiguration` は読み取り中心のフラットなキー／値ストアで、「設定を読む」用途には十分です。一方 Configlue は、次に挙げるような要件に焦点を当てています。

- **独立したソースの合成**: 由来の異なる設定を、優先度付きの層として型付きモデルに合成する。
- **来歴の検査**: `GetDetailsAsync` により、どの値がどの Source 由来で、書き込み可能かどうかを実行時に確認できる。
- **スパース保存**: 変更したフィールドだけを、しかるべき層へ書き戻す。
- **人間が書く設定ファイルの尊重**: コメントや書式の保持、スキーマ生成、バージョン移行。

単純に設定を読むだけであれば既存の仕組みで十分です。書き戻し・優先度合成・来歴の可視化が必要になったときに、Configlue が選択肢になります。

---

## パッケージ構成（主要なもの）

| パッケージ | 内容 |
| --- | --- |
| `Configlue` | ユーザー向けメタパッケージ |
| `Configlue.Abstraction` | 契約（provider / codec / resource / generated-model） |
| `Configlue.Core` | 解決と永続化のランタイム |
| `Configlue.Extensibility` | プロバイダー SDK |
| `Configlue.Extensions.DI` | DI 統合 |
| `Configlue.Extensions.MSOptions` | `IOptions<T>` アダプター |
| `Configlue.Extensions.Reactive` / `.R3` | リアクティブ統合 |
| `Configlue.Generator` | Roslyn アナライザー（スパースなモデルサポート生成） |
| `Configlue.Testing` | インメモリのテストダブル |
| `Configlue.Provider.Json` / `.Xml` / `.Yaml` | 各形式の Codec・セクションリソース・ファイル登録 |
| `Configlue.JsonSchema` | JSON Schema 生成・エクスポート |
| `Configlue.Source.Environment` / `.CommandLine` | 環境変数 / コマンドラインソース |
| `Configlue.Source.Presets` / `.Presets.Yaml` / `.Presets.Xml` | 標準的な層構成のプリセット |
| `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip` | 各種 Resource |
| `Configlue.Transformer.AES` | Resource と Codec の間のバイトを AES-GCM で暗号化・認証 |

---

## ライセンス

Apache-2.0

