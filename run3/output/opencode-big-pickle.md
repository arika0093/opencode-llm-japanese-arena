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

