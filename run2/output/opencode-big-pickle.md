# Configlue

**Make easy configuration management.**

Configlue は .NET アプリケーションの設定管理（configuration management）を代行するライブラリです。
中心にある考え方は、**複数の場所に散らばった設定を 1 つのモデルに「糊付け（glue）」する**ことです。
グローバル設定、実行フォルダーの設定、環境変数、コマンドライン引数、暗号化された資格情報、社内ポリシーや HTTP API といったリモート管理 —
どの場所に何が書いてあるか意識せずに 1 つの型として扱い、**その値がどこから来たのかを説明でき**、**変更したフィールドだけを安全に書き戻せる**ようにします。

- **ライセンス**: Apache-2.0
- **対象**: .NET 10 SDK 以降（C# / ソースジェネレーター。ライブラリ自体は preview でビルド）

> **現状の位置づけ**: Configlue は現時点でアーキテクチャ上の土台です。`Microsoft.Extensions.Configuration` の読み取り機能を置き換えるものではありません。
> 独立した設定ソースの合成、来歴（provenance）の検査、スパースな保存を前提とした設計です。複数の場所に散らばった設定を 1 つの型として扱いたい場合に適しています（→ [Microsoft.Extensions.Configuration との関係](#microsoftextensionsconfiguration-との関係)）。

## 目次

- [インストール](#インストール)
- [Why Configlue?](#why-configlue)
- [Quick Start](#quick-start)
- [6 つの概念](#6-つの概念)
- [主な機能](#主な機能)
- [値の来歴を調べる](#値の来歴を調べる)
- [スパース保存と Unset()](#スパース保存と-unset)
- [API 一覧](#api-一覧)
- [パッケージ](#パッケージ)
- [Microsoft.Extensions.Configuration との関係](#microsoftextensionsconfiguration-との関係)
- [既知の制限](#既知の制限)

## インストール

```bash
dotnet add package Configlue
```

`Configlue` はユーザー向けのメタパッケージで、Core / DI / JSON provider / JSON Schema / HTTP resources / common sources / environment source / generator analyzer を同梱しています（実装アセンブリ自体は持たず、依存として解決されます）。
必要な機能に応じて [個別のパッケージ](#パッケージ)を追加してください。

## Why Configlue?

JSON ファイルを 1 つ読み書きするだけなら数行で済みます。しかし実際に運用しているアプリケーションでは、次の要件が積み重なります。

- **設定が複数箇所にある** — グローバル設定、実行フォルダーの設定、環境変数、コマンドライン引数、暗号化された資格情報、社内ポリシーや HTTP API などのリモート管理
- **設定ファイルが書き換わったら再起動なしで反映したい** — 変更通知
- **書き込み先を自動で選びたい** — 環境変数から読んだ値への書き込みはエラーにしたい
- **設定ファイルは人間が書く** — コメントを消さない、JSON Schema が欲しい、壊れたファイルへの対処
- **既定値のままなら書き出したくない** — ただしユーザーが明示した `null` は尊重する
- **設定ファイルのバージョンアップ** — 旧形式から新形式へ自動変換
- **バックアップと自動整理**
- **書き込みの安全性** — アトミック性（クラッシュしても壊れない）、他プロセスとの競合検出・自動マージ、自動リトライ

これらを毎回自前実装するのは面倒です。Configlue はその「面倒」をライブラリ側に閉じ込めます。

## Quick Start

以下のコードを `example.cs` に保存し、`dotnet run example.cs` で実行できます（.NET 10 以降）。

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

3 つのステップだけです。

1. **モデルを宣言する** — `[ConfiglueModel]` を付けた `partial class` に対し、ソースジェネレーターが Fragment / Patch のサポートを生成します。
2. **層を組み立てる** — `UseCommonSources` がグローバル / ローカル / 環境変数という標準的な層構成を組んでくれます。列挙したソースだけが有効になります。
3. **Options 経由で読み書きする** — `GetValueAsync` で読み、`SaveAsync(patch => ...)` で変更したフィールドだけを保存します。

保存されるのは `Name` と `RunCount` だけです。触っていない `DefaultValue` は対象層に書かれません。

## 6 つの概念

依存関係は直線的で、学習順も同じです。

```text
Resource (location) → Codec (conversion) → Source (contribution) → Fragment (diff) → Options (facade)
                                                        ↘ Patch (edit fragment)
```

| 概念 | 一言で | 例 |
| --- | --- | --- |
| **Resource** | バイトがどこにあるか | ファイル、ZIPエントリ、HTTP 応答、メモリ |
| **Codec** | バイト↔値の変換 | JSON / XML / YAML の読み書き |
| **Source** | 論理的な寄与（どのフィールドを、どの優先度で） | 「ユーザー設定ファイルの `Server` 部分」 |
| **Fragment** | 存在を記憶する差分 | 「`Port` だけ」を持つ状態 |
| **Patch** | 単一フィールドの編集 | 「`Port` を 9000 にする」 |
| **Options** | アプリが見るファサード | 読み・保存・監視・説明・診断 |

### 読み込み

各 Source が Resource からバイトを取得し、Codec が Fragment に変換します。
ランタイムは優先度順に Fragment を重ね、**存在するものだけ**を 1 つのモデルへ合成します。
`Priority` が大きい Source が勝ちます。

### 書き込み

逆向きです。アプリは普通のモデル値を編集します。
内部ではその変更が Fragment の差分になり、`WriteRoute` / `WritePlan` が指す Source にだけ届きます。**無関係な Source は変更されません。**

### Fragment は「不在」と「明示された値」を区別する

Fragment は「メンバーが存在しない」と「null や既定値として存在する」を区別します。
層を合成しても「未設定」が「既定値に設定」を上書きすることはありません。
つまり「触れなかったフィールド」が暗黙に層を壊すことはありません。

### Patch と `Unset()`

生成される `TModel.Patch` は単一フィールドの編集フラグメントです。
`Unset()` を呼ぶと、書き込み先 Source の寄与だけが取り消され、下位優先度の Source の値が再び見えるようになります。

### マージ戦略

`[ConfiglueMerge]` でメンバーごとにマージ挙動を変更できます。
組み込みは `Append` / `Deep` / `Replace` / `SetUnion`、カスタム戦略も指定可能です。
コレクションの層合成と順序はここで決まります。

## 主な機能

### 複数ソースの優先度マージ

`Priority` が大きい Source が勝ちます。`GetDetailsAsync` を使うことで、「どの値がどこから来たのか」を実行時に検査できます（→ [値の来歴を調べる](#値の来歴を調べる)）。

### 読み取り専用ソース

環境変数・コマンドライン・既定の HTTP ソースは読み取り専用です。
読み取り専用の値への書き込みは黙って無視されず、**競合エラー**になります。

### プロジェクション / マウント

既存 Source を別のモデルに整形（**projection**）したり、ネストしたパスに別の Source を接続（**mount**、`AddMounted`）できます。
たとえば 1 つの設定ファイルの中で、異なるモデルが担当するセクションを独立した Source として扱う、といった構成が可能です。

### プリセット

`UseCommonSources` が global / local / environment といった標準的な層構成を組み立てます（→ [Quick Start](#quick-start)）。

### スパース書き込み

変更したフィールドだけが対象層に保存されます。既定値のままのフィールドは書かれません（ただしユーザーが明示した `null` は尊重されます）。

### 編集セッション

`OpenEditSessionAsync` で複数の変更をまとめて適用し、`CommitAsync` までメモリ内で処理します。
競合時は既定で失敗しますが、`WriteConflictResolution.LastWriteWins` を選ぶこともできます。

### スキーマ移行 / ストレージ移行

`[ConfigluePreviousVersion]` と `Fragment.FromPrevious` により、旧バージョンの設定を新しい形式へ自動変換できます。
既存のファイルをそのまま Source として登録することもできます。

### バックアップとアトミック書き込み

`FileResource` はアトミック書き込みとバックアップ世代管理を提供します。
既定で `.bak` 1 世代を保持し、`RestoreLatestBackupAsync` で復元できます。

### セクション

`JsonSectionResource`（および XML 要素、YAML マッピング）により、ファイルの一部を独立した Resource として扱えます。
書き込み時にコメント・空白・引用・スカラー形式が保持されます。
同じファイル内の独立したセクションは、1 回の物理書き込みにバッチされます。

### その他のリソース

- `ZipEntryResource` — ZIP 内のエントリ
- `Configlue.Resource.Http` — ETag による条件付き書き込み・ポーリング
- `Configlue.Resource.S3`
- `Configlue.Resource.Dapr`

### 設定ファイルは人間が書く

- **JSON Schema 生成** — `Configlue.JsonSchema` がスキーマを生成・エクスポートします
- **コメントと書式の保持** — 上記のセクション対応で実現します

### Native AOT

ソース生成された `JsonSerializerContext` を渡すと、トリミング / AOT に強い挙動になります。

### リアクティブ統合（任意）

`Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）に対応しています。
`ObserveChanges()` / `ObserveValues()` / `ObserveReloadFailures()` / `ObserveActiveValues()` / `ObserveActiveProfileNames()` が利用できます。

### DI 統合

`Configlue.Extensions.DI` が Microsoft の DI と統合します。
Microsoft の options アダプターは `Configlue.Extensions.MSOptions`（`IOptions<T>` など）として提供されます。
なお `IOptions<T>` の同期ゲッターは非同期ソースの読み取り中にブロックするため、非同期フローでは `GetValueAsync` の利用を推奨します。

### プロファイル / 動的オプション

名前付きオプションや永続プロファイルにより、ランタイム単位で options インスタンスを作成・削除できます。

## 値の来歴を調べる

マージされた値だけを見ると、どこから来た値は分かりません。`GetDetailsAsync` は各メンバーの来歴を返します。

```csharp
var options = context.GetOptions<SampleSetting>();

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

`details.Name.Sources` には、そのメンバーを提供したすべてのソースが「どの優先度で」「勝ち負けがどうだったか」とともに並びます。
診断用の UI やログ、あるいは「いま有効な値が書き込み可能か」を確認したいときに使えます。

## スパース保存と `Unset()`

指定したメンバーだけを更新するパッチを保存します。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

この例では:

- `Name` は `"Bob"` に更新される
- `RunCount` は書き込み先 Source の寄与が取り消され、下位優先度の Source の値が再び見える
- それ以外のメンバーは一切触られない

## API 一覧

| API | 役割 |
| --- | --- |
| `IReadOnlyOptions<T>` | 日常的な読み取り面。`GetValueAsync` と `OnChange` |
| `GetValueAsync()` | 全ソースをマージした現在の値を取得 |
| `GetDetailsAsync()` | 各メンバーの来歴（どのソースか・書き込み可能か）を取得 |
| `SaveAsync(patch => ...)` | 生成された Patch によるスパース保存 |
| `OpenEditSessionAsync()` / `CommitAsync()` | 複数の変更をまとめて適用 |
| `ApplyPatchesAsync` + `StateSourcePatch` | 明示的なソース別のマルチ書き込み |
| `StateWritePlan.For<T>().Route(...)` | 書き込みルーティング |
| `SourceKey<TModel>` / `options.Source(key)` | ソース単位の操作 |
| `RestoreLatestBackupAsync()` | `FileResource` の直近バックアップから復元 |

## パッケージ

| パッケージ | 役割 |
| --- | --- |
| `Configlue` | ユーザー向けメタパッケージ（実装アセンブリは持たない） |
| `Configlue.Abstraction` | 契約（provider / codec / resource / generated-model） |
| `Configlue.Core` | 解決と永続化のランタイム |
| `Configlue.Extensibility` | プロバイダー SDK |
| `Configlue.Generator` | Roslyn アナライザー（スパースなモデルサポートの生成） |
| `Configlue.Extensions.DI` | Microsoft DI 統合 |
| `Configlue.Extensions.MSOptions` | `IOptions<T>` などの Microsoft options アダプター |
| `Configlue.Extensions.R3` | R3 との統合 |
| `Configlue.Extensions.Reactive` | System.Reactive との統合 |
| `Configlue.Testing` | インメモリのテストダブル |
| `Configlue.Provider.Json` / `.Xml` / `.Yaml` | 各形式の Codec・セクションリソース・ファイル登録 |
| `Configlue.JsonSchema` | JSON Schema の生成・エクスポート |
| `Configlue.Source.Environment` / `.CommandLine` | 環境変数・コマンドライン引数のソース |
| `Configlue.Source.Presets` / `.Presets.Yaml` / `.Presets.Xml` | プリセット（層構成） |
| `Configlue.Resource.Http` / `.Http.AspNetCore` | HTTP ベースのリソース（ETag 条件付き書き込み・ポーリング） |
| `Configlue.Resource.S3` | S3 ベースのリソース |
| `Configlue.Resource.Dapr` | Dapr ベースのリソース |
| `Configlue.Resource.Zip` | ZIP エントリのリソース |
| `Configlue.Transformer.AES` | Resource と Codec の間のバイトを AES-GCM で暗号化・認証 |

## Microsoft.Extensions.Configuration との関係

`IConfiguration` は優れた読み取り中心の設計です。階層的なキー、provider の合成、リロードにも対応しています。
一方で、書き込みは主たる対象ではなく、「どの provider のどの値が勝ったか」を後から説明する方法が限られ、フィールド単位で「この値だけ対象層に書く」という操作も素朴ではありません。

Configlue はこの延長ではなく、別の軸に立っています。

- 設定ソースを**独立した Source** として明示的に管理し、合成結果は Priority で決まる
- **来歴を第一級の対象**にする（`GetDetailsAsync`）
- **スパースな保存**を前提とする（変更したフィールドだけが対象層に届く）
- 書き込み安全性（アトミック性・競合検出・バックアップ）を標準で提供する

設定の読み取りだけが目的で、階層的なキーで十分なら `Microsoft.Extensions.Configuration` が適しています。
一方、複数の独立した設定置き場を合成し、その来歴を説明し、変更だけを安全に反映させる必要があるなら、Configlue がその形に合います。

## 既知の制限

- **異なる Resource 間の書き込みはアトミックではありません** — 1 回の保存が複数の Resource にまたがる場合、それぞれの書き込みは個別にアトミックですが、まとめてはアトミックになりません
- **Source の退役は現在の options インスタンスに閉じ、実データは残ります** — Source を削除しても、削除前の Source が書き込んだ実データは消えません
- **Source 集合は options ランタイムで固定** — ランタイム作成後に Source を追加・削除して、既存の options インスタンスに反映させることはできません

