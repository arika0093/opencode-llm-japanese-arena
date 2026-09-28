## 概要

Configlue は、アプリケーションの設定管理（configuration management）を代行する .NET ライブラリです。キャッチコピーは "Make easy configuration management."。名前のとおり、複数の場所に散らばった設定を 1 つのモデルへ結合（glue）することを中心に設計されています。対象は .NET 10 SDK 以降、ライセンスは Apache-2.0 です。

JSON ファイルの読み書きだけなら数行で済みますが、実際のアプリケーションでは要件が積み重なります。グローバル設定・実行フォルダー設定・環境変数・コマンドライン引数・暗号化された資格情報・HTTP API によるリモート管理など、設定が複数箇所に存在することは珍しくありません。さらに、変更通知による再起動なしの反映、書き込み先の自動選択、人間が編集するためのコメント保持や JSON Schema、既定値の書き出し抑制、旧形式からの自動変換、バックアップ、アトミックな書き込みや競合検出といった要件を自前で実装するのは面倒です。Configlue はこれらをライブラリとして引き受けます。

なお Configlue は現状「アーキテクチャ上の土台」であり、`Configuration.Writable` を完全に置き換えるものではありません。`Microsoft.Extensions.Configuration`（`IConfiguration`）が読み取り中心であるのに対し、Configlue は独立したソースの合成・値の来歴の検査・スパースな保存に向いた設計になっています。

### 基本アーキテクチャ

Configlue は直線的な依存関係を持つ 6 つの概念で構成されており、学習順もこの順番のままです。

```text
Resource (location) → Codec (conversion) → Source (contribution) → Fragment (diff) → Options (facade)
                                                        ↘ Patch (edit fragment)
```

| 概念 | 一言で | 例 |
| --- | --- | --- |
| Resource | バイトがどこにあるか | ファイル、ZIP エントリ、HTTP 応答、メモリ |
| Codec | バイト↔値の変換 | JSON / XML / YAML の読み書き |
| Source | 論理的な寄与（どのフィールドをどの優先度で） | 「ユーザー設定ファイルの Server 部分」 |
| Fragment | 存在を記憶する差分 | 「Port だけ」を持つ状態 |
| Patch | 単一フィールドの編集 | 「Port を 9000 にする」 |
| Options | アプリが見るファサード | 読み・保存・監視・説明・診断 |

**読み込み**では、各 Source が Resource からバイトを取得し、Codec が Fragment に変換します。ランタイムが優先度順に「存在する」フィールドだけを 1 つのモデルへ重ねます。Fragment は「メンバーが存在しない」と「null/既定値で存在する」を区別するため、層の合成で「未設定」が「既定値に設定」を上書きすることはありません。

**書き込み**は逆向きです。アプリは普通のモデル値を編集するだけで、内部では変更が Fragment 差分になり、`WriteRoute` / `WritePlan` が指す Source にだけ届きます。無関係な Source は変更されません。

## 主な特徴

