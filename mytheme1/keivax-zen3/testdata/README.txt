このフォルダは JSON 色置換スクリプトの動作確認用の小さなサンプルです。

使い方:
  python replace_json_colors.py testdata/before.json testdata/replacements.json --output testdata/actual.json

期待結果:
  before.json を replacements.json で置換すると、actual.json は after_expected.json と同じ内容になります。

確認ポイント:
- #07040f と #0a0411 が交換される
- #4ecace と #56f725 が交換される
- #3b76bf と #ef52f2 が交換される
- #333333 や "keep this text" は変わらない
- #ffffff は置換対象外のため、そのまま残る
