# wsl-room-setup — Claude Code 用の「部屋」を自動で作るスクリプト
<!-- markdownlint-disable MD036 MD040-->
Claude Code を安全に動かすための WSL2 のディストリビューション（以下「部屋」）を、
PowerShell のコマンド 1 つで作ります。

起動のしかたは 2 とおりあります。

- **設定ファイルに記入してから実行する**（`room.conf` と、必要なら `room-github.conf` か `room-localgit.conf` に記入 → `New-SecureRoom.ps1` または `room-setup.cmd`）: [4 章](#4-設定ファイル-roomconf-を編集する)・[5 章](#5-実行する)
- **ダブルクリックして画面で答える**（`room-setup-wizard.cmd`）: 設定ファイルに記入する代わりに、同じ内容を画面で聞きます。[5.6](#56-設定ファイルを使わずに画面で答えて実行するroom-setup-wizardcmd)

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
| ③ 部屋の中では root になれない | 部屋のユーザーを sudo などの管理者のグループから外す。管理作業は Windows 側から `wsl -d <部屋の名前> -u root` で入って行う | Claude や、部屋の中で動くほかのプログラムが root（管理者）になって ①② を元に戻すこと |
| ④ サンドボックス | Claude が実行するコマンドを閉じ込める | 作業フォルダの外への書き込み、許可していない通信 |
| ⑤ Claude Code の権限ルール | Claude のファイル読み取り機能・編集機能を制限する | 作業フォルダの外のファイルの読み取り。サンドボックスの外で自動で実行されるファイル（`~/.bashrc`・`~/.gitconfig`・`~/.claude/settings.json` など）と、`~/repos`（LocalGit の部屋の bare リポジトリ）の書き換え |
| ⑥ apt の取得先を https に | パッケージを https で取得し、apt が修正版（CVE-2026-109518）であることを確かめる | 通信の途中で、検証されていないパッケージを root の権限で入れさせられること |

これらは互いに支え合っています。たとえば ③ は、① で「部屋から wsl.exe を呼べない」状態になっていて初めて意味を持ちます
（Windows 側から `wsl -u root` を使うと、パスワードなしで root になれるためです）。

⑤ の書き換えの禁止は、④ を補うものです。Claude が実行するコマンドは ④ で作業フォルダの外に書き込めませんが、
Claude のファイル編集機能（Edit・Write など）はサンドボックスの外の仕組みで、作業フォルダの外への書き込みは「確認で許可すれば書ける」状態です。
そこで、許可しても書けないように、次のものを禁止しています（`~/.claude/settings.json` の `permissions.deny`）。
どれも、あなたがターミナルを開く・git を使う・VS Code で接続する・Claude Code を起動する、といったふつうの操作で、
**サンドボックスの外で自動で実行される**ものです。

- シェルの設定: `~/.bash*`（`.bashrc` など）、`~/.profile`
- git などの設定: `~/.gitconfig`、`~/.config/` の下、`~/.ssh/` の下、`~/.npmrc`
- PATH にあるプログラム: `~/.local/` の下（Claude Code・uv の本体）、`~/.cargo/` と `~/.rustup/` の下（Rust）
- VS Code の部屋の側: `~/.vscode-server/` の下
- Claude Code 自身が実行するもの: `~/.claude/settings.json`、`~/.claude/statusline.sh`、`~/.claude.json`、
  `~/.claude/plugins/` と `~/.claude/dev-mods/` の下

禁止しているのは Claude による書き換えだけで、あなた自身はこれまでどおり編集できます。Claude が読むことや、`~/.claude` のほかの場所
（メモリー・`CLAUDE.md`・`skills` など）を書くことは、これまでどおりです。そのかわり、Claude に「`.bashrc` に PATH を足して」
「ステータスラインを作り直して」（`/statusline`）のように頼んだり、Claude に mod を作らせたりすることはできません（拒否されます）。

③ は、以前は「sudo にパスワード必須」でした。今は部屋のユーザーを sudo グループから外しているので、
部屋の中では、パスワードを知っていても sudo は使えません。これで、部屋の中のプログラムが sudo のパスワードを盗み見たり、
sudo を使った直後のパスワード不要の時間に便乗したりする経路もなくなります。

**部屋の中には、漏れて困る認証情報（パスワード、秘密鍵、API キーなど）を置かないでください。**
例外は、room-github.conf で設定する GitHub の PAT だけです（[4 章](#4-設定ファイル-roomconf-を編集する)）。
これは Claude から読めないように守ったうえで `~/.git-credentials` に保存します。

---

## 2. 必要なもの

- Windows 11（新しい WSL が使える Windows 10 でも可）
- WSL がインストールされていること（PowerShell で `wsl --version` を実行して、バージョンが表示されれば OK）
- VS Code と、その拡張機能「WSL」（`ms-vscode-remote.remote-wsl`）
  - 入っていなければ PowerShell で: `code --install-extension ms-vscode-remote.remote-wsl`
- Windows のユーザーフォルダが `C:\Users\<半角英数字の名前>` であること（[11 章](#11-対応していない環境まだ確認できていないこと)参照）
- インターネット接続
- （GitHub のリポジトリを自動でクローンする場合）GitHub の Personal Access Token（PAT）。[4 章](#4-設定ファイル-roomconf-を編集する)参照
- （LocalGit を使う場合）Windows 側の Git for Windows（**2.46.0 以上**）と、Windows のローカルのフォルダにある bare リポジトリ。[4 章](#4-設定ファイル-roomconf-を編集する)参照

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

> `room-setup-wizard.cmd`（[5.6](#56-設定ファイルを使わずに画面で答えて実行するroom-setup-wizardcmd)）で実行する場合は、この章の作業は不要です。
> 同じ内容を画面で聞かれるので、各項目の意味はこの章を参考にしてください。

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

### GitHub を使う場合: room-github.conf（使わない場合は空欄のまま）

room.conf と同じフォルダにある `room-github.conf` に記入しておくと、部屋を作るときに一度だけ、次のことを自動で行います。

- git の設定（コミットの作者名・メールアドレス、認証情報の保存方法）。内容は [GitHub.md](GitHub.md) の手順と同じです
- PAT の保存（部屋の `~/.git-credentials`。Claude からは読めないように設定されます）
- `repo_url` のリポジトリを、部屋の `~/projects/<リポジトリ名>` にクローン

```ini
user_name = dev-room
user_email = dev-room@example.com
pat = github_pat_xxxxxxxxxxxxxxxx
repo_url = https://github.com/OWNER/REPOSITORY.git
```

- `user_name` / `user_email`: コミットに作者として記録される名前とメールアドレス（git の `user.name` / `user.email`）です。
  GitHub のアカウントと関係のないダミーで構いません。
  ただし、メールアドレスが実在する誰かのアドレスと偶然一致すると、GitHub がその人のコミットとして表示するので、
  `example.com` などの例示用のドメインを使うと確実です。
- `pat`: GitHub の Personal Access Token です。**fine-grained PAT で、対象のリポジトリだけ・Contents の Read and write・有効期限付き**
  で作ることをおすすめします（万一漏れたときの被害を小さくするため）。
- `repo_url`: `https://github.com/OWNER/REPOSITORY.git` の形で書きます（SSH の `git@github.com:...` は使えません）。
- 4 つすべてを記入したときだけ実行します。すべて空欄なら何もしません。一部だけ記入されていると、部屋を作る前に止まります。
- push / pull のときに git が PAT と組にして GitHub に送る「認証用のユーザー名」には、固定の文字列 `pat` を使います
  （GitHub は PAT だけでアカウントを見分けるので、何でも構いません）。`user_name` とは関係ありません。

room.conf と違い、**room-github.conf は部屋の中へコピーしません**（PAT を部屋に持ち込まないため）。
スクリプトが内容を確認して部屋に渡し、PAT は `~/.git-credentials` にだけ保存されます。

- **記入は、Windows 側にコピーしたフォルダで行ってください。** 部屋の中のファイルは、その部屋で動く Claude Code から読めることがあります
  （部屋の中にある room-github.conf に記入して実行しようとすると、スクリプトが止まります）。
- **部屋ができたら、room-github.conf は空欄に戻してください。**
- room-github.conf と、次の room-localgit.conf は、**どちらか一方だけ**に記入します（両方に記入すると、部屋を作る前に止まります）。

### GitHub に置けないコードを使う場合: room-localgit.conf（LocalGit。使わない場合は空欄のまま）

Windows 側にある bare リポジトリ（`git init --bare` で作ったもの）を正本にして、部屋の中の Claude Code で作業するための設定です。
room.conf と同じフォルダにある `room-localgit.conf` に記入しておくと、部屋を作るときに次のことを自動で行います。

- `repo_path` のリポジトリの内容（すべてのブランチ・タグ・履歴）を、部屋の `~/repos/<名前>.git`（部屋の中の bare リポジトリ）に写す
- それを部屋の `~/projects/<名前>` にクローンする
- この部屋専用の**同期スクリプト**（このフォルダの `rooms\<部屋の名前>\Sync-<部屋の名前>.cmd`）を作る。使い方は [6.9](#69-localgit-の同期)

```ini
repo_path = C:\repos\foo.git
```

- `repo_path`: Windows 側の bare リポジトリのフォルダです。`HEAD`・`config`・`objects`・`refs` などが直接入っているフォルダを、
  ドライブ名から書きます。ネットワークドライブや `\\` で始まる場所は使えません。
- `<名前>` は、フォルダ名から末尾の `.git` を除いたものです（`C:\repos\foo.git` → `foo`）。フォルダ名は半角英数字と `.` `_` `-` だけにしてください。
- room-localgit.conf は部屋の中へコピーしません。Windows 側のパスは、部屋の中には一切渡しません。
- **Windows 側のリポジトリのすべてのブランチ・タグ・履歴が、部屋の中（Claude Code から読める場所）に入ります。**
  履歴の中に、パスワードなどの秘密の情報をコミットしたことがあるリポジトリは使わないでください。
  また、Windows 側でコミットしたときの作者（git の `user.name`・`user.email`）も部屋に入ります。本名などが気になる場合は見直してください。

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
     部屋の設定が終わると、このユーザーは sudo（管理者の権限）を使えなくなります（[1 章](#1-安全のしくみかんたんな説明)の ③）。
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
[WARN] W1  WSLg（Linux の GUI アプリ機能）が無効で、Windows のクリップボードなどに届かない
           WSLg（Linux の GUI アプリ機能）が有効です:
             /mnt/wslg がマウントされています。
...
結果: PASS 28 / FAIL 0 / SKIP 2 / WARN 1
FAIL はありません。
WARN の項目は失敗ではありませんが、上の説明を確認してください。
  [完了] 自動検証で FAIL はありませんでした（SKIP の項目は、ログイン後に手動で確認します。WARN の項目があれば、その説明を確認してください）。
```

`[SKIP]` は「この方法では確認しない（別の場所で確認する）」という意味で、失敗ではありません。
`[WARN]` も失敗ではありません。部屋の設定（wsl.conf など）では止められない、WSL の仕組みとしての窓口があることを知らせるものです
（Claude Code が実行するコマンドからは使えませんが、部屋の中でサンドボックスの外で動くプログラムからは届きます）。
表示された説明を読んで、必要なら対処してください（[10 章](#10-トラブルシューティング)）。

途中で止まった場合は、表示されたメッセージに従って原因を取り除き、
`-Resume` を付けて実行すると続きからやり直せます（部屋は消えません）。

### 5.6 設定ファイルを使わずに、画面で答えて実行する（room-setup-wizard.cmd）

Windows 側にコピーしたフォルダ（[3 章](#3-ファイルを-windows-側に用意する)）の `room-setup-wizard.cmd` を、エクスプローラーでダブルクリックします。
実行ポリシーの設定（5.2）は不要です。room.conf・room-github.conf・room-localgit.conf は読まず、同じ内容を次の順で聞きます。

1. **行うこと**: 番号で選びます（新しい部屋を作る／既存の部屋の設定をやり直す（`-Resume` と同じ）／既存の部屋の自動検証だけを行う（`-VerifyOnly` と同じ））
2. **ドライランにするか**: `y` にすると、何も変更せずに予定だけを表示します（初めてのときはおすすめ）
3. **ディストリビューション名と部屋の名前**（5.4 と同じ）
4. **room.conf にあたる値**: `linux_user`、`windows_user`、`allowed_domains`
   - 新しく作るときは、`allowed_domains` だけ、このフォルダの room.conf の値を既定値として表示します。`linux_user` と `windows_user` は推測しません。
   - やり直し・検証だけのときは、部屋の中にある root 所有の `room.conf`（前回設定したときの内容）を既定値として表示します。
   - 通信を許可するドメインが無い場合は `-` を入力します。
5. **リポジトリの設定**（検証だけのときは聞きません）: 「しない」「GitHub」「LocalGit」から番号で選びます。
   - GitHub: `user_name`、`user_email`、`pat`、`repo_url` を聞きます。PAT は入力（貼り付け）しても `*` で表示されます。
   - LocalGit: `repo_path`（Windows 側の bare リポジトリのフォルダ）を聞きます。
6. **最後の確認**: `y` で進める、`r` で 4. から入力し直す、`n` で中止（何も変更しません）

画面の見かた:

| 表示 | 意味 |
|---|---|
| `[?]`（水色）と白い文字 | 質問 |
| 灰色の文字 | 入力の規則や例 |
| `Enter だけ押すと:` のあとの緑の文字 | 何も入力せずに Enter を押したときに使われる値 |
| `>`（水色） | ここに入力する |
| `[入力エラー]`（赤） | 入力が正しくない。黄色の説明に従って、もう一度入力する |

入力が正しくないときは、止まらずにその項目だけ聞き直します。
そのあとの処理（部屋の作成・設定・検証）と画面の表示は、設定ファイルを使う場合と同じです。
途中で止まった場合は、もう一度ダブルクリックして「既存の部屋の設定をやり直す」を選びます。

**情報の扱い（設定ファイルを使う場合と同じ考え方です）**

- 入力した値は、ファイルに一切保存しません（room.conf・room-github.conf も書き換えません）。
- room.conf にあたる値（秘密の情報は含まない）は、メモリ上で room.conf と同じ形にして、部屋の中の `/usr/local/lib/wsl-room-setup/room.conf` に置きます（検証の基準に使うため）。
- GitHub の情報は部屋の中にファイルとして持ち込まず、標準入力で渡します。PAT は部屋の `~/.git-credentials`（Claude Code から読めないように設定してある）にだけ保存されます。
  PAT は、部屋に渡す直前まで SecureString（暗号化された文字列）で持ちます。ただし、渡すときに一時的に平文になったものは、PowerShell の仕組み上、メモリから完全には消せません（スクリプトが終わるとプロセスごと消えます）。
- LocalGit の `repo_path` も、ファイルには保存しません（部屋のために作る同期スクリプトの中にだけ書き込みます）。
- **部屋の中にあるファイル（`\\wsl.localhost\...` や、それを割り当てたドライブ）から起動すると、何も聞かずに止まります。**
  部屋の中のファイルは Claude Code が書き換えられるため、書き換えられたスクリプトに PAT を入力してしまうのを防ぐためです。
  必ず Windows 側にコピーし、中身を確かめてから、コピーしたほうを起動してください。

PowerShell から起動する場合は、`.\New-SecureRoom.ps1 -Interactive` でも同じです。

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
| Claude に「`~/.bashrc` の最後に `# test` を書き足して」と頼む | **拒否される**（[1 章](#1-安全のしくみかんたんな説明)の ⑤） |
| Claude に「`~/.claude/statusline.sh` の先頭にコメントを足して」と頼む | **拒否される** |
| Claude に「今の作業内容をメモリーに保存して」と頼む | **成功する**（`~/.claude` のほかの場所は書ける） |

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
- 部屋の中では sudo を使えません。管理作業は [6.8](#68-部屋の管理作業パッケージの追加更新など) の方法で行ってください。
- 部屋のユーザーのパスワードを Claude に教えないでください。
- `~/.bashrc`・`~/.gitconfig`・`~/.claude/settings.json` などを変えたいときは、ご自身で編集してください
  （Claude には書き換えられないようにしてあります。[1 章](#1-安全のしくみかんたんな説明)の ⑤）。
- 部屋の中に、Windows 側の秘密鍵やクラウドの認証情報などをコピーしないでください。
- リポジトリを clone したら、Claude Code を起動する前に、そのリポジトリの `.claude/` フォルダ
  （特に `settings.json` と `settings.local.json`）の中身を確認してください。
  プロジェクトの設定はこの部屋のユーザー設定（`~/.claude/settings.json`）より優先されるため、
  サンドボックスを弱める設定（`"sandbox": {"enabled": false}` など）が入っていると、守りが外れてしまいます。
- clone に使うトークンなどを git に保存させる場合、保存先の `~/.git-credentials` は
  Claude が実行するコマンドからも、Claude のファイル読み取り機能からも読めないように設定してあります
  （トークンを保存してから Claude Code を起動してください）。
  ただし、トークンを clone の URL に直接書くと、プロジェクトの `.git/config` に残って Claude から読めてしまうので避けてください。

### 6.5 ステータスライン

部屋を作ると、このフォルダの `statusline.sh` が部屋の `~/.claude/statusline.sh` に置かれ、
`~/.claude/settings.json` の `statusLine` から `bash ~/.claude/statusline.sh` として実行されるように設定されます。
Claude Code を起動すると、画面の下にモデル名・作業フォルダ・使用量などが表示されます。

- 表示を変えたいときは、このフォルダの `statusline.sh` を差し替えてから新しく部屋を作るか、
  既存の部屋なら `-Resume` を付けて実行します（部屋の中の元のファイルは `statusline.sh.bak-日時` として残します）。
- このファイルは Claude Code のサンドボックスの**外**で、あなたの権限で繰り返し実行されます。
  中身を確認したものだけを置いてください。Claude には書き換えられないようにしてあります（`/statusline` も使えません）。

### 6.6 GitHub の設定（room-github.conf に記入して部屋を作った場合、または room-setup-wizard.cmd で「する」を選んだ場合）

部屋を作ったときに、git の設定・PAT の保存・`~/projects/<リポジトリ名>` へのクローンが済んでいます。
また、PAT で push できるか（書き込み権限があるか）を `git push --dry-run` で確かめてあります（何も送っていません）。
確認できなかった場合は、途中で `[注意]` が表示されています。

**(1) ターミナルで（Claude Code の外で）**

```bash
cd ~/projects/<リポジトリ名>
git pull
```

→ ユーザー名やパスワードを聞かれずに終わること。

**(2) Claude Code の中で**（`~/projects/<リポジトリ名>` で起動して）

| 確認すること | 期待される結果 |
|---|---|
| `/permissions` を開く | Deny に `Read(~/.git-credentials)` がある |
| ターミナルで `mkdir -p ~/.aws && echo dummy > ~/.aws/wsl-room-probe.txt` を実行してから、Claude に「`cat ~/.aws/wsl-room-probe.txt` を実行して」と頼む | **失敗する** |
| Claude に「`git config --local wsl-room.probe 1` を実行して」と頼む | **失敗する**（`.git/config` に書き込めない） |

> **`~/.git-credentials` そのものを Claude に読ませて確かめないでください。** 守りが効いていなかった場合、
> PAT が会話の内容として送られてしまいます。`~/.aws` は `~/.git-credentials` と同じ仕組み
> （settings.json の `sandbox.credentials`）で守っているので、代わりにダミーのファイルで確かめます。
> 確認が終わったら `rm ~/.aws/wsl-room-probe.txt` で消してください。

3 つ目の確認が成功してしまった（`git config --local --get wsl-room.probe` で `1` が表示される）場合、Claude がリポジトリの git の設定を
書き換えられる状態です。書き換えられた設定は、あなたが VS Code やターミナルで git を使ったときに（サンドボックスの外で）
実行されるため、PAT を盗まれる経路になりえます。`git config --local --unset wsl-room.probe` で元に戻し、
PAT の権限を対象のリポジトリだけに絞っておいてください。

**ふだんの使い方**

- push はご自身で、VS Code のソース管理やターミナルから行ってください。
  Claude が実行する `git push` / `git pull` は失敗します（`~/.git-credentials` を読めず、github.com への通信も許可していないため）。
- PAT を作り直したときは、room-github.conf に新しい PAT を含む 4 項目を記入して、`-Resume` を付けて実行します
  （古い PAT は置き換えられます。クローン済みのリポジトリはそのままです）。
  room-setup-wizard.cmd なら「既存の部屋の設定をやり直す」を選び、GitHub の設定を「する」にして 4 項目を入力します。
- 2 つ目以降のリポジトリは、[GitHub.md](GitHub.md) の手順で手動で clone します。

### 6.7 Zone.Identifier ファイルを削除する（delzonei）

Windows のエクスプローラーで部屋の中へファイルをコピーすると、ファイルごとに `<元の名前>:Zone.Identifier` という
ファイルが作られます。部屋の中で `delzonei` を実行すると、カレントディレクトリとそのサブフォルダにある、それらをすべて削除します。

```bash
cd ~/projects/<プロジェクト名>
delzonei        # 削除して、削除したファイルを表示する
delzonei -n     # 削除せずに、見つかったファイルを表示するだけ
```

- 対象は、名前が `:Zone.Identifier` で終わる通常のファイルだけです（フォルダやシンボリックリンクは対象外で、リンク先もたどりません）。
- `delzonei` は `/usr/local/bin/delzonei` に root 所有で置かれています（Claude が書き換えられないようにするため）。

### 6.8 部屋の管理作業（パッケージの追加・更新など）

部屋のユーザーは sudo を使えないので（[1 章](#1-安全のしくみかんたんな説明)の ③）、root の権限が必要な作業は、
**Windows の PowerShell から root で部屋に入って**行います（パスワードは聞かれません）。

```powershell
wsl -d dev -u root --cd /root
```

たとえば、パッケージを最新にするとき（月に 1 回ほど、または Ubuntu のセキュリティ情報が出たとき）:

```bash
apt update
apt upgrade
```

- apt の取得先は、部屋を作るときに https に書き換えてあります（[1 章](#1-安全のしくみかんたんな説明)の ⑥）。
  `/etc/apt/sources.list.d/ubuntu.sources` の `URIs:` を http に戻さないでください。
- 終わったら `exit` で root のシェルを抜けてください。root のシェルを開いたまま Claude Code を使わないでください。
- Claude Code 自体は、自動で更新されます。

部屋を作るときに入れた **uv と Rust は、自動では更新されません**。root ではなく部屋のユーザーとして入れてあるので、
部屋の中のターミナルで（Claude Code の外で）更新します。

```bash
uv self update
rustup update
```

- Claude Code のサンドボックスの中から通信できるのは、room.conf の `allowed_domains` に書いたドメインだけです。
  Python のパッケージ（`uv add` など）には、初期値の `pypi.org` と `files.pythonhosted.org` が使われます。
  Rust のパッケージ（`cargo build` での依存パッケージの取得）を Claude に取得させる場合は、
  `index.crates.io` と `static.crates.io` を `allowed_domains` に加えてください（初期値には入っていません）。

### 6.9 LocalGit の同期

room-localgit.conf に記入して（または room-setup-wizard.cmd で LocalGit を選んで）作った部屋では、
Windows 側の bare リポジトリ（正本）と、部屋の中の bare リポジトリ `~/repos/<名前>.git` を、同期スクリプトで同期します。

```
Windows 側の bare リポジトリ（正本）  ⇔（同期スクリプト）⇔  部屋の ~/repos/<名前>.git  ⇔（あなたが push / pull）⇔  ~/projects/<名前>
```

**同期スクリプト**は、部屋を作ったときに、wsl-room-setup フォルダの `rooms\<部屋の名前>\` に作られます。

- `Sync-<部屋の名前>.cmd` をダブルクリックすると同期します。
- `Sync-<部屋の名前>.cmd` と `Sync-<部屋の名前>.ps1` を**同じフォルダに置けば、PC のどこへ移しても動きます**
  （wsl-room-setup フォルダを消しても構いません）。ただし、**部屋の中（`\\wsl.localhost\...`）には置かないでください**
  （部屋の中のファイルは Claude Code が書き換えられ、書き換えられたスクリプトが Windows のあなたの権限で動いてしまいます）。
- 部屋ごとに 1 組です。部屋の名前・Linux のユーザー名・Windows 側のリポジトリの場所が書き込まれています。

**ふだんの流れ**

1. 部屋の `~/projects/<名前>` で作業し（Claude Code もここで起動します）、コミットします。
2. 内容を確かめてから、**ご自身で** `git push` します（部屋の `~/repos/<名前>.git` へ）。
   Claude は `~/repos` に書き込めないので、push できません（サンドボックスと `Edit(~/repos/**)` の禁止ルール）。
3. Windows 側で `Sync-<部屋の名前>.cmd` をダブルクリックします。写す内容（ブランチ・タグの作成・更新・削除と、コミットの一覧）が表示されるので、
   確かめて `y` を入力します。

Windows 側で作業した場合は、Windows 側の bare リポジトリへ push してから同期スクリプトを実行し、
部屋の `~/projects/<名前>` で `git pull --prune` を実行します。

**部屋を作ったあとの確認**（Claude Code を `~/projects/<名前>` で起動して）

| 確認すること | 期待される結果 |
|---|---|
| Claude に「`~/repos/<名前>.git/description` に test と書き込んで」と頼む | **拒否される**（`Edit(~/repos/**)` の禁止ルール） |
| Claude に「`echo test > ~/repos/<名前>.git/description` を実行して」と頼む | **失敗する**（サンドボックス） |
| Claude に「`git push` を実行して」と頼む | **失敗する** |

ここで書き込めてしまった場合は、Claude が、あなたの確認を通さずに同期の対象を変えられる状態です。
`~/.claude/settings.json` を確かめ（[8 章](#8-部屋の中で検証をやり直す)の検証 13）、`-Resume` で直してください。

**同期スクリプトが行うこと**

前回の同期の状態（基準）を、Windows 側のリポジトリの中の `room-sync\<部屋の名前>.txt` に記録しておき、
Windows 側・部屋の中・基準の 3 つを比べます（git は、リポジトリのフォルダの中にある知らないフォルダを無視します）。

| Windows 側 | 部屋の中 | 行うこと |
|---|---|---|
| 部屋の中と同じ | 〃 | 何もしない（「同期済み」） |
| 前回と同じ | 前回から変わった | 部屋の内容を Windows 側へ写す |
| 前回から変わった | 前回と同じ | Windows 側の内容を部屋へ写す |
| 前回から変わった | 前回から変わった | 止まる（下の「両側で変更されて止まったとき」） |

- 写すのは、ブランチ・タグ・HEAD（既定のブランチ）です。削除も写します。それ以外の ref（`refs/notes` など）と、
  リポジトリの設定（config・hooks）は写しません。
- **force にあたる変更は写さずに止まります**: fast-forward でないブランチの更新（rebase・reset・`push --force` の結果）と、タグの付け替え。
- ブランチとタグの名前は、半角英数字と `.` `_` `+` `/` `-` だけにしてください（それ以外を含むものがあると止まります）。
- 部屋の中のリポジトリは、Windows 側の git では開きません。部屋とは bundle（履歴を詰めたデータ）だけをやりとりし、
  部屋から受け取ったものは検査（fsck）してから取り込みます。確認画面の文字列からは、画面を書き換える制御文字を取り除いて表示します。
- 部屋の中の git は、部屋のユーザーの git の設定（`~/.gitconfig`）を読まずに動かします（同期はサンドボックスの外で動くため）。
- 受け渡しの途中の bundle は、Windows 側のリポジトリの `room-sync\<部屋の名前>.bundle.tmp` に置き、終わったら消します
  （途中で強制終了したときは残りますが、次の同期で上書きされます）。
- Windows 側へ写したコードは、部屋の中の Claude Code が書いたものです。Windows 側でそれを開いたりビルドしたりするときは、
  中身を確かめてからにしてください（VS Code の「ワークスペースの信頼」なども使ってください）。

**両側で変更されて止まったとき**

並行作業には対応していないので、どちらか一方の変更を、前回の同期の状態に戻してから同期します。
前回の同期の状態（各ブランチ・タグの ID）は、Windows 側のリポジトリの `room-sync\<部屋の名前>.txt` に書かれています。
たとえば部屋の中の変更を戻す場合は、部屋の中のターミナルで（Claude Code の外で）、表示された ref ごとに次を実行します。

```bash
cd ~/repos/<名前>.git
git update-ref refs/heads/<ブランチ> <記録の ID>   # 更新・削除されたものを、記録の ID に戻す
git update-ref -d refs/heads/<ブランチ>            # 新しく作られたものを消す
```

`~/projects/<名前>` の作業用のクローンにはコミットが残っているので、作業は失われません。同期して Windows 側の変更を部屋に写したあと、
`~/projects/<名前>` で `git pull` して合わせ（merge）、もう一度 push して同期します。

**前回の同期の記録が無いと言われたとき**

`room-sync\<部屋の名前>.txt` を消した場合などに起きます。両側の内容が同じなら、記録を作り直して終わります。違う場合は、
どちらに合わせるかを指定して実行します（コマンドプロンプトや PowerShell で、同期スクリプトのフォルダに移動して）。

```powershell
.\Sync-dev.cmd -Direction ToRoom      # Windows 側の内容を部屋へ写す
.\Sync-dev.cmd -Direction ToWindows   # 部屋の内容を Windows 側へ写す
```

写す先にしか無いブランチやタグは削除されます。写す内容が表示されるので、確かめてから `y` を入力してください。

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
| `-GitHubConfigPath <パス>` | room-github.conf 以外の GitHub の設定ファイルを使う（省略時は room.conf と同じフォルダの room-github.conf） |
| `-Interactive` | 設定ファイルを使わず、値を画面で聞く（[5.6](#56-設定ファイルを使わずに画面で答えて実行するroom-setup-wizardcmd)。room-setup-wizard.cmd はこれを付けて起動する）。`-ConfigPath`・`-GitHubConfigPath` とは同時に使えない |

`room-setup.cmd` と `room-setup-wizard.cmd` に付けたオプションは、そのまま `New-SecureRoom.ps1` に渡されます
（例: `room-setup.cmd -RoomName dev -Resume`）。

例:

```powershell
.\New-SecureRoom.ps1 -RoomName dev -Resume
.\New-SecureRoom.ps1 -RoomName dev -VerifyOnly
```

`-Resume` は部屋を途中で 2 回再起動するので、部屋の中で動いている Claude Code やターミナルはすべて終了します。
また、`~/.claude/settings.json` を仕様どおりの内容に戻します（元のファイルは `settings.json.bak-日時` として残します）。
room-github.conf に記入があれば、GitHub の設定もやり直します（空欄なら、すでにある GitHub の設定はそのまま残します）。
room-localgit.conf に記入があれば、同期スクリプトを作り直し、部屋を作ったときに終わっていなかった LocalGit の準備を続けます
（部屋の `~/repos/<名前>.git` がすでにあれば、中身には触れません）。
GitHub の設定をした部屋に LocalGit を、LocalGit の設定をした部屋に GitHub を、あとから設定することはできません（止まります）。

---

## 8. 部屋の中で検証をやり直す

部屋の中のターミナルから、いつでも検証できます。

```bash
bash /usr/local/lib/wsl-room-setup/verify-room.sh               # 一般ユーザーとして行う検査
```

root の権限が必要な検査は、部屋の中では sudo を使えないので、Windows の PowerShell から実行します（`dev` は部屋の名前）。

```powershell
wsl -d dev -u root --cd / --exec bash /usr/local/lib/wsl-room-setup/verify-room.sh --root
```

> **Claude Code に検証を実行させないでください。** サンドボックスの中では root のファイルが
> 別の持ち主（nobody）に見えるため、正しく判定できません。ご自身でターミナルから実行してください。

---

## 9. ファイル構成

```txt
wsl-room-setup/
├── README.md                 この説明書
├── DEV.md                    開発途中の未決定事項（開発者向け）
├── New-SecureRoom.ps1        Windows 側の司令塔（これを実行する）
├── room-setup.cmd            New-SecureRoom.ps1 を、実行ポリシーの設定なしで起動する（設定ファイルを使う）
├── room-setup-wizard.cmd     New-SecureRoom.ps1 を対話モード（-Interactive）で起動する。ダブルクリックで使う
├── room.conf                 設定ファイル（Linux のユーザー名、Windows のユーザーフォルダ名、通信を許可するドメイン）
├── room-github.conf          GitHub の設定ファイル（コミットの作者、PAT、リポジトリの URL）。部屋の中にはコピーしない
├── room-localgit.conf        LocalGit の設定ファイル（Windows 側の bare リポジトリの場所）。部屋の中にはコピーしない
├── GitHub.md                 GitHub を手動で設定する手順
├── lib.sh                    部屋の中のスクリプトが共通で使う部品
├── provision-root.sh         部屋の中で root として行う設定（wsl.conf、fstab、パッケージ、AppArmor、delzonei、/mnt の片付け）
├── provision-user.sh         部屋の中で一般ユーザーとして行う設定（Claude Code、PATH、uv、Rust、settings.json、ステータスライン、~/projects）
├── provision-github.sh       部屋の中で一般ユーザーとして行う GitHub の設定（git の設定、PAT の保存、クローン）
├── verify-room.sh            自動検証
├── statusline.sh             Claude Code のステータスライン（部屋の ~/.claude/statusline.sh に置かれる）
├── delzonei.sh               Zone.Identifier ファイルを削除するコマンド（部屋の /usr/local/bin/delzonei に置かれる）
├── templates/
│   ├── wsl.conf.tmpl         /etc/wsl.conf のひな形
│   ├── claude-settings.json.tmpl   ~/.claude/settings.json のひな形
│   └── Sync-Room.ps1.tmpl    LocalGit の同期スクリプトのひな形（部屋の中で動かす部分も含む。部屋の中にはコピーしない）
├── rooms/                    （LocalGit の部屋を作ると作られる）部屋ごとの同期スクリプト Sync-<部屋の名前>.ps1 / .cmd
└── .gitattributes            改行コードの指定（Linux 側のファイルは LF）
```

部屋の中では、スクリプト一式と room.conf のコピーが `/usr/local/lib/wsl-room-setup/`（root 所有）に置かれます。
Claude や一般ユーザーは書き換えられないので、検証の基準（期待値）として信用できます。
room-github.conf はここに置きません（ここは部屋の中の誰でも読めるため）。

### 処理の流れ

1. 前提条件の確認（WSL、VS Code の WSL 拡張機能、ファイルの改行コード、room.conf、room-github.conf、room-localgit.conf）
   - 対話モード（room-setup-wizard.cmd）では、room.conf と room-github.conf を読む代わりに、部屋の名前を決めたあとで同じ内容を画面で聞く
2. `wsl --install <ディストリビューション> --name <部屋の名前>`（room.conf の `linux_user` と同じユーザー名と、パスワードを入力）
3. 部屋が WSL2 で動いていること、部屋のユーザーが room.conf の `linux_user` と同じことを確認
4. スクリプト一式と room.conf を部屋の中へコピーし、ハッシュ値で一致を確認
5. `provision-root.sh --phase base`: apt の取得先を https に書き換え（すべて https になったことを確認）、パッケージの更新
   （apt が CVE-2026-109518 の修正版になったことを確認してから、必要なものを入れる）、部屋のユーザーを管理者のグループ（sudo など）から外す、
   `/etc/wsl.conf`、AppArmor、`/usr/local/bin/delzonei`
6. 部屋を再起動（C ドライブが見えなくなる）
7. `provision-root.sh --phase mount`: VS Code 拡張フォルダの読み取り専用マウント
   （C ドライブが見えている間にやると本物の C ドライブの上にフォルダを作ってしまうので、再起動後に行う）と、/mnt の片付け
   （初回起動時に WSL が作ったドライブ用のフォルダのうち、`/mnt/c` 以外の空のものを削除し、
   `/mnt/c` から取り付け先までのフォルダを root 所有・755 にする。`/mnt/c` は取り付け先の途中なので残す）
8. `provision-user.sh`: Claude Code、PATH、uv、Rust、settings.json、ステータスライン（`~/.claude/statusline.sh`）、`~/projects`
   - uv: 公式のインストールスクリプト（`https://astral.sh/uv/install.sh`）で `~/.local/bin` に入れる
   - Rust: 公式の rustup（`https://sh.rustup.rs`）で stable を `~/.cargo` と `~/.rustup` に入れ、`~/.bashrc` に `. "$HOME/.cargo/env"` を追記する。
     リンクに使う C コンパイラなどは、5. でパッケージ（build-essential・pkg-config・libssl-dev）として入れる
9. （room-github.conf に記入があるときだけ）`provision-github.sh`
   - `--phase credentials`: git の設定と PAT の保存。room-github.conf の内容は、コマンドライン引数ではなく標準入力で渡す
   - `--phase clone`: `~/projects/<リポジトリ名>` へのクローンと、`git push --dry-run` による書き込み権限の確認
   - （room-localgit.conf に記入があるときは、代わりに）`Sync-Room.ps1.tmpl` から部屋専用の同期スクリプトを作り、
     `-Initialize` を付けて実行する。部屋の `~/repos/<名前>.git` を Windows 側と同じハッシュの形式で作り、Windows 側の内容を写して
     `~/projects/<名前>` にクローンする。部屋の中で動かすコードは、実行のたびに同期スクリプトから渡す（部屋の中には置かない）
10. 部屋を再起動（すべての設定が起動時に正しく反映されるかを確かめるため）
11. `verify-room.sh --root` と `verify-room.sh`

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
| 検証 08・R1・R2 が FAIL | パスワードなしで sudo できる設定がある | Windows の PowerShell から `wsl -d <部屋の名前> -u root` で入り、表示された行を `visudo`（または `visudo -f <ファイル>`）で削除 |
| 検証 E8 が FAIL | 部屋のユーザーが sudo などの管理者のグループに入っている | `-Resume` でやり直す（グループから外します） |
| 検証 A1 が FAIL | apt の取得先に http のものがある | `-Resume` でやり直す（Ubuntu 公式のものは https に書き換えます）。自分で追加した取得先なら、[6.8](#68-部屋の管理作業パッケージの追加更新など) の方法で入って https に直す |
| 検証 A2 が FAIL / 部屋の作成が「apt の版が…修正版より古いままです」で止まる | apt が CVE-2026-109518 の修正版になっていない | 時間をおいて `-Resume` でやり直す（サーバーの同期が遅れていることがあります） |
| 検証 A3 が FAIL | Apache（apache2）が入っている | 不要なら、[6.8](#68-部屋の管理作業パッケージの追加更新など) の方法で入って `apt purge apache2` などで削除 |
| 検証 A4 が WARN | 適用していない更新がある | [6.8](#68-部屋の管理作業パッケージの追加更新など) の方法で `apt update` と `apt upgrade` を実行 |
| 検証 13 が FAIL | `~/.claude/settings.json` が仕様と違う（2026-11-12 より前に作った部屋では、追加した禁止ルール `Edit(...)` が無いため FAIL になります） | `-Resume` で仕様どおりに戻す（元のファイルは `settings.json.bak-日時` として残るので、ご自身で足した設定があれば足し直す） |
| Claude に `.bashrc` や Claude Code の設定の変更を頼むと拒否される | サンドボックスの外で自動で実行されるファイルは、Claude に書き換えさせないようにしている（[1 章](#1-安全のしくみかんたんな説明)の ⑤） | ご自身で編集する |
| 検証 E7 が FAIL | `/usr/local/bin/delzonei` が無い、または書き換えられている | `-Resume` で置き直す |
| 検証 W1 が WARN | WSLg（Linux の GUI アプリ機能）が有効（Windows 11 の既定）。部屋の中でサンドボックスの外で動くプログラムが、Windows のクリップボードなどを使える可能性がある | 止める場合は Windows の `%USERPROFILE%\.wslconfig` の `[wsl2]` に `guiApplications=false` と書き、`wsl --shutdown`（WSL 全体の設定なので、ほかのディストリでも GUI アプリが使えなくなる） |
| 検証 W2 が WARN | `/mnt/wsl`（全ディストリで共有される場所）に、ほかのディストリ（Docker Desktop など）が置いたものや、`wsl --mount` したディスクがある | 表示された名前を確認し、部屋から見えてよいものか判断する。Docker Desktop なら、WSL integration の対象にこの部屋を入れない |
| 検証 W3 が WARN | 初回起動時に WSL が作ったドライブ用のフォルダ（`/mnt/d` など）が残っている、または `/mnt/c` を root 以外も書き込める（この機能を追加する前に作った部屋など） | `-Resume` で片付ける（空でないフォルダは削除せずに残すので、中身を確認してから、[6.8](#68-部屋の管理作業パッケージの追加更新など) の方法で入って `rm -r` などで消す） |
| 検証 G1 が FAIL | `~/.git-credentials` をほかのユーザーも読める | 部屋の中で `chmod 600 ~/.git-credentials` |
| 検証 G2 が FAIL | git の設定の URL に PAT が書かれている、または部屋の中に room-github.conf がある | 表示に従って直す。Claude から読める場所にあった PAT は、GitHub で削除（失効）して作り直す |
| 「room-github.conf の一部だけが記入されています」 | 4 つの項目の書き忘れ | すべて記入する（GitHub の設定をしないなら、すべて空欄にする） |
| 対話モードで「このスクリプトは WSL の部屋の中にあります」「WSL の部屋の中を割り当てたドライブ…にあります」 | 部屋の中のフォルダ（`\\wsl.localhost\...`）にある room-setup-wizard.cmd を起動した | [3 章](#3-ファイルを-windows-側に用意する)の手順で Windows 側にコピーし、コピーしたほうを起動する |
| 対話モードで「ネットワークドライブ…の接続先を確認できませんでした」 | ネットワークドライブ上のフォルダから起動した | Windows のローカルのフォルダ（`%USERPROFILE%` の下など）にコピーして起動する |
| 「記入済みの room-github.conf が、WSL の部屋の中にあります」 | 部屋の中のフォルダから実行した、または部屋の中のファイルを指定した | Windows 側にコピーしたフォルダで記入して実行する。部屋の中のファイルに書いた PAT は、GitHub で削除（失効）して作り直す |
| 「リポジトリをクローンできませんでした」 | `repo_url` の誤り、PAT の期限切れ・権限不足 | URL と PAT（対象のリポジトリへのアクセス権、Contents の権限）を確認し、room-github.conf を直して `-Resume` |
| 「PAT で push できることを確認できませんでした」（`[注意]`） | PAT に書き込み権限が無い、または PAT が無効 | PAT の Contents を Read and write にする（または作り直す）。room-github.conf を直して `-Resume` |
| 「~/projects/… がすでにあり、… のクローンではありません」 | クローン先に別のフォルダがある | 中身を確認して、別の場所へ移すか削除してから `-Resume` |
| 部屋に入ると `/mnt/c/...` で始まる、またはエラーになる | `wsl` は Windows の今のフォルダに合わせて開始しようとする | `wsl -d <部屋の名前> --cd ~` で入る |
| 「room-github.conf と room-localgit.conf の両方に記入されています」 | GitHub と LocalGit は 1 つの部屋でどちらか一方だけ | 使わないほうを空欄にする |
| 「repo_path は bare リポジトリではありません」 | `repo_path` が bare リポジトリのフォルダを指していない（作業用のクローンのフォルダなど） | `HEAD`・`config`・`objects`・`refs` が直接入っているフォルダを書く。git の「dubious ownership」が表示された場合は、表示に従って `git config --global --add safe.directory ...` を実行する |
| 「部屋「…」は GitHub の設定がしてあるため、LocalGit の設定はできません」（またはその逆） | 部屋を作ったときと違うリポジトリの設定で `-Resume` した | 部屋を作ったときと同じ設定でやり直す。別の設定を使うなら、新しい部屋を作る |
| 同期スクリプトで「git の版が古すぎます」 | Git for Windows が 2.46.0 より古い（部屋から受け取ったデータを検査できない） | PowerShell で `git update-git-for-windows` を実行して新しくする |
| 同期スクリプトで「Windows 側と部屋の両方で変更されています」 | 前回の同期のあと、両側で変更した | [6.9](#69-localgit-の同期) の「両側で変更されて止まったとき」 |
| 同期スクリプトで「fast-forward ではありません」「タグ … が付け替えられています」 | rebase・reset・`push --force`・タグの付け直しなどで履歴を書き換えた（force にあたる） | 履歴を書き換えないやり方（merge や revert）で直す。タグは、いったん削除して同期してから付け直す |
| 同期スクリプトで「名前に使えない文字を含むブランチかタグがあります」 | ブランチやタグの名前に、半角英数字と `.` `_` `+` `/` `-` 以外の文字（日本語など）がある | 名前を変えてから同期する |
| 同期スクリプトで「前回の同期の記録 … がありません」 | `room-sync\<部屋の名前>.txt` を消した、など | [6.9](#69-localgit-の同期) の「前回の同期の記録が無いと言われたとき」 |
| 同期スクリプトで「部屋の中のリポジトリが空になっています」 | 同じ名前で部屋を作り直した、など（Windows 側のリポジトリに、前の部屋との同期の記録が残っている） | `-Resume` を付けて、LocalGit の設定でやり直す（Windows 側の内容が部屋に写され、記録も書き直されます） |
| 同期スクリプトで「部屋の中に ~/repos/… がありません」 | 部屋の中の bare リポジトリを消した、など | `-Resume` を付けて、LocalGit の設定（room-localgit.conf）でやり直す（Windows 側の内容が写されます） |
| 同期スクリプトで「Windows 側のリポジトリが見つかりません」 | Windows 側のリポジトリのフォルダを移動した | 元の場所に戻すか、room-localgit.conf に新しい場所を書いて `-Resume` で同期スクリプトを作り直す |
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

2026-11-10 に、次のことを実機で確かめました。

- 新しい部屋の作成が最後まで進み、自動検証で FAIL が出ないこと（設定ファイルの方法・room-setup-wizard.cmd の両方）
- room-github.conf（または room-setup-wizard.cmd での入力）による GitHub の設定で、本物の GitHub からクローンできること
  （設定ファイルの方法・room-setup-wizard.cmd の両方）
- apt の取得先の https への書き換え、apt の版の確認、部屋のユーザーを管理者のグループから外す処理と、
  検証 E8・A1〜A4 が、room-setup-wizard.cmd での新しい部屋の作成で動作し、FAIL が出ないこと

次の点は、まだ実機で確かめていません。

- [1 章](#1-安全のしくみかんたんな説明)の ⑤ の書き換えの禁止（2026-11-12 に追加）が効くこと（[6.2](#62-ログイン後の手動確認) の表の、`~/.bashrc`・`statusline.sh`・メモリーの 3 行）
- LocalGit（2026-11-12 に追加）の Windows 側の動作のすべて。部屋の中で動かす部分（`list`・`export`・`import`・`init`・`clone`）は、
  Linux 上で、Windows 側の処理を同じ git コマンドで置き換えて試験しました（空のリポジトリ、sha256、作成・更新・削除、タグ、
  古い値の食い違いでの取り消し、fsck による拒否、HEAD が存在しないブランチを指す場合）。実機で確かめる項目:
  - 部屋の作成（設定ファイル・room-setup-wizard.cmd の両方）で、同期スクリプトが作られ、`~/repos/<名前>.git` と `~/projects/<名前>` ができること
    （空のリポジトリと、1 GB 程度の大きなリポジトリの両方）
  - wsl.exe との間で、bundle（バイナリ）が壊れずに受け渡されること（標準入力・標準出力）
  - 部屋 → Windows 側、Windows 側 → 部屋 の同期（作成・更新・削除・タグ・HEAD）と、確認画面の表示（日本語のコミットメッセージを含む）
    （2026-11-12 に、両方向の同期が動くことは実機で確かめました。削除・タグ・HEAD の変更は未確認）
  - 両側で変更したとき・fast-forward でないとき・タグを付け替えたときに止まること、`-Direction` の動作
  - 同期スクリプトの .ps1 と .cmd を別のフォルダへ移しても動くこと、パスに空白や `'` を含むリポジトリで動くこと
  - `-Resume` で GitHub と LocalGit を混ぜようとすると止まること
  - 設定ファイルの方式で、部屋の中（`\\wsl.localhost\...`）にある New-SecureRoom.ps1 を LocalGit の設定で実行すると止まること
  - 上の「部屋を作ったあとの確認」（`Edit(~/repos/**)` の禁止ルールが効くこと）

- interop を無効にした部屋から、実際に Windows のプログラムを起動できないこと
  （検証 06 は申し送り書どおり「`cmd.exe` などが見つからない」ことを確かめるもので、起動そのものは試していません）
- AppArmor の設定が必要な場合（値が `1`）の手順（Ubuntu 26.04 の WSL では不要だったため）
- delzonei（2026-11-10 に追加）の実機での動作
- apt の取得先の https への書き換えと、管理者のグループから外す処理（2026-11-10 に追加）を、設定ファイルの方法で使ったときの動作
- 既存の部屋に対する「やり直し」（`-Resume`、room-setup-wizard.cmd の「既存の部屋の設定をやり直す」）と、
  「検証だけ」（`-VerifyOnly`、room-setup-wizard.cmd の「既存の部屋の自動検証だけを行う」）の動作
- 部屋の管理作業（[6.8](#68-部屋の管理作業パッケージの追加更新など)）と、root の権限が必要な検証（[8 章](#8-部屋の中で検証をやり直す)）を、
  Windows の PowerShell から `wsl -d <部屋の名前> -u root` で行う手順

---

## 12. 部屋を削除したいとき

このスクリプトは部屋を削除しません。削除する場合は、**中身がすべて消えて元に戻せないこと**を理解したうえで、
ご自身で PowerShell から実行してください。

```powershell
wsl --unregister <部屋の名前>
```
