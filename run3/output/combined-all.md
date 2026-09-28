# Configlue README 日本語 - run3（英語コンテキスト + 英語の最小指示） 全モデル

---

# ===== opencode-go/deepseek-v4.1-flash =====

# Configlue

**Make easy configuration management.**

Configlue は、アプリケーションの構成管理を引き受ける .NET ライブラリです。
複数の場所に散らばった構成を 1 つのモデルに **glue（接着）** することを中心的な考え方としており、名前は configuration + glue に由来します。

- 要件: .NET 10 SDK 以降。C#（`LangVersion` がソースジェネレーターをサポートしていること。リポジトリでは `preview` でビルド）
- ライセンス: Apache-2.0
- 現状は「アーキテクチャの土台」であり、`Configuration.Writable` を完全に置き換えるものではありません。

## なぜ Configlue か

JSON ファイルを読み書きするだけなら数行で済みます。しかし実際には、次のような要件が積み重なっていきます。

- 構成が複数の場所にある: グローバル設定、実行フォルダーごとの設定、環境変数、コマンドライン引数、暗号化された資格情報、社内ポリシーや HTTP API などのリモート管理。
- 構成ファイルが書き換えられたら、アプリを再起動せずに反映したい（変更通知）。
- 書き込み先を自動で選びたい。環境変数から読んだ値への書き込みはエラーにしたい。
- 構成ファイルは人間が書くものなので、コメントを消したくない、JSON Schema が欲しい、壊れたファイルも扱いたい。
- 値が既定のままなら書き出したくない（ただし、ユーザーが明示的に設定した `null` は尊重したい）。
- 構成ファイルをバージョンアップしたい（旧形式から新形式への自動変換）。
- バックアップと自動クリーンアップ。
- 書き込みの安全性: アトミック性（クラッシュしても壊れない）、他プロセスとの競合検出と自動マージ、自動リトライ。

これらをすべて自分で実装するのは面倒です。Configlue はそこを引き受けます。

## コアアーキテクチャ（6 つの概念）

依存関係は一直線で、学習順も同じです。

```text
Resource (場所) → Codec (変換) → Source (寄与) → Fragment (差分) → Options (ファサード)
                                                    ↘ Patch (編集フラグメント)
```

| 概念 | ひとことで | 例 |
| --- | --- | --- |
| Resource | バイトが存在する場所 | ファイル、ZIP エントリ、HTTP レスポンス、メモリ |
| Codec | バイトと値の相互変換 | JSON / XML / YAML の読み書き |
| Source | 論理的な寄与（どのフィールドをどの優先度で） | 「ユーザー設定ファイルの `Server` の部分」 |
| Fragment | 存在を覚えている差分 | 「`Port` だけ」を持っている状態 |
| Patch | 単一フィールドの編集 | 「`Port` を 9000 に設定」 |
| Options | アプリが見るファサード | 読み取り、保存、監視、説明、診断 |

**読み取り**: 各 Source が Resource からバイトを取得し、Codec がそれを Fragment に変換します。ランタイムは「存在する」フィールドだけを優先度順に重ね合わせ、1 つのモデルにします。

**書き込み**: 逆方向です。アプリは普通のモデル値を編集します。内部的には変更が Fragment の差分になり、`WriteRoute` / `WritePlan` が指定した Source にだけ届きます。無関係な Source は変更されません。

- Fragment は「メンバーが欠落している」ことと「null / 既定値として存在する」ことを区別します。レイヤーの合成で「未設定」が「既定値に設定」を上書きすることはありません。
- Patch は生成される `TModel.Patch`（単一フィールドの編集フラグメント）です。`Unset()` は書き込み先 Source の寄与だけを撤回し、下位優先度の値を再び露出させます。
- `[ConfiglueMerge]` はメンバーごとのマージ動作を変更します（組み込み: `Append`、`Deep`、`Replace`、`SetUnion`。カスタム戦略も可）。コレクションのレイヤー合成と順序はここで決まります。

## 主な機能

- **複数 Source の優先度マージ**: `Priority` が大きい Source が勝ちます。`GetDetailsAsync` で「どの値がどこから来たか」を調べられます。
- **読み取り専用 Source**: 環境変数、コマンドライン、既定の HTTP Source は読み取り専用です。読み取り専用の値への書き込みは黙って無視されず、競合エラーになります。
- **射影 / マウント**: 既存の Source を別のモデルに整形（射影）したり、別の Source をネストしたパスに取り付けたり（マウント、`AddMounted`）できます。
- **プリセット**: `UseCommonSources` が標準的なレイヤー構成（グローバル / ローカル / 環境など）を組み立てます。
- **スパース書き込み**: 変更したフィールドだけが対象レイヤーに保存されます。既定のままのフィールドは書き出されません。
- **編集セッション**: `OpenEditSessionAsync` で複数の変更をまとめて適用します。`CommitAsync` まではメモリ上です。競合時は既定で失敗し、`WriteConflictResolution.LastWriteWins` も利用できます。
- **スキーマ移行 / ストレージ移行**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` による旧バージョン構成の自動変換。既存ファイルを Source として登録できます。
- **バックアップと復元**: `FileResource` がアトミック書き込みとバックアップ世代管理を提供します。既定で `.bak` を 1 世代保持し、`RestoreLatestBackupAsync` で復元できます。
- **安全な書き込み**: アトミック性、競合検出、リトライ。
- **セクション**: `JsonSectionResource` / XML 要素 / YAML マッピングにより、ファイルの一部を独立した Resource として扱えます。書き込み時にはコメント、空白、クォート、スカラースタイルが保持されます。同一ファイル内の独立したセクションは 1 回の物理書き込みにまとめられます。
- **ZIP / HTTP / S3 / Dapr**: `ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込みとポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **JSON Schema 生成**: 構成は人間が書くものなので `Configlue.JsonSchema` を用意しています。
- **Native AOT 対応**: ソース生成された `JsonSerializerContext` を渡すことでトリミング / AOT 耐性が向上します。
- **リアクティブ統合（任意）**: `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）。`ObserveChanges()`、`ObserveValues()`、`ObserveReloadFailures()`、`ObserveActiveValues()`、`ObserveActiveProfileNames()`。
- **DI 統合**: `Configlue.Extensions.DI`。Microsoft オプションのアダプターは `Configlue.Extensions.MSOptions`（`IOptions<T>` など。同期ゲッターは非同期 Source の読み取り中にブロックするため、非同期フローでは `GetValueAsync` を推奨）。
- **プロファイル / 動的オプション**: 名前付きオプションと永続プロファイルにより、ランタイムを単位として作成・削除できます。
- **既知の制限**: 異なる Resource にまたがる書き込みはアトミックではありません。Source の退役は現在のオプションインスタンスにスコープされ、背後のデータはそのまま残ります。Source の集合はオプションランタイムごとに固定です。

## パッケージ構成（主なもの）

- `Configlue` … ユーザー向けメタパッケージ（Core / DI / JSON プロバイダー / JSON Schema / HTTP リソース / 共通 Source / 環境 Source / ジェネレーターアナライザーを同梱。実装アセンブリは持ちません）。
- `Configlue.Abstraction` … コントラクト（provider / codec / resource / 生成モデル）。
- `Configlue.Core` … 解決と永続化のランタイム。
- `Configlue.Extensibility` … プロバイダー SDK。
- `Configlue.Extensions.DI` / `Configlue.Extensions.MSOptions` / `Configlue.Extensions.R3` / `Configlue.Extensions.Reactive`
- `Configlue.Generator` … Roslyn アナライザー（スパースモデルのサポートを生成）。
- `Configlue.Testing` … インメモリのテストダブル。
- `Configlue.Provider.Json` / `.Xml` / `.Yaml` … 各形式のコーデック、セクションリソース、ファイル登録。
- `Configlue.JsonSchema` … JSON Schema の生成とエクスポート。
- `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml`
- `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip`
- `Configlue.Transformer.AES` … Resource と Codec の間のバイトに対する AES-GCM 暗号化と認証。

インストールは `dotnet add package Configlue` から始めます。必要に応じて機能パッケージを追加してください。

## クイックスタート

次を `example.cs` に保存し、`dotnet run example.cs` で実行します（.NET 10 以降）。

```csharp
#!/usr/bin/env dotnet
#:package Configlue@*

using Configlue;
using Configlue.Source.Presets;

// 1. 設定モデルを宣言する。ジェネレーターが Fragment/Patch サポートを生成する。
[ConfiglueModel("SampleSetting", Version = 1)]
public partial class SampleSetting
{
    public string Name { get; set; } = "World";
    public int RunCount { get; set; }
    public bool DefaultValue { get; set; } = true;
}

// 2. プリセットレイヤーを宣言する。ここに列挙した Source だけが有効になる。
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);

// 3. options インスタンスを通して読み書きする。
var options = context.GetOptions<SampleSetting>();
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// スパース編集: 変更したフィールドだけが対象レイヤーに保存される。
await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue は変更していないので、対象レイヤーには保存されない。
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

## 値の出所を調べる / スパース保存

```csharp
var options = context.GetOptions<AppSettings>();
// 1. 現在の値（すべての Source からマージされたもの）を取得する
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

指定したメンバーだけを更新する Patch を保存します。`Unset()` はその Source の寄与を取り除き、下位優先度の Source が値を提供できるようにします。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

その他の API:

- `IReadOnlyOptions<T>` … 日常的な読み取り面は `GetValueAsync` と `OnChange`。
- `SaveAsync(patch => ...)` … 生成された Patch によるスパース保存。
- `OpenEditSessionAsync()` … 複数の変更をまとめて編集し、`CommitAsync` で確定。
- `ApplyPatchesAsync` + `StateSourcePatch` … Source 単位の明示的な複数書き込み。
- `StateWritePlan.For<T>().Route(...)` … 書き込みルーティング。
- `SourceKey<TModel>` と `options.Source(key)` … Source 単位の操作。

## 対象読者

.NET 開発者、とりわけ構成管理に悩みを感じている人向けです。
`Microsoft.Extensions.Configuration` との違いとしては、`IConfiguration` が読み取り志向であるのに対し、Configlue は独立した Source の合成、出所の調査、スパース保存に適している点が挙げられます。


---

# ===== opencode-go/glm-5.3 =====

# Configlue

**Make easy configuration management.**

Configlue は、アプリケーションの構成管理を丸ごと引き受ける .NET ライブラリです。複数の場所に散らばった構成を 1 つのモデルに **貼り合わせる(glue)** のが中心思想で、名前も configuration + glue に由来します。

- 動作要件: .NET 10 SDK 以降。C# の `LangVersion` はソースジェネレーターをサポートする必要があります(リポジトリは `preview` でビルドされています)。
- ライセンス: Apache-2.0
- 現状は「アーキテクチャの基盤」であり、`Configuration.Writable` の完全な置き換えではありません。

## 目次

- [なぜ Configlue か](#なぜ-configlue-か)
- [コアアーキテクチャ(6 つの概念)](#コアアーキテクチャ6-つの概念)
- [主な機能](#主な機能)
- [クイックスタート](#クイックスタート)
- [値の出所を確認する・疎な保存](#値の出所を確認する疎な保存)
- [パッケージ構成](#パッケージ構成)
- [既知の制限事項](#既知の制限事項)

## なぜ Configlue か

JSON ファイルを 1 つ読み書きするだけなら、数行のコードで済みます。しかし実際の構成管理は、こうした要件が積み重なっていきます。

- 構成は複数の場所に存在する。グローバル設定、ランタイムフォルダーごとの設定、環境変数、コマンドライン引数、暗号化されたクレデンシャル、企業ポリシーや HTTP API といったリモート管理。
- 書き換えた構成を、アプリを再起動せずに反映したい(変更通知)。
- 書き込み先を自動的に選びたい。環境変数から読んだ値への書き込みはエラーにすべき。
- 構成ファイルは人間が書く。コメントを消したくない。JSON Schema が欲しい。壊れたファイルにも対応したい。
- デフォルト値のままの値は書き出したくない(ただしユーザーが明示的に設定した `null` は尊重する)。
- 構成ファイルのバージョンアップ(旧形式から新形式への自動変換)をしたい。
- バックアップと自動クリーンアップ。
- 書き込みの安全性。原子性(クラッシュ時にも壊れない)、他プロセスとの競合検出と自動マージ、自動リトライ。

これらを全部自前で実装するのは骨の折れる仕事です。Configlue はその一式を引き受けます。

## コアアーキテクチャ(6 つの概念)

依存関係は一直線で、学ぶ順序も同じです。

```text
Resource (場所) → Codec (変換) → Source (提供) → Fragment (差分) → Options (ファサード)
                                                      ↘ Patch (編集フラグメント)
```

| 概念 | 一言でいうと | 例 |
| --- | --- | --- |
| Resource | バイトが存在する場所 | ファイル、ZIP エントリ、HTTP レスポンス、メモリ |
| Codec | バイトと値の相互変換 | JSON / XML / YAML の読み書き |
| Source | 論理的な提供(どのフィールドをどの優先度で) | 「ユーザー設定ファイルの `Server` 部分」 |
| Fragment | 存在を覚えている差分 | 「`Port` だけを持つ状態」 |
| Patch | 単一フィールドへの編集 | 「`Port` を 9000 にする」 |
| Options | アプリが触るファサード | 読み取り、保存、監視、説明、診断 |

**読み取り**: 各 Source が Resource からバイトを取得し、Codec がそれを Fragment に変換します。ランタイムは「存在する」フィールドだけを、優先度順にオーバーレイして 1 つのモデルに合成します。

**書き込み**: 逆向きです。アプリはごく普通のモデル値を編集します。内部ではその変更が Fragment の差分になり、`WriteRoute` / `WritePlan` が指定する Source だけに届きます。関係のない Source は変更されません。

- Fragment は「メンバーが存在しない」ことと「null / デフォルトとして存在する」ことを区別します。レイヤー合成で「未設定」が「デフォルト設定」を上書きすることはありません。
- Patch は生成された `TModel.Patch`(単一フィールド編集フラグメント)です。`Unset()` は書き込み先 Source の提供だけを取り下げ、より低い優先度の値を再び見えるようにします。
- `[ConfiglueMerge]` でメンバーごとのマージ挙動を変更できます(組み込み: `Append`、`Deep`、`Replace`、`SetUnion`。カスタム戦略も可)。コレクションのレイヤー合成と順序付けはここで決まります。

## 主な機能

- **複数ソース間の優先度マージ**: `Priority` が大きい Source が優先されます。`GetDetailsAsync` で「どの値がどこから来たか」を調べられます。
- **読み取り専用ソース**: 環境変数、コマンドライン、デフォルトの HTTP ソースは読み取り専用です。読み取り専用の値への書き込みは黙って無視されず、競合エラーになります。
- **プロジェクション / マウント**: 既存の Source を別のモデルに組み替える(プロジェクション)ことや、別の Source をネストしたパスに取り付ける(マウント、`AddMounted`)ことができます。
- **プリセット**: `UseCommonSources` が標準的なレイヤー構成(グローバル / ローカル / 環境変数など)を組み立てます。
- **疎な保存(sparse writes)**: 変更したフィールドだけが対象レイヤーに保存されます。デフォルト値のままのフィールドは書き出されません。
- **編集セッション**: `OpenEditSessionAsync` で複数の変更をまとめて適用します。`CommitAsync` まではメモリ上です。競合時はデフォルトで失敗しますが、`WriteConflictResolution.LastWriteWins` も選べます。
- **スキーマ移行 / ストレージ移行**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` で旧バージョンの構成を自動変換します。既存のファイルも Source として登録できます。
- **バックアップと復元**: `FileResource` がアトミックな書き込みとバックアップ世代の管理を提供します。デフォルトで `.bak` を 1 世代。`RestoreLatestBackupAsync` で復元します。
- **安全な書き込み**: 原子性、競合検出、リトライ。
- **セクション**: `JsonSectionResource` / XML 要素 / YAML マッピングで、ファイルの一部を独立した Resource として扱えます。書き込み時にはコメント、空白、クォート、スカラーのスタイルが保持されます。同じファイル内の独立したセクションは 1 回の物理書き込みにまとめられます。
- **ZIP / HTTP / S3 / Dapr**: `ZipEntryResource`、`Configlue.Resource.Http`(ETag による条件付き書き込みとポーリング)、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **JSON Schema 生成**: `Configlue.JsonSchema`。構成ファイルは人間が書くものだからです。
- **Native AOT 対応**: ソース生成された `JsonSerializerContext` を渡すと、トリミング / AOT 耐性が向上します。
- **Reactive 統合(任意)**: `Configlue.Extensions.Reactive`(System.Reactive 7.0.0)と `Configlue.Extensions.R3`(R3 1.3.1)。`ObserveChanges()`、`ObserveValues()`、`ObserveReloadFailures()`、`ObserveActiveValues()`、`ObserveActiveProfileNames()`。
- **DI 統合**: `Configlue.Extensions.DI`。Microsoft オプションのアダプターは `Configlue.Extensions.MSOptions`(`IOptions<T>` など。同期ゲッターは非同期ソースの読み取り中にブロックするため、非同期フローでは `GetValueAsync` を推奨)。
- **プロファイル / 動的オプション**: 名前付きオプションと永続プロファイルで、ランタイムをまとめて作成・削除できます。

### Microsoft.Extensions.Configuration との違い

`IConfiguration` は読み取り中心の API です。一方 Configlue は、独立したソース同士の合成、値の出所の確認、そして疎な保存に向いています。

## クイックスタート

次の内容で `example.cs` を保存し、`dotnet run example.cs` で実行します(.NET 10 以降)。

```csharp
#!/usr/bin/env dotnet
#:package Configlue@*

using Configlue;
using Configlue.Source.Presets;

// 1. 設定モデルを宣言。ジェネレーターが Fragment/Patch サポートを生成します。
[ConfiglueModel("SampleSetting", Version = 1)]
public partial class SampleSetting
{
    public string Name { get; set; } = "World";
    public int RunCount { get; set; }
    public bool DefaultValue { get; set; } = true;
}

// 2. プリセットのレイヤーを宣言。ここに列挙したソースだけが有効になります。
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);

// 3. オプション経由で読み書きします。
var options = context.GetOptions<SampleSetting>();
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 疎な編集: 変更したフィールドだけが対象レイヤーに保存されます。
await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue は変更していないので、対象レイヤーには保存されません。
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

## 値の出所を確認する・疎な保存

```csharp
var options = context.GetOptions<AppSettings>();
// 1. 現在値を取得(すべてのソースからマージされた値)
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 2. それぞれの値がどこから来たのかを確認
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

指定したメンバーだけを更新するパッチを保存します。`Unset()` はその Source の提供を取り除き、より低い優先度の Source に値を任せます。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

### その他の API

- `IReadOnlyOptions<T>` … 日常の読み取り面は `GetValueAsync` と `OnChange`。
- `SaveAsync(patch => ...)` … 生成された Patch による疎な保存。
- `OpenEditSessionAsync()` … 複数の編集をまとめて行い、`CommitAsync` で確定。
- `ApplyPatchesAsync` + `StateSourcePatch` … ソース単位を明示した複数書き込み。
- `StateWritePlan.For<T>().Route(...)` … 書き込みルーティング。
- `SourceKey<TModel>` と `options.Source(key)` … ソース単位の操作。

## パッケージ構成

インストールは `dotnet add package Configlue` から始め、必要な機能パッケージを追加します。

