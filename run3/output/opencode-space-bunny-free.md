# Configlue

**Make easy configuration management.**

Configlue は、アプリケーションの設定管理を引き継ぐ .NET ライブラリです。名前の由来は configuration（設定）+ glue（接着剤）。judged: 複数の場所に散らばった設定を、ひとつのモデルに「接着」するのが中心となる考え方です。

- 必要環境: .NET 10 SDK 以降（`LangVersion` はソースジェネレーター対応が必要）
- ライセンス: Apache-2.0
- 現時点では「アーキテクチャの土台」であり、`Configuration.Writable` の完全な代替ではありません

---

## なぜ Configlue なのか

JSON ファイルを読み書きするのは数行で済みます。しかし実運用では要求が積み上がります。

- 設定が複数の場所にある — グローバル設定、実行フォルダごとの設定、環境変数、コマンドライン引数、暗号化された資格情報、企業ポリシーや HTTP API などのリモート管理
- 設定ファイルが書き換えられたときに、アプリ再起動なしで反映したい（変更通知）
- 書き込み先を自動的に決めたい — 環境変数から読んだ値への書き込みはエラーにしたい
- 設定ファイルは人間が書く — コメントを消したくない、JSON Schema ferm 対応したい、壊れたファイル ἀ'handleしたい
- まだ既定値のままである値は書き出したくない（ただし利用者が明示的に設定した `null` は尊重する）
- 設定ファイルのバージョンアップ（旧形式から新形式へ自動変換）
- バックアップと自動整理
- 書き込みの安全性 — アトミックティ（クラッシュしても壊れない）、他プロセスとの競合検出と自動マージ、自動リトライ

これらを自前で実装するのは面倒、というのが動機です。

---

## コア構成 — 6つの概念

依存関係は一直線です。学ぶ順番も同じです。

```text
Resource（格納場所） → Codec（変換） → Source（提供） → Fragment（差分） → Options（ファサード）
                                                          ↘ Patch（編集用の差分）
```

| 概念 | 一言で言うと | 例 |
| --- | --- | --- |
| Resource | バイト列がどこにあるか | ファイル、ZIP エントリ、HTTP レスポンス、メモリ |
| Codec | バイト列と値の相互変換 | JSON / XML / YAML の読み書き |
| Source | 論理的な提供（どのフィールドをどの優先度で） | 「ユーザー設定ファイルの `Server` 部分」 |
| Fragment | 「存在したか」を 기억する差分 | 「`Port` だけを持つ」状態 |
| Patch | 単一フィールドの編集 | 「`Port` を 9000 に設定」 |
| Options | アプリが見るファサード | 読み取り・保存・監視・説明・診断 |

**読み取り**: 各 Source が Resource からバイト列を取得し、Codec がそれを Fragment に変換します。ランタイムは「存在する」フィールドだけを優先度順に重ね合わせて、ひとつのモデルに合成します。

**書き込み**: 逆方向です。アプリは普通のモデル値を編集します。内部ではその変更が Fragment の差分になり、`WriteRoute` / `WritePlan` が指定した Source にだけ届きます。無関係な Source は変更されません。

- Fragment は「メンバーが存在しない」と「null / 既定値として存在する」を区別します。層の合成において「未設定」が「既定値を設定」に上書きされることはありません。
- Patch は生成される `TModel.Patch`（単一フィールドの編集 Fragment）です。`Unset()` は書き込み先 Source の提供を取り消すだけで、下位優先度の値が再び現れます。
- `[ConfiglueMerge]` はメンバー単位のマージ動作を変更します（組み込み: `Append` / `Deep` / `Replace` / `SetUnion`。カスタム戦略も可）。コレクションの層合成と順序決定はここで行われます。

---

## 主な機能