- **複数ソースの優先度マージ**: `Priority` が大きい Source が勝ちます。`GetDetailsAsync` で「どの値がどこ由来か」を検査できます。
- **読み取り専用ソース**: 環境変数・コマンドライン・既定の HTTP ソースは読み取り専用です。読み取り専用の値への書き込みは黙って無視されず、競合エラーになります。
- **スパース書き込み**: 変更したフィールドだけを対象層に保存します。既定値のままのフィールドは書き出されません（ユーザーが明示した `null` は尊重されます）。
- **編集セッション**: `OpenEditSessionAsync` で複数の変更をまとめて適用できます。`CommitAsync` まではインメモリです。競合時は既定で失敗しますが、`WriteConflictResolution.LastWriteWins` も選択できます。
- **安全な書き込み**: アトミック書き込み、他プロセスとの競合検出・自動マージ、自動リトライに対応しています。`FileResource` はバックアップ世代管理を備え、既定で `.bak` を 1 世代保持し、`RestoreLatestBackupAsync` で復元できます。
- **プリセット**: `UseCommonSources` が標準的な層構成（global / local / environment など）を組み立てます。
- **プロジェクション / マウント**: 既存 Source を別モデルに整形（projection）したり、ネストしたパスに別 Source を接続（mount, `AddMounted`）したりできます。
- **マージ挙動のカスタマイズ**: `[ConfiglueMerge]` でメンバーごとのマージ挙動を変更できます（組み込み: `Append`, `Deep`, `Replace`, `SetUnion`。カスタム戦略も可能）。コレクションの層合成・順序はここで決まります。
- **スキーマ移行 / ストレージ移行**: `[ConfigluePreviousVersion]` と `Fragment.FromPrevious` により、旧バージョンの設定を新形式へ自動変換できます。既存ファイルを Source として登録することも可能です。
- **セクション**: `JsonSectionResource` / XML 要素 / YAML マッピングで、ファイルの一部を独立した Resource として扱えます。書き込み時はコメント・空白・引用・スカラー形式を保持し、同じファイル内の独立セクションは 1 回の物理書き込みにバッチされます。
- **多様な Resource**: `ZipEntryResource`、HTTP（ETag 条件付き書き込み・ポーリング）、S3、Dapr などを利用できます。`Configlue.Transformer.AES` により、Resource と Codec の間のバイトを AES-GCM で暗号化・認証することもできます。
- **JSON Schema 生成**: `Configlue.JsonSchema` で、人間が設定ファイルを書くための JSON Schema を生成・エクスポートできます。
- **Native AOT 対応**: ソース生成の `JsonSerializerContext` を渡すとトリミング / AOT に強くなります。
- **DI / リアクティブ統合（任意）**: `Configlue.Extensions.DI` による DI 統合、`Configlue.Extensions.MSOptions` による `IOptions<T>` アダプター（同期ゲッターは非同期ソース読み取り中にブロックするため、非同期フローでは `GetValueAsync` を推奨）、`Configlue.Extensions.Reactive`（System.Reactive）と `Configlue.Extensions.R3` による `ObserveChanges()` / `ObserveValues()` / `ObserveReloadFailures()` などのリアクティブ統合が利用できます。
- **プロファイル / 動的オプション**: 名前付きオプションや永続プロファイルで、ランタイムを単位にオプションを作成・削除できます。

### 既知の制限

- 異なる Resource 間の書き込みはアトミックではありません。
- Source の退役は現在の options インスタンスに閉じ、実データは残ります。
- Source 集合は options ランタイムで固定です。

## 基本的な使い方

インストールは `dotnet add package Configlue` から始め、必要な機能パッケージを追加します。

次のコードを `example.cs` に保存し、`dotnet run example.cs` で実行できます（.NET 10 以降）。

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

### 値の由来を調べる

`GetDetailsAsync` を使うと、マージ後の各値がどの Source から来たのか、その Source が書き込み可能かどうかを検査できます。

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

### スパース保存と Unset

指定したメンバーだけを更新するパッチを保存できます。`Unset()` は書き込み先 Source の寄与だけを取り消し、下位優先度の Source が値を提供できるようにします。

```csharp
await options.SaveAsync(patch =>
{
    patch.Name = "Bob";
    patch.RunCount.Unset();
});
```

### その他の API

- `IReadOnlyOptions<T>` … 日常の読み取り面は `GetValueAsync` と `OnChange`。
- `SaveAsync(patch => ...)` … 生成される Patch でスパース保存。
- `OpenEditSessionAsync()` … まとめて編集し `CommitAsync` で確定。
- `ApplyPatchesAsync` + `StateSourcePatch` … 明示的なソース別マルチ書き込み。
- `StateWritePlan.For<T>().Route(...)` … 書き込みルーティング。
- `SourceKey<TModel>` と `options.Source(key)` … ソース単位の操作。
