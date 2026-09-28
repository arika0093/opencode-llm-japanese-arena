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