| パッケージ | 役割 |
| --- | --- |
| `Configlue` | ユーザー向けメタパッケージ(Core / DI / JSON プロバイダー / JSON Schema / HTTP リソース / 共通ソース / 環境変数ソース / ジェネレーター analyzer を同梱。実装アセンブリは持たない) |
| `Configlue.Abstraction` | 契約(provider / codec / resource / generated-model) |
| `Configlue.Core` | 解決と永続化のランタイム |
| `Configlue.Extensibility` | プロバイダー SDK |
| `Configlue.Generator` | Roslyn analyzer(疎なモデルサポートを生成) |
| `Configlue.Testing` | メモリ上のテストダブル |
| `Configlue.Provider.Json` / `.Xml` / `.Yaml` | 各形式のコーデック、セクションリソース、ファイル登録 |
| `Configlue.JsonSchema` | JSON Schema の生成とエクスポート |
| `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml` | 各種ソースとプリセット |
| `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip` | 各種リソース |
| `Configlue.Extensions.DI` / `.MSOptions` / `.R3` / `.Reactive` | DI・オプション・Reactive 統合 |
| `Configlue.Transformer.AES` | Resource と Codec の間のバイトを AES-GCM で暗号化・認証 |

## 既知の制限事項

- 異なる Resource にまたがる書き込みはアトミックではありません。
- Source の引退(retirement)は現在のオプションインスタンスに範囲が限定され、背後のデータはそのまま残ります。
- オプションランタイムのソース構成は固定です。

---

ライセンス: Apache-2.0


---

# ===== opencode-go/glm-5.3-flash =====

# Configlue

**Make easy configuration management.**

Configlue は、アプリケーションの設定管理を担う .NET ライブラリです。名前は configuration + glue に由来し、複数の場所に散らばった設定を 1 つのモデルへ **glue(接着)** するという発想が中心にあります。

> [!NOTE]
> 現在は「アーキテクチャの基盤」であり、`Configuration.Writable` の完全な置き換えではありません。

- **要件**: .NET 10 SDK 以降。C# の `LangVersion` がソース ジェネレーターを利用できる必要があります(リポジトリは `preview` でビルドしています)。
- **ライセンス**: Apache-2.0

## なぜ Configlue なのか

JSON ファイルの読み書き自体は数行で済みます。しかし現実には、要求は次のように積み上がります。

- 設定は複数の場所に存在します。グローバル設定、ランタイム フォルダーごとの設定、環境変数、コマンドライン引数、暗号化された資格情報、企業ポリシーや HTTP API によるリモート管理。
- 設定ファイルが書き換えられたら、アプリを再起動せずに反映してほしい(変更通知)。
- 書き込み先を自動的に選びたい。環境変数から読み取った値への書き込みはエラーにしてほしい。
- 設定ファイルは人間が書くものです。コメントを消したくない、JSON Schema をサポートしてほしい、壊れたファイルも扱いたい。
- 既定値のままの値は書き出したくない(ただしユーザーが明示的に設定した `null` は尊重する)。
- 設定ファイルをバージョンアップしたい(旧形式から新形式への自動変換)。
- バックアップと自動クリーンアップ。
- 書き込みの安全性。原子性(クラッシュしても破損しない)、他プロセスとの競合検出と自動マージ、自動リトライ。

これらをすべて自前で実装するのは面倒です。Configlue はその受け皿です。

`Microsoft.Extensions.Configuration`(`IConfiguration`)は読み取り専用に寄った設計です。Configlue は、独立した複数ソースの構成、値の由来(provenance)の調査、スパース書き込みに適しています。

## コア アーキテクチャ(6 つの概念)

依存関係は一直線であり、学習順序も同じです。

```text
Resource (場所) → Codec (変換) → Source (寄与) → Fragment (差分) → Options (facade)
                                                        ↘ Patch (編集フラグメント)
```

| 概念 | 一言で言うと | 例 |
| --- | --- | --- |
| Resource | バイトがどこに存在するか | ファイル、ZIP エントリ、HTTP レスポンス、メモリ |
| Codec | バイトと値の相互変換 | JSON / XML / YAML の読み書き |
| Source | 論理的な寄与(どのフィールドをどの優先度で) | 「ユーザー設定ファイルの `Server` 部分」 |
| Fragment | 存在を記憶する差分 | 「`Port` だけを持つ」状態 |
| Patch | 1 フィールドの編集 | 「`Port` を 9000 に設定する」 |
| Options | アプリから見える外観 | 読み取り、保存、監視、説明、診断 |

**読み取り**: 各 Source が Resource からバイトを取得し、Codec が Fragment に変換します。ランタイムは「存在する(present)」フィールドだけを優先度順にオーバーレイし、1 つのモデルへ合成します。

**書き込み**: その逆方向です。アプリは普通のモデル値を編集します。内部ではその変更が Fragment の差分となり、`WriteRoute` / `WritePlan` が名指した Source にだけ届きます。無関係な Source は変更されません。

- Fragment は「メンバーが欠落している」ことと「null / 既定値として存在する」ことを区別します。レイヤー合成では「未設定」が「既定値の設定」を上書きすることはありません。
- Patch は生成される `TModel.Patch`(1 フィールドの編集フラグメント)です。`Unset()` は書き込み先 Source の寄与だけを引き上げ、下位の優先度の値を再び表に出します。
- `[ConfiglueMerge]` でメンバーごとのマージ挙動を変更できます(組み込みは `Append`、`Deep`、`Replace`、`SetUnion`。カスタム戦略も許可)。コレクションのレイヤー合成と順序はここで決まります。

## クイックスタート

以下を `example.cs` に保存し、`dotnet run example.cs` で実行します(.NET 10 以降)。

```csharp
#!/usr/bin/env dotnet
#:package Configlue@*

using Configlue;
using Configlue.Source.Presets;

// 1. 設定モデルを宣言します。ジェネレーターが Fragment/Patch サポートを生成します。
[ConfiglueModel("SampleSetting", Version = 1)]
public partial class SampleSetting
{
    public string Name { get; set; } = "World";
    public int RunCount { get; set; }
    public bool DefaultValue { get; set; } = true;
}

// 2. プリセット レイヤーを宣言します。ここで列挙したソースだけが有効になります。
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);

// 3. options インスタンスを介して読み書きします。
var options = context.GetOptions<SampleSetting>();
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// スパース編集: 変更したフィールドだけがターゲット レイヤーに保存されます。
await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue は変更していないため、ターゲット レイヤーには保存されません。
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

## 値の由来の調査とスパース保存

```csharp
var options = context.GetOptions<AppSettings>();
// 1. 現在値を取得する(全ソースをマージした結果)
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 2. 各値がどこから来たのかを調べる
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

保存は、指定したメンバーだけを更新するパッチで行います。`Unset()` を呼ぶと、その Source の寄与が引き上げられ、下位の優先度の Source が値を提供できるようになります。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

その他の API:

- `IReadOnlyOptions<T>` … 日常的な読み取りの表面は `GetValueAsync` と `OnChange`。
- `SaveAsync(patch => ...)` … 生成された Patch によるスパース保存。
- `OpenEditSessionAsync()` … 複数の変更をまとめて編集し、`CommitAsync` で確定する。
- `ApplyPatchesAsync` + `StateSourcePatch` … ソースごとの明示的な複数書き込み。
- `StateWritePlan.For<T>().Route(...)` … 書き込みルーティング。
- `SourceKey<TModel>` と `options.Source(key)` … ソースごとの操作。

## 主な機能

- **複数ソース間の優先度マージ**: `Priority` の大きい Source が勝ちます。`GetDetailsAsync` で「どの値がどこから来たか」を調べられます。
- **読み取り専用ソース**: 環境変数、コマンドライン、既定の HTTP ソースは読み取り専用です。読み取り専用の値への書き込みは黙って無視されるのではなく、競合エラーを発生させます。
- **プロジェクション / マウント**: 既存の Source を別のモデルへ整形する(プロジェクション)、またはネストされたパスに独立した Source を接続する(マウント、`AddMounted`)ことができます。
- **プリセット**: `UseCommonSources` が標準的なレイヤー構成(グローバル/ローカル/環境変数など)を組み立てます。
- **スパース書き込み**: 変更したフィールドだけがターゲット レイヤーに保存されます。既定値のままのフィールドは書き込まれません。
- **編集セッション**: `OpenEditSessionAsync` は複数の変更をまとめて適用します。`CommitAsync` までメモリ内に保持されます。競合時は既定で失敗します。`WriteConflictResolution.LastWriteWins` も利用できます。
- **スキーマ移行 / ストレージ移行**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` による旧バージョン設定の自動変換。既存のファイルを Source として登録することもできます。
- **バックアップと復元**: `FileResource` がアトミック書き込みとバックアップ世代管理を提供します。既定は 1 世代の `.bak`。`RestoreLatestBackupAsync` で復元します。
- **安全な書き込み**: 原子性、競合検出、リトライ。
- **セクション**: `JsonSectionResource` / XML 要素 / YAML マッピングにより、ファイルの一部を独立した Resource として扱えます。書き込み時、コメント・空白・引用符・スカラーのスタイルは保持されます。同一ファイル内の独立したセクションは 1 回の物理書き込みにまとめられます。
- **ZIP / HTTP / S3 / Dapr**: `ZipEntryResource`、`Configlue.Resource.Http`(ETag 条件付き書き込みとポーリング)、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **JSON Schema 生成**: `Configlue.JsonSchema`。設定は人間が書くものだからです。
- **Native AOT サポート**: ソース生成の `JsonSerializerContext` を渡すことで、トリミング/AOT への耐性が向上します。
- **リアクティブ統合(オプション)**: `Configlue.Extensions.Reactive`(System.Reactive 7.0.0)と `Configlue.Extensions.R3`(R3 1.3.1)。`ObserveChanges()`、`ObserveValues()`、`ObserveReloadFailures()`、`ObserveActiveValues()`、`ObserveActiveProfileNames()`。
- **DI 統合**: `Configlue.Extensions.DI`。Microsoft options アダプターは `Configlue.Extensions.MSOptions`(`IOptions<T>` など。同期 getter は非同期ソースの読み取り中にブロックするため、非同期フローでは `GetValueAsync` を推奨)。
- **プロファイル / 動的 options**: 名前付き options と永続プロファイルにより、ランタイムを単位として作成・削除できます。

## パッケージ構成(主要なもの)

- `Configlue` … ユーザー向けメタパッケージ(Core / DI / JSON プロバイダー / JSON Schema / HTTP リソース / common sources / 環境変数ソース / ジェネレーター アナライザーをバンドル。実装アセンブリは自前で持ちません)。
- `Configlue.Abstraction` … 契約(プロバイダー/コーデック/リソース/生成モデル)。
- `Configlue.Core` … 解決と永続化のランタイム。
- `Configlue.Extensibility` … プロバイダー SDK。
- `Configlue.Extensions.DI` / `Configlue.Extensions.MSOptions` / `Configlue.Extensions.R3` / `Configlue.Extensions.Reactive`
- `Configlue.Generator` … Roslyn アナライザー(スパース モデル サポートを生成)。
- `Configlue.Testing` … インメモリのテスト ダブル。
- `Configlue.Provider.Json` / `.Xml` / `.Yaml` … 各フォーマット向けのコーデック、セクション リソース、ファイル登録。
- `Configlue.JsonSchema` … JSON Schema の生成とエクスポート。
- `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml`
- `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip`
- `Configlue.Transformer.AES` … Resource と Codec の間のバイトに対する AES-GCM の暗号化と認証。

## インストール

`dotnet add package Configlue` から始め、必要な機能パッケージを追加してください。

## 既知の制限

- 異なる Resource 間にまたがる書き込みはアトミックではありません。
- Source の引退は現在の options インスタンスにスコープされ、バッキング データはそのまま残ります。
- ソース集合は options ランタイムに対して固定です。

## ライセンス

Apache-2.0


---

# ===== opencode-go/gpt-6-luna =====

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


---

# ===== opencode-go/grok-4.7 =====

# Configlue

Configlue は、複数の場所に分かれたアプリケーション設定を一つのモデルにまとめ、読み取りと書き戻しを扱う .NET ライブラリです。名前は configuration と glue を重ねたものです。プロジェクトの標語は "Make easy configuration management." です。

設定ファイルを一つ読むだけなら、数行で足ります。運用が進むと、置き場所が先に増えます。グローバルな設定、実行フォルダーごとの設定、環境変数、コマンドライン引数、暗号化した資格情報、社内ポリシーや HTTP API のような遠隔の設定が、同時に存在します。

置き場所が増えると、満たしたい条件も増えます。ファイルの変更は再起動せずに反映したい。書き込み先は選び、環境変数から読んだ値へ書いたら失敗させたい。人が残したコメントは消したくない。既定値のままの項目はファイルに出したくないが、明示した `null` は残したい。形式の移行、バックアップ、落ちても壊れない書き込みまでを、アプリケーションごとに実装するのは手間です。

`Microsoft.Extensions.Configuration` の `IConfiguration` は、読み取りが中心です。Configlue は、独立した設定源を重ねること、値の出所を調べること、変えた項目だけを保存することに向いています。

利用には .NET 10 SDK 以降が必要です。C# の言語バージョンはソースジェネレーターに対応している必要があり、このリポジトリは `preview` でビルドしています。ライセンスは Apache-2.0 です。現時点の Configlue は、設定管理の仕組みを組むための土台です。`Configuration.Writable` の完全な置き換えではありません。

## 存在する項目だけを、優先度順に一つのモデルへ重ねる

バイト列の置き場所、形式の変換、どの項目を渡すかは、別の役割です。読み書きの差分と、アプリから使う入口は、その後ろに続きます。依存はこの順に並び、学ぶ順序も同じです。

```text
Resource（置き場所）→ Codec（変換）→ Source（渡す項目）→ Fragment（差分）→ Options（読み書きの入口）
                                                      ↘ Patch（一つの項目の編集）
```

各名前の意味は、次のとおりです。

| 名前 | 意味 | 例 |
| --- | --- | --- |
| Resource | バイト列が置いてある場所 | ファイル、ZIP 内のエントリ、HTTP の応答、メモリ |
| Codec | バイト列と値の相互変換 | JSON、XML、YAML の読み書き |
| Source | どの項目を、どの優先度で渡すか | ユーザー設定ファイルのうち `Server` の部分 |
| Fragment | 項目の有無を覚えた差分 | `Port` だけを持っている状態 |
| Patch | 一つの項目に対する編集 | `Port` を 9000 にする |
| Options | アプリが読み、保存し、監視する入口 | 読み取り、保存、監視、説明、診断 |

読み取りでは、各 Source が Resource からバイト列を取り、Codec がそれを Fragment にします。実行時は、項目が存在する分だけを、優先度の高い順に一つのモデルへ重ねます。この重なりの一段を、層と呼びます。優先度を表す `Priority` が大きい Source の値が採用されます。

Fragment は、項目が無いことと、`null` や既定値として項目があることを区別します。層を重ねるとき、未設定が「既定値として設定済み」を上書きすることはありません。利用者が明示した `null` は、未設定とは別に残ります。

コレクションをどう重ねるかは、メンバーごとに指定できます。属性は `[ConfiglueMerge]` で、組み込みの戦略は `Append`、`Deep`、`Replace`、`SetUnion` です。独自の戦略も追加できます。層を重ねたときの中身と順序は、この指定で決まります。

既にある Source は、別のモデルの形に読み替えることも、入れ子のパスへ別の Source を載せることもできます。後者の登録メソッドは `AddMounted` です。`UseCommonSources` は、グローバル、ローカル、環境変数といったよくある層の組み合わせを組み立てます。ここに挙げた Source だけが有効になります。

## 変えた項目だけを、書ける層へ戻す

書き込みは、読み取りと逆向きに進みます。アプリが編集するのは、普段使うモデルの値です。内部ではその変更が差分になり、書き込み経路が指した Source にだけ届きます。経路は `WriteRoute` と `WritePlan` で表します。関係のない Source は変更されません。

保存されるのは、変更した項目だけです。既定値のまま触っていない項目は、対象の層へ書き出されません。書き込み先は、この経路に沿って決まります。

環境変数、コマンドライン、既定の HTTP ソースは読み取り専用です。読み取り専用の値へ書こうとすると、書き込みは黙って無視されず、競合エラーになります。HTTP の Resource 自体は、後述のとおり条件付きの書き込みに対応します。読み取り専用なのは、既定の HTTP ソースです。

Patch は、ソースジェネレーターがモデルごとに作る `TModel.Patch` です。`Unset()` は、書き込み先の Source が渡していた値だけを外します。外したあとは、より優先度の低い Source の値が再び読めるようになります。

いくつかの変更をまとめて確定するときは、`OpenEditSessionAsync` で編集セッションを開きます。`CommitAsync` まではメモリ上の変更です。競合したときは既定で失敗します。後から書いた値を残す場合は、`WriteConflictResolution.LastWriteWins` を指定します。

## 人が書いたファイルの形を残して更新する

設定ファイルは人が書く前提です。JSON のセクション、XML の要素、YAML のマッピングは、ファイルの一部を独立した Resource として扱えます。JSON の場合の型は `JsonSectionResource` です。書き戻しても、コメント、空白、引用符、数値や文字列の表記は残ります。同じファイル内の独立したセクションは、物理的な書き込み 1 回にまとめられます。JSON Schema の生成と書き出しは `Configlue.JsonSchema` で行います。壊れたファイルへの対処も、この受け取りに含まれます。

ファイルへの書き込みは、途中で落ちてもファイルが壊れない形で行います。他プロセスとの競合検出、自動のマージ、失敗時の再試行も、書き込みの安全性に含まれます。バックアップの世代管理は `FileResource` が行い、既定では `.bak` を 1 世代残します。最新の世代へ戻すメソッドは `RestoreLatestBackupAsync` です。

設定の版を上げるときは、`[ConfigluePreviousVersion]` と `Fragment.FromPrevious` で、古い形式から新しい形式へ自動変換します。既存のファイルは Source として登録できます。

## バイト列の置き場所を、ファイルの外に広げる

Resource はファイルだけではありません。ZIP 内のエントリは `ZipEntryResource`、HTTP は `Configlue.Resource.Http`、S3 は `Configlue.Resource.S3`、Dapr は `Configlue.Resource.Dapr` です。HTTP では、ETag による条件付き書き込みとポーリングが使えます。Resource と Codec の間では、`Configlue.Transformer.AES` がバイト列を AES-GCM で暗号化し、認証します。

## モデルを宣言して、共通の層で読み書きする

導入は次のコマンドから始めます。足りない能力は、後述のパッケージを追加します。

```text
dotnet add package Configlue
```

`Configlue` は利用者向けのメタパッケージです。実装のアセンブリは持たず、Core、依存性注入、JSON のプロバイダー、JSON Schema、HTTP の Resource、共通ソース、環境変数ソース、ジェネレーターのアナライザーを同梱します。

次のコードを `example.cs` に保存し、.NET 10 以降で `dotnet run example.cs` を実行します。モデルは `partial` クラスとして宣言し、`[ConfiglueModel]` に名前と版を付けます。ジェネレーターが Fragment と Patch を作ります。読み書きは、`GetOptions` で得たインスタンスに対して行います。

```csharp
#!/usr/bin/env dotnet
#:package Configlue@*

using Configlue;
using Configlue.Source.Presets;

// 設定モデルを宣言する。ジェネレーターが Fragment と Patch を作る。
[ConfiglueModel("SampleSetting", Version = 1)]
public partial class SampleSetting
{
    public string Name { get; set; } = "World";
    public int RunCount { get; set; }
    public bool DefaultValue { get; set; } = true;
}

// 使う層を宣言する。ここに挙げた Source だけが有効になる。
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);

// Options を通して読み書きする。
var options = context.GetOptions<SampleSetting>();
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 変えた項目だけが対象の層に保存される。
await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue は変更していないので、対象の層には保存されない。
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

この例では `Name` と `RunCount` だけを変えています。`DefaultValue` は触っていないので、対象の層には保存されません。

## 値の出所を見てから、その層が渡した値を外す

