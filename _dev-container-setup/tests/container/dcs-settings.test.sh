#!/usr/bin/env bash
# dcs-settings（~/.claude/settings.json を置き直す）のテスト。dcs-image のコンテナの中で、dev として bash -s で動かす
# （tests\TestHelpers.ps1 の Invoke-ImageTest）。最後に PASS を表示する。
set -Eeuo pipefail
f=~/.claude/settings.json; p=/usr/local/share/dcs/claude-settings.json; m=/etc/claude-code/managed-settings.json
rm -f ~/.claude/settings.json*
dcs-settings; diff <(jq -S . "$f") <(jq -S -s '.[0] * .[1]' "$p" "$m")                       # 1. 無いときは、好み * 守り
echo '{"model":"x","permissions":{"deny":["Bash(git push --force:*)"],"allow":["Bash(ls)"]}}' > "$f"; dcs-settings
[[ $(jq -r .model "$f") == x && $(jq -r '.permissions.allow[0]' "$f") == 'Bash(ls)' ]]       # 2. ほかの設定は残す
[[ $(jq -c .permissions.deny "$f") == "$(jq -c '.permissions.deny + ["Bash(git push --force:*)"]' "$m")" ]]  #    deny は、守りのものに、利用者が足したものを続ける（消さない。I3）
ls "$f".bak-* > /dev/null                                                                     #    元のファイルを残す
n=$(ls "$f".bak-* | wc -l); dcs-settings; [[ $(ls "$f".bak-* | wc -l) == "$n" ]]             #    2 回目は何もしない
echo '{"permissions":{"deny":"x"}}' > "$f"; dcs-settings
[[ $(jq -c .permissions.deny "$f") == "$(jq -c .permissions.deny "$m")" ]]                      #    deny が配列でなければ、守りのものだけ
echo 'not json' > "$f"; dcs-settings; diff <(jq -S . "$f") <(jq -S -s '.[0] * .[1]' "$p" "$m")  # 3. 壊れていたら作り直す
n=$(ls "$f".bak-* | wc -l); dcs-settings; [[ $(ls "$f".bak-* | wc -l) == "$n" ]]             # 4. 同じなら何もしない
echo PASS
