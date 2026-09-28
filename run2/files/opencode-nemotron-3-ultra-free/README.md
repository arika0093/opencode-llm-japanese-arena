# Configlue

**.NET アプリケーションの設定管理を簡単に。**

> "Make easy configuration management."

Configlue は、複数の場所に散らばった設定を 1 つのモデルに **結合（glue）** する .NET ライブラリです。  
.NET 10 SDK 以降 / Apache-2.0 ライセンス。

---

## なぜ Configlue か？

JSON の読み書きだけなら数行で済みます。しかし現実には次の要件が積み重なります：

- 設定が複数箇所にある（グローバル / ローカル / 環境変数 / コマンドライン / 暗号化資格情報 / リモート API 等）
- ファイル変更を再起動なしで反映したい（変更通知）
- 書き込み先を自動で選びたい（環境変数由来の値への書き込みはエラーにしたい）
- 人間が編集するファイル：コメントを消さない、JSON Schema がほしい、壊れたファイルへの対処
- 既定値のままなら書き出さない（明示的な `null` は尊重）
- 設定ファイルのバージョンアップ（旧形式→新形式への自動変換）
- バックアップと自動整理
- 安全な書き込み：アトミック性、競合検出・自動マージ、リトライ

これらを自前実装するのは面倒です。Configlue がそれを肩代わりします。

---

## 基本アーキテクチャ（6つの概念）

依存関係は直線的で、学習順も同じです：

```
Resource (場所) → Codec (変換) → Source (寄与) → Fragment (差分) → Options (ファサード)
                                                      ↘ Patch (編集フラグメント)
```

| 概念 | 一言で | 例 |
| --- | --- | --- |
| **Resource** | バイトがどこにあるか | ファイル、ZIPエントリ、HTTP応答、メモリ |
| **Codec** | バイト↔値の変換 | JSON / XML / YAML の読み書き |
| **Source** | 論理的な寄与（どのフィールドをどの優先度で） | 「ユーザー設定ファイルの Server 部分」 |
| **Fragment** | 存在を記憶する差分 | 「Port だけ」を持つ状態 |
| **Patch** | 単一フィールドの編集 | 「Port を 9000 にする」 |
| **Options** | アプリが見るファサード | 読み・保存・監視・説明・診断 |

**読み込み**：各 Source が Resource からバイトを取得し、Codec が Fragment に変換。ランタイムが優先度順に「存在する」フィールドだけを 1 つのモデルへ重ねます。

**書き込み**：逆向き。アプリは普通のモデル値を編集し、内部では変更が Fragment 差分になり、対象 Source にだけ届きます。無関係な Source は変更されません。

- Fragment は「メンバーが存在しない」と「null/既定値で存在する」を区別します。層の合成で「未設定」が「既定値に設定」を上書きすることはありません。
- Patch は生成される `TModel.Patch`（単一フィールドの編集フラグメント）。`Unset()` は書き込み先 Source の寄与だけを取り消し、下位優先度の値を再び見せます。
- `[ConfiglueMerge]` でメンバーごとのマージ挙動を変更可能（組み込み: `Append`, `Deep`, `Replace`, `SetUnion`、カスタム戦略も可）。コレクションの層合成・順序はここで決まります。

---

## 主な機能