重ねた結果だけでなく、各項目がどの Source から来たかも調べられます。`GetDetailsAsync` は、採用された Source の位置、その項目を編集できるか、各 Source の状態を返します。次の `AppSettings` は、利用側が宣言したモデルの例です。

```csharp
var options = context.GetOptions<AppSettings>();
// すべての Source を重ねた現在の値を取得する。
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 各値がどこから来たかを調べる。
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

ループは、その項目に値を渡した Source を順に示します。種類、位置、書き込めるか、状態が分かります。

`SaveAsync` に渡す Patch は、指定した項目だけを更新します。次の例では `Name` を更新し、`RunCount` については書き込み先が渡していた値を外します。外した項目は、より優先度の低い Source の値に戻ります。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

普段の読み取りは `IReadOnlyOptions<T>` で行い、使うメソッドは `GetValueAsync` と `OnChange` です。ソースを指定して複数箇所へ書くときは `ApplyPatchesAsync` と `StateSourcePatch`、経路の定義は `StateWritePlan.For<T>().Route(...)` です。特定の Source だけを操作するときは、`SourceKey<TModel>` と `options.Source(key)` を使います。

## ファイルの変更を、再起動せずに受け取る

ファイルが書き換わったら、再起動せずに変更通知で反映できます。購読を Reactive で書く場合は、任意の拡張を追加します。`Configlue.Extensions.Reactive` は System.Reactive 7.0.0、`Configlue.Extensions.R3` は R3 1.3.1 を使います。購読できるのは、変更、値、再読み込みの失敗、有効な値、有効なプロファイル名です。メソッド名は `ObserveChanges`、`ObserveValues`、`ObserveReloadFailures`、`ObserveActiveValues`、`ObserveActiveProfileNames` です。

## 依存性の注入と、名前を付けた実行時

依存性の注入は `Configlue.Extensions.DI` です。`Configlue.Extensions.MSOptions` は `IOptions<T>` など、Microsoft のオプションへつなぎます。同期の取得は、非同期の Source を読んでいるあいだブロックします。非同期の処理では `GetValueAsync` を使ってください。

名前を付けたオプションと、保存しておくプロファイルを使うと、実行時の単位をまとめて追加したり外したりできます。ネイティブコードへ事前コンパイルする Native AOT では、ソース生成した `JsonSerializerContext` を渡すと、未使用コードの削除や AOT への耐性が上がります。

## 同梱されない能力は、パッケージを追加する

`Configlue` に同梱されない能力は、次のパッケージから必要なものだけを追加します。

| パッケージ | 役割 |
| --- | --- |
| `Configlue.Abstraction` | プロバイダー、Codec、Resource、生成モデルの契約 |
| `Configlue.Core` | 値の解決と保存を行う中核 |
| `Configlue.Extensibility` | 独自のプロバイダーを作るための SDK |
| `Configlue.Generator` | 差分モデルを生成する Roslyn アナライザー |
| `Configlue.Testing` | テスト用の、メモリ上の代用品 |
| `Configlue.Provider.Json` / `.Xml` / `.Yaml` | 各形式の Codec、セクション、ファイル登録 |
| `Configlue.JsonSchema` | JSON Schema の生成と書き出し |
| `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml` | 環境変数、コマンドライン、共通の層 |
| `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip` | HTTP、ASP.NET Core、Dapr、S3、ZIP |
| `Configlue.Extensions.DI` / `.MSOptions` / `.R3` / `.Reactive` | 依存性注入、Microsoft のオプション、購読 |
| `Configlue.Transformer.AES` | Resource と Codec の間の AES-GCM |

## 書き込みとソース集合に残る制約

異なる Resource への書き込みには、すべてが成功するか、すべてが失敗するかという保証はありません。

ソースを外しても、外れるのは今のオプションのインスタンスだけです。保存先のデータは残ります。

一つの実行時について、ソースの集合は固定されています。



---

# ===== opencode-go/hy4-preview =====

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


---

# ===== opencode-go/kimi-k3 =====

# Configlue

> Make easy configuration management.

**Configlue** は、アプリケーションの設定管理をまるごと引き受ける .NET ライブラリです。複数の場所に散らばった設定を 1 つのモデルに「接着 (glue)」することを中心思想としており、名前は configuration + glue に由来します。

- **要件**: .NET 10 SDK 以降。C# の `LangVersion` はソースジェネレーターに対応していること (リポジトリでは `preview` でビルドしています)。
- **ライセンス**: Apache-2.0
- **現状**: 現時点では「アーキテクチャの土台」であり、`Configuration.Writable` の完全な代替ではありません。

## なぜ Configlue?

JSON ファイルの読み書き自体は数行で書けます。しかし実際には、次のような要求が積み上がっていきます。

- 設定は複数の場所に存在する: グローバル設定、実行フォルダーごとの設定、環境変数、コマンドライン引数、暗号化された資格情報、社内ポリシーや HTTP API によるリモート管理。
- 設定ファイルが書き換えられたら、アプリを再起動せずに反映したい (変更通知)。
- 書き込み先を自動で選びたい。環境変数から読んだ値への書き込みはエラーにしたい。
- 設定ファイルは人間が書くもの: コメントを消さないでほしい、JSON Schema 対応がほしい、壊れたファイルをハンドリングしたい。
- 値が既定値のままなら書き出さないでほしい (ただしユーザーが明示的に設定した `null` は尊重する)。
- 設定ファイルをバージョンアップしたい (旧形式から新形式への自動変換)。
- バックアップと自動クリーンアップ。
- 書き込みの安全性: アトミック性 (クラッシュしても壊れない)、他プロセスとの競合検出と自動マージ、自動リトライ。

これらをすべて自分で実装するのは骨が折れます。Configlue はそのためにあります。

### Microsoft.Extensions.Configuration との違い

`IConfiguration` は読み取り中心の設計です。一方 Configlue は、独立したソースの合成、値の出所の検査、スパース保存 (変更したフィールドだけを保存) に適した設計になっています。

## インストール

```text
dotnet add package Configlue
```

`Configlue` はユーザー向けのメタパッケージです (Core / DI / JSON プロバイダー / JSON Schema / HTTP リソース / 共通ソース / 環境変数ソース / ジェネレーター アナライザーを束ねており、自身の実装アセンブリーは持ちません)。必要に応じて機能パッケージを追加してください (「パッケージ構成」を参照)。

## クイックスタート

以下を `example.cs` に保存し、`dotnet run example.cs` で実行できます (.NET 10 以降)。

```csharp
#!/usr/bin/env dotnet
#:package Configlue@*

using Configlue;
using Configlue.Source.Presets;

// 1. 設定モデルを宣言します。ジェネレーターが Fragment/Patch サポートを生成します。
[ConfiglueModel("SampleSetting", Version = 1)]
public partial class SampleSetting
{
    public string Name { get; set; } = "World";
    public int RunCount { get; set; }
    public bool DefaultValue { get; set; } = true;
}

// 2. プリセットのレイヤーを宣言します。ここに列挙したソースだけが有効になります。
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);

// 3. options インスタンスを通して読み書きします。
var options = context.GetOptions<SampleSetting>();
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// スパース編集: 変更したフィールドだけが対象レイヤーに保存されます。
await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue は変更していないため、対象レイヤーには保存されません。
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

## コアアーキテクチャ (6 つの概念)

依存関係は一直線で、学習順序も同じです。

```text
Resource (場所) → Codec (変換) → Source (寄与) → Fragment (差分) → Options (ファサード)
                                                      ↘ Patch (編集フラグメント)
```

| 概念 | 一言で言うと | 例 |
| --- | --- | --- |
| Resource | バイト列の置き場所 | ファイル、ZIP エントリー、HTTP レスポンス、メモリー |
| Codec | バイト列と値の相互変換 | JSON / XML / YAML の読み書き |
| Source | 論理的な「寄与」(どのフィールドをどの優先度で) | 「ユーザー設定ファイルの `Server` 部分」 |
| Fragment | 存在を記憶する差分 | 「`Port` だけを持つ」状態 |
| Patch | 1 フィールドの編集 | 「`Port` を 9000 に設定する」 |
| Options | アプリから見えるファサード | 読み取り、保存、監視、説明、診断 |

**読み取り**: 各 Source が Resource からバイト列を取得し、Codec がそれを Fragment に変換します。ランタイムは「存在する」フィールドだけを優先度順に重ねて、1 つのモデルに合成します。

**書き込み**: 逆方向です。アプリは普通のモデル値を編集します。内部的には変更が Fragment の差分となり、`WriteRoute` / `WritePlan` が指名した Source にだけ届きます。無関係な Source は変更されません。

- Fragment は「メンバーが存在しない」と「null / 既定値として存在する」を区別します。レイヤー合成で「未設定」が「既定値に設定済み」を上書きすることはありません。
- Patch は生成される `TModel.Patch` (単一フィールドの編集フラグメント) です。`Unset()` は書き込み先 Source の寄与だけを取り下げ、低優先度の値を再び表面に出します。
- `[ConfiglueMerge]` でメンバーごとのマージ動作を変更できます (組み込み: `Append`、`Deep`、`Replace`、`SetUnion`。カスタム戦略も可能)。コレクションのレイヤー合成や順序はここで決まります。

## 主な機能

- **複数ソースの優先度マージ**: `Priority` が大きい Source が勝ちます。`GetDetailsAsync` で「どの値がどこから来たか」を検査できます。
- **読み取り専用ソース**: 環境変数、コマンドライン、既定の HTTP ソースは読み取り専用です。読み取り専用の値への書き込みは暗黙に無視されず、競合エラーになります。
- **プロジェクション / マウント**: 既存の Source を別のモデルに整形 (プロジェクション) したり、ネストしたパスに別の Source を取り付け (マウント、`AddMounted`) たりできます。
- **プリセット**: `UseCommonSources` が標準的なレイヤー構成 (グローバル / ローカル / 環境変数など) を組み立てます。
- **スパース書き込み**: 変更したフィールドだけが対象レイヤーに保存されます。既定値のままのフィールドは書き込まれません。
- **編集セッション**: `OpenEditSessionAsync` で複数の変更をまとめて適用できます。`CommitAsync` まではメモリー上の変更です。競合時は既定で失敗します。`WriteConflictResolution.LastWriteWins` も利用可能です。
- **スキーマ移行 / ストレージ移行**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` による旧バージョン設定の自動変換。既存ファイルを Source として登録できます。
- **バックアップと復元**: `FileResource` はアトミックな書き込みとバックアップ世代管理を提供します。既定で `.bak` を 1 世代保持し、`RestoreLatestBackupAsync` で復元できます。
- **安全な書き込み**: アトミック性、競合検出、リトライ。
- **セクション**: `JsonSectionResource` / XML 要素 / YAML マッピングにより、ファイルの一部を独立した Resource として扱えます。書き込み時にコメント、空白、引用符、スカラースタイルが保持されます。同一ファイル内の独立したセクションは 1 回の物理書き込みにバッチ処理されます。
- **ZIP / HTTP / S3 / Dapr**: `ZipEntryResource`、`Configlue.Resource.Http` (ETag 条件付き書き込みとポーリング)、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **JSON Schema 生成**: `Configlue.JsonSchema`。人間が設定を書くからこそ。
- **Native AOT 対応**: ソース生成された `JsonSerializerContext` を渡すことで、トリミング / AOT 耐性が向上します。
- **リアクティブ連携 (オプション)**: `Configlue.Extensions.Reactive` (System.Reactive 7.0.0) と `Configlue.Extensions.R3` (R3 1.3.1)。`ObserveChanges()`、`ObserveValues()`、`ObserveReloadFailures()`、`ObserveActiveValues()`、`ObserveActiveProfileNames()`。
- **DI 連携**: `Configlue.Extensions.DI`。Microsoft オプションアダプターは `Configlue.Extensions.MSOptions` (`IOptions<T>` など。同期ゲッターは非同期ソースの読み取り中にブロックするため、非同期フローでは `GetValueAsync` を推奨)。
- **プロファイル / 動的オプション**: 名前付きオプションと永続化プロファイルにより、ランタイムを単位として作成・削除できます。

### 既知の制限

- 異なる Resource にまたがる書き込みはアトミックではありません。
- Source の退避 (retirement) は現在の options インスタンスにスコープされ、背後のデータはそのまま残ります。
- ソース集合は options ランタイムごとに固定です。

## 値の出所の検査とスパース保存

```csharp
var options = context.GetOptions<AppSettings>();
// 1. 現在の値を取得 (全ソースをマージしたもの)
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 2. 各値の出所を検査
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

指定したメンバーだけを更新するパッチを保存できます。`Unset()` はその Source の寄与を取り除くため、より低い優先度の Source が値を提供できるようになります。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

その他の API:

- `IReadOnlyOptions<T>` … 日常的な読み取り面は `GetValueAsync` と `OnChange`。
- `SaveAsync(patch => ...)` … 生成された Patch によるスパース保存。
- `OpenEditSessionAsync()` … 複数の変更をまとめて編集し、`CommitAsync`。
- `ApplyPatchesAsync` + `StateSourcePatch` … ソースごとの明示的な複数書き込み。
- `StateWritePlan.For<T>().Route(...)` … 書き込みルーティング。
- `SourceKey<TModel>` と `options.Source(key)` … ソースごとの操作。

## パッケージ構成 (主なもの)

- `Configlue` … ユーザー向けメタパッケージ (Core / DI / JSON プロバイダー / JSON Schema / HTTP リソース / 共通ソース / 環境変数ソース / ジェネレーター アナライザーを束ねる。自身の実装アセンブリーは持たない)。
- `Configlue.Abstraction` … コントラクト (プロバイダー / コーデック / リソース / 生成モデル)。
- `Configlue.Core` … 解決と永続化のランタイム。
- `Configlue.Extensibility` … プロバイダー SDK。
- `Configlue.Extensions.DI` / `Configlue.Extensions.MSOptions` / `Configlue.Extensions.R3` / `Configlue.Extensions.Reactive`
- `Configlue.Generator` … Roslyn アナライザー (スパースモデルサポートを生成)。
- `Configlue.Testing` … インメモリーのテストダブル。
- `Configlue.Provider.Json` / `.Xml` / `.Yaml` … 各形式のコーデック、セクションリソース、ファイル登録。
- `Configlue.JsonSchema` … JSON Schema の生成とエクスポート。
- `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml`
- `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip`
- `Configlue.Transformer.AES` … Resource と Codec の間のバイト列に対する AES-GCM 暗号化と認証。

## ライセンス

Apache-2.0


---

# ===== opencode-go/longcat-2.5-preview-free =====

# Configlue

> **Make easy configuration management.**

Configlue は、.NET アプリケーションの設定管理を包括的にサポートするライブラリです。複数の場所に散らばった設定を「糊（グルー）」のように一つのモデルにまとめ上げます。名前のとおり、**Config**uration + **glue** に由来します。

## 特徴

- **複数ソースの優先度マージ** — グローバル設定、ローカル設定、環境変数、コマンドライン引数などを優先度付きで重ね合わせ、単一のモデルとして提供
- **読み取り専用ソース** — 環境変数・コマンドライン・HTTP ソースは読み取り専用。書き込み時に黙って無せず、コンフリクトエラーを発生
- **スパース書き込み** — 変更したフィールドのみをターゲット層に保存。デフォルト値のままのフィールドは書き出さない
- **編集セッション** — `OpenEditSessionAsync` で複数の変更をまとめて適用。`CommitAsync` までメモリ上に保持
- **スキーマ移行** — `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` で旧バージョン設定を自動変換
- **バックアップと復元** — `FileResource` がアトミック書き込みとバックアップ世代管理を提供。`RestoreLatestBackupAsync` で復元
- **セクション** — ファイル内の一部を独立したリソースとして扱う。コメント・空白・引用・スカラースタイルを保持
- **多様なプロバイダ** — JSON / XML / YAML、ZIP / HTTP / S3 / Dapr
- **JSON Schema 生成** — 人間が書く設定ファイルのためのスキーマ出力
- **リアクティブ / DI 統合** — `Configlue.Extensions.Reactive`、`Configlue.Extensions.R3`、`Configlue.Extensions.DI`、`Configlue.Extensions.MSOptions`

## 要件

- .NET 10 SDK 以降
- C#（ソースジェネレーターをサポートする `LangVersion`。リポジトリは `preview` でビルド）
- ライセンス: Apache-2.0

## インストール

```bash
dotnet add package Configlue
```

必要な機能パッケージを追加してください（例: `Configlue.Provider.Json`、`Configlue.Extensions.DI` など）。

## クイックスタート

`example.cs` として保存し、`dotnet run example.cs` で実行（.NET 10 以降）:

```csharp
#!/usr/bin/env dotnet
#:package Configlue@*

using Configlue;
using Configlue.Source.Presets;

// 1. 設定モデルを宣言。ジェネレーターが Fragment/Patch サポートを生成。
[ConfiglueModel("SampleSetting", Version = 1)]
public partial class SampleSetting
{
    public string Name { get; set; } = "World";
    public int RunCount { get; set; }
    public bool DefaultValue { get; set; } = true;
}

// 2. プリセット層を宣言。ここにリストされたソースのみが有効。
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);

// 3. Options インスタンス経由で読み書き。
var options = context.GetOptions<SampleSetting>();
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// スパース編集: 変更したフィールドのみがターゲット層に保存される。
await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue は変更されていないため、ターゲット層に保存されない。
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

## コアアーキテクチャ

6 つの概念が一直線に依存関係を持ち、学習順序も同じです:

```
Resource (場所) → Codec (変換) → Source (寄与) → Fragment (差分) → Options (ファサード)
                                                        ↘ Patch (編集フラグメント)
```

| 概念 | 一言で | 例 |
| --- | --- | --- |
| **Resource** | バイト列が存在する場所 | ファイル、ZIP エントリ、HTTP レスポンス、メモリ |
| **Codec** | バイト列と値の変換 | JSON / XML / YAML の読み書き |
| **Source** | 論理的な寄与（どのフィールドをどの優先度で） | 「ユーザー設定ファイルの `Server` 部分」 |
| **Fragment** | 存在を記憶する差分 | 「`Port` のみ」という状態 |
| **Patch** | 単一フィールドの編集 | 「`Port` を 9000 に設定」 |
| **Options** | アプリが見るファサード | 読取、保存、監視、説明、診断 |

### 読み取り

各 Source が Resource からバイト列を取得し、Codec が Fragment に変換。ランタイムは「存在する」フィールドのみを優先度順に重ね合わせ、単一のモデルを構築します。

### 書き込み

逆方向。アプリが通常のモデル値を編集すると、内部で Fragment 差分となり、`WriteRoute` / `WritePlan` が指定する Source のみに到達します。無関係な Source は変更されません。

- **Fragment** は「メンバーが存在しない」と「null/デフォルト値として存在」を区別。層の合成で「未設定」が「デフォルト値設定」を上書きすることはありません。
- **Patch** は生成された `TModel.Patch`（単一フィールド編集フラグメント）。`Unset()` は書き込み先 Source の寄与を取り消し、低優先度の値を再び露出させます。
- `[ConfiglueMerge]` でメンバーごとのマージ動作を変更（組み込み: `Append`、`Deep`、`Replace`、`SetUnion`、カスタム戦略も可能）。

## 値の出所の確認とスパース保存

```csharp
var options = context.GetOptions<AppSettings>();

// 1. 現在の値（全ソースからマージ）を取得
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 2. 各値の出所を確認
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

指定したメンバーのみを更新する Patch を保存。`Unset()` はその Source の寄与を取り消し、低優先度 Source が値を提供:

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

## 主な API

| API | 説明 |
| --- | --- |
| `IReadOnlyOptions<T>` | 日常の読み取り画面: `GetValueAsync`、`OnChange` |
| `SaveAsync(patch => ...)` | 生成された Patch によるスパース保存 |
| `OpenEditSessionAsync()` | 複数編集をまとめて `CommitAsync` |
| `ApplyPatchesAsync` + `StateSourcePatch` | ソースごとの明示的複数書き込み |
| `StateWritePlan.For<T>().Route(...)` | 書き込みルーティング |
| `SourceKey<TModel>` / `options.Source(key)` | ソースごとの操作 |

