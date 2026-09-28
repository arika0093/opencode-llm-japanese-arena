# Configlue

> Make easy configuration management.

Configlue は、アプリケーションの設定管理をまるごと引き受けるための **.NET ライブラリ**です。名前が示す通り「Configuration + glue」、つまり複数の場所に散らばった設定を **糊付け (glue) して 1 つのモデルに統合する** ことが中核のアイデアです。

- 動作要件: **.NET 10 SDK** 以降 / `LangVersion` がソース ジェネレーターに対応する C#
- ライセンス: Apache-2.0
- 位置付け: まだ「アーキテクチャ的な土台」であり、`Microsoft.Extensions.Configuration.Writable` の完全な置き換えではありません。

インストールは `dotnet add package Configlue` から開始し、必要に応じて機能別パッケージを追加します。

---

## なぜ Configlue なのか

JSON ファイルの読み書きそのものは数行で済みます。しかし実運用では、こうした要件が雪だるま式に積み上がっていきます。

- 設定が複数箇所に存在する(グローバル設定、ランタイム フォルダ別設定、環境変数、コマンドライン引数、暗号化された資格情報、企業ポリシや HTTP API などのリモート管理)
- 設定ファイルが書き換えられたとき、アプリを再起動せず変更を反映したい(変更通知)
- 書き込み先を自動で選びたい。環境変数から読み取った値への書き込みはエラーにしたい
- 人間が設定ファイルを編集する: コメントを消さない、JSON Schema サポート、壊れたファイルへの対応
- 値が既定値のままなら書き出さない(ただしユーザーが明示的に設定した `null` は尊重)
- 設定ファイルのバージョンを上げたい(旧フォーマットから新フォーマットへの自動変換)
- バックアップと自動クリーンアップ
- 書き込みの安全性: 原子性(クラッシュで破損させない)、他プロセスとの競合検出と自動マージ、自動リトライ

これらを自前で実装するのは退屈で間違いやすい作業です。Configlue はそれらを最初から組み込んだ土台を提供します。

---

## コア アーキテクチャ(6 つの概念)

依存関係は一直線に並んでおり、学習順序も同じです。

```text
Resource(場所) → Codec(変換) → Source(寄与) → Fragment(差分) → Options(ファサード)
                                              ↘ Patch(編集フラグメント)
```

| 概念 | 一言で | 例 |
| --- | --- | --- |
| Resource | バイトが置かれている場所 | ファイル、ZIP エントリ、HTTP レスポンス、メモリ |
| Codec | バイトと値の相互変換 | JSON / XML / YAML の読み書き |
| Source | 論理的な寄与(どのフィールドをどの優先度で) | 「ユーザー設定ファイルの `Server` 部分」 |
| Fragment | 「存在」を記憶する差分 | 「`Port` だけがある」状態 |
| Patch | 単一フィールドの編集 | 「`Port` を 9000 に設定」 |
| Options | アプリから見えるファサード | 読み取り、保存、監視、説明、診断 |

**読み取り**: 各 Source が Resource からバイトを取得し、Codec がそれを Fragment に変換します。ランタイムは「存在する」フィールドだけを、優先度に従って 1 つのモデルに重ね合わせます。

**書き込み**: 逆方向です。アプリは通常のモデル値を編集します。内部ではその変更が Fragment の差分となり、`WriteRoute` / `WritePlan` で指定された Source にだけ届きます。関係のない Source は変更されません。

- Fragment は「メンバーが未設定」と「null/既定値で設定済み」を区別します。レイヤーを重ね合わせても「未設定」が「既定値で設定済み」を上書きしません。
- Patch は生成された `TModel.Patch`(単一フィールドの編集フラグメント)です。`Unset()` を呼ぶと、書き込み先 Source の寄与だけが取り下げられ、より低い優先度の値が再公開されます。
- `[ConfiglueMerge]` でメンバーごとのマージ挙動を変更できます(組み込み: `Append` / `Deep` / `Replace` / `SetUnion`、カスタム戦略も可)。コレクションのレイヤー合成と順序はここで決まります。

---

## 主な機能