- **複数ソースの優先度マージ**: `Priority` が大きい Source が勝ちます。`GetDetailsAsync` で「どの値はどこから来たか」を調べられます。
- **読み取り専用ソース**: 環境変数、コマンドライン、既定の HTTP ソースは読み取り専用です。読み取り専用な値への書き込みは黙って無視されず、競合エラーを発生させます。
- **プロジェクション / マウント**: 既存の Source を別のモデルへ変形する（projection）、ネストしたパスに別の Source を取り付ける（mount、`AddMounted`）ことができます。
- **プリセット**: `UseCommonSources` が標準的な層構成（グローバル / ローカル / 環境変数など）を組み立てます。
- **スパース書き込み**: 変更したフィールドだけを書き込み先レイヤーに保存します。既定値のままのフィールドは書き込まれません。
- **編集セッション**: `OpenEditSessionAsync` で複数の変更をまとめて適用します。`CommitAsync` まではメモリ上です。既定では競合時に失敗します。`WriteConflictResolution.LastWriteWins` も利用できます。
- **スキーマ移行 / ストレージ移行**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` により旧バージョンの設定を自動変換します。既存ファイルを Source として登録することもできます。
- **バックアップと復元**: `FileResource` がアトミック書き込みとバックアップ世代の管理を提供します。既定で 1 世代の `.bak` を保持し、`RestoreLatestBackupAsync` で復元できます。
- **安全な書き込み**: アトミックティ、競合検出、リトライ。
- **セクション**: `JsonSectionResource`、XML 要素、YAML マッピングにより、ファイルの一部だけを独立した Resource として扱えます。書き込み時にコメント、空白、クォート、スキャラー style は保持されます。同じファイル内の独立したセクションは 1 回の物理書き込みにまとめられます。
- **ZIP / HTTP / S3 / Dapr**: `ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込みとポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **JSON Schema 生成**: 設定を 사람이書くため、`Configlue.JsonSchema` でスキーマを生成・出力できます。
- **Native AOT 対応**: ソース生成された `JsonSerializerContext` を渡すと、トリミング / AOT 耐性が向上します。
- **リアクティブ連携（任意）**: `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）。`ObserveChanges()`、`ObserveValues()`、`ObserveReloadFailures()`、`ObserveActiveValues()`、`ObserveActiveProfileNames()` が使えます。
- **DI 連携**: `Configlue.Extensions.DI`。Microsoft options アダプターは `Configlue.Extensions.MSOptions`（`IOptions<T>` など）。同期ゲッターは非同期ソースの読み取り中にブロックするため、非同期フローでは `GetValueAsync` の利用を推奨します。
- **プロファイル / 動的オプション**: 名前付きオプションと永続プロファイルにより、ランタイムをまとめて作成・破棄できます。
- **既知の制限**: 異なる Resource にまたがる書き込みはアトミックではありません。Source の退役は現在の options インスタンスにスコープされ、実データは残ります。Source の集合は options ランタイムごとに固定です。

---

## パッケージ構成（主なもの）

| パッケージ | 役割 |
| --- | --- |
| `Configlue` | ユーザー向けメタパッケージ（Core / DI / JSON provider / JSON Schema / HTTP resources / common sources / environment source / generator analyzer をまとめて取り込む。実装アセンブリ自体は持たない） |
| `Configlue.Abstraction` | 契約（provider / codec / resource / 生成モデル） |
| `Configlue.Core` | 解決と永続化のランタイム |
| `Configlue.Extensibility` | プロバイダー SDK |
| `Configlue.Extensions.DI` / `.MSOptions` / `.R3` / `.Reactive` | 各連携 |
| `Configlue.Generator` | Roslyn  jihad ライナライザ（スパースモデルサポートを生成） |
| `Configlue.Testing` | インメモリのテストダブル |
| `Configlue.Provider.Json` / `.Xml` / `.Yaml` | 各形式の codec、セクション Resource、ファイル登録 |
| `Configlue.JsonSchema` | JSON Schema の生成と出力 |
| `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml` | ソース関連 |
| `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip` | リソース関連 |
| `Configlue.Transformer.AES` | Resource と Codec の間にあるバイト列に対する AES-GCM 暗号化・認証 |

インストールは `dotnet add package Configlue` から始め、必要な機能パッケージを追加します。

---

## クイックスタート

以下を `example.cs` として保存し、`dotnet run example.cs` で実行してください（.NET 10 以降）。

```csharp
#!/usr/bin/env dotnet
#:package Configlue@*

using Configlue;
using Configlue.Source.Presets;

// 1. 設定モデルを宣言する。ジェネレーターが Fragment / Patch サポートを生成する。
[ConfiglueModel("SampleSetting", Version = 1)]
public partial class SampleSetting
{
    public string Name { get; set; } = "World";
    public int RunCount { get; set; }
    public bool DefaultValue { get; set; } = true;
}

// 2. プリセットレイヤーを宣言する。ここでは列挙したソースだけが有効になる。
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);

// 3. options インスタンス経由で読み書きする。
var options = context.GetOptions<SampleSetting>();
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// スパース編集: 変更したフィールドだけが書き込み先レイヤーに保存される。
await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue は変更していないので、書き込み先レイヤーには保存されない。
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

---

## 値の由来を調べる / スパース保存

```csharp
var options = context.GetOptions<AppSettings>();
// 1. 現在の値を取得する（全ソースからマージ済み）
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

指定したメンバーだけを更新する Patch を保存します。`Unset()` はその Source の提供を取り消すため、下位優先度の Source が値を提供し直します。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

その他の API:

- `IReadOnlyOptions<T>` … 日常的な読み取り面は `GetValueAsync` と `OnChange`
- `SaveAsync(patch => ...)` … 生成された Patch によるスパース保存
- `OpenEditSessionAsync()` … 複数をまとめて編集し、`CommitAsync` で確定
- `ApplyPatchesAsync` + `StateSourcePatch` … Source ごとの複数書き込みを明示的に行う
- `StateWritePlan.For<T>().Route(...)` … 書き込みルーティング
- `SourceKey<TModel>` と `options.Source(key)` … Source 単位の操作

---

## `Microsoft.Extensions.Configuration` との違い

`IConfiguration` は読み取り中心の設計です。Configlue は、互いに独立したソースの合成、由来（provenance）の調査、スパースでの保存紡合 suited に設計されています。ENDO

