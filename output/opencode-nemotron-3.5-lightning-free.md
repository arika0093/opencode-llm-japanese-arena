# Configlue 日本語解説

## 概要

Configlue は、アプリケーションの設定管理を代行する .NET ライブラリです。キャッチコピーは "Make easy configuration management." です。

複数の場所に散らばった設定を 1 つのモデルに結合（glue）するのが中心的な考え方で、名前も configuration + glue になっています。対象は .NET 10 SDK 以降で、C# の利用にはソースジェネレーター対応の LangVersion が必要です。ライセンスは Apache-2.0 です。

現状はアーキテクチャ上の土台であり、`Configuration.Writable` を完全に置き換えるものではありません。

主な解決課題は以下の通りです。

- 設定がグローバル設定、実行フォルダー設定、環境変数、コマンドライン引数、暗号化された資格情報、社内ポリシーや HTTP API など複数箇所にある
- 設定ファイルが書き換わったら再起動なしで反映したい（変更通知）
- 書き込み先を自動で選びたい。環境変数から読んだ値への書き込みはエラーにしたい
- 設定ファイルは人間が書くため、コメントを残し、JSON Schema が欲しく、壊れたファイルへの対処が必要
- 既定値のままなら書き出さず、ユーザーが明示した `null` は尊重する
- 設定ファイルのバージョンアップ（旧形式→新形式への自動変換）
- バックアップと自動整理
- アトミック性、競合検出・自動マージ、自動リトライによる書き込みの安全性

これらを自前実装するのは面倒というのが動機です。

## 主な特徴

- **複数ソースの優先度マージ**: `Priority` が大きい Source が勝ち、`GetDetailsAsync` で「どの値がどこ由来か」を検査できます
- **読み取り専用ソース**: 環境変数・コマンドライン・既定の HTTP ソースは読み取り専用です。読み取り専用の値への書き込みは黙って無視せず競合エラーになります
- **プロジェクション / マウント**: 既存 Source を別モデルに整形（projection）したり、ネストしたパスに別 Source を接続（mount, `AddMounted`）できます
- **プリセット**: `UseCommonSources` が標準的な層構成（global/local/environment など）を組み立てます
- **スパース書き込み**: 変更したフィールドだけを対象層に保存。既定値のままのフィールドは書かれません
- **編集セッション**: `OpenEditSessionAsync` で複数変更をまとめて適用。`CommitAsync` までインメモリです。競合時は既定で失敗し、`WriteConflictResolution.LastWriteWins` も選べます
- **スキーマ移行 / ストレージ移行**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` による旧バージョン設定の自動変換。既存ファイルを Source として登録できます
- **バックアップと復元**: `FileResource` はアトミック書き込みとバックアップ世代管理。既定で `.bak` 1 世代、`RestoreLatestBackupAsync` で復元できます
- **安全な書き込み**: アトミック性、競合検出、リトライ
- **セクション**: `JsonSectionResource` / XML 要素 / YAML マッピングで、ファイルの一部を独立した Resource として扱えます。書き込み時はコメント・空白・引用・スカラー形式を保持し、同じファイル内の独立セクションは 1 回の物理書き込みにバッチされます
- **ZIP / HTTP / S3 / Dapr**: `ZipEntryResource`、`Configlue.Resource.Http`（ETag 条件付き書き込み・ポーリング）、`Configlue.Resource.S3`、`Configlue.Resource.Dapr`
- **JSON Schema 生成**: `Configlue.JsonSchema`。人間が設定を書くためです
- **Native AOT 対応**: ソース生成の `JsonSerializerContext` を渡すとトリミング/AOT に強くなります
- **リアクティブ統合（任意）**: `Configlue.Extensions.Reactive` と `Configlue.Extensions.R3`。`ObserveChanges()`, `ObserveValues()`, `ObserveReloadFailures()`, `ObserveActiveValues()`, `ObserveActiveProfileNames()` を使用できます
- **DI 統合**: `Configlue.Extensions.DI`。Microsoft の options アダプター `Configlue.Extensions.MSOptions`（`IOptions<T>` など。同期ゲッターは非同期ソース読み取り中ブロックするので非同期フローでは `GetValueAsync` 推奨）
- **プロファイル / 動的オプション**: 名前付きオプションや永続プロファイルでランタイムを単位に作成・削除できます
- **既知の制限**: 異なる Resource 間の書き込みはアトミックでなく、Source の退役は現在の options インスタンスに閉じ実データは残るほか、Source 集合は options ランタイムで固定されます

## 基本的な使い方

### クイックスタート

`example.cs` に保存し `dotnet run example.cs` で実行（.NET 10 以降）します。

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

指定したメンバーだけを更新するパッチを保存。`Unset()` はその Source の寄与を外し、下位優先度の Source が値を提供できるようにします。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

その他の API:

- `IReadOnlyOptions<T>` … 日常の読み取り面は `GetValueAsync` と `OnChange`
- `SaveAsync(patch => ...)` … 生成 Patch でスパース保存
- `OpenEditSessionAsync()` … まとめて編集し `CommitAsync`
- `ApplyPatchesAsync` + `StateSourcePatch` … 明示的なソース別マルチ書き込み
- `StateWritePlan.For<T>().Route(...)` … 書き込みルーティング
- `SourceKey<TModel>` と `options.Source(key)` … ソース単位の操作
