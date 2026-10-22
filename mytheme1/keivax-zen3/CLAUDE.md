# keivax-zen3

VS Code カラーテーマ（modernUI + `"pill"` タブ前提）．要求仕様は `README.md` が正で，`## Prompt ...` の積み上げで管理する．

## 構成と編集ルール

- `themes/keivax-zen3-theme.json` は元テーマ．alpha のキー構成の参照元なので編集しない．
- `themes/keivax-zen3-alpha-theme.json` は `build_alpha.py` の生成物（`package.json` が参照）．直接編集せず，`build_alpha.py` の `COLORS_SPEC` / `TOKEN_SETTINGS` / `SEMANTIC_SETTINGS` を編集して再生成する．
- 背景違いの比較版 `themes/keivax-zen3-alpha-blue-theme.json`（テーマ名「Keivax-zen3 Blue」）も同じ表から生成する（`VARIANTS`）．背景色以外の割り当ては両版で共通．
- 色は README の NewColorPalette のみ（透明度の付加は可）．`#rrggbb` の直書きは避け，`build_alpha.py` 冒頭の役割名定数を使う．新しい色が必要ならパレット内から定数を追加する．
- 元JSONのキー・`tokenColors` の name/scope・順序は変えない（`validate_alpha.py` が検査する）．
- ユーザーからの新しい指示は README に `## Prompt zen3 N` として追記する．

## 変更後の検証

変更のたびに次の順で実行する．引数なしの `check_palette.py` / `validate_alpha.py` は alpha（標準版）が対象で，Blue 版はファイルを引数に渡す．

1. `python build_alpha.py`（両版を生成）
2. `python check_palette.py` と `python check_palette.py themes/keivax-zen3-alpha-blue-theme.json`
3. `python validate_alpha.py` と `python validate_alpha.py themes/keivax-zen3-alpha-blue-theme.json`

目視確認は F5（`Extension` 起動構成）で開発ホストを開き，`sandbox.py` と `sandbox.rs` を見る．トークンの色の原因は `Developer: Inspect Editor Tokens and Scopes` で確認する．

## 設計方針（合意済み）

- 背景は `#1e2323` に厳密統一する．サジェスト・ホバー・メニュー・通知などのポップアップも同色にし，`widget.shadow` などの影のみで分離する．
- 枠線は透明が基本．フォーカス・アクティブ表示・入力欄・ハイライト枠など機能的なものだけ残す．
- エラー `#dd2a57`・警告 `#fcb346` は診断専用．シンタックスでは使わない．
- ルーラー・ガター・ハイライト・ファイル名の色は，赤系と黄系を避けて互いに区別できるようにする（追加=緑，変更=青，削除=紫）．
- 自作コードは鮮やかな色（宣言は太字），外部ライブラリ/ビルトインは別色の斜体にする．
- 役割ごとの色の近さは `validate_alpha.py` の距離（OKLab x100）で確認する．
- 重要なコード上の要素に白系の色は使わない．
- 非アクティブ・静かな文字や線は寒色の灰（`DIM` / `MUTED` = `FG2` の透明度違い）にする．暖色寄りの灰は使わない．暖灰 `DOC` は Docstring 専用（コメント・キーワードと色相で区別するため）．
- ユーザーは色の違いを見分けにくい特性がある．色相の違いだけに頼らず，明度差・太字/斜体/下線・バッジなどの併用を前提に設計する．
- Git 装飾（ファイル名の色）は視認性を優先し，コンセプトから外れてもよい．変更=`FG`（最も明るい），コミット対象（追加・名前変更・ステージ済み変更）=淡緑，未追跡=オリーブ（控えめ），無視=`DIM`．エクスプローラーの基本文字は `FG2` で，変更が目立つようにする．
- 選択・ホバー・タブの強調は `BLUE` の透明度で作る（`BLUE_M` はボタン・バッジ・エディタ本文の選択）．

## コミット規約

- 変更のたびにコミットする．複数の変更をまとめない．
- `main` に直接コミットする．push はユーザーの指示があるまで行わない．
- 書式は `[add]` / `[update]` / `[WIP]` + 説明（日本語可）．例: `[update]背景色を #1e2323 に統一`
- コミットメッセージに Claude 関係の記述（`Co-Authored-By` など）は書かない．
- 生成物（alpha JSON）は，生成元スクリプトの変更と同じコミットに含める．
- `git add` はファイル名を明示する．ワークスペース外の未追跡ファイル（`../keivax-zen2/hoge.md` など）はコミットしない．
