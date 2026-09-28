# Configlue

.NET アプリケーションのための設定管理ライブラリ。"Make easy configuration management."

複数の場所に散らばった設定（グローバル、ローカル、環境変数、コマンドライン、リモート API など）を 1 つのモデルに **結合（glue）** し、読み書き・変更通知・スキーマ移行・安全な保存までを一貫して扱えます。

- 対象: .NET 10 SDK 以降
- ライセンス: Apache-2.0
- インストール: `dotnet add package Configlue`

---

## 概要

JSON ファイルの読み書きだけなら数行で済みますが、実用的な設定管理には次のような要件が積み重なります。

- 設定が複数箇所にある（グローバル / ローカル / 環境変数 / コマンドライン / 暗号化資格情報 / HTTP API 等）
- ファイル変更を再起動なしで反映したい
- 書き込み先を自動で選びたい（環境変数由来の値への書き込みはエラーにしたい）
- 人間が編集する前提：コメントを残したい、JSON Schema がほしい、壊れたファイルに対処したい
- 既定値のままなら書き出さない（明示的な `null` は尊重する）
- 設定ファイルのバージョンアップ（旧形式 → 新形式の自動変換）
- バックアップと自動整理
- 書き込みの安全性：アトミック性、競合検出・自動マージ、自動リトライ

Configlue はこれらを **6 つの概念** で整理し、ランタイムが自動で解決します。

```text
Resource (場所) → Codec (変換) → Source (寄与) → Fragment (差分) → Options (ファサード)
                                                      ↘ Patch (編集)
```

| 概念 | 役割 |
|------|------|
| **Resource** | バイトがどこにあるか（ファイル、ZIP、HTTP、メモリ等） |
| **Codec** | バイト ↔ 値の相互変換（JSON / XML / YAML） |
| **Source** | 論理的な寄与（どのフィールドをどの優先度で提供するか） |
| **Fragment** | 「存在するフィールドだけ」を持つ差分状態 |
| **Patch** | 単一フィールドの編集操作 |
| **Options** | アプリが触るファサード（読み・保存・監視・診断） |

**読み込み**：各 Source が Resource からバイトを取得し、Codec で Fragment に変換。ランタイムが優先度順に「存在する」フィールドだけをモデルへ重ね合わせます。  
**書き込み**：逆方向。アプリは普通のモデル値を編集し、内部で Fragment 差分に変換され、`WriteRoute` / `WritePlan` が指す Source だけへ届きます。無関係な Source は変更されません。

- Fragment は「メンバーが存在しない」と「null/既定値で存在する」を区別します。層の合成で「未設定」が「既定値に設定」を上書きすることはありません。
- Patch は生成される `TModel.Patch`。`Unset()` は書き込み先 Source の寄与だけを取り消し、下位優先度の値を再び見せます。
- `[ConfiglueMerge]` でメンバーごとのマージ挙動を変更可能（組み込み: `Append`, `Deep`, `Replace`, `SetUnion`、カスタム戦略も可）。

---

## 主な特徴

- **複数ソースの優先度マージ**  
  `Priority` が大きい Source が勝つ。`GetDetailsAsync` で「どの値がどこ由来か」を検査可能。

- **読み取り専用ソース**  
  環境変数・コマンドライン・既定の HTTP ソースは読み取り専用。読み取り専用の値への書き込みは黙って無視せず競合エラーになる。

- **プロジェクション / マウント**  
  既存 Source を別モデルに整形（projection）したり、ネストしたパスに別 Source を接続（mount, `AddMounted`）できる。

- **プリセット**  
  `UseCommonSources` が標準的な層構成（global / local / environment 等）を組み立てる。

- **スパース書き込み**  
  変更したフィールドだけを対象層に保存。既定値のままのフィールドは書かれない。

- **編集セッション**  
  `OpenEditSessionAsync` で複数変更をまとめて適用。`CommitAsync` までインメモリ。競合時は既定で失敗、`WriteConflictResolution.LastWriteWins` も選択可能。

- **スキーマ移行 / ストレージ移行**  
  `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` による旧バージョン設定の自動変換。既存ファイルを Source として登録可能。

- **バックアップと復元**  
  `FileResource` はアトミック書き込みとバックアップ世代管理。既定で `.bak` 1 世代、`RestoreLatestBackupAsync` で復元。

- **安全な書き込み**  
  アトミック性、競合検出、自動リトライ。

- **セクション**  
  `JsonSectionResource` / XML 要素 / YAML マッピングで、ファイルの一部を独立した Resource として扱える。書き込み時はコメント・空白・引用・スカラー形式を保持。同じファイル内の独立セクションは 1 回の物理書き込みにバッチされる。

- **多様なリソース**  
  `ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込み・ポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`。

- **JSON Schema 生成**  
  `Configlue.JsonSchema`。人間が設定を書くためのスキーマを出力。

- **Native AOT 対応**  
  ソース生成の `JsonSerializerContext` を渡すとトリミング / AOT に強くなる。

- **リアクティブ統合（任意）**  
  `Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）。`ObserveChanges()`, `ObserveValues()`, `ObserveReloadFailures()`, `ObserveActiveValues()`, `ObserveActiveProfileNames()`。

- **DI 統合**  
  `Configlue.Extensions.DI`。Microsoft の options アダプター `Configlue.Extensions.MSOptions`（`IOptions<T>` 等。同期ゲッターは非同期ソース読み取り中ブロックするため、非同期フローでは `GetValueAsync` 推奨）。

- **プロファイル / 動的オプション**  
  名前付きオプションや永続プロファイルでランタイムを単位に作成・削除できる。

- **既知の制限**  
  異なる Resource 間の書き込みはアトミックでない。Source の退役は現在の options インスタンスに閉じ、実データは残る。Source 集合は options ランタイムで固定。

---

## 基本的な使い方

### クイックスタート

`example.cs` に保存し `dotnet run example.cs` で実行（.NET 10 以降）：

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

### 値の由来を調べる / スパース保存

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

指定したメンバーだけを更新するパッチを保存。`Unset()` はその Source の寄与を外し、下位優先度の Source が値を提供できるようにする：

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

### 主な API

- `IReadOnlyOptions<T>` … 日常の読み取り面は `GetValueAsync` と `OnChange`。
- `SaveAsync(patch => ...)` … 生成 Patch でスパース保存。
- `OpenEditSessionAsync()` … まとめて編集し `CommitAsync`。
- `ApplyPatchesAsync` + `StateSourcePatch` … 明示的なソース別マルチ書き込み。
- `StateWritePlan.For<T>().Route(...)` … 書き込みルーティング。
- `SourceKey<TModel>` と `options.Source(key)` … ソース単位の操作。

---

## Microsoft.Extensions.Configuration との違い

`IConfiguration` は読み取り中心のキーバリューストアですが、Configlue は **独立したソースの合成・来歴の検査・スパース保存** に特化しています。設定を「値の集合」ではなく「層を持つモデル」として扱いたい場合に適しています。
