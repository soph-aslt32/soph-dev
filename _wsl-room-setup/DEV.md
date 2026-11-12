# DEV.md — 開発途中の未決定事項

<!-- markdownlint-disable MD036 -->
仕様は README.md です。このファイルには、**まだ決めていないこと・検討中のこと**だけを書きます。
決まったら README（と各スクリプト）に反映し、ここからは消してください。

最終更新: 2026-11-12

---

## 1. 判断待ちの事項

### 1.1 プロジェクトの中の `.git/config`・`.git/hooks`・`.claude/settings*.json` を、Claude の書き換え禁止に加えるか

- **背景**: README 1 章の ⑤ で、サンドボックスの外で自動で実行されるホームフォルダのファイル（`~/.bashrc`・`~/.gitconfig`・`~/.claude/settings.json` など）は、
  Claude のファイル編集機能で書き換えられないようにした（`templates/claude-settings.json.tmpl` の `permissions.deny`）。
  プロジェクトの中の次のファイルも同じ種類だが、禁止していない。今は Claude Code の「保護されたパス」として、書き換えのたびに確認が出るだけ。
  - `.git/config`: VS Code はフォルダを開いている間、裏で git を繰り返し実行する。`core.fsmonitor` などを書かれると、何もしなくてもサンドボックスの外で実行される
  - `.git/hooks`: commit や push をしたときに実行される
  - `.claude/settings.json`・`.claude/settings.local.json`: hooks を書かれると、次に Claude Code を起動したときにサンドボックスの外で実行される
- **案**: `Edit(~/projects/**/.git/config)`、`Edit(~/projects/**/.git/hooks/**)`、`Edit(~/projects/**/.claude/settings.json)`、
  `Edit(~/projects/**/.claude/settings.local.json)` を deny に加え、`verify-room.sh` の検証 13 の一覧にも加える。
- **影響**: Claude は git の操作をコマンドで行う（コマンドからは、サンドボックスのため、もともと書けない）。設定ファイルは人が編集する前提なので、
  Claude の作業の自由はほとんど減らない。
- **おすすめ**: 加える。

### 1.2 Claude が書いたコードを、サンドボックスの外で動かすことの注意を README に書くか

- **背景**: 仕組みでは防げない。あなたがターミナルで `cargo build`・`npm test`・`uv run` などを実行したり、
  VS Code の拡張機能が自動で実行したりすると、Claude の書いたコードがサンドボックスの外で動く。
  - rust-analyzer: フォルダを開くと `build.rs` と手続きマクロを自動で実行する（部屋には Rust が入っている）
  - Python 拡張機能: テストを探すときに `conftest.py` などを実行する
- **案**: README 6.4 に、ビルドとテストはなるべく Claude に頼む（サンドボックスの中で動く）こと、自分で動かす前に変更を確かめること、
  rust-analyzer の自動実行を止める設定（`rust-analyzer.cargo.buildScripts.enable`・`rust-analyzer.procMacro.enable`）を書く。
- **おすすめ**: 書く。

### 1.3 LocalGit: 写すコミットに `.gitattributes`・`.lfsconfig`・`.gitmodules` があるとき、確認画面で注意を出すか

- **背景**: Git for Windows には、ふつう Git LFS が有効な状態で入っている。部屋の中で `.gitattributes` と `.lfsconfig` を書かれると、
  それを Windows 側で `git pull`・checkout したときに、git-lfs が `.lfsconfig` に書かれた接続先へ通信することがある。
  部屋には Git LFS を入れていないので、部屋の側では起きない。
- **案**: 同期スクリプト（`templates/Sync-Room.ps1.tmpl`）の部屋 → Windows 側の確認画面で、写すコミットの中でこれらのファイルが
  追加・変更されていたら `[注意]` を表示する（十数行）。
- **おすすめ**: 出す。

### 1.4 同期スクリプトだけを作り直す、軽い方法を用意するか

- **背景**: ひな形（`templates/Sync-Room.ps1.tmpl`）を直したとき、生成済みの同期スクリプトを作り直すには `-Resume` を実行するしかない。
  `-Resume` は、部屋の再起動 2 回やパッケージの更新まで行うので時間がかかる。
- **案**: New-SecureRoom.ps1 に、同期スクリプトの生成と `-Initialize` だけを行うオプションを加える。または、今のままにする。

### 1.5 配布物の管理

- `rooms/`（部屋ごとに生成される同期スクリプト）は生成物なので、配布物を git などで管理する場合は管理の対象から外す。
- README 9 章のファイル構成に `.gitattributes` が載っているが、今のフォルダには無い。用意するか、README から消すか。

---

## 2. 実機で確かめていないこと

README 11 章の「まだ実機で確かめていません」を参照。主なもの:

- README 1 章の ⑤ の書き換えの禁止が効くこと（README 6.2 の表の 3 行）
- README 1 章の ⑤ の読み取りの禁止に加えた `~/.ssh`・`~/.aws` が効くことと、作業フォルダの外を初めて読むときの確認で Yes を選んだあとの動作（README 6.2 の表の 2 行）
- LocalGit: 削除・タグ・HEAD の変更の同期、止まるべき場合（両側の変更、fast-forward でない、タグの付け替え、日本語のブランチ名）、
  `-Direction`、大きなリポジトリ、パスに空白や `'` を含むリポジトリ、`-Resume` での GitHub と LocalGit の混在の防止、
  部屋の中から New-SecureRoom.ps1 を実行したときに止まること、同じ名前で部屋を作り直したとき（2026-11-12 に直した不具合）

---

## 3. 既知の制約（今のところ対応しない）

- Windows の環境変数 `WSLENV` に書いた変数は、wsl を呼ぶたびに部屋へ渡る（New-SecureRoom.ps1・同期スクリプトとも）。設定していなければ関係ない。
- WSLg（検証 W1）や `/mnt/wsl`（検証 W2）の窓口は、部屋の設定では閉じられない（サンドボックスの外で動くプログラムからは届く）。
- Windows のユーザーフォルダの名前（room.conf の `windows_user`）は、部屋の中の Claude からも見える
  （VS Code 拡張フォルダのマウント先 `/mnt/c/Users/<名前>/...` が `/proc/mounts` に出る。部屋の中の room.conf にも書かれている）。
  フォルダの中身は見えない。マウントに必要なので、名前を隠すことはできない。
- LocalGit:
  - ブランチ・タグの名前は、半角英数字と `. _ + / -` だけ
  - Windows 側と部屋の並行作業には対応しない（両側で変更すると止まる）
  - `refs/notes` などの、ブランチ・タグ以外の ref は同期しない
  - Windows 側へ写したコードは、部屋の中の Claude Code が書いたもの（Windows 側で開く・ビルドする前に確かめる）
