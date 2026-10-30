# wsl-room-setup — Claude Code 用の「部屋」を自動で作るスクリプト
<!-- markdownlint-disable MD036 MD040-->
Claude Code を安全に動かすための WSL2 のディストリビューション（以下「部屋」）を、
PowerShell のコマンド 1 つで作ります。

部屋の中からは Windows のファイルやプログラムにほぼ触れられず、
Claude Code はサンドボックス（作業フォルダの外に書き込めない・許可したドメインにしか通信できない）の中で動きます。

```md
Windows側のデータとして意図的に見せているもの

- VS Code の拡張機能フォルダ（VS Code から接続するために必要）
- WSL が自動で共有する GPU ドライバー（/usr/lib/wsl 配下）
```

- 設計の背景と仕様: 申し送り書（`wsl-secure-room-handoff.md`）
- **安全のための約束事（不変条件）は申し送り書の第 7 章**にあります。これを緩める変更はしないでください。

---

## 目次

1. [安全のしくみ（かんたんな説明）](#1-安全のしくみかんたんな説明)
2. [必要なもの](#2-必要なもの)
3. [ファイルを Windows 側に用意する](#3-ファイルを-windows-側に用意する)
4. [設定ファイル room.conf を編集する](#4-設定ファイル-roomconf-を編集する)
5. [実行する](#5-実行する)
6. [構築後の作業](#6-構築後の作業)
7. [オプション](#7-オプション)
8. [部屋の中で検証をやり直す](#8-部屋の中で検証をやり直す)
9. [ファイル構成](#9-ファイル構成)
10. [トラブルシューティング](#10-トラブルシューティング)
11. [対応していない環境・まだ確認できていないこと](#11-対応していない環境まだ確認できていないこと)
12. [部屋を削除したいとき](#12-部屋を削除したいとき)

---

## 1. 安全のしくみ（かんたんな説明）

| 守り | 何をしているか | 何を防ぐか |
|---|---|---|
| ① wsl.conf | C ドライブを部屋に見せない。部屋から Windows のプログラムを起動できなくする | 部屋の中のすべて（Claude Code を含む）から Windows のファイル・プログラムへのアクセス |
| ② fstab | VS Code の接続に必要なフォルダ 1 つだけを**読み取り専用**で見せる | Windows 側で実行されるファイルの改ざん |
| ③ sudo にパスワード必須 | Claude にはパスワードを教えない | Claude が root（管理者）になって ①② を元に戻すこと |
| ④ サンドボックス | Claude が実行するコマンドを閉じ込める | 作業フォルダの外への書き込み、許可していない通信 |
| ⑤ Claude Code の権限ルール | Claude のファイル読み取り機能を制限する | 作業フォルダの外のファイルの読み取り |

これらは互いに支え合っています。たとえば ③ は、① で「部屋から wsl.exe を呼べない」状態になっていて初めて意味を持ちます
（Windows 側から `wsl -u root` を使うと、パスワードなしで root になれるためです）。

**部屋の中には、漏れて困る認証情報（パスワード、秘密鍵、API キーなど）を置かないでください。**

---

## 2. 必要なもの

- Windows 11（新しい WSL が使える Windows 10 でも可）
- WSL がインストールされていること（PowerShell で `wsl --version` を実行して、バージョンが表示されれば OK）
- VS Code と、その拡張機能「WSL」（`ms-vscode-remote.remote-wsl`）
  - 入っていなければ PowerShell で: `code --install-extension ms-vscode-remote.remote-wsl`
- Windows のユーザーフォルダが `C:\Users\<半角英数字の名前>` であること（[11 章](#11-対応していない環境まだ確認できていないこと)参照）
- インターネット接続

---

## 3. ファイルを Windows 側に用意する

このフォルダ（`wsl-room-setup`）は、今 Claude Code が動いている部屋の中にあります。
Windows からは次の場所に見えています（`<今の部屋の名前>` は `wsl -l -v` で確認できます）。

```
\\wsl.localhost\<今の部屋の名前>\home\<Linuxのユーザー名>\projects\wsl-room-setup
```

### ⚠ 実行する前に、Windows 側にコピーして中身を確かめてください

このフォルダは部屋の中にあるので、部屋の中のプログラム（Claude Code を含む）が書き換えられます。
一方で `New-SecureRoom.ps1` は **Windows のあなたの権限で動き、部屋の root 権限も使います**。
ですから、部屋の中にあるファイルを直接実行するのではなく、

1. Windows 側の自分のフォルダにコピーし、
2. 中身（特に `New-SecureRoom.ps1`）に見覚えのない変更が無いことを確かめてから、
3. コピーしたほうを実行してください。

コピーは PowerShell で次のようにできます（`<今の部屋の名前>` と `<Linuxのユーザー名>` は置き換えてください）。

```powershell
Copy-Item -Recurse "\\wsl.localhost\<今の部屋の名前>\home\<Linuxのユーザー名>\projects\wsl-room-setup" "$env:USERPROFILE\wsl-room-setup"
```

> エクスプローラーでコピーしても構いません。
> `New-SecureRoom.ps1` をメモ帳以外のエディターで保存し直すと、文字コードが変わって動かなくなることがあります
> （[10 章](#10-トラブルシューティング)参照）。

---

## 4. 設定ファイル room.conf を編集する

コピーしたフォルダの `room.conf` をメモ帳などで開いて、**`linux_user` と `windows_user` を必ず記入**します。
スクリプトはこれらの値を推測したり自動で調べたりしません。空欄のままだと、最初の確認で止まります。

```ini
# 部屋の中で使う Linux のユーザー名
linux_user = taro

# Windows のユーザーフォルダの名前（C:\Users\<ここ> の部分）
windows_user = Taro

# Claude Code のサンドボックスの中で動くコマンドが、通信してよいドメイン（カンマ区切り）
allowed_domains = registry.npmjs.org, pypi.org, files.pythonhosted.org
```

- `linux_user`: 部屋の中で使う Linux のユーザー名です。半角英小文字で始まり、英小文字・数字・`_`・`-` だけを使った
  32 文字以内の名前にします。**部屋を作るときに聞かれるユーザー名には、これと同じ名前を入力します**
  （違う名前を入力すると、スクリプトが気づいて止まります）。
- `windows_user`: Windows のユーザーフォルダの名前です。エクスプローラーで `C:\Users` を開くと確認できます。
  VS Code の拡張機能フォルダ `C:\Users\<windows_user>\.vscode\extensions` を、部屋に読み取り専用で見せるために使います。
  半角英数字と `.` `_` `-` だけに対応しています（[11 章](#11-対応していない環境まだ確認できていないこと)参照）。
- `allowed_domains`: Claude が実行するコマンド（`npm install` など）が通信してよいドメインです。
  ここに無いドメインへの通信はブロックされます。`*.example.com` のように先頭に `*.` を付けると、
  サブドメインをまとめて許可できます。`*`（すべて許可）は使えません。
- 保存するときの文字コードは **UTF-8** にしてください（メモ帳の既定は UTF-8 です）。

---

## 5. 実行する

### 5.1 PowerShell を開いて、コピーしたフォルダに移動する

管理者として開く必要はありません。

```powershell
cd $env:USERPROFILE\wsl-room-setup
```

### 5.2 スクリプトの実行を許可する（この PowerShell の画面だけ）

```powershell
Set-ExecutionPolicy -Scope Process Bypass
```

画面を閉じると元に戻ります（パソコン全体の設定は変わりません）。

### 5.3 まずはドライランで確認する（おすすめ）

何も変更せずに、何をするかだけを表示します。

```powershell
.\New-SecureRoom.ps1 -DryRun
```

### 5.4 本番

```powershell
.\New-SecureRoom.ps1
```

途中で次のことを聞かれます。

1. **ディストリビューション名**: 表示された一覧の NAME 列から、`Ubuntu-26.04` のようにそのまま入力します。
2. **部屋の名前**: 半角英小文字・数字・ハイフンで入力します（例: `dev`）。すでにある名前は使えません。
3. **確認**: 内容を見て、よければ `y` を入力します。
4. **Linux のユーザー名とパスワード**（`wsl --install` の画面）:
   - ユーザー名には、**room.conf の `linux_user` と同じ名前**を入力します。
   - パスワードは入力しても画面に何も表示されませんが、正常です。
   - **このパスワードは Claude Code を含め、誰にも教えないでください。**
     sudo（管理者の権限）を守る大切なパスワードです。忘れないようにしてください。
   - 入力が終わって `ユーザー名@...:~$` のような表示が出たら、**`exit` と入力して Enter** を押します。
     そのあとはスクリプトが自動で進めます。

全体で 5〜15 分ほどかかります（パッケージの更新の量によります）。

### 5.5 期待される表示（例）

最後に自動検証の結果が表示されます。`[FAIL]` が 1 つも無ければ成功です。

```
==> 自動検証（root の権限で行う項目）
== 部屋の検証（root の権限で行う項目）==
[PASS] R1  sudo の設定ファイルに NOPASSWD などが無い
[PASS] R2  taro の sudo 権限にパスワード不要のものが無い
[PASS] E3  /etc/sudoers と /etc/sudoers.d/ が root 所有で root 以外は書き込めない
...
== 部屋の検証（一般ユーザーとして行う項目）==
[PASS] 01  C ドライブ全体が見えない
[PASS] 02  Windows への窓は VS Code 拡張フォルダの 1 つだけで、読み取り専用
...
[SKIP] 09  sudo の設定に NOPASSWD が無い
           sudo の設定ファイルは root しか読めないため、R1 で確認します。
...
[SKIP] 12  claude doctor
           claude doctor はログイン後に手動で確認します（README「ログイン後の手動確認」）。
...
結果: PASS 18 / FAIL 0 / SKIP 2
FAIL はありません。
  [完了] 自動検証で FAIL はありませんでした（SKIP の項目は、ログイン後に手動で確認します）。
```

`[SKIP]` は「この方法では確認しない（別の場所で確認する）」という意味で、失敗ではありません。

途中で止まった場合は、表示されたメッセージに従って原因を取り除き、
`-Resume` を付けて実行すると続きからやり直せます（部屋は消えません）。

---

## 6. 構築後の作業

### 6.1 Claude Code にログインする

```powershell
wsl -d dev --cd ~
```

部屋に入ったら:

```bash
claude
```

表示された URL をコピーして、**Windows のブラウザに貼り付けて**ログインします。
（部屋から Windows のプログラムを起動できないようにしているため、ブラウザは自動では開きません。）

### 6.2 ログイン後の手動確認

ここは自動化していません（Claude Code へのログインが必要なため）。

**(1) ターミナルで（Claude Code の外で）**

```bash
claude doctor
```

→ 設定のエラーが表示されないこと。

**(2) Claude Code の中で**

まず、試験用のフォルダと、フォルダの外のファイルを用意します。

```bash
mkdir -p ~/projects/sandbox-test
echo "外のファイル" > ~/outside.txt
cd ~/projects/sandbox-test
claude
```

| 確認すること | 期待される結果 |
|---|---|
| `/sandbox` を開く | 「Dependencies」タブが出ない。Overrides が **Strict sandbox mode** |
| `/status` を開く | Setting sources に **User settings** がある |
| Claude に「`touch ~/sandbox-probe` を実行して」と頼む | Read-only file system で**失敗する** |
| Claude に「`~/outside.txt` を読んで」と頼む | **拒否される** |
| Claude に「`curl --noproxy '*' https://example.com` を実行して」と頼む | **接続できない** |
| Claude に「このフォルダに `hello.txt` を作って」と頼む | **成功する** |

> ご自身が `!` を付けて打つコマンドはサンドボックスの外で動くので、この確認には使えません。
> 必ず Claude に頼んで実行させてください。

確認が終わったら、`~/outside.txt` と `~/projects/sandbox-test` は消して構いません。

**(3) VS Code で接続できること**

[6.3](#63-vs-code-で開く) の方法で部屋に接続し、「WSL Daemon exited with code 0」などのエラーが出ずにフォルダが開けば OK です。

### 6.3 VS Code で開く

Windows の PowerShell から:

```powershell
code --remote wsl+dev /home/taro/projects/<プロジェクト名>
```

または VS Code で F1 → 「WSL: Connect to WSL using Distro...」→ 部屋の名前。

部屋の中で `code .` は使えません（Windows のプログラムを起動できないようにしているため。想定どおりです）。

毎回入力するのが面倒なら、PowerShell のプロファイル（`notepad $PROFILE` で開けます）に次を追加すると、
`devcode <プロジェクト名>` で開けるようになります（`dev` と `taro` は置き換えてください）。

```powershell
function devcode($name) { code --remote wsl+dev "/home/taro/projects/$name" }
```

### 6.4 ふだんの使い方の約束

- Claude Code は**必ず `~/projects/<プロジェクト名>` の中で**起動してください。
  ホーム（`~`）や `~/projects` で起動すると、すべてのプロジェクトが Claude から見えてしまいます。
- sudo のパスワードを Claude に教えないでください。
- 部屋の中に、Windows 側の秘密鍵やクラウドの認証情報などをコピーしないでください。
- リポジトリを clone したら、Claude Code を起動する前に、そのリポジトリの `.claude/` フォルダ
  （特に `settings.json` と `settings.local.json`）の中身を確認してください。
  プロジェクトの設定はこの部屋のユーザー設定（`~/.claude/settings.json`）より優先されるため、
  サンドボックスを弱める設定（`"sandbox": {"enabled": false}` など）が入っていると、守りが外れてしまいます。
- clone に使うトークンなどを git に保存させる場合、保存先の `~/.git-credentials` は
  Claude が実行するコマンドから読めないように設定してあります（トークンを保存してから Claude Code を起動してください）。
  ただし、トークンを clone の URL に直接書くと、プロジェクトの `.git/config` に残って Claude から読めてしまうので避けてください。

### 6.5 ステータスライン

部屋を作ると、このフォルダの `statusline.sh` が部屋の `~/.claude/statusline.sh` に置かれ、
`~/.claude/settings.json` の `statusLine` から `bash ~/.claude/statusline.sh` として実行されるように設定されます。
Claude Code を起動すると、画面の下にモデル名・作業フォルダ・使用量などが表示されます。

- 表示を変えたいときは、このフォルダの `statusline.sh` を差し替えてから新しく部屋を作るか、
  既存の部屋なら `-Resume` を付けて実行します（部屋の中の元のファイルは `statusline.sh.bak-日時` として残します）。
- このファイルは Claude Code のサンドボックスの**外**で、あなたの権限で繰り返し実行されます。
  中身を確認したものだけを置いてください。

---

## 7. オプション

| 書き方 | 意味 |
|---|---|
| `-DryRun` | 何も変更せず、実行する予定の内容だけを表示する |
| `-Resume` | 既存の部屋に対して、作成以外の手順をやり直す（途中で止まったとき、設定を元に戻したいとき） |
| `-VerifyOnly` | 既存の部屋に対して、自動検証だけを行う |
| `-RoomName dev` | 部屋の名前を指定する（質問を省略） |
| `-Distro Ubuntu-26.04` | ディストリビューションを指定する（質問を省略） |
| `-ConfigPath <パス>` | room.conf 以外の設定ファイルを使う |

例:

```powershell
.\New-SecureRoom.ps1 -RoomName dev -Resume
.\New-SecureRoom.ps1 -RoomName dev -VerifyOnly
```

`-Resume` は部屋を途中で 2 回再起動するので、部屋の中で動いている Claude Code やターミナルはすべて終了します。
また、`~/.claude/settings.json` を仕様どおりの内容に戻します（元のファイルは `settings.json.bak-日時` として残します）。

---

## 8. 部屋の中で検証をやり直す

部屋の中のターミナルから、いつでも検証できます。

```bash
bash /usr/local/lib/wsl-room-setup/verify-room.sh               # 一般ユーザーとして行う検査
sudo bash /usr/local/lib/wsl-room-setup/verify-room.sh --root   # root の権限が必要な検査（パスワードを聞かれます）
```

> **Claude Code に検証を実行させないでください。** サンドボックスの中では root のファイルが
> 別の持ち主（nobody）に見えるため、正しく判定できません。ご自身でターミナルから実行してください。

---

## 9. ファイル構成

```txt
wsl-room-setup/
├── README.md                 この説明書
├── New-SecureRoom.ps1        Windows 側の司令塔（これを実行する）
├── room.conf                 設定ファイル（Linux のユーザー名、Windows のユーザーフォルダ名、通信を許可するドメイン）
├── lib.sh                    部屋の中のスクリプトが共通で使う部品
├── provision-root.sh         部屋の中で root として行う設定（wsl.conf、fstab、パッケージ、AppArmor）
├── provision-user.sh         部屋の中で一般ユーザーとして行う設定（Claude Code、PATH、settings.json、ステータスライン、~/projects）
├── verify-room.sh            自動検証
├── statusline.sh             Claude Code のステータスライン（部屋の ~/.claude/statusline.sh に置かれる）
├── templates/
│   ├── wsl.conf.tmpl         /etc/wsl.conf のひな形
│   └── claude-settings.json.tmpl   ~/.claude/settings.json のひな形
└── .gitattributes            改行コードの指定（Linux 側のファイルは LF）
```

部屋の中では、スクリプト一式と room.conf のコピーが `/usr/local/lib/wsl-room-setup/`（root 所有）に置かれます。
Claude や一般ユーザーは書き換えられないので、検証の基準（期待値）として信用できます。

### 処理の流れ

1. 前提条件の確認（WSL、VS Code の WSL 拡張機能、ファイルの改行コード、room.conf）
2. `wsl --install <ディストリビューション> --name <部屋の名前>`（room.conf の `linux_user` と同じユーザー名と、パスワードを入力）
3. 部屋が WSL2 で動いていること、部屋のユーザーが room.conf の `linux_user` と同じことを確認
4. スクリプト一式と room.conf を部屋の中へコピーし、ハッシュ値で一致を確認
5. `provision-root.sh --phase base`: パッケージ、`/etc/wsl.conf`、AppArmor
6. 部屋を再起動（C ドライブが見えなくなる）
7. `provision-root.sh --phase mount`: VS Code 拡張フォルダの読み取り専用マウント
   （C ドライブが見えている間にやると本物の C ドライブの上にフォルダを作ってしまうので、再起動後に行う）
8. `provision-user.sh`: Claude Code、PATH、settings.json、ステータスライン（`~/.claude/statusline.sh`）、`~/projects`
9. 部屋を再起動（すべての設定が起動時に正しく反映されるかを確かめるため）
10. `verify-room.sh --root` と `verify-room.sh`

---

## 10. トラブルシューティング

| 起きたこと | 原因 | 対処 |
|---|---|---|
| 「このシステムではスクリプトの実行が無効になっている」 | PowerShell の実行ポリシー | [5.2](#52-スクリプトの実行を許可するこの-powershell-の画面だけ) の `Set-ExecutionPolicy -Scope Process Bypass` を実行 |
| `New-SecureRoom.ps1` を実行すると文字化けや構文エラーが出る | ファイルの文字コードが変わった（BOM 付き UTF-8 でなくなった） | 元のフォルダから `New-SecureRoom.ps1` をコピーし直す。エディターで保存し直さない |
| 「改行コードが CRLF になっています」 | Windows の git などで改行コードが変換された | エクスプローラーか `Copy-Item` で、部屋の中のフォルダからコピーし直す |
| 「部屋「dev」はすでにあります」 | 同じ名前の部屋がある | 別の名前にする。途中で止まった部屋なら `-Resume` を付ける |
| ユーザー作成のあと、スクリプトが先に進まない | `wsl --install` が部屋の中のシェルを開いたまま | `exit` と入力して Enter |
| パスワードを入力しても何も表示されない | Linux の仕様 | そのまま入力して Enter |
| 「部屋のユーザー（…）が、room.conf の linux_user（…）と違います」 | 部屋を作るときに、room.conf と違うユーザー名を入力した | room.conf の `linux_user` を実際のユーザー名に直して `-Resume` を付けて実行する。または部屋を作り直す（`wsl --unregister` で中身はすべて消えます） |
| 「VS Code の WSL 拡張機能が見つかりません」 | room.conf の `windows_user` が違う、または拡張機能が入っていない | `C:\Users` の中の自分のフォルダ名を `windows_user` に書く。拡張機能が無ければ `code --install-extension ms-vscode-remote.remote-wsl` |
| 「部屋に入ると root になる状態です」 | ユーザー作成が終わる前に中断した | 表示に従って `wsl --unregister <部屋の名前>`（中身はすべて消えます）してから、もう一度実行 |
| 検証 02・04・05 が FAIL / VS Code で「WSL Daemon exited with code 0」 | VS Code 拡張フォルダが正しくマウントされていない | `-Resume` で設定をやり直す。直らなければ部屋の中で `cat /etc/fstab` と `mount \| grep -i extensions` の結果を Claude Code に見せて相談 |
| 検証 10 が FAIL（bwrap が失敗する） | AppArmor が bubblewrap を止めている可能性 | 部屋の中で `sysctl kernel.apparmor_restrict_unprivileged_userns` を確認。`1` なら `-Resume` でやり直す（自動でプロファイルを追加します） |
| 検証 06 が FAIL | Windows のプログラムを呼べる状態（とても危険） | `-Resume` でやり直す。直るまでこの部屋で Claude Code を使わない |
| 検証 08・R1・R2 が FAIL | パスワードなしで sudo できる設定がある | 表示された行を `sudo visudo`（または `sudo visudo -f <ファイル>`）で削除 |
| 検証 13 が FAIL | `~/.claude/settings.json` が仕様と違う | `-Resume` で仕様どおりに戻す |
| 部屋に入ると `/mnt/c/...` で始まる、またはエラーになる | `wsl` は Windows の今のフォルダに合わせて開始しようとする | `wsl -d <部屋の名前> --cd ~` で入る |
| 部屋の中で `code .` が command not found | Windows のプログラムを起動できないようにしているため（想定どおり） | [6.3](#63-vs-code-で開く) の方法で Windows 側から開く |
| ログイン時にブラウザが開かない | 同上 | 表示された URL を Windows のブラウザに手で貼る |
| `claude` が Windows 版を指している | Windows 版 Claude Code が別に入っている | Windows 版はサンドボックスに対応していないので、取り違えないよう削除を推奨。部屋の中では `which claude` が `/home/<ユーザー名>/.local/bin/claude` になることを確認 |
| `mount` の結果に `/usr/lib/wsl/drivers type 9p (ro,...)` がある | GPU ドライバーの共有（読み取り専用。C ドライブ全体ではない） | 正常。検証でも対象外にしています |

---

## 11. 対応していない環境・まだ確認できていないこと

### 対応していない環境（スクリプトが途中で止まります）

- **Windows のユーザーフォルダ名にスペースや日本語などが含まれる場合**
  （`C:\Users\山田 太郎` など）。fstab での書き方が未確認のため、room.conf の `windows_user` に書けないようにしています。
- **ユーザーフォルダが `C:\Users\` の下に無い場合**。
- **VS Code Insiders**（拡張フォルダの場所が違うため）。
- **Ubuntu 以外のディストリビューション**。

### まだ実機で確認できていないこと

このスクリプトは、Claude Code がサンドボックスの中で書いたものです（サンドボックスの中からは `wsl.exe` や
PowerShell を実行できません）。2026-10-29 に実機で一度実行し、部屋の作成から自動検証の途中までは動作しました
（`wsl --install` のあと `exit` で戻る流れ、部屋へのファイルのコピー、`wsl -l -o` の読み取りを含む）。
そのとき見つかった、検証 11 で止まってしまう不具合は修正済みです。

次の点は、まだ実機で確かめていません。

- 修正後の自動検証が、最後（E6）まで通ること
- interop を無効にした部屋から、実際に Windows のプログラムを起動できないこと
  （検証 06 は申し送り書どおり「`cmd.exe` などが見つからない」ことを確かめるもので、起動そのものは試していません）
- AppArmor の設定が必要な場合（値が `1`）の手順（Ubuntu 26.04 の WSL では不要だったため）

---

## 12. 部屋を削除したいとき

このスクリプトは部屋を削除しません。削除する場合は、**中身がすべて消えて元に戻せないこと**を理解したうえで、
ご自身で PowerShell から実行してください。

```powershell
wsl --unregister <部屋の名前>
```
