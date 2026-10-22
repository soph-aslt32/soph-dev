# keivax-zen3

VS Code カラーテーマ（modernUI + `"pill"` タブ前提）．要求仕様は `README.md` が正で，`## Prompt ...` の積み上げで管理する．

## 構成と編集ルール

- `themes/keivax-zen3-theme.json` は元テーマ．alpha のキー構成の参照元なので編集しない．
- `themes/keivax-zen3-alpha-theme.json` は `build_alpha.py` の生成物（`package.json` が参照）．直接編集せず，`build_alpha.py` の `COLORS_SPEC` / `TOKEN_SETTINGS` / `SEMANTIC_SETTINGS` を編集して再生成する．
- 色は README の NewColorPalette のみ（透明度の付加は可）．`#rrggbb` の直書きは避け，`build_alpha.py` 冒頭の役割名定数を使う．新しい色が必要ならパレット内から定数を追加する．
- 元JSONのキー・`tokenColors` の name/scope・順序は変えない（`validate_alpha.py` が検査する）．
- ユーザーからの新しい指示は README に `## Prompt zen3 N` として追記する．

## 変更後の検証

変更のたびに次の順で実行する（いずれも引数なしで alpha が対象）．

1. `python build_alpha.py`
2. `python check_palette.py`
3. `python validate_alpha.py`

目視確認は F5（`Extension` 起動構成）で開発ホストを開き，`sandbox.py` と `sandbox.rs` を見る．トークンの色の原因は `Developer: Inspect Editor Tokens and Scopes` で確認する．

## 設計方針（合意済み）

- 背景は `#1e2323` に厳密統一する．サジェスト・ホバー・メニュー・通知などのポップアップも同色にし，`widget.shadow` などの影のみで分離する．
- 枠線は透明が基本．フォーカス・アクティブ表示・入力欄・ハイライト枠など機能的なものだけ残す．
- エラー `#dd2a57`・警告 `#fcb346` は診断専用．シンタックスでは使わない．
- ルーラー・ガター・ハイライト・ファイル名の色は，赤系と黄系を避けて互いに区別できるようにする（追加=緑，変更=青，削除=紫）．
- 自作コードは鮮やかな色（宣言は太字），外部ライブラリ/ビルトインは別色の斜体にする．
- 役割ごとの色の近さは `validate_alpha.py` の距離（OKLab x100）で確認する．
- 重要な要素に白系の色は使わない．

## コミット規約

- 変更のたびにコミットする．複数の変更をまとめない．
- `main` に直接コミットする．push はユーザーの指示があるまで行わない．
- 書式は `[add]` / `[update]` / `[WIP]` + 説明（日本語可）．例: `[update]背景色を #1e2323 に統一`
- 生成物（alpha JSON）は，生成元スクリプトの変更と同じコミットに含める．
- `git add` はファイル名を明示する．ワークスペース外の未追跡ファイル（`../keivax-zen2/hoge.md` など）はコミットしない．
