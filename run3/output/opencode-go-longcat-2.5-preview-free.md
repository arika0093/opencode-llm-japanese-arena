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