## パッケージ構成

| パッケージ | 内容 |
| --- | --- |
| `Configlue` | ユーザー向けメタパッケージ（Core / DI / JSON / JsonSchema / HTTP / 共通ソース / 環境変数 / ジェネレーターを同梱） |
| `Configlue.Abstraction` | コントラクト（プロバイダー / コーデック / リソース / 生成モデル） |
| `Configlue.Core` | 解決・永続化ランタイム |
| `Configlue.Extensibility` | プロバイダー SDK |
| `Configlue.Extensions.DI` | DI 統合 |
| `Configlue.Extensions.MSOptions` | Microsoft options アダプター（`IOptions<T>` 等） |
| `Configlue.Extensions.R3` | R3 リアクティブ統合 |
| `Configlue.Extensions.Reactive` | System.Reactive 統合 |
| `Configlue.Generator` | Roslyn アナライザー（スパースモデルサポート生成） |
| `Configlue.Testing` | インメモリテストダブル |
| `Configlue.Provider.Json` / `.Xml` / `.Yaml` | 各フォーマットのコーデック・セクションリソース・ファイル登録 |
| `Configlue.JsonSchema` | JSON Schema 生成・エクスポート |
| `Configlue.Source.Environment` / `.CommandLine` / `.Presets` | 環境変数・コマンドライン・プリセットソース |
| `Configlue.Resource.Http` / `.Dapr` / `.S3` / `.Zip` | リソースプロバイダー |
| `Configlue.Transformer.AES` | Resource と Codec 間の AES-GCM 暗号化・認証 |

## Microsoft.Extensions.Configuration との違い

`IConfiguration` は読み取り指向です。Configlue は独立したソースの合成、出所の確認、スパース保存に適しています。

## 既知の制限

- 異なる Resource 間の書き込みはアトミックではない
- Source の引退は現在の Options インスタンスに限定され、バックアップデータは保持される
- Options ランタイムのソースセットは固定


---

# ===== opencode-go/mimo-v2.6-flash =====

# Configlue

> Make easy configuration management.

Configlue は、アプリケーションの設定管理を引き受ける **.NET ライブラリ** です。名前は **config**uration + **glue** に由来し、複数の場所に散らばった設定を単一のモデルに「glue（接着）」することを目的としています。

- 要件: .NET 10 SDK 以降（ソースジェネレーターを使うため `LangVersion` は `preview`）
- ライセンス: Apache-2.0
- 現状は「アーキテクチャ上の土台」であり、`Configuration.Writable` の完全な代替ではありません

```text
Resource (所在) → Codec (変換) → Source (寄与) → Fragment (差分) → Options (外観)
                                                ↘ Patch (編集断片)
```

## 目次