- **複数ソースの優先度マージ**：`Priority` が大きい Source が勝つ。`GetDetailsAsync` で「どの値がどこ由来か」を検査可能
- **読み取り専用ソース**：環境変数・コマンドライン・既定の HTTP ソースは読み取り専用。書き込みは黙って無視せず競合エラーになる
- **プロジェクション / マウント**：既存 Source を別モデルに整形（projection）したり、ネストしたパスに別 Source を接続（mount, `AddMounted`）可能
- **プリセット**：`UseCommonSources` が標準的な層構成（global/local/environment など）を組み立てる
- **スパース書き込み**：変更したフィールドだけを対象層に保存。既定値のままのフィールドは書かれない
- **編集セッション**：`OpenEditSessionAsync` で複数変更をまとめて適用。`CommitAsync` までインメモリ。競合時は既定で失敗、`WriteConflictResolution.LastWriteWins` も選択可能
- **スキーマ移行 / ストレージ移行**：`[ConfigluePreviousVersion]` と `Fragment.FromPrevious` による旧バージョン設定の自動変換。既存ファイルを Source として登録可能
- **バックアップと復元**：`FileResource` はアトミック書き込みとバックアップ世代管理。既定で `.bak` 1 世代、`RestoreLatestBackupAsync` で復元
- **安全な書き込み**：アトミック性、競合検出、リトライ
- **セクション**：`JsonSectionResource` / XML 要素 / YAML マッピングで、ファイルの一部を独立した Resource として扱える。書き込み時はコメント・空白・引用・スカラー形式を保持。同じファイル内の独立セクションは 1 回の物理書き込みにバッチされる
- **ZIP / HTTP / S3 / Dapr**：`ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込み・ポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`
- **JSON Schema 生成**：`Configlue.JsonSchema`。人間が設定を書くため
- **Native AOT 対応**：ソース生成の `JsonSerializerContext` を渡すとトリミング/AOT に強くなる
- **リアクティブ統合（任意）**：`Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）。`ObserveChanges()`, `ObserveValues()`, `ObserveReloadFailures()`, `ObserveActiveValues()`, `ObserveActiveProfileNames()`
- **DI 統合**：`Configlue.Extensions.DI`。Microsoft の options アダプター `Configlue.Extensions.MSOptions`（`IOptions<T>` など。同期ゲッターは非同期ソース読み取り中ブロックするので非同期フローでは `GetValueAsync` 推奨）
- **プロファイル / 動的オプション**：名前付きオプションや永続プロファイルでランタイムを単位に作成・削除可能

### 既知の制限

- 異なる Resource 間の書き込みはアトミックでない
- Source の退役は現在の options インスタンスに閉じ、実データは残る
- Source 集合は options ランタイムで固定

---

## パッケージ構成（主要なもの）

| パッケージ | 説明 |
| --- | --- |
| `Configlue` | ユーザー向けメタパッケージ（Core / DI / JSON provider / JSON Schema / HTTP resources / common sources / environment source / generator analyzer を同梱。実装アセンブリは持たない） |
| `Configlue.Abstraction` | 契約（provider/codec/resource/generated-model） |
| `Configlue.Core` | 解決と永続化のランタイム |
| `Configlue.Extensibility` | プロバイダー SDK |
| `Configlue.Extensions.DI` / `Configlue.Extensions.MSOptions` / `Configlue.Extensions.R3` / `Configlue.Extensions.Reactive` | 統合パッケージ |
| `Configlue.Generator` | Roslyn アナライザー（スパースなモデルサポート生成） |
| `Configlue.Testing` | インメモリのテストダブル |
| `Configlue.Provider.Json` / `.Xml` / `.Yaml` | 各形式の Codec・セクションリソース・ファイル登録 |
| `Configlue.JsonSchema` | JSON Schema 生成・エクスポート |
| `Configlue.Source.Environment` / `.CommandLine` / `.Presets` / `.Presets.Yaml` / `.Presets.Xml` | 組み込みソース |
| `Configlue.Resource.Http` / `.Http.AspNetCore` / `.Dapr` / `.S3` / `.Zip` | リモートリソース |
| `Configlue.Transformer.AES` | Resource と Codec の間のバイトを AES-GCM 暗号化・認証 |

**インストール**：
```bash
dotnet add package Configlue
```
必要な機能パッケージを追加してください。

---

## Quick Start

`example.cs` に保存し `dotnet run example.cs` で実行（.NET 10 以降）：

```csharp
#!/usr/bin/env dotnet
#:package Configlue@*

using Configlue;
using Configlue.Source.Presets;

// 1. 設定モデルを宣言。ジェネレーターが Fragment/Patch サポートを生成
[ConfiglueModel("SampleSetting", Version = 1)]
public partial class SampleSetting
{
    public string Name { get; set; } = "World";
    public int RunCount { get; set; }
    public bool DefaultValue { get; set; } = true;
}

// 2. プリセット層を宣言。ここに列挙した Source のみ有効化される
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);

// 3. Options インスタンス経由で読み書き
var options = context.GetOptions<SampleSetting>();
var current = await options.GetValueAsync();
Console.WriteLine($"Hello, {current.Name}! (Run #{current.RunCount})");

// スパース編集：変更したフィールドだけ対象層に保存
await options.SaveAsync(patch =>
{
    patch.Name = "Alice";
    patch.RunCount = current.RunCount + 1;
    // DefaultValue は未変更なので対象層に書かれない
});

var updated = await options.GetValueAsync();
Console.WriteLine($"Saved. Hello, {updated.Name}! (Run #{updated.RunCount})");
```

---

## 値の由来を調べる / スパース保存

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

指定したメンバーだけを更新するパッチを保存。`Unset()` はその Source の寄与を外し、下位優先度の Source が値を提供できるようにします：

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

### その他の API

- `IReadOnlyOptions<T>` … 日常の読み取り面は `GetValueAsync` と `OnChange`
- `SaveAsync(patch => ...)` … 生成 Patch でスパース保存
- `OpenEditSessionAsync()` … まとめて編集し `CommitAsync`
- `ApplyPatchesAsync` + `StateSourcePatch` … 明示的なソース別マルチ書き込み
- `StateWritePlan.For<T>().Route(...)` … 書き込みルーティング
- `SourceKey<TModel>` と `options.Source(key)` … ソース単位の操作

---

## Microsoft.Extensions.Configuration との違い

| 観点 | `IConfiguration` | Configlue |
| --- | --- | --- |
| 主眼 | 読み取り中心 | **独立ソースの合成・来歴の検査・スパース保存** |
| 書き込み | ほぼ非対応 | **スパース書き込み・編集セッション・競合検出** |
| 値の由来 | 取得困難 | `GetDetailsAsync` で**完全に追跡可能** |
| 既定値の扱い | 暗黙的 | **「未設定」と「既定値で存在」を区別** |
| ファイル保持 | コメント等消失 | **コメント・空白・形式を保持** |
| スキーマ移行 | 手動 | **属性ベースで自動変換** |

---

## 対象読者・トーン

- **読者**: .NET 開発者。設定管理に課題を感じている人
- **トーン**: 技術的で簡潔、誇張しない