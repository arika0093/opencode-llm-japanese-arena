# Configlue

**Make easy configuration management.**

Configlue は、アプリケーションの設定管理を代行する .NET ライブラリです。複数の場所に散らばった設定を 1 つのモデルにまとめる（glue する）のが中心的な考え方であり、名前も configuration + glue に由来します。.NET 10 SDK 以降を対象とし、Apache-2.0 ライセンスの下で公開されています。

# 主な特徴

## 複数ソースの優先度マージ

設定はグローバルファイル、実行フォルダー、環境変数、コマンドライン引数、リモート HTTP API など複数の場所に存在しえます。各 Source には優先度（Priority）があり、大きいほうが勝ちます。`GetDetailsAsync` を呼べば、「どの値がどこ由来か」を検査できます。

## 読み取り専用ソースと書き込み保護

環境変数・コマンドライン・既定の HTTP ソースは読み取り専用です。読み取り専用の値への書き込みは黙って無視されるのではなく、競合エラーとして通知されます。環境変数から読んだ値への書き込みが原因で設定が意図せず上書きされることを防ぎます。

## スパース書き込み

変更したフィールドだけを対象層に保存します。既定値のままのフィールドは書き出されず、ユーザーが明示的に `null` を指定した場合は尊重されます。これにより、不要な設定の破壊を防ぎます。

## 編集セッションと安全な書き込み

`OpenEditSessionAsync` で複数の変更をまとめ、`CommitAsync` までインメモリで保持できます。競合が発生した場合は既定で失敗し、`WriteConflictResolution.LastWriteWins` を選択することも可能です。`FileResource` はアトミック書き込みとバックアップ世代管理を扱い、`.bak` ファイルによる復元（`RestoreLatestBackupAsync`）が可能です。

## スキーマ移行とセクション

`[ConfigluePreviousVersion]` と `Fragment.FromPrevious` により、旧形式の設定を自動的に新形式に変換できます。`JsonSectionResource`・XML 要素・YAML マッピングでは、ファイルの一部を独立した Resource として扱え、書き込み時にコメント・空白・引用・スカラー形式を保持します。

## プロジェクション、マウント、プロファイル

既存の Source を別モデルに整形（projection）したり、ネストしたパスに別 Source を接続（mount）できます。`UseCommonSources` により、global / local / environment などの標準的な層構成を組み立てられます。名前付きオプションや永続プロファイルで、ランタイムを単位にした作成・削除が可能です。

## JSON Schema と Native AOT 対応

`Configlue.JsonSchema` により、人間が設定ファイルを記述するための JSON Schema を生成できます。ソース生成の `JsonSerializerContext` を渡すことで、トリミングや Native AOT ビルドに強くなります。

## リアクティブ・DI 統合

`Configlue.Extensions.Reactive`（System.Reactive 7.0.0）と `Configlue.Extensions.R3`（R3 1.3.1）により、`ObserveChanges()`、`ObserveValues()`、`ObserveReloadFailures()` などのリアクティブ API が利用できます。`Configlue.Extensions.DI` と `Configlue.Extensions.MSOptions` により、Microsoft の `IOptions<T>` アダプターで DI 統合が可能です。非同期フローでは `GetValueAsync` の使用を推奨します。

# 基本的な使い方

## インストール

```
dotnet add package Configlue
```

必要に応じて機能パッケージを追加してください。

## モデルの定義

ソースジェネレーターにより、モデルに Fragment / Patch のサポートを自動生成させます。

```csharp
[ConfiglueModel("SampleSetting", Version = 1)]
public partial class SampleSetting
{
    public string Name { get; set; } = "World";
    public int RunCount { get; set; }
    public bool DefaultValue { get; set; } = true;
}
```

## コンテキストとプリセットの構成

`UseCommonSources` で標準的な層構成を組み立てます。

```csharp
await using var context = ConfiglueApp.CreateContext(conf =>
    conf.UseCommonSources(sources =>
    {
        sources.WithGlobal("SampleApp");
        sources.WithLocal();
        sources.WithEnvironment("SAMPLE");
        sources.Add<SampleSetting>();
    })
);
```

## 読み取りと書き込み

`GetOptions<T>` で取得した `Options` インスタンスを通じて、読み取りと書き込みを行います。

```csharp
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

## 値の由来の確認とスパース保存

`GetDetailsAsync` で各値の由来や書き込み可否を検査できます。`Unset()` を使うと、特定の Source の寄与を取り消し、下位優先度の Source が値を提供できるようにします。

```csharp
var details = await options.GetDetailsAsync();
Console.WriteLine($"Name came from {details.Name.Source?.Locator}");
Console.WriteLine($"Can write Name? {details.Name.IsEditable}");

await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```