- [なぜ Configlue なのか](#なぜ-configlue-なのか)
- [コアアーキテクチャ（6 つの概念）](#コアアーキテクチャ6-つの概念)
- [主な機能](#主な機能)
- [インストール](#インストール)
- [クイックスタート](#クイックスタート)
- [値の出所の確認とスパース保存](#値の出所の確認とスパース保存)
- [主要 API](#主要-api)
- [Microsoft.Extensions.Configuration との違い](#microsoftextensionsconfiguration-との違い)
- [既知の制限](#既知の制限)

## なぜ Configlue なのか

JSON ファイルを読み書きするだけなら数行で済みます。しかし実務では、要求が積み上がっていきます。

- **設定が複数の場所に存在する**: グローバル設定、実行フォルダーごとの設定、環境変数、コマンドライン引数、暗号化された認証情報、社内ポリシーや HTTP API といったリモート管理。
- **再起動なしの変更通知**: 設定ファイルが書き換えられたら、アプリを再起動せずに反映したい。
- **書き込み先の自動選択**: 環境変数から読んだ値への書き込みはエラーにしたい（黙って無視しない）。
- **人間が書く設定ファイル**: コメントを消さない、JSON Schema を欲しい、壊れたファイルにも対応したい。
- **デフォルト値は書き出したくない**: まだデフォルトのままなら保存しない（ただし、ユーザーが明示的に設定した `null` は尊重する）。
- **設定ファイルのバージョンアップ**: 旧形式から新形式への自動変換。
- **バックアップと自動クリーンアップ**。
- **書き込みの安全さ**: 原子性（クラッシュによる破損防止）、他プロセスとの競合検知と自動マージ、自動リトライ。

これらを自分で実装するのは面倒です。その動機が Configlue の出発点です。

## コアアーキテクチャ（6 つの概念）

依存は一直線に並んでおり、学習順序も同じです。

| 概念 | ひとことで | 例 |
| --- | --- | --- |
| **Resource** | バイトがどこにあるか | ファイル、ZIP エントリ、HTTP レスポンス、メモリ |
| **Codec** | バイトと値の変換 | JSON / XML / YAML の読み書き |
| **Source** | 論理的な寄与（どのフィールドをどの優先度で） | 「ユーザ設定ファイルの `Server` 部分」 |
| **Fragment** | 有無を記憶する差分 | 「`Port` だけがある」状態 |
| **Patch** | 1 フィールドの編集 | 「`Port` を 9000 にする」 |
| **Options** | アプリが見る外観 | 読み取り、保存、監視、説明、診断 |

**読み取り**: 各 Source が Resource からバイトを取り込み、Codec がそれを Fragment に変換します。ランタイムは「存在する」フィールドだけを優先度順に、単一のモデルへ重ね合わせます。

**書き込み**: その逆方向です。アプリは普通のモデル値を編集し、内部でそれが Fragment 差分に変換されて、`WriteRoute` / `WritePlan` が指名した Source だけに届きます。無関係な Source は変更されません。

- Fragment は「メンバーが無い」ことと「`null` / デフォルトとして存在する」ことを区別します。「未設定」が「デフォルトに設定済み」を上書きすることは、レイヤー合成でも起きません。
- Patch は生成される `TModel.Patch`（1 フィールドの編集断片）です。`Unset()` は書き込み先の Source の寄与だけを取り下げ、下優先の Source の値を再び露出させます。
- `[ConfiglueMerge]` でメンバーごとの合成挙動を変更できます（組み込み: `Append` / `Deep` / `Replace` / `SetUnion`、カスタム戦略も可）。コレクションのレイヤー合成と順序はここで決まります。

## 主な機能

- **複数ソースの優先度マージ**: `Priority` が大きい Source が勝ちます。`GetDetailsAsync` で「どの値がどこから来たか」を調べられます。
- **読み取り専用ソース**: 環境変数、コマンドライン、既定の HTTP ソースは読み取り専用です。読み取り専用の値への書き込みは黙って無視されず、競合エラーを送出します。
- **投影 / マウント**: 既存の Source を別のモデルに再整形（投影）したり、ネストしたパスに別 Source を取り付けたりできます（マウント、`AddMounted`）。
- **プリセット**: `UseCommonSources` が標準的なレイヤー構成（グローバル / ローカル / 環境変数など）を組み立てます。
- **スパース書き込み**: 変更したフィールドだけが対象レイヤーに保存されます。デフォルトのままのフィールドは書き出されません。
- **編集セッション**: `OpenEditSessionAsync` で複数の変更をまとめて適用し、`CommitAsync` までメモリ上に保持します。競合時は既定で失敗し、`WriteConflictResolution.LastWriteWins` も選べます。
- **スキーママイグレーション / ストレージマイグレーション**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` で旧バージョンの設定を自動変換します。既存ファイルをそのまま Source として登録できます。
- **バックアップと復元**: `FileResource` が原子的な書き込みとバックアップ世代管理を提供します。既定で `.bak` を 1 世代残し、`RestoreLatestBackupAsync` で復元します。
- **安全な書き込み**: 原子性、競合検知、リトライ。
- **セクション**: `JsonSectionResource` / XML 要素 / YAML マッピングにより、ファイルの一部分を独立した Resource として扱えます。書き込み時はコメント、空白、引用符、スカラー スタイルを保持します。同じファイル内の独立したセクションは 1 回の物理書き込みにまとめられます。
- **ZIP / HTTP / S3 / Dapr**: `ZipEntryResource`、`Configlue.Resource.Http`（ETag による条件付き書き込みとポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **JSON Schema 生成**: 設定は人間が書くものなので、`Configlue.JsonSchema` を用意しています。
- **Native AOT 対応**: ソースジェネレーターで生成した `JsonSerializerContext` を渡すと、トリミング / AOT 耐性が向上します。
- **リアクティブ統合（任意）**: `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）。`ObserveChanges()`、`ObserveValues()`、`ObserveReloadFailures()`、`ObserveActiveValues()`、`ObserveActiveProfileNames()`。
- **DI 統合**: `Configlue.Extensions.DI`。Microsoft options アダプターは `Configlue.Extensions.MSOptions`（`IOptions<T>` など）。同期 getter は非同期ソースの読み込み中にブロックするため、非同期のフローでは `GetValueAsync` を推奨します。
- **プロファイル / 動的 options**: 名前付き options と永続プロファイルにより、ランタイムを単位として作成・削除できます。

## インストール

```bash
dotnet add package Configlue
```

必要な機能のパッケージを追加します。

### パッケージ構成（主なもの）

- `Configlue` … ユーザー向けメタパッケージ（Core / DI / JSON プロバイダー / JSON Schema / HTTP リソース / 共通ソース / 環境変数ソース / ジェネレーター アナライザーを同梱。独自の実装アセンブリはありません）
- `Configlue.Abstraction` … 契約（provider / codec / resource / generated-model）
- `Configlue.Core` … 解決と永続化のランタイム
- `Configlue.Extensibility` … プロバイダー SDK
- `Configlue.Extensions.DI` / `Configlue.Extensions.MSOptions` / `Configlue.Extensions.R3` / `Configlue.Extensions.Reactive`
- `Configlue.Generator` … Roslyn アナライザー（スパースモデル対応を生成）
- `Configlue.Testing` … インメモリのテスト用ダブル
- `Configlue.Provider.Json` / `.Xml` / `.Yaml` … 各形式の codec、セクション resource、ファイル登録
- `Configlue.JsonSchema` … JSON Schema の生成とエクスポート
- `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml`
- `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip`
- `Configlue.Transformer.AES` … Resource と Codec の間のバイトを AES-GCM で暗号化・認証

## クイックスタート

以下を `example.cs` として保存し、.NET 10 以降で `dotnet run example.cs` を実行します。

```csharp
#!/usr/bin/env dotnet
#:package Configlue@*

using Configlue;
using Configlue.Source.Presets;

// 1. 設定モデルを宣言する。ジェネレーターが Fragment / Patch 対応を生成する。
[ConfiglueModel("SampleSetting", Version = 1)]
public partial class SampleSetting
{
    public string Name { get; set; } = "World";
    public int RunCount { get; set; }
    public bool DefaultValue { get; set; } = true;
}

// 2. プリセットのレイヤーを宣言する。ここに挙げたソースだけが有効になる。
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

// スパース編集: 変更したフィールドだけが対象レイヤーに保存される。
await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue は変更していないので、対象レイヤーには保存されない。
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

## 値の出所の確認とスパース保存

```csharp
var options = context.GetOptions<AppSettings>();
// 1. 現在の値を取得する（すべてのソースからマージ済み）
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

指定したメンバーだけを更新するパッチを保存できます。`Unset()` はその Source の寄与を取り下げ、下優先の Source に値を委ねます。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

## 主要 API

- `IReadOnlyOptions<T>` … 日常の読み取り面は `GetValueAsync` と `OnChange`
- `SaveAsync(patch => ...)` … 生成された Patch によるスパース保存
- `OpenEditSessionAsync()` … 複数をまとめて編集し、`CommitAsync`
- `ApplyPatchesAsync` + `StateSourcePatch` … ソース単位の明示的な複数書き込み
- `StateWritePlan.For<T>().Route(...)` … 書き込みルーティング
- `SourceKey<TModel>` と `options.Source(key)` … ソース単位の操作

## Microsoft.Extensions.Configuration との違い

`IConfiguration` は読み取り中心の API です。一方 Configlue は、独立したソースの合成、出所（provenance）の調査、そしてスパース保存に向いています。複数レイヤーを優先度で重ね、どの値がどこから来たかを問い、変更したフィールドだけを書き戻すといった用途では Configlue のモデルが合います。

## 既知の制限

- 異なる Resource をまたぐ書き込みは原子的ではありません。
- ソースの退役は現在の options インスタンスの範囲に限定され、裏側のデータは残ります。
- ソース集合は options ランタイムに対して固定です。

## ライセンス

Apache-2.0


---

# ===== opencode-go/mimo-v2.6-pro =====

I've reviewed the research notes and the benchmark harness. Here's my plan.

## Plan

**Deliverable:** a new file `README.md` in the working directory (`work/opencode-go-mimo-v2.6-pro/`), containing a Japanese README for Configlue. The harness collects any file created in that folder besides `context.md`, so that single file is the artifact. I'll also produce a short chat summary of the content (the harness captures stdout as well).

**Structure of the README** (mapped to the research memo):

1. **タイトル + タグライン** — `Configlue` / 「Make easy configuration management.」 + 名前の由来（configuration + glue）と一文要約
2. **Configlue とは** — 複数の場所に散らばった設定を1つのモデルに「グルー」する .NET ライブラリ。.NET 10 SDK 以降 / Apache-2.0 / 現状は「アーキテクチャ基盤」であり `Configuration.Writable` の完全な代替ではない、と明記
3. **なぜ Configlue か（解決する課題）** — メモ §2 の箇条書きを自然な日本語のリストに（複数ソース・変更通知・書き込み先の自動選択・人間が書く設定ファイル対応・スパース書き込み・バージョンアップ・バックアップ・書き込み安全性）
4. **コアアーキテクチャ** — `Resource → Codec → Source → Fragment → Options`（+ Patch）の依存図、6概念の表（日本語の説明 + 例）、読み取り/書き込みの流れ、Fragment の「未設定 vs null/default」区別、`[ConfiglueMerge]`
5. **主な機能** — メモ §4 の項目を過不足なく（優先度マージ / 読み取り専用ソース / プロジェクション・マウント / プリセット / スパース書き込み / 編集セッション / スキーマ移行 / バックアップ・復元 / セーフライト / セクション / ZIP・HTTP・S3・Dapr / JSON Schema / Native AOT / リアクティブ連携 / DI・MSOptions / プロファイル / 既知の制限）
6. **パッケージ構成** — メモ §5 の一覧 + `dotnet add package Configlue` から始める導入手順
7. **クイックスタート** — メモ §6 のサンプルコードをそのまま（C# のまま）掲載し、1〜3のコメントを日本語のセクション見出しで補足
8. **値の出所の確認とスパース保存** — メモ §7 の `GetDetailsAsync` サンプルと `Unset()` の説明、その他の API（`IReadOnlyOptions<T>` など）の簡潔な一覧
9. **既知の制限事項** — メモ §4 末尾の3点（他 Resource への書き込みは非アトミック等）
10. **ライセンス** — Apache-2.0

**トーン方針**（メモ §8 準拠）：.NET 開発者向け、技術的で簡潔、誇張なし。`Microsoft.Extensions.Configuration` との違い（読み取り重視の `IConfiguration` に対し、Configlue は独立ソースの合成・出所の追跡・スパース保存に向く）を導入部か機能の節に1段落で入れる。

**方針：**
- コードブロックは原文の C# サンプルをそのまま使い、コメントだけ自然な日本語のまま維持（既に日本語寄りの英語コメントがある箇所も一貫させる）
- 囲みコード・表は GFM 形式を維持
- 「不明なことは書かない」— メモにない API や数値を創作しない
- 不要なファイル（追加の .md 等）は作らない。出力は `README.md` のみ

質問が1点あります：ファイル名は **`README.md`**（日本語本文でよい）で確定してよいですか？それとも `README.ja.md` を希望されますか？（他のモデルの出力例には両方の命名が混在しています）


---

# ===== opencode-go/minimax-m3 =====

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


---

# ===== opencode-go/muse-spark-1.3-contributor =====

# Configlue

**Make easy configuration management.**

Configlue は、アプリケーションの構成管理を引き受ける .NET ライブラリです。複数の場所に散らばった構成をひとつのモデルに **glue（貼り合わせ）** するのが中心思想で、名前は configuration + glue に由来します。

- 要件: .NET 10 SDK 以降。C# の `LangVersion` はソースジェネレーターをサポートすること（リポジトリは `preview` でビルド）。
- ライセンス: Apache-2.0。
- 現状は「アーキテクチャの基盤」であり、`Configuration.Writable` の完全な置き換えではありません。

## なぜ Configlue か

JSON ファイルをひとつ読み書きするだけなら数行で済みます。しかし実際には、次のような要件が積み重なります。

- 構成は複数の場所に存在する: グローバル設定、ランタイムフォルダーごとの設定、環境変数、コマンドライン引数、暗号化されたクレデンシャル、企業ポリシーや HTTP API のようなリモート管理。
- 構成ファイルが書き換えられたら、アプリを再起動せずに反映したい（変更通知）。
- 書き込み先を自動で選びたい。環境変数から読んだ値への書き込みはエラーにすべき。
- 構成ファイルは人間が書く: コメントを消さない、JSON Schema が欲しい、壊れたファイルへの対応。
- デフォルト値のままの値は書き出さない（ただしユーザーが明示的に設定した `null` は尊重する）。
- 構成ファイルのバージョンアップ（旧形式から新形式への自動変換）。
- バックアップと自動クリーンアップ。
- 書き込みの安全性: 原子性（クラッシュしても壊れない）、他プロセスとの競合検出と自動マージ、自動リトライ。

これらをすべて自前で実装するのは手間のかかる仕事です。

## コアアーキテクチャ（6 つの概念）

依存関係は一直線で、学ぶ順序も同じです。

```text
Resource (場所) → Codec (変換) → Source (提供) → Fragment (差分) → Options (ファサード)
                                                        ↘ Patch (編集フラグメント)
```

| 概念 | 一言でいうと | 例 |
| --- | --- | --- |
| Resource | バイトが存在する場所 | ファイル、ZIP エントリ、HTTP レスポンス、メモリ |
| Codec | バイトと値の相互変換 | JSON / XML / YAML の読み書き |
| Source | 論理的な提供（どのフィールドをどの優先度で） | 「ユーザー設定ファイルの `Server` 部分」 |
| Fragment | 存在を覚えている差分 | 「`Port` だけを持つ状態」 |
| Patch | 単一フィールドへの編集 | 「`Port` を 9000 にする」 |
| Options | アプリが触るファサード | 読み取り、保存、監視、説明、診断 |

**読み取り**: 各 Source が Resource からバイトを取得し、Codec がそれを Fragment に変換します。ランタイムは「存在する」フィールドだけを優先度順にオーバーレイして、ひとつのモデルに合成します。

**書き込み**: 逆方向です。アプリは通常のモデル値を編集します。内部ではその変更が Fragment の差分になり、`WriteRoute` / `WritePlan` で指定された Source だけに届きます。関係のない Source は変更されません。

- Fragment は「メンバーが存在しない」と「null / デフォルトとして存在する」を区別します。レイヤー合成で「未設定」が「デフォルト設定」を上書きすることはありません。
- Patch は生成された `TModel.Patch`（単一フィールド編集フラグメント）です。`Unset()` は書き込み先 Source の提供だけを取り下げ、より優先度の低い値を再び見えるようにします。
- `[ConfiglueMerge]` でメンバーごとのマージ動作を変更できます（組み込み: `Append`、`Deep`、`Replace`、`SetUnion`。カスタム戦略も可）。コレクションのレイヤー合成と順序付けはここで決まります。

## 主な機能

- **複数ソース間の優先度マージ**: `Priority` の大きい Source が勝ちます。`GetDetailsAsync` で「どの値がどこから来たか」を調べられます。
- **読み取り専用ソース**: 環境変数、コマンドライン、デフォルトの HTTP ソースは読み取り専用です。読み取り専用の値への書き込みは黙って無視されず、競合エラーになります。
- **プロジェクション / マウント**: 既存の Source を別のモデルに組み替える（プロジェクション）ことや、別の Source をネストしたパスに取り付ける（マウント、`AddMounted`）ことができます。
- **プリセット**: `UseCommonSources` が標準的なレイヤー構成（グローバル / ローカル / 環境変数など）を組み立てます。
- **疎な書き込み**: 変更したフィールドだけが対象レイヤーに保存されます。デフォルト値のままのフィールドは書き出されません。
- **編集セッション**: `OpenEditSessionAsync` で複数の変更をまとめて適用します。`CommitAsync` まではメモリ上です。競合時はデフォルトで失敗しますが、`WriteConflictResolution.LastWriteWins` も選べます。
- **スキーマ移行 / ストレージ移行**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` で旧バージョンの構成を自動変換します。既存のファイルも Source として登録できます。
- **バックアップと復元**: `FileResource` がアトミックな書き込みとバックアップ世代管理を提供します。デフォルトで `.bak` を 1 世代。`RestoreLatestBackupAsync` で復元します。
- **安全な書き込み**: 原子性、競合検出、リトライ。
- **セクション**: `JsonSectionResource` / XML 要素 / YAML マッピングで、ファイルの一部を独立した Resource として扱えます。書き込み時にはコメント、空白、クォート、スカラーのスタイルが保持されます。同じファイル内の独立したセクションは 1 回の物理書き込みにまとめられます。
- **ZIP / HTTP / S3 / Dapr**: `ZipEntryResource`、`Configlue.Resource.Http`（ETag による条件付き書き込みとポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **JSON Schema 生成**: `Configlue.JsonSchema`。構成ファイルは人間が書くものだからです。
- **Native AOT 対応**: ソース生成された `JsonSerializerContext` を渡すと、トリミング / AOT 耐性が向上します。
- **Reactive 統合（任意）**: `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）。`ObserveChanges()`、`ObserveValues()`、`ObserveReloadFailures()`、`ObserveActiveValues()`、`ObserveActiveProfileNames()`。
- **DI 統合**: `Configlue.Extensions.DI`。Microsoft オプションのアダプターは `Configlue.Extensions.MSOptions`（`IOptions<T>` など。同期ゲッターは非同期ソースの読み取り中にブロックするため、非同期フローでは `GetValueAsync` を推奨）。
- **プロファイル / 動的オプション**: 名前付きオプションと永続プロファイルで、ランタイムをまとめて作成・削除できます。

### `Microsoft.Extensions.Configuration` との違い

`IConfiguration` は読み取り中心なのに対し、Configlue は独立したソースの合成、値の出所の確認、疎な保存に向いています。

### 既知の制限事項

- 異なる Resource にまたがる書き込みはアトミックではありません。
- Source の引退（retirement）は現在のオプションインスタンスに範囲が限定され、背後のデータはそのまま残ります。
- オプションランタイムのソース構成は固定です。

## クイックスタート

`example.cs` として保存し、`dotnet run example.cs` で実行します（.NET 10 以降）。

```csharp
#!/usr/bin/env dotnet
#:package Configlue@*

using Configlue;
using Configlue.Source.Presets;

// 1. 設定モデルを宣言。ジェネレーターが Fragment/Patch サポートを生成します。
[ConfiglueModel("SampleSetting", Version = 1)]
public partial class SampleSetting
{
    public string Name { get; set; } = "World";
    public int RunCount { get; set; }
    public bool DefaultValue { get; set; } = true;
}

// 2. プリセットのレイヤーを宣言。ここに列挙したソースだけが有効になります。
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);

// 3. オプション経由で読み書きします。
var options = context.GetOptions<SampleSetting>();
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 疎な編集: 変更したフィールドだけが対象レイヤーに保存されます。
await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue は変更していないので、対象レイヤーには保存されません。
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

## 値の出所を確認する・疎な保存

```csharp
var options = context.GetOptions<AppSettings>();
// 1. 現在値を取得（すべてのソースからマージされた値）
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 2. それぞれの値がどこから来たのかを確認
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

指定したメンバーだけを更新するパッチを保存します。`Unset()` はその Source の提供を取り除き、より優先度の低い Source に値を任せます。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

その他の API:

- `IReadOnlyOptions<T>` … 日常の読み取り面は `GetValueAsync` と `OnChange`。
- `SaveAsync(patch => ...)` … 生成された Patch による疎な保存。
- `OpenEditSessionAsync()` … 複数の編集をまとめて行い、`CommitAsync` で確定。
- `ApplyPatchesAsync` + `StateSourcePatch` … ソース単位を明示した複数書き込み。
- `StateWritePlan.For<T>().Route(...)` … 書き込みルーティング。
- `SourceKey<TModel>` と `options.Source(key)` … ソース単位の操作。

## パッケージ構成

インストールは `dotnet add package Configlue` から始め、必要な機能パッケージを追加します。

| パッケージ | 役割 |
| --- | --- |
| `Configlue` | ユーザー向けメタパッケージ（Core / DI / JSON プロバイダー / JSON Schema / HTTP リソース / 共通ソース / 環境変数ソース / ジェネレーター analyzer を同梱。実装アセンブリは持たない） |
| `Configlue.Abstraction` | 契約（provider / codec / resource / generated-model） |
| `Configlue.Core` | 解決と永続化のランタイム |
| `Configlue.Extensibility` | プロバイダー SDK |
| `Configlue.Extensions.DI` / `.MSOptions` / `.R3` / `.Reactive` | DI・オプション・Reactive 統合 |
| `Configlue.Generator` | Roslyn analyzer（疎なモデルサポートを生成） |
| `Configlue.Testing` | メモリ上のテストダブル |
| `Configlue.Provider.Json` / `.Xml` / `.Yaml` | 各形式のコーデック、セクションリソース、ファイル登録 |
| `Configlue.JsonSchema` | JSON Schema の生成とエクスポート |
| `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml` | 各種ソースとプリセット |
| `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip` | 各種リソース |
| `Configlue.Transformer.AES` | Resource と Codec の間のバイトを AES-GCM で暗号化・認証 |


---

# ===== opencode-go/qwen3.8-flash =====

# Configlue

> Make easy configuration management.

Configlue は、アプリケーションの設定管理を引き受ける .NET ライブラリです。あちこちに散在する設定を一つのモデルに **glue**（接着）することが中心のアイデアで、名前は configuration + glue に由来します。

- 要件: .NET 10 SDK 以降（ソースジェネレーターが使える `LangVersion` が必要。リポジトリは `preview` でビルド）
- ライセンス: Apache-2.0
- 現状は「アーキテクチャの基盤」であり、`Configuration.Writable` の完全な代替ではありません

## Why Configlue?

JSON ファイルを読み書きするだけなら数行で書けます。しかし実際の要件はこのように積み上がります:

- 設定が複数の場所に存在する: グローバル設定、実行フォルダごとの設定、環境変数、コマンドライン引数、暗号化された資格情報、企業ポリシーや HTTP API による遠隔管理
- 設定ファイルが書き換えられたら、アプリを再起動せずに反映したい（変更通知）
- 書き込み先を自動的に選び分けたい。環境変数から読み込んだ値への書き込みはエラーにしたい
- 設定ファイルは人間が書く: コメントを消したくない、JSON Schema が欲しい、壊れたファイルを扱いたい
- デフォルト値のままの項目は書き出したくない（ただしユーザーが明示的に設定した `null` は尊重する）
- 設定ファイルのバージョンアップ（旧形式から新形式への自動変換）
- バックアップと自動クリーンアップ
- 書き込みの安全性: 原子的性（クラッシュで破損しない）、他プロセスとの競合検出と自動マージ、自動リトライ

これらを全部自分で実装するのは面倒、というのが動機です。

### Microsoft.Extensions.Configuration との違い

`IConfiguration` は読み取り志向です。Configlue は、独立したソースの合成・値の出所の検査・稀疏（sparse）保存に向いています。

## 中核アーキテクチャ（6 つの概念）

依存関係は一直線になり、これが学習順序もそのままです:

```text
Resource (場所) → Codec (変換) → Source (寄与) → Fragment (差分) → Options (ファサード)
                                              ↘ Patch (一項目の編集)
```

| 概念 | 一言で | 例 |
| --- | --- | --- |
| Resource | バイト列がどこにあるか | ファイル、ZIP エントリ、HTTP レスポンス、メモリ |
| Codec | バイト列と値の変換 | JSON / XML / YAML の読み書き |
| Source | 論理的な寄与（どの項目をどの優先度で出すか） | 「ユーザー設定ファイルの `Server` の部分」 |
| Fragment | 存在を覚えている差分 | 「`Port` だけ持っている」状態 |
| Patch | 一項目の編集 | 「`Port` を 9000 にする」 |
| Options | アプリが見るファサード | 読み取り、保存、監視、説明、診断 |

**読み取り**: 各 Source が Resource からバイト列を取り、Codec が Fragment に変換します。ランタイムは「存在する」項目だけを優先度順に重ね合わせて、一つのモデルにします。

**書き込み**: 逆方向です。アプリは普通のモデル値を編集します。内部的には変更は Fragment の差分になり、`WriteRoute` / `WritePlan` が指定する Source にだけ届きます。無関係な Source は変更されません。

- Fragment は「メンバーが存在しない」と「null/デフォルトとして存在する」を区別します。レイヤー合成で「未設定」が「デフォルトに設定済み」を上書きすることは決してありません。
- Patch は生成される `TModel.Patch`（一項目の編集フラグメント）です。`Unset()` は書き込み先 Source の寄与だけを退避し、優先度の低い値を再び露出させます。
- `[ConfiglueMerge]` はメンバーごとのマージ挙動を変えます（組み込み: `Append`、`Deep`、`Replace`、`SetUnion`。カスタム戦略も可）。コレクションのレイヤー合成と順序はここで決まります。

## 主な機能

- **複数ソースの優先度マージ**: `Priority` が大きい Source が勝ります。`GetDetailsAsync` で「どの値がどこから来たか」を検査できます。
- **読み取り専用ソース**: 環境変数、コマンドライン、デフォルトの HTTP ソースは読み取り専用です。読み取り専用の値への書き込みは、黙って無視するのではなく競合エラーになります。
- **射影 / マウント**: 既存の Source を別のモデルに形変換できます（射影）。別の Source を入れ子のパスに取り付けられます（マウント、`AddMounted`）。
- **プリセット**: `UseCommonSources` が標準的なレイヤー構成（グローバル/ローカル/環境など）を組み立てます。
- **稀疏書き込み**: 変更した項目だけがターゲットレイヤーに保存されます。デフォルトのままの項目は書かれません。
- **編集セッション**: `OpenEditSessionAsync` で複数の変更をまとめて適用します。`CommitAsync` までメモリ内に留まります。競合時はデフォルトで失敗し、`WriteConflictResolution.LastWriteWins` も選べます。
- **スキーママイグレーション / ストレージマイグレーション**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` により旧バージョンの設定を自動変換します。既存のファイルを Source として登録できます。
- **バックアップと復元**: `FileResource` は原子的書き込みとバックアップ世代管理を提供します。デフォルトは `.bak` 一代で、`RestoreLatestBackupAsync` で復元できます。
- **安全な書き込み**: 原子的性、競合検出、リトライ。
- **セクション**: `JsonSectionResource` / XML 要素 / YAML マッピングで、ファイルの一部を独立した Resource として扱えます。書き込み時はコメント、空白、引用、スカラースタイルが保持されます。同一ファイル内の独立セクションは一つの物理書き込みにまとめられます。
- **ZIP / HTTP / S3 / Dapr**: `ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込みとポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **JSON Schema 生成**: 人間が設定を書くものなので、`Configlue.JsonSchema` で生成・出力できます。
- **Native AOT 対応**: ソース生成された `JsonSerializerContext` を渡すと、トリミング/AOT 耐性が向上します。
- **リアクティブ統合（オプション）**: `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）。`ObserveChanges()`、`ObserveValues()`、`ObserveReloadFailures()`、`ObserveActiveValues()`、`ObserveActiveProfileNames()`。
- **DI 統合**: `Configlue.Extensions.DI`。Microsoft Options アダプターは `Configlue.Extensions.MSOptions` にあります（`IOptions<T>` など。同期ゲッターは非同期ソースの読み取り中にブロックするため、非同期フローでは `GetValueAsync` を推奨）。
- **プロファイル / 動的オプション**: 名前付きオプションと永続プロファイルにより、ランタイムを単位として作成・削除できます。

## インストール

```bash
dotnet add package Configlue
```

必要な能力に応じてパッケージを追加します。

### パッケージ構成（主要なもの）

| パッケージ | 役割 |
| --- | --- |
| `Configlue` | ユーザー向けメタパッケージ（Core / DI / JSON プロバイダー / JSON Schema / HTTP リソース / 共通ソース / 環境ソース / ジェネレーター・アナライザーを同梱。独自の実装アセンブリは持たない） |
| `Configlue.Abstraction` | 契約（プロバイダー/コーデック/リソース/生成モデル） |
| `Configlue.Core` | 解決と永続化のランタイム |
| `Configlue.Extensibility` | プロバイダー SDK |
| `Configlue.Extensions.DI` / `.MSOptions` / `.R3` / `.Reactive` | DI・MSOptions・リアクティブ統合 |
| `Configlue.Generator` | Roslyn アナライザー（稀疏モデルサポートを生成） |
| `Configlue.Testing` | インメモリ test double |
| `Configlue.Provider.Json` / `.Xml` / `.Yaml` | 各形式のコーデック、セクションリソース、ファイル登録 |
| `Configlue.JsonSchema` | JSON Schema 生成と出力 |
| `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml` | ソースとプリセット |
| `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip` | リソース |
| `Configlue.Transformer.AES` | Resource と Codec の間のバイト列に対する AES-GCM 暗号化と認証 |

## クイックスタート

`example.cs` に保存して `dotnet run example.cs` で実行できます（.NET 10 以降）:

```csharp
#!/usr/bin/env dotnet
#:package Configlue@*

using Configlue;
using Configlue.Source.Presets;

// 1. 設定モデルを宣言。ジェネレーターが Fragment/Patch サポートを生成します。
[ConfiglueModel("SampleSetting", Version = 1)]
public partial class SampleSetting
{
    public string Name { get; set; } = "World";
    public int RunCount { get; set; }
    public bool DefaultValue { get; set; } = true;
}

// 2. プリセットレイヤーを宣言。ここに列挙したソースだけが有効になります。
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);

// 3. Options インスタンス経由で読み書き。
var options = context.GetOptions<SampleSetting>();
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 稀疏編集: 変更したフィールドだけがターゲットレイヤーに保存されます。
await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue は変更していないので、ターゲットレイヤーには保存されません。
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

## 値の出所の検査 / 稀疏保存

```csharp
var options = context.GetOptions<AppSettings>();
// 1. 現在の値（全ソースからマージ）を取得
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 2. 各値がどこから来たかを検査
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

指定したメンバーだけを更新する Patch を保存します。`Unset()` はその Source の寄与を取り除き、優先度の低い Source が値を提供できるようにします:

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

その他の API:

- `IReadOnlyOptions<T>` … 日常の読み取り面は `GetValueAsync` と `OnChange`
- `SaveAsync(patch => ...)` … 生成された Patch による稀疏保存
- `OpenEditSessionAsync()` … 複数箇所をまとめて編集し、`CommitAsync`
- `ApplyPatchesAsync` + `StateSourcePatch` … Source を明示した複数書き込み
- `StateWritePlan.For<T>().Route(...)` … 書き込みルーティング
- `SourceKey<TModel>` と `options.Source(key)` … Source 単位の操作

## 既知の制限

- 異なる Resource にまたがる書き込みは原子的ではありません
- Source の退役は現在の Options インスタンスのスコープであり、裏のデータはそのまま残ります
- ソースセットは Options ランタイムの間固定です

## ライセンス

Apache-2.0


---

# ===== opencode-go/qwen3.8-max =====

# Configlue

> Make easy configuration management.

Configlue は、アプリケーションの設定管理を引き受ける .NET ライブラリです。
グローバル設定・実行フォルダーごとの設定・環境変数・コマンドライン引数・暗号化された資格情報・HTTP API など、**複数の場所に散らばった設定をひとつのモデルに糊付け（glue）する**ことを中心思想としており、ライブラリ名は configuration + glue に由来します。

現在は「アーキテクチャ基盤」の段階であり、`Configuration.Writable` の完全な置き換えではありません。

## 目次

- [なぜ Configlue なのか](#なぜ-configlue-なのか)
- [コアアーキテクチャ（6 つの概念）](#コアアーキテクチャ6-つの概念)
- [主な機能](#主な機能)
- [インストールとパッケージ構成](#インストールとパッケージ構成)
- [クイックスタート](#クイックスタート)
- [値の出所の確認とスパース保存](#値の出所の確認とスパース保存)
- [その他の API](#その他の-api)
- [Microsoft.Extensions.Configuration との違い](#microsoftextensionsconfiguration-との違い)
- [既知の制限](#既知の制限)
- [動作環境とライセンス](#動作環境とライセンス)

## なぜ Configlue なのか

JSON ファイルを 1 つ読み書きするだけなら数行で済みます。しかし実際の運用では、要件が次のように積み上がっていきます。

- 設定が複数の場所に存在する（グローバル設定、実行フォルダーごとの設定、環境変数、コマンドライン引数、暗号化された資格情報、企業ポリシーや HTTP API によるリモート管理）
- 設定ファイルが書き換えられたら、アプリケーションを再起動せずに反映したい（変更通知）
- 書き込み先を自動的に選びたい。環境変数から読み取った値への書き込みはエラーにしたい
- 設定ファイルは人間が書くものである。コメントを消したくない、JSON Schema に対応したい、壊れたファイルを扱いたい
- 既定値のままの項目は書き出したくない（ただしユーザーが明示的に設定した `null` は尊重したい）
- 設定ファイルをバージョンアップしたい（旧形式から新形式への自動変換）
- バックアップと自動クリーンアップ
- 書き込みの安全性。原子性（クラッシュしても壊れない）、他プロセスとの競合検出と自動マージ、自動リトライ

これらをすべて自前で実装するのは骨が折れます。Configlue はその面倒を引き受けます。

## コアアーキテクチャ（6 つの概念）

依存関係は一直線で、学習順序も同じです。

```text
Resource (location) → Codec (conversion) → Source (contribution) → Fragment (diff) → Options (facade)
                                                        ↘ Patch (edit fragment)
```

| 概念 | ひとことで言うと | 例 |
| --- | --- | --- |
| Resource | バイト列がどこにあるか | ファイル、ZIP エントリ、HTTP レスポンス、メモリ |
| Codec | バイト列と値の変換 | JSON / XML / YAML の読み書き |
| Source | 論理的な寄与（どのフィールドをどの優先度で供給するか） | 「ユーザー設定ファイルの `Server` 部分」 |
| Fragment | 存在を記憶する差分 | 「`Port` だけを持っている」状態 |
| Patch | 単一フィールドの編集 | 「`Port` を 9000 にする」 |
| Options | アプリケーションから見えるファサード | 読み取り、保存、監視、説明、診断 |

**読み取り** では、各 Source が Resource からバイト列を取得し、Codec が Fragment に変換します。ランタイムは「存在する」フィールドだけを優先度順に重ね合わせ、ひとつのモデルに合成します。

**書き込み** はその逆方向です。アプリケーションはごく普通のモデル値を編集します。内部的にはその変更が Fragment の差分となり、`WriteRoute` / `WritePlan` で指名された Source にのみ到達します。関係のない Source は変更されません。

- Fragment は「メンバーが存在しない」ことと「`null` や既定値として存在する」ことを区別します。レイヤー合成で「未設定」が「既定値に設定済み」を上書きすることはありません。
- Patch は生成される `TModel.Patch`（単一フィールド編集用の Fragment）です。`Unset()` は書き込み先 Source の寄与だけを取り下げ、下位優先度の値を再び表出させます。
- `[ConfiglueMerge]` でメンバーごとのマージ挙動を変更できます（組み込みは `Append`、`Deep`、`Replace`、`SetUnion`。カスタム戦略も可能）。コレクションのレイヤー合成と順序はここで決まります。

## 主な機能

- **複数ソースの優先度マージ** — `Priority` の大きい Source が勝ちます。`GetDetailsAsync` で「どの値がどこから来たか」を検査できます。
- **読み取り専用ソース** — 環境変数、コマンドライン、既定の HTTP ソースは読み取り専用です。読み取り専用値への書き込みは黙って無視されるのではなく、競合エラーになります。
- **射影 / マウント** — 既存の Source を別のモデルに再構成（射影）したり、入れ子のパスに別の Source を取り付け（マウント、`AddMounted`）たりできます。
- **プリセット** — `UseCommonSources` が標準的なレイヤー構成（グローバル／ローカル／環境変数など）を組み立てます。
- **スパース書き込み** — 変更したフィールドだけが対象レイヤーに保存されます。既定値のままのフィールドは書き込まれません。
- **編集セッション** — `OpenEditSessionAsync` で複数の変更をまとめて適用します。`CommitAsync` まではメモリ内です。競合時は既定で失敗します。`WriteConflictResolution.LastWriteWins` も利用できます。
- **スキーマ移行 / ストレージ移行** — `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` により、旧バージョン設定の自動変換を行います。既存ファイルを Source として登録できます。
- **バックアップと復元** — `FileResource` が原子書き込みとバックアップ世代管理を提供します。既定では `.bak` を 1 世代保持し、`RestoreLatestBackupAsync` で復元します。
- **安全な書き込み** — 原子性、競合検出、リトライ。
- **セクション** — `JsonSectionResource` / XML 要素 / YAML マッピングにより、ファイルの一部を独立した Resource として扱えます。書き込み時にコメント、空白、クォート、スカラー形式を保持します。同一ファイル内の独立したセクションは 1 回の物理書き込みにまとめられます。
- **ZIP / HTTP / S3 / Dapr** — `ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込みとポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **JSON Schema 生成** — 設定を書くのは人間なので、`Configlue.JsonSchema` を用意しています。
- **Native AOT 対応** — ソース生成した `JsonSerializerContext` を渡すと、トリミングや AOT に対する耐性が向上します。
- **リアクティブ統合（オプション）** — `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）。`ObserveChanges()`、`ObserveValues()`、`ObserveReloadFailures()`、`ObserveActiveValues()`、`ObserveActiveProfileNames()`。
- **DI 統合** — `Configlue.Extensions.DI`。Microsoft オプションアダプターは `Configlue.Extensions.MSOptions`（`IOptions<T>` など）にあります。同期 getter は非同期ソースの読み込み中にブロックするため、非同期フローでは `GetValueAsync` を推奨します。
- **プロファイル / 動的オプション** — 名前付きオプションと永続プロファイルにより、ランタイムを一単位として作成・削除できます。

## インストールとパッケージ構成

```bash
dotnet add package Configlue
```

`Configlue` から始め、必要な機能パッケージを追加してください。

| パッケージ | 内容 |
| --- | --- |
| `Configlue` | 利用者を想定したメタパッケージ（Core / DI / JSON プロバイダー / JSON Schema / HTTP リソース / 共通ソース / 環境変数ソース / ジェネレーター分析器を同梱。実装アセンブリ自体は持ちません） |
| `Configlue.Abstraction` | 契約（プロバイダー／コーデック／リソース／生成モデル） |
| `Configlue.Core` | 解決と永続化のランタイム |
| `Configlue.Extensibility` | プロバイダー SDK |
| `Configlue.Extensions.DI` / `.MSOptions` / `.R3` / `.Reactive` | DI・Microsoft オプション・リアクティブ統合 |
| `Configlue.Generator` | Roslyn 分析器（スパースモデル支援を生成） |
| `Configlue.Testing` | インメモリのテストダブル |
| `Configlue.Provider.Json` / `.Xml` / `.Yaml` | 各形式のコーデック、セクションリソース、ファイル登録 |
| `Configlue.JsonSchema` | JSON Schema の生成とエクスポート |
| `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml` | 環境変数・コマンドライン・プリセット |
| `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip` | リモート・アーカイブ系リソース |
| `Configlue.Transformer.AES` | Resource と Codec の間でバイト列に対する AES-GCM の暗号化と認証 |

## クイックスタート

次のコードを `example.cs` として保存し、`dotnet run example.cs` で実行できます（.NET 10 以降）。

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

手順は次の 3 つです。

1. `[ConfiglueModel]` を付けた設定モデルを宣言します。ジェネレーターが Fragment / Patch 支援を生成します。
2. `ConfiglueApp.CreateContext` と `UseCommonSources` でレイヤーを宣言します。ここに挙げたソースだけが有効になります。
3. オプションインスタンス経由で読み書きします。`SaveAsync` に渡したパッチのうち、変更したフィールドだけが対象レイヤーに保存されます。

## 値の出所の確認とスパース保存

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

指定したメンバーだけを反映するパッチを保存できます。`Unset()` はその Source の寄与を削除し、下位優先度の Source が値を供給できるようにします。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

## その他の API

| API | 役割 |
| --- | --- |
| `IReadOnlyOptions<T>` | 日常の読み取り面。`GetValueAsync` と `OnChange` |
| `SaveAsync(patch => ...)` | 生成された Patch によるスパース保存 |
| `OpenEditSessionAsync()` | 複数変更をまとめて編集し、`CommitAsync` で確定 |
| `ApplyPatchesAsync` + `StateSourcePatch` | ソースを明示した複数書き込み |
| `StateWritePlan.For<T>().Route(...)` | 書き込みルーティング |
| `SourceKey<TModel>` と `options.Source(key)` | ソース単位の操作 |

## Microsoft.Extensions.Configuration との違い

`IConfiguration` は読み取り志向です。一方 Configlue は、独立したソースの合成、値の出所（来歴）の検査、スパース保存に向いています。設定を書き戻し、その書き込み先を意識する必要がある場面が Configlue の対象です。

## 既知の制限

- 異なる Resource をまたぐ書き込みは原子的ではありません。
- Source の退役は現在のオプションインスタンスの範囲に限られ、背後のデータはそのまま残ります。
- オプションランタイムのソース集合は固定です。

## 動作環境とライセンス

- **.NET 10 SDK 以降**
- C#（`LangVersion` はソースジェネレーターをサポートする必要があります。リポジトリは `preview` でビルドしています）
- License: **Apache-2.0**



---

# ===== opencode-go/space-bunny-free =====

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



---

# ===== opencode/big-pickle =====

# Configlue

**Make easy configuration management.**

Configlue は、アプリケーションの設定管理を引き継ぐ .NET ライブラリです。
読み書きを行うだけでなく、複数の場所に散らばった設定を 1 つのモデルに「接着（glue）」し、
どこから値が来たか、どこに書き戻すかを明示的に扱えるようにします。
ライブラリの名前は configuration と glue を合わせたものです。

- 動作環境: .NET 10 SDK 以降（C#。`LangVersion` はソースジェネレーターに対応している必要があります）
- ライセンス: Apache-2.0

> 現時点では「アーキテクチャの土台」としての位置づけです。`Configuration.Writable` の完全な置き換えではありません。

## なぜ Configlue なのか

JSON ファイルを読み書きするだけのコードは数行で書けます。
しかし実際に製品を作ると、要件は自然と積み重なります。

- 設定が複数の場所に存在する
  - グローバル設定／実行ディレクトリごとの設定
  - 環境変数、コマンドライン引数
  - 暗号化された資格情報
  - 企業ポリシーや HTTP API のようなリモート管理
- 設定ファイルを書き換えたときに、アプリを再起動せずに反映したい（変更通知）
- 書き込み先を自動的に決めたい。環境変数から読んだ値への書き込みはエラーにしたい
- 設定ファイルは人間が書くもの
  - コメントを消さない
  - JSON Schema による補完がほしい
  - 壊れたファイルを適切に扱いたい
- 初期値のままの値は書き出さない（ただし利用者が明示的に `null` にした場合は尊重する）
- 設定ファイルにバージョンを付け、古い形式から新しい形式へ自動変換したい
- バックアップと自動整理
- 書き込みの安全性
  - アトミックな書き込み（クラッシュしても壊れない）
  - 他プロセスとの競合検出と自動マージ
  - 自動リトライ

これらをすべて自前で実装する作業が面倒、というのが出発点です。

## 6 つの中心概念

依存関係は一続きで、学ぶ順番も同じです。

```text
Resource（格納場所） → Codec（変換） → Source（提供元） → Fragment（差分） → Options（ファサード）
                                                     ↘ Patch（編集する差分）
```

| 概念 | ひとことで言うと | 例 |
| --- | --- | --- |
| Resource | バイト列がどこにあるか | ファイル、ZIP エントリ、HTTP 応答、メモリ |
| Codec | バイト列と値の相互変換 | JSON / XML / YAML の読み書き |
| Source | 論理的な提供元（どのフィールドを、どの優先度で） | 「ユーザー設定ファイルの `Server` の部分」 |
| Fragment | 「存在したか」を記憶する差分 | 「`Port` だけを持つ」状態 |
| Patch | 1 フィールド分の編集 | 「`Port` を 9000 にする」 |
| Options | アプリケーションが見る顔 | 読み書き、監視、説明、診断 |

**読み取り**: 各 Source が Resource からバイト列を取得し、Codec がそれを Fragment に変換します。
ランタイムは「存在する」フィールドだけを優先度順に重ね合わせて 1 つのモデルにします。

**書き込み**: 逆方向です。アプリケーションは通常のモデル値を編集します。
内部ではその変更が Fragment の差分になり、`WriteRoute` / `WritePlan` で指定された Source にだけ届きます。
無関係な Source は変更されません。

- Fragment は「メンバーが存在しない」状態と「`null` や初期値として存在する」状態を区別します。
  レイヤーの合成では「未設定」が「初期値として設定済み」を上書きすることはありません。
- Patch は生成される `TModel.Patch`（1 フィールドの編集用 Fragment）です。
  `Unset()` は書き込み先 Source の提供内容だけを取り下げ、下位優先度の値を再び表に出させます。
- `[ConfiglueMerge]` はメンバー単位のマージ動作を変更します
  （組み込み: `Append` / `Deep` / `Replace` / `SetUnion`、カスタム戦略も可）。
  コレクションのレイヤー合成と順序もこの属性で決まります。

## 主な機能

- **複数 Source の優先度マージ**: `Priority` が大きい Source が勝ちます。
  `GetDetailsAsync` で「どの値はどこから来たか」を調べられます。
- **読み取り専用 Source**: 環境変数、コマンドライン、既定の HTTP Source は読み取り専用です。
  読み取り専用の値への書き込みは黙って無視されず、競合エラーになります。
- **射影 / マウント**: 既存の Source を別のモデルへ整形（射影）したり、
  入れ子のパスに別の Source を取り付けたり（マウント、`AddMounted`）できます。
- **プリセット**: `UseCommonSources` がグローバル／ローカル／環境変数などの標準的な合成を組み立てます。
- **疎（スパース）な保存**: 変更したフィールドだけが対象のレイヤーに保存されます。
  初期値のまま残ったフィールドは書き出されません。
- **編集セッション**: `OpenEditSessionAsync` で複数の変更をまとめて適用します。
  `CommitAsync` までメモリ上にとどまり、競合時は既定で失敗します
  （`WriteConflictResolution.LastWriteWins` も選べます）。
- **スキーマ移行 / ストレージ移行**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` により、
  旧バージョンの設定を自動変換します。既存ファイルを Source として登録することもできます。
- **バックアップと復元**: `FileResource` はアトミックな書き込みと世代管理を備えています。
  既定で 1 世代の `.bak` を残し、`RestoreLatestBackupAsync` で復元できます。
- **安全な書き込み**: アトミック性、競合検出、リトライ。
- **セクション**: `JsonSectionResource` / XML 要素 / YAML マッピングにより、ファイルの一部を独立した Resource として扱えます。
  書き込み時にコメント・空白・クォート・スカラー表記は保持されます。
  同じファイル内の独立したセクションは 1 回の物理的な書き込みにまとめられます。
- **ZIP / HTTP / S3 / Dapr**: `ZipEntryResource`、`Configlue.Resource.Http`（ETag による条件付き書き込みとポーリング）、
  `Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **JSON Schema の生成**: 設定は人間が書くものなので `Configlue.JsonSchema` で生成・出力します。
- **Native AOT 対応**: ソース生成した `JsonSerializerContext` を渡すと、トリミング／AOT への耐性が上がります。
- **リアクティブ連携（任意）**: `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と
  `Configlue.Extensions.R3`（R3 1.3.1）。
  `ObserveChanges()`、`ObserveValues()`、`ObserveReloadFailures()`、`ObserveActiveValues()`、`ObserveActiveProfileNames()`。
- **DI 連携**: `Configlue.Extensions.DI`。
  `Configlue.Extensions.MSOptions` に Microsoft options 用のアダプタ（`IOptions<T>` など）があります
  （同期ゲッターは非同期 Source の読み取り中にブロックするため、非同期フローでは `GetValueAsync` の利用を推奨します）。
- **プロファイル / 動的 options**: 名前付き options と永続プロファイルにより、ランタイムをまとめて作成・破棄できます。

## インストール

```bash
dotnet add package Configlue
```

`Configlue` はユーザー向けのメタパッケージです（実装アセンブリ自体は持たず、下列をまとめて取り込みます）。
必要な機能だけを追加してください。

| パッケージ | 役割 |
| --- | --- |
| `Configlue` | メタパッケージ（Core / DI / JSON プロバイダー / JSON Schema / HTTP リソース / 共通 Source / 環境変数 Source / ジェネレーター解析器） |
| `Configlue.Abstraction` | 契約（プロバイダー / Codec / Resource / 生成モデル） |
| `Configlue.Core` | 解決と永続化のランタイム |
| `Configlue.Extensibility` | プロバイダー SDK |
| `Configlue.Extensions.DI` / `.MSOptions` / `.R3` / `.Reactive` | 各フレームワーク・仕様との統合 |
| `Configlue.Generator` | Roslyn 解析器（疎なモデルサポートを生成） |
| `Configlue.Testing` | インメモリのテストダブル |
| `Configlue.Provider.Json` / `.Xml` / `.Yaml` | 各形式の Codec、セクションリソース、ファイル登録 |
| `Configlue.JsonSchema` | JSON Schema の生成と出力 |
| `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml` | 入力元の追加 |
| `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip` | 配置先の追加 |
| `Configlue.Transformer.AES` | Resource と Codec の間のバイト列に対する AES-GCM 暗号化と認証 |

## クイックスタート

以下の内容を `example.cs` として保存し、.NET 10 以降で `dotnet run example.cs` を実行します。

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

// 2. プリセットのレイヤーを宣言します。ここで挙げた Source だけが有効になります。
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

// 疎な編集: 変更したフィールドだけが対象レイヤーに保存されます。
await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue は変更していないので、対象レイヤーには保存されません。
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

## 値の取得元を確認する / 疎な保存

```csharp
var options = context.GetOptions<AppSettings>();
// 1. 現在の値を取得する（全 Source をマージした結果）
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

指定したメンバーだけを更新する Patch を保存します。
`Unset()` はその Source の提供内容を取り除き、下位優先度の Source に値を委ねます。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

## 主な API

- `IReadOnlyOptions<T>` … 日常的な読み取り面は `GetValueAsync` と `OnChange` です。
- `SaveAsync(patch => ...)` … 生成された Patch による疎な保存。
- `OpenEditSessionAsync()` … 複数をまとめて編集し、`CommitAsync` で確定します。
- `ApplyPatchesAsync` + `StateSourcePatch` … Source を明示した複数書き込み。
- `StateWritePlan.For<T>().Route(...)` … 書き込みルーティング。
- `SourceKey<TModel>` と `options.Source(key)` … Source 単位の操作。

## Microsoft.Extensions.Configuration との違い

`IConfiguration` は読み取りを中心とした Facade です。
一方 Configlue は、独立した Source の合成、値の取得元の可視化、疎な保存と書き込み先の選択を
対象とした API 群で、「どの値がどこから来たか」「どこに書き戻すか」をアプリケーション側で
把握できることを重視します。

## 既知の制限

- 異なる Resource をまたぐ書き込みはアトミックではありません。
- Source の削除（retirement）は現在の options インスタンスにスコープされ、
  背後のデータはそのまま残ります。
- 1 つの options ランタイムに対して Source 集合は固定です。

## ライセンス

Apache-2.0



---

# ===== opencode/ling-3.0-flash-fin-free =====





---

# ===== opencode/longcat-2.5-preview-free =====

# Configlue

**Make easy configuration management.**

Configlue は、.NET アプリケーションの設定管理を引き受けるライブラリです。複数の場所に散らばった設定を「糊（グルー）」のように一つのモデルにまとめ上げます。名前のとおり、configuration + glue に由来します。

## 必要なもの

- .NET 10 SDK 以降
- C#（ソースジェネレーターをサポートする `LangVersion`。リポジトリは `preview` でビルド）
- ライセンス: Apache-2.0

## なぜ Configlue なのか

JSON ファイルの読み書きは数行で書けます。しかし実際には、次のような要求が積み上がります。

- 設定が複数の場所に存在する: グローバル設定、実行時フォルダごとの設定、環境変数、コマンドライン引数、暗号化された認証情報、企業ポリシーや HTTP API などのリモート管理
- 設定ファイルの書き換えをアプリの再起動なしに反映したい（変更通知）
- 書き込み先を自動的に選びたい。環境変数から読んだ値への書き込みはエラーにすべき
- 設定ファイルは人間が書く: コメントを消さない、JSON Schema のサポート、壊れたファイルの処理
- 値がデフォルトのままなら書き出さない（ただしユーザーが明示的に設定した `null` は尊重する）
- 設定ファイルのバージョンアップ（旧フォーマットからの自動変換）
- バックアップと自動クリーンアップ
- 書き込みの安全性: アトミック性（クラッシュ時の破損防止）、他プロセスとの競合検出と自動マージ、自動リトライ

これらをすべて自分で実装するのは退屈な作業です。Configlue がその負担を軽減します。

## コアアーキテクチャ（6 つの概念）

依存関係は一直線をなし、学習順序も同じです。

```text
Resource（場所） → Codec（変換） → Source（寄与） → Fragment（差分） → Options（ファサード）
                                                        ↘ Patch（編集フラグメント）
```

| 概念 | 一言で | 例 |
| --- | --- | --- |
| Resource | バイトが存在する場所 | ファイル、ZIP エントリ、HTTP レスポンス、メモリ |
| Codec | バイトと値の変換 | JSON / XML / YAML の読み書き |
| Source | 論理的な寄与（どのフィールドをどの優先度で） | 「ユーザー設定ファイルの `Server` 部分」 |
| Fragment | 存在を記憶する差分 | 「`Port` のみ」という状態 |
| Patch | 単一フィールドの編集 | 「`Port` を 9000 に設定」 |
| Options | アプリが見るファサード | 読取、保存、監視、説明、診断 |

**読み取り**: 各 Source が Resource からバイトを取得し、Codec が Fragment に変換します。ランタイムは「存在する」フィールドのみを優先順位順に重ね、一つのモデルに合成します。

**書き込み**: 逆方向です。アプリは通常のモデル値を編集します。内部的には変更が Fragment 差分となり、`WriteRoute` / `WritePlan` が指定する Source のみに到達します。無関係な Source は変更されません。

- Fragment は「メンバーが存在しない」ことと「null/デフォルトとして存在すること」を区別します。レイヤー合成では「未設定」が「デフォルト設定済み」を上書きすることはありません。
- Patch は生成された `TModel.Patch`（単一フィールド編集フラグメント）です。`Unset()` は書き込み先 Source の寄与を取り消し、優先度の低い値が再び見えるようにします。
- `[ConfiglueMerge]` でメンバーごとのマージ動作を変更できます（組み込み: `Append`、`Deep`、`Replace`、`SetUnion`、カスタム戦略も可能）。コレクションレイヤーの合成と順序はここで決まります。

## 主な機能

- **複数ソース間の優先度マージ**: `Priority` が大きい Source が優先されます。`GetDetailsAsync` で「どの値がどこから来たか」を確認できます。
- **読み取り専用ソース**: 環境変数、コマンドライン、デフォルトの HTTP ソースは読み取り専用です。読み取り専用値への書き込みは無視せず、競合エラーを発生させます。
- **プロジェクション / マウント**: 既存の Source を別のモデルに変形させたり（プロジェクション）、ネストしたパスに別の Source をアタッチしたりできます（マウント、`AddMounted`）。
- **プリセット**: `UseCommonSources` が標準的なレイヤー構成（グローバル/ローカル/環境変数など）を組み立てます。
- **スパース書き込み**: 変更したフィールドのみがターゲットレイヤーに保存されます。デフォルトのままのフィールドは書き出されません。
- **編集セッション**: `OpenEditSessionAsync` で複数の変更をまとめて適用します。`CommitAsync` まではメモリ内で保持されます。競合時はデフォルトで失敗し、`WriteConflictResolution.LastWriteWins` も利用可能です。
- **スキーマ移行 / ストレージ移行**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` により、旧バージョンの設定を自動変換します。既存ファイルを Source として登録できます。
- **バックアップと復元**: `FileResource` はアトミック書き込みとバックアップ世代管理を提供します。デフォルトで 1 世代の `.bak` を保持し、`RestoreLatestBackupAsync` で復元できます。
- **安全な書き込み**: アトミック性、競合検出、リトライ。
- **セクション**: `JsonSectionResource` / XML 要素 / YAML マッピングにより、ファイルの一部を独立した Resource として扱えます。書き込み時、コメント、空白、引用符、スカラースタイルは保持されます。同一ファイル内の独立セクションは 1 回の物理書き込みにまとめられます。
- **ZIP / HTTP / S3 / Dapr**: `ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込みとポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **JSON Schema 生成**: `Configlue.JsonSchema`。設定は人間が書くものだからです。
- **Native AOT 対応**: ソース生成された `JsonSerializerContext` を渡すことで、トリミング/AOT 耐性が向上します。
- **リアクティブ統合（任意）**: `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）および `Configlue.Extensions.R3`（R3 1.3.1）。`ObserveChanges()`、`ObserveValues()`、`ObserveReloadFailures()`、`ObserveActiveValues()`、`ObserveActiveProfileNames()`。
- **DI 統合**: `Configlue.Extensions.DI`。Microsoft options アダプターは `Configlue.Extensions.MSOptions`（`IOptions<T>` など）。同期ゲッターは非同期ソースの読み取り中にブロックするため、非同期フローでは `GetValueAsync` を推奨します。
- **プロファイル / 動的オプション**: 名前付きオプションと永続プロファイルにより、実行時を単位として作成・削除できます。
- **既知の制限**: 異なる Resource を跨ぐ書き込みはアトミックではありません。Source の廃止は現在のオプションインスタンスに限定され、基盤データは残ります。ソースセットはオプションランタイムに対して固定されます。

## パッケージ構成（主なもの）

- `Configlue` … ユーザー向けメタパッケージ（Core / DI / JSON プロバイダー / JSON Schema / HTTP リソース / コモンソース / 環境変数ソース / ジェネレーターアナライザーを同梱。実装アセンブリは持たない）
- `Configlue.Abstraction` … コントラクト（プロバイダー/コーデック/リソース/生成モデル）
- `Configlue.Core` … 解決と永続化のランタイム
- `Configlue.Extensibility` … プロバイダー SDK
- `Configlue.Extensions.DI` / `Configlue.Extensions.MSOptions` / `Configlue.Extensions.R3` / `Configlue.Extensions.Reactive`
- `Configlue.Generator` … Roslyn アナライザー（スパースモデルサポートを生成）
- `Configlue.Testing` … インメモリテストダブル
- `Configlue.Provider.Json` / `.Xml` / `.Yaml` … 各フォーマットのコーデック、セクションモソース、ファイル登録
- `Configlue.JsonSchema` … JSON Schema 生成とエクスポート
- `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml`
- `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip`
- `Configlue.Transformer.AES` … Resource と Codec の間のバイト列に対する AES-GCM 暗号化と認証

インストールは `dotnet add package Configlue` から始めてください。必要な機能パッケージを追加してください。

## クイックスタート

`example.cs` として保存し、`dotnet run example.cs` で実行します（.NET 10 以降）:

```csharp
#!/usr/bin/env dotnet
#:package Configlue@*

using Configlue;
using Configlue.Source.Presets;

// 1. 設定モデルを宣言。ジェネレーターが Fragment/Patch サポートを生成。
[ConfiglueModel("SampleSetting", Version = 1)]
public partial class SampleSetting
{
    public string Name { get; set; } = "World";
    public int RunCount { get; set; }
    public bool DefaultValue { get; set; } = true;
}

// 2. プリセットレイヤーを宣言。ここにリストされたソースのみが有効。
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);

// 3. オプションインスタンス経由で読み書き。
var options = context.GetOptions<SampleSetting>();
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// スパース編集: 変更したフィールドのみがターゲットレイヤーに保存される。
await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue は変更していないので、ターゲットレイヤーには保存されない。
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

## 値の出所の確認 / スパース保存

```csharp
var options = context.GetOptions<AppSettings>();
// 1. 現在の値を取得（全ソースからマージ）
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 2. 各値の出所を確認
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

指定したメンバーのみを更新する Patch を保存します。`Unset()` はその Source の寄与を取り消し、優先度の低い Source が値を提供できるようにします:

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

その他の API:
- `IReadOnlyOptions<T>` … 日常的な読み取り画面は `GetValueAsync` と `OnChange`
- `SaveAsync(patch => ...)` … 生成された Patch によるスパース保存
- `OpenEditSessionAsync()` … 複数項目をまとめて編集し、`CommitAsync`
- `ApplyPatchesAsync` + `StateSourcePatch` … 明示的なソースごとの複数書き込み
- `StateWritePlan.For<T>().Route(...)` … 書き込みルーティング
- `SourceKey<TModel>` と `options.Source(key)` … ソースごとの操作

## 想定読者

設定管理に痛みを感じている .NET 開発者向け。`Microsoft.Extensions.Configuration` との違いとして、`IConfiguration` は読み取り指向であるのに対し、Configlue は独立したソースの合成、出所の確認、スパース保存に適しています。



---

# ===== opencode/mimo-v2.6-flash-free =====

# Configlue

> Make easy configuration management.

Configlue は、アプリケーションの設定管理を引き受ける .NET ライブラリです。名前は **config**uration + **glue** に由来し、複数の場所に分散した設定を一つのモデルへ「グルー（接着）」して扱うことがコンセプトの中心です。

- 要件: .NET 10 SDK 以降（ソースジェネレーターを使うため `LangVersion` は `preview` でビルドしています）
- ライセンス: Apache-2.0
- 現状: 「アーキテクチャの土台」であり、`Configuration.Writable` の完全な置き換えではありません

## なぜ Configlue なのか

JSON ファイルを読み書きするだけなら数行で済みます。しかし実運用では、次の要求が積み上がっていきます。

- 設定が複数の場所に存在する：グローバル設定、ランタイムフォルダーごとの設定、環境変数、コマンドライン引数、暗号化された資格情報、社内ポリシーや HTTP API などのリモート管理。
- 設定ファイルの書き換えを、アプリ再起動なしで反映したい（変更通知）。
- 書き込み先を自動で選びたい。環境変数から読んだ値への書き込みはエラーにしたい。
- 設定ファイルは人間が書く：コメントを消さない、JSON Schema が欲しい、壊れたファイルにも対応したい。
- まだデフォルト値のままなら書き出したくない（ただし、ユーザーが明示した `null` は尊重したい）。
- 設定ファイルをバージョンアップしたい（旧形式から新形式への自動変換）。
- バックアップと自動クリーンアップ。
- 書き込みの安全性：アトミック性（クラッシュによる破壊がない）、他プロセスとの競合検知と自動マージ、自動リトライ。

これらを自分で実装するのは煩雑なので、Configlue はその面倒な部分を引き受けます。

`Microsoft.Extensions.Configuration`（`IConfiguration`）が読み取り志向なのに対し、Configlue は独立したソースの合成、出所（プロヴナンス）の調査、疎な保存に向いています。

## コアアーキテクチャ（6 つの概念）

依存は一直線で、学習順も同じです。

```text
Resource (場所) → Codec (変換) → Source (寄与) → Fragment (差分) → Options (外向け API)
                                                     ↘ Patch (編集フラグメント)
```

| 概念 | 一言で | 例 |
| --- | --- | --- |
| Resource | バイトが住む場所 | ファイル、ZIP エントリ、HTTP レスポンス、メモリ |
| Codec | バイトと値の変換 | JSON / XML / YAML の読み書き |
| Source | 論理的な寄与（どのフィールドをどの優先度で） | 「ユーザ設定ファイルの `Server` 部分」 |
| Fragment | 「存在」を覚える差分 | 「`Port` だけを持つ」状態 |
| Patch | 1 フィールドの編集 | 「`Port` を 9000 に設定」 |
| Options | アプリが見る外向け API | 読む、保存、監視、説明、診断 |

**読み取り**: 各 Source は Resource からバイトを取り込み、Codec がそれを Fragment に変換します。ランタイムは「存在する」フィールドだけを優先度順に重ねて、単一のモデルに合成します。

**書き込み**: その逆方向です。アプリはふつうのモデル値を編集します。内部ではその変更が Fragment の差分になり、`WriteRoute` / `WritePlan` が指名した Source にだけ届きます。無関係な Source は変更されません。

- Fragment は「メンバーが欠落している」と「null/デフォルトとして存在している」を区別します。レイヤー合成で「未設定」が「デフォルトで設定済み」を上書きすることはありません。
- Patch はジェネレーターが生成する `TModel.Patch`（1 フィールドの編集フラグメント）です。`Unset()` は書き込み先の Source からの寄与だけを取り下げ、より優先度の低い値を再び露出させます。
- `[ConfiglueMerge]` でメンバーごとのマージ挙動を変更できます（組み込み: `Append` / `Deep` / `Replace` / `SetUnion`、独自戦略も可）。コレクションのレイヤー合成と順序はここで決めます。

## 主な機能

- **複数ソースの優先度マージ**: `Priority` が大きい Source が勝ちます。`GetDetailsAsync` で「どの値がどこから来たか」を調査できます。
- **読み取り専用ソース**: 環境変数、コマンドライン、既定の HTTP ソースは読み取り専用です。読み取り専用の値への書き込みは黙って無視されず、競合エラーを送出します。
- **投影 / マウント**: 既存の Source を別のモデルへ整形し直して（投影して）扱えます。また、ネストしたパスに別の Source を取り付けられます（マウント、`AddMounted`）。
- **プリセット**: `UseCommonSources` が標準的なレイヤー構成（グローバル / ローカル / 環境変数など）を組み立てます。
- **疎な書き込み**: 変更したフィールドだけが対象レイヤーに保存されます。デフォルトのまま残したフィールドは書き出されません。
- **編集セッション**: `OpenEditSessionAsync` で複数の変更をまとめて適用し、`CommitAsync` までメモリ上に保持します。競合時は既定で失敗し、`WriteConflictResolution.LastWriteWins` も選べます。
- **スキーマ移行 / ストレージ移行**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` により旧バージョンの設定を自動変換します。既存ファイルを Source として登録できます。
- **バックアップと復元**: `FileResource` がアトミック書き込みとバックアップ世代管理を提供します。既定で `.bak` は 1 世代、`RestoreLatestBackupAsync` で復元します。
- **安全な書き込み**: アトミック性、競合検知、リトライ。
- **セクション**: `JsonSectionResource` / XML 要素 / YAML マッピングで、ファイルの一部を独立した Resource として扱えます。書き込み時はコメント、空白、クォート、スカルースタイルを保持します。同じファイル内の独立セクションは 1 回の物理書き込みにまとめられます。
- **ZIP / HTTP / S3 / Dapr**: `ZipEntryResource`、`Configlue.Resource.Http`（ETag による条件付き書き込みとポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **JSON Schema 生成**: 設定は人間が書くものなので、`Configlue.JsonSchema` を用意しています。
- **Native AOT 対応**: ソースジェネレーター出力の `JsonSerializerContext` を渡すと、トリミング / AOT に強くなります。
- **リアクティブ統合（任意）**: `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）。`ObserveChanges()`、`ObserveValues()`、`ObserveReloadFailures()`、`ObserveActiveValues()`、`ObserveActiveProfileNames()`。
- **DI 統合**: `Configlue.Extensions.DI`。Microsoft options アダプタは `Configlue.Extensions.MSOptions`（`IOptions<T>` など）。同期のゲッターは非同期ソースの読み込み中にブロックするため、非同期フローでは `GetValueAsync` を推奨します。
- **プロファイル / 動的オプション**: 名前付きオプションと永続プロファイルにより、ランタイムを単位として生成・削除できます。
- **既知の制限**: 異なる Resource 間の書き込みはアトミックではありません。Source の退役は現在のオプションインスタンスにスコープされ、裏のデータは残ります。ソース集合はオプションのランタイムに対して固定です。

## パッケージ構成（主なもの）

- `Configlue` … ユーザー向けメタパッケージ（Core / DI / JSON プロバイダー / JSON Schema / HTTP リソース / 共通ソース / 環境変数ソース / ジェネレーター解析器を同梱。独自の実装アセンブリはありません）
- `Configlue.Abstraction` … 契約（provider / codec / resource / 生成モデル）
- `Configlue.Core` … 解決と永続化のランタイム
- `Configlue.Extensibility` … プロバイダー SDK
- `Configlue.Extensions.DI` / `Configlue.Extensions.MSOptions` / `Configlue.Extensions.R3` / `Configlue.Extensions.Reactive`
- `Configlue.Generator` … Roslyn アナライザー（疎なモデル対応を生成）
- `Configlue.Testing` … インメモリのテスト用替身
- `Configlue.Provider.Json` / `.Xml` / `.Yaml` … 各形式のコーデック、セクションリソース、ファイル登録
- `Configlue.JsonSchema` … JSON Schema の生成とエクスポート
- `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml`
- `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip`
- `Configlue.Transformer.AES` … Resource と Codec の間のバイトを AES-GCM で暗号化・認証

インストールは `dotnet add package Configlue` から。必要な機能パッケージを追加してください。

## クイックスタート

次を `example.cs` に保存し、`dotnet run example.cs` で実行します（.NET 10 以降）。

```csharp
#!/usr/bin/env dotnet
#:package Configlue@*

using Configlue;
using Configlue.Source.Presets;

// 1. 設定モデルを宣言する。ジェネレーターが Fragment/Patch 対応を生成する。
[ConfiglueModel("SampleSetting", Version = 1)]
public partial class SampleSetting
{
    public string Name { get; set; } = "World";
    public int RunCount { get; set; }
    public bool DefaultValue { get; set; } = true;
}

// 2. プリセットのレイヤーを宣言する。ここに挙げたソースだけが有効になる。
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);

// 3. オプションインスタンス経由で読み書きする。
var options = context.GetOptions<SampleSetting>();
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 疎な編集：変更したフィールドだけが対象レイヤーに保存される。
await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue は変更していないので対象レイヤーに保存されない。
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

## 値の出所を調べる / 疎な保存

```csharp
var options = context.GetOptions<AppSettings>();
// 1. 現在の値（全ソースのマージ結果）を取得する
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

指定したメンバーだけを更新するパッチを保存できます。`Unset()` はその Source の寄与を取り下げ、より優先度の低い Source に値を委ねます。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

その他の API:

- `IReadOnlyOptions<T>` … 日常の読み取り面は `GetValueAsync` と `OnChange`。
- `SaveAsync(patch => ...)` … 生成された Patch による疎な保存。
- `OpenEditSessionAsync()` … 複数をまとめて編集し、`CommitAsync` する。
- `ApplyPatchesAsync` + `StateSourcePatch` … ソースごとの明示的な複数書き込み。
- `StateWritePlan.For<T>().Route(...)` … 書き込みルーティング。
- `SourceKey<TModel>` と `options.Source(key)` … ソースごとの操作。



---

# ===== opencode/muse-spark-1.3-contributor-free =====

# Configlue

設定管理を引き受ける .NET 向けライブラリです。合言葉は「Make easy configuration management.」です。

アプリケーションの設定は、全体設定ファイル、実行フォルダーごとのファイル、環境変数、コマンドライン引数、暗号化された credential、HTTP API や社内ポリシーによる遠隔管理など、複数の場所に散らばりがちです。Configlue はこれらを貼り合わせて、ひとつのモデルとして扱います。名前は configuration と glue に由来します。JSON ファイルを数行で読み書きするだけなら簡単ですが、実運用で積み上がる細かな要求を自前で実装する手間を省くためのライブラリです。

`Microsoft.Extensions.Configuration` の `IConfiguration` が読み取り中心であるのに対し、Configlue は独立した提供元を組み合わせること、値の由来を確認できること、変更した分だけを書き戻せることに向いています。現在の位置づけは土台となる実装であり、`Configuration.Writable` を完全に置き換えるものではありません。

動作条件は .NET 10 SDK 以降です。C# はソースジェネレーターを利用できる `LangVersion` が必要であり、リポジトリは `preview` でビルドしています。ライセンスは Apache-2.0 です。

## まずは動かす

`example.cs` に保存して `dotnet run example.cs` で実行できます（.NET 10 以降）。

```csharp
#!/usr/bin/env dotnet
#:package Configlue@*

using Configlue;
using Configlue.Source.Presets;

// 1. 設定モデルを宣言する。Fragment と Patch の対応はジェネレーターが作る。
[ConfiglueModel("SampleSetting", Version = 1)]
public partial class SampleSetting
{
    public string Name { get; set; } = "World";
    public int RunCount { get; set; }
    public bool DefaultValue { get; set; } = true;
}

// 2. 使う層を宣言する。ここに挙げた提供元だけが有効になる。
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);

// 3. options 経由で読み書きする。
var options = context.GetOptions<SampleSetting>();
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 変更した項目だけが対象層に保存される。
await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue に触れていないため、対象層には書き出されない。
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

導入は `dotnet add package Configlue` から始めます。必要に応じて機能ごとのパッケージを追加します。`Configlue` は利用者向けの取りまとめパッケージであり、Core や DI、JSON 提供元、JSON Schema、HTTP リソース、共通提供元、環境変数提供元、ジェネレーターなどを束ねています。自前の実装 assembly は持ちません。

## 読み書きの考え方を六つの言葉で整理する

依存関係は一直線に並び、学ぶ順番も同じです。

```text
Resource (場所) → Codec (変換) → Source (寄与) → Fragment (差分) → Options (窓口)
                                                        ↘ Patch (1項目の編集)
```

| 言葉 | 意味 | 例 |
| --- | --- | --- |
| Resource | バイト列の置き場所 | ファイル、ZIP 内項目、HTTP 応答、メモリー |
| Codec | バイト列と値の変換 | JSON、XML、YAML の読み書き |
| Source | どの項目をどの優先度で受け持つかという論理的な寄与 | 使用者設定ファイルの `Server` 部分 |
| Fragment | 有無を覚えている差分 | `Port` だけを持っている状態 |
| Patch | 1項目分の編集 | `Port` を 9000 にする |
| Options | アプリケーションが触る窓口 | 読み取り、保存、監視、説明、診断 |

読み取りでは、各 Source が Resource からバイト列を取り寄せ、Codec が Fragment に変換します。実行時は「存在する」項目だけを優先度順に重ねて、ひとつのモデルにします。

書き込みは逆向きです。アプリケーションは普段どおりのモデル値を編集します。内部では変更が Fragment の差分になり、`WriteRoute` や `WritePlan` で指名された Source にだけ届きます。関係のない Source には触れません。

この重ね合わせを支える約束は三つあります。

まず、Fragment は「項目がない」ことと「null や既定値として存在する」ことを区別します。そのため、未設定が既定値として設定済みの値を上書きすることはありません。利用者が明示した null は尊重されます。

次に、Patch は生成される `TModel.Patch` であり、1項目単位の編集用差分です。`Unset()` は書き込み先 Source の寄与だけを取り下げ、下位の優先度の値を再び見えるようにします。

さらに、項目ごとの重ね方は `[ConfiglueMerge]` で変えられます。組み込みは `Append`、`Deep`、`Replace`、`SetUnion` であり、自作の方式も使えます。コレクションの重ね方や順序はここで決まります。

## 値の由来を確かめて必要な分だけ書き戻す

日常の読み取りは `IReadOnlyOptions<T>` の `GetValueAsync` と `OnChange` を使います。ファイルが書き換えられたら再起動なしで反映し、変更通知で知ることができます。

各値がどこから来たかは `GetDetailsAsync` で調べられます。

```csharp
var options = context.GetOptions<AppSettings>();
// 現在値を読む。すべての提供元の重ね合わせ結果である。
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 値の由来を調べる。
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

優先度は `Priority` の大きい Source が勝ちます。環境変数、コマンドライン、既定の HTTP 提供元は読み取り専用です。読み取り専用の値に書き込もうとしても黙って無視されるのではなく、競合の誤りとして報告されます。書き込み先は自動で選ばれます。

保存は `SaveAsync` に Patch を渡します。指定した項目だけを更新します。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

まとめ書きには `OpenEditSessionAsync` を使います。複数の変更を一括で扱い、`CommitAsync` まではメモリー上にとどまります。競合時は既定で失敗し、`WriteConflictResolution.LastWriteWins` も選べます。提供元を明示して複数書き込みする場合は `ApplyPatchesAsync` と `StateSourcePatch`、書き込み先の割り当ては `StateWritePlan.For<T>().Route(...)`、提供元ごとの操作は `SourceKey<TModel>` と `options.Source(key)` を使います。

既存の Source を別のモデルに作り替える投影と、入れ子になった経路に別の Source を取り付けるマウントもできます。マウントには `AddMounted` を使います。定型の層構成は `UseCommonSources` で組み立てます。

## 人が書くファイルを壊さないための仕組み

設定ファイルは人が書きます。Configlue は注釈や空白、引用の仕方、スカラーの書き方を書き込み時に保ちます。ファイルの一部を独立した Resource として扱う仕組みとして、`JsonSectionResource`、XML 要素、YAML マッピングがあります。同じファイル内の独立した区分への書き込みは、1回の物理書き込みにまとめられます。壊れたファイルへの対処や、人が書くための JSON Schema 対応も含まれます。Schema の生成と出力は `Configlue.JsonSchema` が受け持ちます。

古い形式の自動変換もできます。`[ConfigluePreviousVersion]` と `Fragment.FromPrevious` により、版つきの設定を移行します。既存のファイルは Source として登録できます。既定値のままの値は書き出さないため、ファイルが必要以上に膨らみません。

## 書き込みを安全に終えるための仕組み

`FileResource` は不可分な書き込みと世代つき予備複製の管理を行います。既定では `.bak` を1世代作ります。戻すときは `RestoreLatestBackupAsync` を使います。不可分性、他過程との競合検出と自動統合、自動再試行により、途中停止による破損を防ぎます。

ただし、異なる Resource にまたがる書き込みは不可分ではありません。また、Source の利用停止は現在の options 実体の中だけに閉じ、裏側の実データは残ります。options 実行ごとの提供元の集合は固定です。

## 置き場所と周辺連携の広げ方

置き場所として、ZIP 内項目は `ZipEntryResource`、HTTP は `Configlue.Resource.Http`（ETag による条件つき書き込みと定時確認）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr` があります。ASP.NET Core 側の受け口は `Configlue.Resource.Http.AspNetCore` です。

Resource と Codec の間でバイト列を暗号化・認証する場合は `Configlue.Transformer.AES` を使います。方式は AES-GCM です。

利用の広げ方は次のとおりです。

- 永続プロファイルと名前つき options により、実行環境を単位として作ったり消したりできます。
- JSON、XML、YAML ごとに Codec、区分 Resource、ファイル登録が用意されています。
- トリミングや Native AOT への耐性を高めるには、ソース生成済みの `JsonSerializerContext` を渡します。
- DI は `Configlue.Extensions.DI`、Microsoft の options への橋渡しは `Configlue.Extensions.MSOptions`（`IOptions<T>` など）です。同期取得は非同期提供元の読み取り待ちで止まるため、非同期の流れでは `GetValueAsync` の利用が勧められます。
- 反応型の連携は任意です。`Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）があり、`ObserveChanges()`、`ObserveValues()`、`ObserveReloadFailures()`、`ObserveActiveValues()`、`ObserveActiveProfileNames()` を使えます。
- 試験用のメモリー内二重体は `Configlue.Testing`、提供元を作る側の SDK は `Configlue.Extensibility`、契約は `Configlue.Abstraction`、解決と永続化の実行部は `Configlue.Core`、疎なモデル対応の生成は Roslyn による `Configlue.Generator` が受け持ちます。

形式別の共通層は `Configlue.Source.Presets` を基本に、`Configlue.Source.Presets.Yaml` と `Configlue.Source.Presets.Xml` を足します。環境変数は `Configlue.Source.Environment`、コマンドライン引数は `Configlue.Source.CommandLine` です。



---

# ===== opencode/nemotron-3-ultra-free =====

# Configlue

**.NET アプリケーションの構成管理をシンプルに。**

Configlue は、複数の場所に分散した設定を単一のモデルに **glue（接着）** する .NET ライブラリです。
「Make easy configuration management.」を掲げ、設定の読み取り・書き込み・監視・移行・バックアップまでを包括的に支援します。

- 対象: .NET 10 SDK 以降（C# ソースジェネレータ必須、`LangVersion: preview` 推奨）
- ライセンス: Apache-2.0
- 現状: 「アーキテクチャ基盤」として提供。`Configuration.Writable` の完全な代替ではありません。

---

## なぜ Configlue か？

JSON ファイルの読み書き自体は数行で済みますが、実運用では以下の要件が積み重なります。

- 設定が **複数の場所** にある: グローバル/ローカル設定ファイル、環境変数、コマンドライン引数、暗号化資格情報、HTTP API や企業ポリシー等のリモート管理
- ファイル書き換えを **再起動なしで反映**（変更通知）
- 書き込み先を **自動判別**。環境変数由来の値への書き込みはエラーにしたい
- **人間が編集する** ファイル: コメント保持、JSON Schema 対応、壊れたファイルへの耐性
- **デフォルト値は書き出さない**（ユーザーが明示的に `null` を設定した場合は尊重）
- 設定ファイルの **バージョンアップ**（旧形式から新形式への自動変換）
- **バックアップと自動クリーンアップ**
- **安全な書き込み**: 原子性（クラッシュ時の破損防止）、競合検知・自動マージ、自動リトライ

これらを自前で実装するのは骨が折れます。Configlue はこの負担を肩代わりします。

---

## コアアーキテクチャ（6 つの概念）

依存関係は一直線で、学習順序も同じです。

```
Resource（場所） → Codec（変換） → Source（寄与） → Fragment（差分） → Options（ファサード）
                                                      ↘ Patch（編集片）
```

| 概念 | 一言で | 例 |
|------|--------|-----|
| **Resource** | バイト列が置かれている場所 | ファイル、ZIP エントリ、HTTP レスポンス、メモリ |
| **Codec** | バイト列 ⇔ 値の変換 | JSON / XML / YAML の読み書き |
| **Source** | 論理的な寄与（どのフィールドをどの優先度で） | 「ユーザー設定ファイルの `Server` 部分」 |
| **Fragment** | 存在を記憶する差分 | 「`Port` だけ持っている」状態 |
| **Patch** | 単一フィールドの編集 | 「`Port` を 9000 にする」 |
| **Options** | アプリが見るファサード | 読み取り、保存、監視、説明、診断 |

**読み取り**: 各 Source が Resource からバイト列を取得し、Codec で Fragment に変換。ランタイムは「存在する」フィールドだけを優先度順に重ね合わせ、単一モデルを構築します。

**書き込み**: 逆方向。アプリが通常のモデル値を編集すると、内部で Fragment 差分になり、`WriteRoute`/`WritePlan` で指定された Source のみに到達。無関係な Source は変更されません。

- Fragment は「メンバーが欠けている」ことと「null/デフォルトとして存在する」ことを区別。レイヤー合成で「未設定」が「デフォルト設定」を上書きすることはありません。
- Patch は生成される `TModel.Patch`（単一フィールド編集片）。`Unset()` でその Source の寄与だけを取り下げ、より低優先度の値を露出させます。
- `[ConfiglueMerge]` でメンバー単位のマージ挙動を変更可能（組み込み: `Append`、`Deep`、`Replace`、`SetUnion`、カスタム戦略も可）。コレクションの合成順序もここで決めます。

---

## 主な機能

- **複数ソースの優先度マージ**: `Priority` が大きい Source が勝つ。`GetDetailsAsync` で「どの値がどこから来たか」を検査可能。
- **読み取り専用ソース**: 環境変数、コマンドライン、既定の HTTP ソースは読み取り専用。書き込み試行はサイレント無視せず **競合エラー** を発生。
- **射影 / マウント**: 既存 Source を別モデルに射影（プロジェクション）、または別 Source をネストしたパスにマウント（`AddMounted`）。
- **プリセット**: `UseCommonSources` で標準的なレイヤー構成（グローバル/ローカル/環境等）を一括組み立て。
- **スパース書き込み**: 変更したフィールドのみを対象レイヤーに保存。デフォルトのままのフィールドは書き出さない。
- **編集セッション**: `OpenEditSessionAsync` で複数変更をまとめて適用。メモリ上で完結し `CommitAsync` で確定。競合時は既定で失敗、`WriteConflictResolution.LastWriteWins` も選択可。
- **スキーマ移行 / ストレージ移行**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` で旧バージョン設定を自動変換。既存ファイルを Source として登録可能。
- **バックアップと復元**: `FileResource` が原子的書き込みとバックアップ世代管理を提供。既定で `.bak` 1 世代、`RestoreLatestBackupAsync` で復元。
- **安全な書き込み**: 原子性、競合検知、リトライ。
- **セクション**: `JsonSectionResource` / XML 要素 / YAML マッピングで、ファイルの一部分を独立した Resource として扱える。書き込み時はコメント・空白・クォート・スカラスタイルを保持。同一ファイル内の独立セクションは 1 回の物理書き込みにバッチ処理。
- **ZIP / HTTP / S3 / Dapr**: `ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込みとポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。
- **JSON Schema 生成**: `Configlue.JsonSchema`。人間が設定を書くためのスキーマを出力。
- **Native AOT 対応**: ソース生成された `JsonSerializerContext` を渡すことでトリミング/AOT 耐性を向上。
- **リアクティブ連携（オプション）**: `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）、`Configlue.Extensions.R3`（R3 1.3.1）。`ObserveChanges()`、`ObserveValues()`、`ObserveReloadFailures()`、`ObserveActiveValues()`、`ObserveActiveProfileNames()`。
- **DI 統合**: `Configlue.Extensions.DI`。Microsoft Options アダプタは `Configlue.Extensions.MSOptions`（`IOptions<T>` 等。同期ゲッターは非同期ソースの読み取り中にブロックするため、非同期フローでは `GetValueAsync` 推奨）。
- **プロファイル / 動的オプション**: 名前付きオプションと永続プロファイルで、ランタイムを単位として作成・削除。
- **既知の制限**: 異なる Resource 間の書き込みは原子的ではない。Source のリタイアは現在のオプション インスタンスにスコープされ、バックエンド データは残る。ソース集合はオプション ランタイムの生存中固定。

---

## パッケージ構成（主要なもの）

- `Configlue` … ユーザー向けメタパッケージ（Core / DI / JSON プロバイダ / JSON Schema / HTTP リソース / 共通ソース / 環境変数ソース / ジェネレータ アナライザをバンドル。実装アセンブリは持たない）
- `Configlue.Abstraction` … 契約（プロバイダ/コーデック/リソース/生成モデル）
- `Configlue.Core` … 解決と永続化のランタイム
- `Configlue.Extensibility` … プロバイダ SDK
- `Configlue.Extensions.DI` / `Configlue.Extensions.MSOptions` / `Configlue.Extensions.R3` / `Configlue.Extensions.Reactive`
- `Configlue.Generator` … Roslyn アナライザ（スパースモデルサポートを生成）
- `Configlue.Testing` … インメモリテストダブル
- `Configlue.Provider.Json` / `.Xml` / `.Yaml` … 各フォーマットのコーデック、セクションリソース、ファイル登録
- `Configlue.JsonSchema` … JSON Schema 生成とエクスポート
- `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml`
- `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip`
- `Configlue.Transformer.AES` … Resource と Codec の間のバイト列に対する AES-GCM 暗号化と認証

導入は `dotnet add package Configlue` から。必要な機能パッケージを追加してください。

---

## クイックスタート

`example.cs` として保存し、`dotnet run example.cs` で実行（.NET 10 以降）：

```csharp
#!/usr/bin/env dotnet
#:package Configlue@*

using Configlue;
using Configlue.Source.Presets;

// 1. 設定モデルを宣言。ジェネレータが Fragment/Patch サポートを生成。
[ConfiglueModel("SampleSetting", Version = 1)]
public partial class SampleSetting
{
    public string Name { get; set; } = "World";
    public int RunCount { get; set; }
    public bool DefaultValue { get; set; } = true;
}

// 2. プリセットレイヤーを宣言。ここに列挙した Source のみ有効化される。
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);

// 3. オプションインスタンス経由で読み書き。
var options = context.GetOptions<SampleSetting>();
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// スパース編集: 変更したフィールドのみ対象レイヤーに保存される。
await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue は未変更なので対象レイヤーに書き出されない。
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

---

## 値の由来を検査 / スパース保存

```csharp
var options = context.GetOptions<AppSettings>();
// 1. 現在値を取得（全ソースからマージ済み）
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// 2. 各値がどこから来たかを検査
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

指定したメンバーだけを更新するパッチを保存。`Unset()` でその Source の寄与を取り下げ、より低優先度の値を露出させます：

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

その他の API：
- `IReadOnlyOptions<T>` … 日常的な読み取り面は `GetValueAsync` と `OnChange`。
- `SaveAsync(patch => ...)` … 生成された Patch でスパース保存。
- `OpenEditSessionAsync()` … 複数変更をまとめて編集、`CommitAsync` で確定。
- `ApplyPatchesAsync` + `StateSourcePatch` … ソース単位の明示的マルチ書き込み。
- `StateWritePlan.For<T>().Route(...)` … 書き込みルーティング。
- `SourceKey<TModel>` と `options.Source(key)` … ソース単位操作。

---

## 対象読者とトーン

- 対象: .NET 開発者、特に構成管理の悩みを持つ方
- トーン: 技術的、簡潔、誇張なし。`Microsoft.Extensions.Configuration` との違い（`IConfiguration` は読み取り志向、Configlue は独立したソースの合成・由来検査・スパース保存に適している）を示唆すると良いでしょう。


---

# ===== opencode/nemotron-3.5-lightning-free =====

# Configlue 説明 (日本語)

## 1. 概要

- **Configlue** は .NET アプリケーションの設定管理を担うライブラリ
- キャッチフレーズ: "Make easy configuration management."
- 中央アイデア: 複数の場所に散らばる設定を単一のモデルに "glue"（結合）する
- 必要条件: .NET 10 SDK 以降。C# (`LangVersion` はソース ジェネレータに対応; リポジトリは `preview` でビルド)
- ライセンス: Apache-2.0.
- 現在は "アーキテクチャの基盤" であり、`Configuration.Writable` の完全な代替にはなっていない

## 2. Configlue が解決する問題

JSON ファイルの読み書きは数行で済むが、実際の現場では以下のような要件が積み重なる。

- 設定はグローバル設定、ランチルーフォルダ設定、環境変数、コマンドライン引数、暗号化された認証情報、企業ポリシーや HTTP API などのリモート管理など、複数の場所に存在する
- 設定ファイルが書き換わった際、アプリケーションの再起動なく反映したい (変更通知)
- 書き込み先を自動的に選択したい。環境変数から読み取った値への書き込みはエラーにしたい
- 設定ファイルは人間が書く: コメントを削除したくない、JSON Schema に対応したい、壊れたファイルへの対応
- 値がデフォルトのままなら書き出さない (が、ユーザーが明示的に `null` 設定した場合は尊重)
- 設定ファイルのバージョンアップ (旧形式から新形式への自動変換)
- バックアップと自動クリーンアップ
- 安全な書き込み: アトミシティ (クラッシュ時の破損防止)、競合検出と他プロセスとのオートメージ、自動リトライ

これらを自分で実装するのは手間がかかる。

## 3. コアアーキテクチャ (6つの概念)

依存関係は一直線で、学習順も以下の通り。

```text
Resource (場所) → Codec (変換) → Source (寄与) → Fragment (差分) → Options (ファサード)
                                                        ↘ Patch (差分の編集)
```

| 概念 | 一文で | 例 |
| --- | --- | --- |
| **Resource** | バイトが residing する場所 | ファイル、ZIP largelyNM stretches of across d is d is cl August tan complete P in y le three d [ car day being and residue
 breaks and the y H professional where for between through timing, y d tru vacation at p,,Y y y completeY favor from y under
  of Y T y y/y y y y y y y * y y y T d six d all  who el P y and T dY. P y y y y y y y y the y y y y y y y  y y y a y y  y of y y y y  youth ( denominYW started​ yY D stochastic k y in yK ( y unser y implic composed el conveyed y y y yY y y y y y y Y yY y y y y y y y y
Y K th.

 y y y y y y y y y y y y y y  y K yY europe yY y y y y y yY indigenous y y called yY.

 single. y y y y  y K eu y y Y,y y y
 el y y y K ranc K elY K y YemenK
 every yK y-.

 y y y y elY y K el y * K8 y‐ y y the Y K el y >KY y k extremely ** el[K

 y since y

 el-
.



 y y-el



 heal\ K el- el yY elY K el y yellow
 y Y bus y y”, KK y y.y.

 yY y.
 K (-Y y y elY y el y ting y y- a y-

 elYK el y1YK in of.
-Y_y;
 of,-



- K and y 민족 PA y[ y K H.

 y K * YK
 Y K.

 y y-- y- your/yY valueY y y y the.

 yY y y.

 KY K1 y y elY asYY K Kale y el through.



---

# ===== opencode/space-bunny-free =====

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