- **複数ソースの優先度マージ**: `Priority` が大きい Source が勝ちます。`GetDetailsAsync` で「値がどこから来たか」を確認できます。
- **読み取り専用ソース**: 環境変数、コマンドライン、デフォルトの HTTP ソースは読み取り専用です。読み取り専用への書き込みは黙って無視されず、競合としてエラーになります。
- **プロジェクション / マウント**: 既存の Source を別のモデルとして再構成(プロジェクション)したり、別の Source をネストされたパスに取り付けたり(マウント、`AddMounted`)できます。
- **プリセット**: `UseCommonSources` が標準的なレイヤー構成(グローバル / ローカル / 環境変数など)を組み立てます。
- **スパース書き込み**: 変更したフィールドだけが対象レイヤーに保存されます。既定値のままのフィールドは書き出されません。
- **編集セッション**: `OpenEditSessionAsync` で複数の変更をまとめて適用し、`CommitAsync` までメモリ内に留めます。競合時は既定で失敗し、`WriteConflictResolution.LastWriteWins` を選ぶこともできます。
- **スキーマ移行 / ストレージ移行**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` で旧バージョンの設定を自動変換。既存ファイルを Source として登録できます。
- **バックアップと復元**: `FileResource` が原子的な書き込みとバックアップ世代管理を提供します。`.bak` は既定で 1 世代。`RestoreLatestBackupAsync` で復元します。
- **安全な書き込み**: 原子性、競合検出、リトライ。
- **セクション**: `JsonSectionResource` / XML 要素 / YAML マッピングで、ファイルの一部を独立した Resource として扱えます。書き込み時はコメント、空白、クォート、スカラーのスタイルが保持されます。同じファイル内の独立したセクションは 1 回の物理書き込みにまとめられます。
- **ZIP / HTTP / S3 / Dapr**: `ZipEntryResource`、`Configlue.Resource.Http`(ETag 条件付き書き込みとポーリング)、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **JSON Schema 生成**: 人間が設定ファイルを書き換えるため、`Configlue.JsonSchema` で生成・エクスポートできます。
- **Native AOT 対応**: ソース生成された `JsonSerializerContext` を渡すことで、トリミング / AOT 耐性が向上します。
- **Reactive 連携(任意)**: `Configlue.Extensions.Reactive`(System.Reactive 7.0.0)、`Configlue.Extensions.R3`(R3 1.3.1)。`ObserveChanges()` / `ObserveValues()` / `ObserveReloadFailures()` / `ObserveActiveValues()` / `ObserveActiveProfileNames()` を提供。
- **DI 連携**: `Configlue.Extensions.DI`。`Configlue.Extensions.MSOptions` で Microsoft オプション(`IOptions<T>` など)のアダプターを利用できます(同期ゲッターは非同期ソースの読み取り中にブロックするため、非同期フローでは `GetValueAsync` の利用が推奨されます)。
- **プロファイル / 動的オプション**: 名前付きオプションと永続プロファイルにより、ランタイムをまとめて作成・削除できます。
- **既知の制約**: 異なる Resource 間の書き込みは非アトミックです。Source のリタイアは現在の Options インスタンスにスコープされ、背後のデータはそのまま残ります。Options ランタイムに対して Source セットは固定です。

---

## パッケージ構成(主なもの)

- `Configlue` — ユーザー向けメタ パッケージ(Core / DI / JSON プロバイダー / JSON Schema / HTTP リソース / 共通ソース / 環境変数ソース / ジェネレーター アナライザーを束ねます。実装アセンブリは持ちません)
- `Configlue.Abstraction` — 契約(provider / codec / resource / 生成モデル)
- `Configlue.Core` — 解決と永続化のランタイム
- `Configlue.Extensibility` — プロバイダー SDK
- `Configlue.Extensions.DI` / `.MSOptions` / `.R3` / `.Reactive`
- `Configlue.Generator` — Roslyn アナライザー(スパース モデルのサポートを生成)
- `Configlue.Testing` — インメモリ テスト ダブル
- `Configlue.Provider.Json` / `.Xml` / `.Yaml` — 各フォーマットの codec、セクション resource、ファイル登録
- `Configlue.JsonSchema` — JSON Schema の生成とエクスポート
- `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml`
- `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip`
- `Configlue.Transformer.AES` — Resource と Codec の間のバイトに対する AES-GCM 暗号化 / 認証

---

## Quick Start

次の内容を `example.cs` として保存し、.NET 10 以降で `dotnet run example.cs` を実行します。

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

// 2. プリセット レイヤーを宣言する。ここで列挙したソースだけが有効になる。
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);

// 3. Options インスタンスを通して読み書きする。
var options = context.GetOptions<SampleSetting>();
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// スパース編集: 変更したフィールドだけが対象レイヤーに保存される。
await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue は変更されていないので対象レイヤーには保存されない。
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

---

## 値の由来を調べる / スパースに保存する

```csharp
var options = context.GetOptions<AppSettings>();
// 1. 現在の値を取得する(全ソースからマージ済み)
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 2. 各値がどこから来たかを確認する
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

指定したメンバーだけを更新するパッチを保存できます。`Unset()` を呼ぶと、その Source の寄与だけが取り下げられ、より低い優先度のソースから値が提供されるようになります。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

その他の API:

- `IReadOnlyOptions<T>` — 日常的な読み取り面は `GetValueAsync` と `OnChange`。
- `SaveAsync(patch => ...)` — 生成された Patch によるスパース保存。
- `OpenEditSessionAsync()` — 複数の編集をまとめて扱い、`CommitAsync` で確定。
- `ApplyPatchesAsync` + `StateSourcePatch` — Source を明示した複数書き込み。
- `StateWritePlan.For<T>().Route(...)` — 書き込みルーティング。
- `SourceKey<TModel>` と `options.Source(key)` — Source 単位の操作。

---

## `Microsoft.Extensions.Configuration` との違い

`IConfiguration` は読み取り中心の API であるのに対し、Configlue は **独立したソースの合成、出典の追跡、スパースな保存** に重点を置いています。設定の「読み書きの往復」を安全に行いたい場面、複数の提供源を重ねたい場面で強みを発揮します。
