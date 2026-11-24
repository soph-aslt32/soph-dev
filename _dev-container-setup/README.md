# dev-container-setup — Claude Code 用の開発環境（Dev Container）を作るツール
<!-- markdownlint-disable MD036 MD040-->
Windows 11 の上に、Claude Code を `--dangerously-skip-permissions` で使うための開発環境を、Claude Code の公式の Dev Container 方式で作るツールです。
1 回の実行で、開発環境（コンテナ）を 1 つ作ります。Windows の VS Code からコンテナにつなぎ、VS Code のソース管理で commit・pull・push します。

## このツールの考え方

- **公式の推奨に従います。** Claude Code の公式の文書（[開発コンテナ](https://code.claude.com/docs/ja/devcontainer)・[サンドボックス環境](https://code.claude.com/docs/ja/sandbox-environments#choose-an-approach)）が勧める Dev Container 方式で作ります。隔離を最大にすることは目的にしていません。
- **公式の方式でも残るリスクは、黙認します。** 公式の文書のとおり、「開発コンテナは実質的な保護を提供していますが、すべての攻撃に完全に耐性のあるシステムはありません」。黙認するものは [10 章](#11-既知のリスク黙認するもの) にまとめています。
- **信頼できるリポジトリで使ってください。** Claude の誤った操作の被害をコンテナの中に収めるためのもので、悪意のあるプロジェクトから中身を守るものではありません。
- **開発環境どうしは分けます。** 開発環境 A の中で動くものから、コンテナどうしの直接の経路で、開発環境 B の情報（コード・PAT・Claude のログイン）には届きません。
- **モードは 2 つです。** GitHub のリポジトリを使う「GitHub モード」と、Windows 側の bare リポジトリを使う「LocalGit モード」です。

## 目次

1. [安全のしくみ（かんたんな説明）](#1-安全のしくみかんたんな説明)
2. [必要なもの](#2-必要なもの)
3. [初めてのときだけ行う設定](#3-初めてのときだけ行う設定)
4. [ツールのフォルダを用意する](#4-ツールのフォルダを用意する)
5. [開発環境を作る（setup-wizard.cmd）](#5-開発環境を作るsetup-wizardcmd)
6. [作ったあとの作業](#6-作ったあとの作業)
7. [管理（やり直す・検証だけ・更新・削除）](#7-管理やり直す検証だけ更新削除)
8. [カスタマイズ](#8-カスタマイズ)
9. [ファイル構成](#9-ファイル構成)
10. [困ったとき](#10-困ったとき)
11. [既知のリスク（黙認するもの）](#11-既知のリスク黙認するもの)
12. [出典](#12-出典)

---

## 1. 安全のしくみ（かんたんな説明）

```
Windows 11
 ├ VS Code（Windows に入れたもの。画面と操作）
 ├ ツールのフォルダ（このフォルダ）
 │   └ envs\<名前>\Code-<名前>.cmd、Sync-<名前>.cmd（Sync は LocalGit だけ）
 └ WSL 2
     └ 土台 dcs-base（Docker 用の Ubuntu 26.04。1 つだけ）
         ├ Docker Engine
         ├ ~/envs/<名前>/  ← 開発環境ごとのフォルダ（注文書・コード）
         └ 開発環境ごとのコンテナ（イメージ dcs-image。Claude Code はこの中で動く）
```

| 部品 | 役割 | 主な守り |
|---|---|---|
| 土台（`dcs-base`） | Docker を動かす WSL のディストリビューション。すべての開発環境で 1 つを共有する | C ドライブを見せない。Windows のプログラムを動かさない。VS Code の拡張機能フォルダだけを読み取り専用で見せる。土台では Claude やコードを動かさない |
| イメージ（`dcs-image`） | すべての開発環境が使う、共通のコンテナのひな形 | コンテナのユーザーは root ではない（`dev`）。sudo できるのはファイアウォールのスクリプトだけ。Claude Code の権限ルール（deny）を、managed settings とユーザーの設定の両方に置く |
| 開発環境（コンテナ） | 1 つのリポジトリで作業する場所 | その開発環境のフォルダとボリュームだけをつなぐ。開発環境ごとに別のネットワーク。許可したドメインにしか通信できないファイアウォール。注文書（`devcontainer.json`）はコンテナから見えない |
| VS Code の受け渡し | VS Code が Windows のものをコンテナに渡すしくみ | Windows の git の認証情報・`.gitconfig`・画面のソケットなどを渡さない設定にする（[3 章](#3-初めてのときだけ行う設定)）。渡されていれば、VS Code がつながるたびに警告する |

- GitHub の PAT は、Windows 側には保存しません。開発環境のボリュームにだけ保存します。
- コンテナの中の作業フォルダは `/workspaces/<リポジトリ名>` です。実体は土台の `~/envs/<名前>/work` にあり、コンテナを作り直しても残ります。

## 2. 必要なもの

| もの | 内容 |
|---|---|
| Windows 11 | WSL 2 が使えること（`wsl --install` が済んでいること）。Hyper-V の VM は要りません |
| VS Code（Windows 版） | 拡張機能の「WSL」（`ms-vscode-remote.remote-wsl`）と「Dev Containers」（`ms-vscode-remote.remote-containers`）。インストールのときに「PATH への追加」を選び、`code` コマンドを使えるようにしておく |
| インターネット | 土台の Ubuntu・Docker Engine・イメージのベース（Docker Hub の `ubuntu:26.04`）・Claude Code などを取ってきます |
| ディスクの空き | 土台とイメージで数 GB |
| GitHub モード | GitHub のリポジトリと、そのリポジトリだけに使える期限付きの fine-grained PAT（[6.5](#65-github-モードの使い方)） |
| LocalGit モード | Windows 側の bare リポジトリ（コミットが 1 つ以上あるもの）と、Git for Windows 2.46.0 以上 |
| Claude Code のアカウント | 開発環境ごとにログインします（組織のアカウントの SSO も使えます） |

- Docker Desktop は使いません（入っていなくてかまいません）。
- 土台を初めて作るときは、全部で十数分かかります。

## 3. 初めてのときだけ行う設定

### 3.1 Windows の VS Code のユーザーの設定（5 つ）

VS Code で「ユーザー設定を開く（JSON）」を選び、次の 5 つを足してください。どれも、ツールが代わりに書けない種類の設定です。

```json
"dev.containers.mountWaylandSocket": false,
"dev.containers.forwardWSLServices": false,
"dev.containers.executeInWSL": true,
"dev.containers.executeInWSLDistro": "dcs-base",
"dev.containers.cacheVolume": false
```

| 設定 | 理由 |
|---|---|
| `mountWaylandSocket: false`・`forwardWSLServices: false` | 画面のソケットや、WSL の側のサービス（SSH エージェントなど）を、コンテナに渡さない |
| `executeInWSL: true`・`executeInWSLDistro: "dcs-base"` | VS Code が、土台の Docker を使ってコンテナを開く。これが無いと、「Reopen in Container」のときに Windows の側で Docker を探して止まります。この PC の Dev Containers は、すべて dcs-base の Docker を使うようになります |
| `cacheVolume: false` | VS Code が、すべての開発環境のコンテナに同じキャッシュのボリュームをつなぐのをやめる（開発環境どうしの共有をなくす）。代わりに、コンテナを作り直すたびに、VS Code のサーバーと拡張機能を取り直します |

- `.gitconfig` のコピーや git の認証情報の受け渡しを止める設定（`copyGitConfig` など）は、ツールが開発環境の注文書に書くので、ここには書かなくてかまいません。

### 3.2 `.wslconfig`（2 つ）

`%USERPROFILE%\.wslconfig`（無ければ作る）を、次のようにしてください。

```ini
[wsl2]
guiApplications=false
```

- `guiApplications=false` を書く。WSLg（WSL の画面の機能）を止めて、コンテナから WSLg の画面のサーバーにつながれないようにするためです。すべてのディストリビューションで、GUI のアプリが使えなくなります。
- `hostFileSystemAccess=false` の行があれば、消す。この行があると、土台が VS Code の拡張機能フォルダを見られず、VS Code から土台につなげません。
- 直したら、PowerShell で `wsl --shutdown` を実行してください（実行中のディストリビューションはすべて止まります）。
- 設定していなくても、ウィザードは止まらずに、土台の検証で警告（`[WARN] B4`・`[WARN] B5`）を出します。

## 4. ツールのフォルダを用意する

- このフォルダ（`_dev-container-setup`）を、Windows のどこかに置きます。土台やコンテナからは見えないので、置き場所はどこでもかまいません。
- 受け取ったファイルは、実行する前に中身を確かめてください。
- git で受け取るとき（clone・pull）も、改行コードは変わりません（`.gitattributes`）。`base\`・`image\`・`templates\devcontainer.json.tmpl` は LF のまま使います。エディターで保存し直して CRLF になると、ウィザードが止まって知らせます。
- よく変えるファイルは次の 2 つです。ほかに変えてよいもの（注文書のひな形の決まった場所など）は、[8 章](#8-カスタマイズ) にまとめています。

| ファイル | 内容 |
|---|---|
| `defaults.conf` | `allowed_domains`（コンテナが通信してよいドメイン）の既定値。新しい開発環境を作るときに、Enter だけ押すとこの値になります |
| `extensions.txt` | コンテナの VS Code に入れる拡張機能（1 行に 1 つ、「発行者.名前」）。Claude Code の拡張（`anthropic.claude-code`）も、ここに書いたときだけ入ります |

## 5. 開発環境を作る（setup-wizard.cmd）

`setup-wizard.cmd` をダブルクリックします。最初に行うことを番号で選び、次にドライランにするかを選びます。

| 番号 | 行うこと |
|---|---|
| 1 | 新しい開発環境を作る（土台が無ければ、先に作ります） |
| 2 | 開発環境の設定をやり直す（[7 章](#7-管理やり直す検証だけ更新削除)） |
| 3 | 開発環境を削除する |
| 4 | 検証だけ |
| 5 | 更新 |

- 初めてのときは、まずドライランで流れを確かめるのがおすすめです。ドライランでは何も変更せず、実行する予定の内容だけを表示します。
- 土台が無いときは「土台（dcs-base）がまだ無いので、先に作ります（初回だけ時間がかかります）。」、あるときは「既にある土台（dcs-base）を使います。」と表示します。
- 最後の確認で `y` を入力するまでは、何も変更しません。途中でやめるときは Ctrl+C を押してください。

### 5.1 聞かれること

| 項目 | 内容 |
|---|---|
| 開発環境の名前 | 半角英小文字・数字・ハイフンだけで、32 文字以内（先頭と末尾はハイフン以外。例: `myapp`）。同じ名前の残りが土台にあれば、止まって知らせます |
| リポジトリの使い方 | 1: GitHub、2: LocalGit |
| `repo_url`（GitHub） | `https://github.com/OWNER/REPOSITORY.git` の形。SSH（`git@github.com:...`）は使えません |
| `user_name`・`user_email`（GitHub） | コミットの作者。GitHub のアカウントと関係のないものでかまいません。メールアドレスは、`example.com` などの例示用のドメインがおすすめです |
| `pat`（GitHub） | 入力した文字は `*` で表示されます |
| `repo_path`（LocalGit） | Windows 側の bare リポジトリのフォルダを、ドライブ名から（例: `C:\repos\foo.git`） |
| `allowed_domains` | コンテナが通信してよいドメイン（[5.2](#52-allowed_domains-の書き方)） |

- コンテナの中の作業フォルダの名前は、リポジトリ名になります（GitHub は `repo_url` の最後、LocalGit は `repo_path` のフォルダ名から `.git` を除いたもの）。
- 作り終わると、外からの検証（`docker inspect`）と中からの検証（`dcs-verify`）を行い、すべて `[OK]` なら「次にすること」を表示します。

### 5.2 `allowed_domains` の書き方

- カンマ区切りで書きます（例: `registry.npmjs.org, pypi.org`）。通信を許可するドメインが無い場合は `-` を入力します。
- Claude Code・GitHub・VS Code・Rust・uv など、ツールが動くのに要る通信先は、ツールが別に許可しています。ここに書くのは、それ以外のものだけです。
- `*.example.com` のような、サブドメインをまとめて許す書き方は使えません。ファイアウォールが、コンテナを起動するときにドメインごとに IP アドレスを引くためです。使うサブドメインを 1 つずつ書いてください。`*`（すべて許可）も使えません。
- 許可するドメインを増やすほど、データを外へ持ち出される経路も増えます。必要なものだけを書いてください。
- VS Code の拡張機能を、コンテナの中で自動で入れたいとき（[6.2](#62-拡張機能が自動で入らないとき)）は、拡張機能の発行者ごとに `<発行者>.gallerycdn.vsassets.io` と `<発行者>.gallery.vsassets.io` を足します。
- 変えるときは、ウィザードの 2（やり直す）を使います。

### 5.3 情報の扱い

- 画面で入力した値は、Windows 側のファイルには保存しません。
- PAT は、入力のあいだ SecureString で持ち、コンテナに標準入力で渡します。画面・コマンドの引数・環境変数には出しません。保存先は、その開発環境のボリューム（コンテナの中の `/home/dev/.dcs-git/credentials`。モード 600）だけです。
- コミットの作者（`user_name`・`user_email`）は、コンテナの中のリポジトリの設定（`.git/config`）に書きます。
- LocalGit の `repo_path` は、Windows 側の同期スクリプト（`envs\<名前>\Sync-<名前>.ps1`）に書き込まれます。前回の同期の記録は、Windows 側の bare リポジトリの中の `dcs-sync\<名前>.txt` に書きます。

## 6. 作ったあとの作業

### 6.1 VS Code で開く（Code-<名前>.cmd と「Reopen in Container」）

1. ツールのフォルダの `envs\<名前>\Code-<名前>.cmd` をダブルクリックします。VS Code が、土台のフォルダ（`/home/dcs/envs/<名前>/config`）を WSL のウィンドウで開きます（左下に「WSL: dcs-base」と出ます）。
2. 右下の通知の「Reopen in Container」を押します（コマンドパレットの「Dev Containers: Reopen in Container」でも同じです）。
3. コンテナの中のウィンドウに切り替わり、作業フォルダ `/workspaces/<リポジトリ名>` が開きます。ツールが作ったコンテナを、そのまま使います。

**土台の WSL のウィンドウでは、作業しないでください。**

- 手順 1 のウィンドウでは、VS Code に組み込まれた Copilot などが、土台の中で動きます。土台のユーザーは Docker を操作できるので、土台では root と同じことができ、ファイアウォールもありません。
- このウィンドウでは、チャットもターミナルも使わず、すぐに「Reopen in Container」を押してください。これは利用者の責任です（ツールでは止めていません）。

VS Code がコンテナにつながるたびに、受け渡しの確かめ（`dcs-check-forwarding`）が動きます。`[警告]` が出たら、[3.1](#31-windows-の-vs-code-のユーザーの設定5-つ) の設定を確かめてください。何も無ければ、何も表示しません。

ファイアウォールのメッセージ（`Running the postStartCommand from devcontainer.json...` のあとの行）は、VS Code がコンテナを起動したとき（止まっていたコンテナを開いたとき）だけ、ターミナルに出ます。ウィザードや同期スクリプトが起動したコンテナが、まだ動いているうちに開いたときは、そのときにファイアウォールを入れてあるので、VS Code は入れ直さず、このメッセージも出ません（入れたときのメッセージは、ウィザードの画面に出ています）。どちらも問題ありません。ファイアウォールが入っていることを確かめたいときは、ウィザードの「検証だけ」を使います（[7 章](#7-管理やり直す検証だけ更新削除)）。
`wsl --shutdown`後などで，コンテナが停止してから再度起動すると，ファイアウォールのメッセージが出ます．

### 6.2 拡張機能が自動で入らないとき

- `extensions.txt` の拡張機能は、VS Code がコンテナにつながったときに入れます。
- 拡張機能の取得先はファイアウォールで許可していないので、VS Code が Windows の側で取ってきて、コンテナに入れ直します。それでも入らなかったものは、拡張機能のビューで、その拡張機能の「Install」を押してください。
- 自動で入れたいときは、`allowed_domains` に発行者ごとの名前を足します（[5.2](#52-allowed_domains-の書き方)）。

**使うときに、何かをダウンロードする拡張機能**

- 拡張機能によっては、入ったあと、使うときに、追加のもの（ブラウザー・言語のサーバー・道具など）をインターネットから取ってきます。
- コンテナの中で動く拡張機能の通信はファイアウォールの対象なので、取ってくる先が許可リストに無いと、失敗して、その機能が動かないことがあります。
- 例: Markdown PDF（`yzane.markdown-pdf`）は、PDF を作るための Chromium を `storage.googleapis.com` から取ってこようとして、次のエラーを出します。

  ```
  ERROR: Failed to download Chromium! If you are behind a proxy, set the http.proxy option to settings.json and restart Visual Studio Code.
  ```

- そのような拡張機能は、コンテナの中では使わず（`extensions.txt` から外すか、コンテナのウィンドウでアンインストールする）、Windows の VS Code（コンテナにつないでいないウィンドウ）で使ってください。
- 取ってくる先を `allowed_domains` に足すこともできますが、`storage.googleapis.com` のように、誰でも置き場所を作れる広いドメインを許すと、データを外へ持ち出される経路が大きく広がります（[11 章](#11-既知のリスク黙認するもの)の R5）。

### 6.3 Claude Code にログインする

- コンテナのターミナルで `claude` を起動し、ログインします。
- ログインは開発環境ごとに別々です（開発環境のあいだで、ログインのデータを共有しません）。
- `--dangerously-skip-permissions` を付けるかは、起動するときに選んでください。

### 6.4 手で行う確かめ

ログインしたら、次を確かめてください。

1. Claude Code で `/status` を実行し、設定の読み込み元（Setting sources）に「User settings」と「Enterprise managed settings (file)」があること。組織が claude.ai の管理画面から managed settings を配っている場合は、ファイルの managed settings の代わりに、それが表示されます。
2. 権限ルール（deny）が効くこと。本物の PAT のファイルではなく、同じ規則に当たる確かめ用のファイルを使います。
   - ターミナルで `echo test > ~/.dcs-git/deny-check.txt` を実行する。
   - Claude に「`~/.dcs-git/deny-check.txt` を読んで」と頼み、断られることを確かめる。
   - ターミナルで `rm ~/.dcs-git/deny-check.txt` を実行して消す。

deny で読み取りを止めているのは、PAT のファイル（`~/.dcs-git/`）・Claude Code のログイン情報（`~/.claude/.credentials.json`）・`~/.ssh`・`~/.aws` です。編集を止めているのは `~/.claude/settings.json` です。これらは「うっかり」の歯止めで、スクリプトを通してわざと読むことは止めません（[10 章](#11-既知のリスク黙認するもの)）。

### 6.5 GitHub モードの使い方

- VS Code のソース管理で、commit・pull・push します。コンテナの中の git が、保存した PAT を使います。
- PAT は、次のように作ってください（GitHub の Settings → Developer settings → Personal access tokens → Fine-grained tokens）。
  - Expiration（有効期限）: 短めにする
  - Repository access: Only select repositories で、その開発環境のリポジトリだけを選ぶ
  - Permissions: Repository permissions の Contents を「Read and write」にする
- PAT の期限が切れたときは、ウィザードの 2（やり直す）で、その開発環境を選び、「PAT（とコミットの作者）を入れ直しますか？」に `y` と答えます。
- 作るときに、ツールは PAT で push できるか（`git push --dry-run`。何も送りません）を確かめます。
- リポジトリに Claude Code の設定（`.claude`・`.mcp.json`）が入っていれば、注意を表示します。そのときは、Claude Code を起動する前に中身を確かめてください（hooks や MCP サーバーの設定は、起動したときに効きます）。

### 6.6 LocalGit モードの使い方（Sync-<名前>.cmd）

- コンテナの中では、VS Code のソース管理で commit・pull・push します。相手は、開発環境の中継の bare リポジトリ（`/relay.git`）です。
- Windows 側の bare リポジトリとのやりとりは、`envs\<名前>\Sync-<名前>.cmd` をダブルクリックして行います。
  - Windows 側・開発環境の中・前回の同期の記録の 3 つを比べて、変わったほうの内容をもう一方へ写します。
  - 写す内容を表示するので、確かめてから `y` を入力します。
  - 両側が変わっているときと、force にあたる変更（fast-forward でない更新、タグの付け替え）があるときは、写さずに止まります。
  - 開発環境の中へ写したあとは、コンテナの作業フォルダで `git pull --prune` を実行すると、作業用の clone にも入ります。
  - 前回の同期の記録が無く、両側が違うときは、どちらに合わせるかを指定します（`Sync-<名前>.cmd -Direction ToEnv` で Windows 側に合わせる、`-Direction ToWindows` で開発環境に合わせる）。
- **コミットの作者は、コンテナの作業フォルダのリポジトリの設定に書いてください**（`--global` は使いません）。

  ```bash
  cd /workspaces/<リポジトリ名>
  git config user.name "あなたの名前"
  git config user.email "you@example.com"
  ```

### 6.7 ふだんの使い方の約束

- 開くときは、いつも `Code-<名前>.cmd` から開きます。
- コンテナを止めるときは、VS Code のウィンドウを閉じます。
- `docker start` などで、コンテナを直接起動しないでください。ファイアウォールが入りません（ファイアウォールは、VS Code かツールがコンテナを起動したときに入れます）。
- 土台やコンテナに、Windows の秘密の情報（`~/.ssh` やクラウドの認証情報）を持ち込まないでください。
- Windows のエクスプローラーから開発環境のフォルダ（`\\wsl.localhost\dcs-base\...`）へファイルをコピーすると、`<元の名前>:Zone.Identifier` というファイルができます。コンテナのターミナルで `delzonei`（`-n` で、消さずに表示だけ）を実行すると消せます。

## 7. 管理（やり直す・検証だけ・更新・削除）

どれも、その開発環境を VS Code で開いていると、閉じるよう表示して止まります（何も変更しません）。

| 行うこと | 内容 |
|---|---|
| 2. やり直す | `allowed_domains` の変更、PAT の入れ直し、`extensions.txt` や注文書のひな形を変えたあとの注文書とスクリプトの作り直し。コンテナも作り直します（`work/` とボリュームは残ります）。モードは変えられません。GitHub モードでは、clone したリポジトリも変えられません（別のリポジトリにしたいときは、別の開発環境を作ります）。LocalGit モードでは、`repo_path` を聞き直します（既定は前の値） |
| 4. 検証だけ | 土台と、選んだ開発環境の守りの設定を確かめます。コンテナが止まっていれば起動します |
| 5. 更新 | 土台の Ubuntu と Docker Engine の更新、Dev Containers CLI の入れ直し、`/etc/wsl.conf` の置き直しと土台の起動し直し、イメージの作り直し（ベースの `ubuntu:26.04` も取り直す）、すべての開発環境のコンテナの作り直しと検証、古いイメージの削除。数分から十数分かかります。Windows の WSL（`wsl --update`）と VS Code の更新は含みません |
| 3. 削除 | その開発環境のコンテナ・ボリューム・ネットワーク・土台のフォルダ・`envs\<名前>\` をまとめて消します。push や同期をしていない変更、Claude Code の会話の履歴とログイン、PAT も消えます。確かめのため、名前をもう一度入力します。Windows 側の LocalGit のリポジトリと、その中の `dcs-sync\<名前>.txt` は残ります |

- Claude Code は、コンテナの中で自動で更新されます。「更新」は、コンテナを作り直したときに戻る版（イメージの版）を新しくします。
- ツールを新しい版にするときは、[7.1](#71-ツールの完全削除ツールを新しい版にするとき使い終わったとき) のとおり、ツールを完全に消してから入れ直します（ツールには、版を上げる仕組みがありません）。「更新」は、今の版のまま、土台の Ubuntu・Docker Engine とイメージを新しくするためのものです。
- 「作る」「やり直す」は、今あるイメージをそのまま使います。`image\` のファイルを変えたとき（8 章）は、「更新」でイメージを作り直します。
- 「作る」が、開発環境のものを作り始めたあとで止まったときは、作りかけの開発環境が土台に残ります（同じ名前では作れません）。原因を取り除いてから「やり直す」で続けるか、「削除」で消してください。
- 削除の名前の一覧には、土台にフォルダがある開発環境だけが出ます。「新しい開発環境を作る」で「残りがあります」と表示された名前は、一覧に無くても、入力して消せます。
- 土台ごとすべてを消すときは、[7.1](#71-ツールの完全削除ツールを新しい版にするとき使い終わったとき) の「ツールの完全削除」を行います。

### 7.1 ツールの完全削除（ツールを新しい版にするとき・使い終わったとき）

ツールには、版を上げる仕組みがありません。ツールを新しい版にするときは、次の手順で土台ごと消してから、入れ直します。開発環境の成果物は、GitHub か Windows 側の LocalGit のリポジトリに出しておくので、作り直した開発環境に、もう一度取り込めます。

- **消えるもの**: 土台（dcs-base）の中のすべて。どの開発環境の作業フォルダ（`work/`）・中継のリポジトリ（`/relay.git`）も、Claude Code の会話の履歴とログイン、PAT、イメージも消えます。元に戻せません。
- **残るもの**:
  - GitHub のリポジトリと、Windows 側の LocalGit のリポジトリ
  - LocalGit のリポジトリの中の `dcs-sync\<名前>.txt`（作り直した開発環境の最初の同期で書き直されるので、そのままでかまいません）
  - ツールのフォルダ（`envs\` は手順 4 で消します）
  - Windows の VS Code の設定と `.wslconfig`

1. 開発環境ごとに、成果物を外に出します。push や同期をしていない変更は消えます。
   - GitHub モード: コンテナの中で commit して push する。
   - LocalGit モード: コンテナの中で commit して `/relay.git` に push し、`Sync-<名前>.cmd` で Windows 側に写す。
2. dcs-base につないでいる VS Code のウィンドウを、すべて閉じます。
3. PowerShell で、土台を消します（土台の中のものは、すべて消えます）。

   PowerShell:

   ```
   wsl --unregister dcs-base
   ```

4. ツールのフォルダの `envs\` の中（開発環境ごとの `Code-<名前>.cmd`・`Sync-<名前>.cmd`・`Sync-<名前>.ps1`）を消します。
5. 新しい版にするときは、ツールのフォルダを新しい版に入れ替えます。自分で変えたもの（`defaults.conf`・`extensions.txt`・注文書のひな形など。[8 章](#8-カスタマイズ)）は、先に控えておき、新しい版に入れ直します。
6. `setup-wizard.cmd` で「新しい開発環境を作る」を選びます（土台から作り直します）。
   - 開発環境ごとに作り直し、Claude Code にログインし直します（GitHub モードは PAT も入れ直します）。
   - 同じ名前・同じリポジトリで作り直すと、VS Code で開いたときに「構成ファイルが変更されました」が 1 回出ることがあります。「Ignore」を押してください（[10 章](#10-困ったとき)）。

使い終わったとき（入れ直さないとき）は、手順 1〜4 のあとで、次も元に戻してください。

- Windows の VS Code のユーザーの設定の 5 つ（[3.1](#31-windows-の-vs-code-のユーザーの設定5-つ)）。特に `executeInWSL`・`executeInWSLDistro` が残ると、ほかの Dev Containers が dcs-base を探して動きません。
- `.wslconfig` の `guiApplications=false`（[3.2](#32-wslconfig2-つ)）。残っていると、すべてのディストリビューションで GUI のアプリが使えません。直したら、PowerShell で `wsl --shutdown` を実行します。
- ツールのフォルダそのもの。

## 8. カスタマイズ

直してよいのは、次の表のファイル（とその場所）だけです。表に無いところ（`base\`・`image\` のほかのファイル、`lib\`、注文書のひな形の守りの部分など）を変えたときの動きは、サポートしません。

| ファイル | 変えられること | 反映されるとき |
|---|---|---|
| `defaults.conf` | `allowed_domains` の既定値 | 次に開発環境を作るとき。今ある開発環境は、ウィザードの 2（やり直す）で入力し直す |
| `extensions.txt` | コンテナに入れる VS Code の拡張機能 | 作るとき・やり直すとき（注文書を書き直すとき） |
| `templates\devcontainer.json.tmpl`（注文書のひな形）の、決まった 2 か所 | コンテナのウィンドウの VS Code の設定（`customizations.vscode.settings`）と、コンテナの環境変数（`containerEnv`）を足す | 作るとき・やり直すとき |
| `image\claude-settings.json` | Claude Code の好みの設定の既定（今はステータスラインと `"tui": "fullscreen"`） | 「更新」のあとに新しく作る開発環境。今ある開発環境の `~/.claude/settings.json` は、そのまま残ります |
| `image\Dockerfile` の、「足してよい」というコメントのある 2 か所 | 道具のパッケージ（`git build-essential …` の行に、apt のパッケージを足す）と、道具を入れる `RUN` の行（ファイルの最後の「ここに足してよい」の場所に、コンテナのユーザー `dev` として入れる行を足す） | 「更新」のとき（イメージを作り直す） |
| `image\statusline.sh` | Claude Code のステータスライン | 「更新」のとき |

**注文書のひな形（`templates\devcontainer.json.tmpl`）の決まった 2 か所**

- `customizations.vscode.settings` と `containerEnv` の中の「ここに足してよい」というコメントの行の下（守りの設定より上）に、1 行に 1 つずつ足します。

  ```jsonc
  "settings": {
    // ここに足してよい: 1 行に 1 つ、"設定の名前": 値, の形（最後にカンマを付ける）
    "editor.fontSize": 15,
    "files.autoSave": "afterDelay",
    // ここから下の 8 つは、VS Code の受け渡し（git の認証情報・.gitconfig など）を止める守りの設定。変えないでください。
    "dev.containers.copyGitConfig": false,
  ```

- 足す行は、どれも最後にカンマ（`,`）を付けます。コメントは `//` で始まる行だけが使えます（行の途中の `//` は使えません）。
- 環境変数は、コンテナの中の Claude からも見えます。PAT やパスワードなどの秘密の値は書かないでください。
- 環境変数のうち、`PATH`・`LD_PRELOAD`・`LD_LIBRARY_PATH`・`LD_AUDIT`・`BASH_ENV`・`SHELLOPTS`・`BASHOPTS`・`PS4`（動くプログラムや bash の動きを変えるもの）と、名前の形でないもの（`"PATH=…"` など。名前は半角英数字と `_` だけで、先頭は数字以外）は書けません。書くとウィザードが止まります（`PATH` の前に Claude が書けるフォルダが来ると、起動のときの処理や検証で、Claude のものが動いてしまうため）。
- 拡張機能は、ひな形ではなく `extensions.txt` に書きます。
- ひな形が JSON として読めない、印（`__ENV_NAME__` などの、前後に `_` が 2 つずつ付いた大文字の名前）が足りない・知らない印がある、ときは、ウィザードが止まって知らせます。
- 変えたあとは、今ある開発環境ごとに、ウィザードの 2（やり直す）で注文書を書き直してください。「更新」では、注文書は書き直しません。

**ほかに知っておくこと**

- VS Code の設定の多くは、Windows の VS Code のユーザーの設定に書けば、コンテナのウィンドウでも効きます（範囲が machine の設定は効きません。その場合は注文書のひな形に足します）。
- Claude Code の設定は、コンテナの中で `~/.claude/settings.json` を直しても、残ります。ツールは、コンテナを起動するとき（作る・やり直す・更新・検証だけ）に、守りの部分（deny）だけを置き直します（変わるときは、前のファイルを `.bak-日時` で残します）。自分で足した deny も残ります（守りの deny のあとに続けます）。
- コンテナでは、VS Code とツールが、起動のときやコマンドを実行するときに `~/.bashrc` などを読みません（注文書の `"userEnvProbe": "none"`。Claude が書けるファイルなので、ファイアウォールより先に何かを動かせないようにするため）。`~/.bashrc` で足した PATH や環境変数は、ターミナルでは効きますが、VS Code の拡張機能・タスク・デバッグからは見えません。拡張機能に見せたい環境変数は、注文書のひな形の `containerEnv` に足します（`PATH` などは書けません。上の「決まった 2 か所」）。
- コンテナの PATH は、システムのフォルダが先で、`~/.local/bin`（Claude Code・uv）と `~/.cargo/bin`（Rust）はその後ろです。同じ名前のコマンドがあれば、システムのものが使われます。
- コンテナを作ったあと、コンテナの中で道具（`uv tool install`・`cargo install` など）を入れるのは自由です。拡張機能から使いたい道具は、`~/.local/bin` に入れる（かリンクを置く）と、どこからでも見つかります。すべての開発環境に入れたい道具は、`image\Dockerfile` の「ここに足してよい」の場所で入れます。
- `image\Dockerfile` に足すときも、`ENV PATH=…` のように `PATH`・`LD_PRELOAD` などを変えないでください（上の注文書と同じ理由です。こちらはウィザードも検証も見つけられません）。入れた道具を PATH に通すときは、`~/.local/bin` にリンクを置きます（`RUN ln -s …`）。
- `image\managed-settings.json`（deny）、`image\firewall-domains.txt`（固定の許可リスト）、`base\wsl.conf` は、守りの設定です。この表には入れていません。

## 9. ファイル構成

**ツールのフォルダ（Windows）**

```
_dev-container-setup\
 ├ setup-wizard.cmd          ← 入口（ダブルクリック）
 ├ DevContainerSetup.ps1     ← ウィザードの本体
 ├ defaults.conf             ← allowed_domains の既定値
 ├ extensions.txt            ← コンテナに入れる VS Code の拡張機能
 ├ lib\                      ← ウィザードの部品（PowerShell）
 ├ base\                     ← 土台に置くもの（setup-base.sh・verify-base.sh・wsl.conf）
 ├ image\                    ← イメージの材料（Dockerfile・ファイアウォール・検証・設定のひな形など）
 ├ templates\                ← ひな形（devcontainer.json.tmpl: 注文書、Sync-Env.ps1.tmpl: 同期スクリプト）
 ├ tests\                    ← テスト
 ├ envs\<名前>\              ← 開発環境ごとに作るスクリプト（Code-<名前>.cmd、Sync-<名前>.cmd・.ps1）
 └ README.md・SPEC.md・DEV.md・TEST.md・DESIGN.md・VERIFY.md・PLAN.md・PROGRESS.md
```

**土台（dcs-base）**

```
/opt/dcs/base/・/opt/dcs/image/   ← ツールが置いた材料（root の持ち物）
/home/dcs/envs/<名前>/
 ├ config/.devcontainer/devcontainer.json   ← 注文書。コンテナにはつながない
 ├ work/                                    ← コードの実体。コンテナの中では /workspaces/<リポジトリ名>
 ├ relay.git/                               ← LocalGit だけ: 中継の bare リポジトリ（コンテナの中では /relay.git）
 └ allowed-domains.txt                      ← 開発環境ごとの通信先。コンテナには読み取り専用でつなぐ
```

**ボリュームとネットワーク（Docker）**

| 名前 | 中身 |
|---|---|
| `dcs-<名前>-claude` | Claude Code の会話履歴・設定・ログイン情報（`~/.claude`） |
| `dcs-<名前>-git` | PAT（GitHub モードだけ） |
| `dcs-<名前>`（ネットワーク） | その開発環境のコンテナだけがつながるネットワーク |

## 10. 困ったとき

**「開発環境（…）のコンテナが動いています。」と出て止まる**

- その開発環境を VS Code で開いているときは、そのウィンドウを閉じてください（閉じると、コンテナは止まります）。
- VS Code で開いていないのに動いているときは、ほかの開発環境を VS Code で開いているか、閉じたばかりで、土台がまだ動いているためです。ウィザードや同期スクリプトが起動したコンテナは、土台が動いている間は動いたままになります（ファイアウォールは入っています）。
- dcs-base の VS Code のウィンドウをすべて閉じて、1 分ほど待ってから、もう一度実行してください。それでも止まらないときは、次の「土台が休まない」を見てください。

**土台が休まない（`wsl -l -v` で dcs-base が Running のまま）**

- 土台を作った直後に、VS Code で初めて土台につないだあと、VS Code を閉じても土台が休まなくなることがありました（Windows 側に `wslhost.exe` が残り、土台を動かし続けます。原因は確かめきれていません）。
- PowerShell で `wsl --terminate dcs-base` を実行すると止まります。土台を止めるだけで、中のものは消えません。dcs-base を開いている VS Code のウィンドウがあれば、つながりが切れるので、先に閉じてください。

**土台の検証で `[WARN] B4`・`[WARN] B5` が出る**

- B4（WSLg が止まっていない）: `.wslconfig` の `guiApplications=false` を確かめてください（[3.2](#32-wslconfig2-つ)）。
- B5（VS Code の拡張機能フォルダがマウントされていない）: `.wslconfig` の `hostFileSystemAccess=false` の行を消してください。
- どちらも、直したら `wsl --shutdown` を実行します。

**「Reopen in Container」で、Docker が見つからないなどのエラーになる**

- [3.1](#31-windows-の-vs-code-のユーザーの設定5-つ) の `executeInWSL`・`executeInWSLDistro` を確かめてください。

**コンテナで開いたときに「構成ファイルが変更されました: devcontainer.json。変更を適用するには、コンテナーの再構築が必要な場合があります。」と出る**

- VS Code は、コンテナのウィンドウ（開発環境の名前とリポジトリ名で決まる）ごとに、前に開いたときの注文書を覚えていて、今の注文書と違うとこの通知を出します。ツールの「やり直す」で注文書が変わったあとや、消した開発環境と同じ名前・同じリポジトリで作り直したあとに、1 回出ることがあります。
- ツールが、今の注文書に合わせてコンテナを作ったあとなので、再構築は要りません。「Ignore」（無視）を押してください。VS Code が今の注文書を覚え直し、注文書がまた変わるまでは出ません。
- 「Rebuild」を押しても壊れませんが、VS Code が自分でコンテナを作り直すので、ツールの検証を通っていない状態になります。押したときは、ウィンドウを閉じてから、ウィザードの 4（検証だけ）を実行してください。
- この通知を止める設定は、Dev Containers 拡張にはありません。

**コンテナの中で `[警告]` が出る（dcs-check-forwarding）**

- VS Code が、Windows のもの（`.gitconfig`・認証情報・画面のソケットなど）をコンテナに渡しています。[3.1](#31-windows-の-vs-code-のユーザーの設定5-つ) の設定を確かめ、コンテナを作り直して（ウィザードの 2）ください。

**許可したドメインに届かなくなった**

- ファイアウォールは、コンテナを起動したときにドメインの IP アドレスを引きます。途中で IP アドレスが変わると届かなくなります。VS Code のウィンドウを閉じて、開き直してください。

**ファイアウォールの `[WARN]`（「固定の許可リストの … は、IPv4 のアドレスを引けなかったので飛ばします。」）が出る**

- ツールが持つ許可リスト（`image\firewall-domains.txt`）のドメインを、コンテナを起動したときに引けなかったので、そのドメインだけを許さずに、ファイアウォールを入れました。ほかのドメインは、ふつうに使えます。そのドメインの用途（Claude Code のログイン・自動更新など）は使えません。
- `=` の線で囲んだ `[WARN]` に、用途と理由（`NXDOMAIN`・`SERVFAIL` など）が出ます。最後（`[完了]` のあと）にも、飛ばしたドメインをもう一度出します。
- DNS の一時的な不調（`SERVFAIL` など）なら、コンテナを起動し直すと、もう一度引きます（コンテナが止まってから、VS Code で開き直します。止まらないときは、上の「土台が休まない」の `wsl --terminate dcs-base`）。
- `NXDOMAIN`（そのドメインが無い）が続くときは、Claude Code の公式の一覧からドメインが無くなった見込みです。ツールの新しい版を確かめてください。
- DNS そのものから答えが無いとき（オフラインなど）は、飛ばさずに失敗します（外への通信を止めた状態になり、`[失敗]` が出ます）。ネットワークを直してから、コンテナを起動し直してください。

**検証で `[NG]` が出た**

- 表示された理由を取り除いてから、ウィザードの 2（やり直す）を実行してください。
- `[NG] I4`（managed settings がツールのひな形と違う）や、土台の検証の `[NG] B2`（`/etc/wsl.conf` がツールのものと違う）は、完全削除をせずに、ツールのフォルダだけを新しい版にしたときに出ます。ツールの版を変えるときは、[7.1](#71-ツールの完全削除ツールを新しい版にするとき使い終わったとき) のとおり、完全に消してから入れ直してください。
  - そのまま続けたいときは、ウィザードの 5（更新）でも直ります（イメージを作り直し、`/etc/wsl.conf` を置き直して土台を起動し直します。更新のときは、B2 の NG では止まりません）。ただ、版のあいだの違いをすべて直せるとは限りません。

**ウィザードや同期スクリプトの日本語が化ける**

- `setup-wizard.cmd`・`Sync-<名前>.cmd` から起動してください（画面の文字コードを、起動のあいだ UTF-8 にそろえます）。

**予期しないエラーが出た**

- ウィザードは、表示の最後に、原因を調べるための情報を出します。それを Claude Code に伝えると、原因を調べられます。

## 11. 既知のリスク（黙認するもの）

公式の方式でも残るもので、このツールは止めません。前提は「信頼できるリポジトリで使い、Claude の作業を見守る」ことです。

| # | リスク | 減らす方法 |
|---|---|---|
| R1 | 悪意のあるコードが、コンテナの中のもの（Claude のログイン情報・PAT・コード）を持ち出す（公式の警告のとおり） | 信頼できるリポジトリで使う。PAT はリポジトリ限定・期限付きにする。使い終わった開発環境は削除する |
| R2 | Windows の VS Code は、コンテナの中の VS Code サーバーと拡張機能を信用する。コンテナの中のコード（拡張機能など）が、Windows の VS Code を通して、Windows でコマンドを実行する・URI を開く・クリップボードを読み書きする、などができる | 入れる拡張機能を絞る（`extensions.txt`）。信頼できるリポジトリで使う |
| R3 | Claude が、Python などのスクリプトを通して PAT を読める（deny はスクリプトでの読み取りを止めない） | PAT をリポジトリ限定・期限付きにする |
| R4 | hooks・VS Code の拡張機能・利用者が実行するビルドやテストは、Claude の権限ルールの外で動く | 何を実行するかを確かめる |
| R5 | 通信を許可したドメインへ、データを送られる | `allowed_domains` を必要なものだけにする |
| R6 | コンテナにつないだフォルダ（`work/`・`relay.git/`）のコードを書き換えられる | LocalGit の Windows 側への反映は、同期スクリプトで内容を確かめてから `y` で行う |
| R7 | WSL 2 の VM とカーネルを、すべてのディストリビューションとコンテナが共有している（突くには脆弱性が要る） | Windows と WSL を更新する |
| R8 | ネットワークの制限の残り（下の表） | — |
| R9 | 組織の managed settings があるとき、Claude がスクリプトで `~/.claude/settings.json` を書き換えて、deny を外せる | — |
| R10 | Windows の VS Code を通る経路（R2）で、開発環境 A から開発環境 B に届く。開発環境どうしの隔離で保証するのは「コンテナどうしの直接の経路は閉じる」までです | 信頼できるリポジトリで使う |

**ネットワークの制限で黙認するもの（R8）**

- 許したドメインの IP アドレスは、共有の CDN のものが多く、許す範囲はドメイン名より広くなります。
- IP アドレスはコンテナを起動したときの値なので、途中で変わると届かなくなります（起動し直せば直ります）。
- 土台（ゲートウェイ）の IP アドレスを通して、WSL のほかのディストリビューションで、すべてのアドレスに向けて待ち受けているサーバーに届きます。
- DNS は Docker の内部の DNS だけに絞っていますが、内部の DNS も外へ問い合わせを中継するので、DNS を使ったデータの持ち出しは止めません。

**このツールの使い方で残るもの**

- 土台の WSL のウィンドウ（[6.1](#61-vs-code-で開くcode-名前cmd-とreopen-in-container) の手順 1）では、VS Code に組み込まれた Copilot が、頼まないうちに土台の中で起動します。土台ではファイアウォールが無く、Docker を操作できます。このウィンドウでは作業しないでください。
- ウィザードや同期スクリプトが起動したコンテナは、土台が動いている間は動いたままになります（ファイアウォールは入っています。[9 章](#10-困ったとき)）。
- `extensions.txt` の拡張機能は、VS Code が Windows の側で取ってきてコンテナに入れます（コンテナの中で動き、R2・R4 の対象です）。

## 12. 出典

- Claude Code の公式の文書: [開発コンテナ](https://code.claude.com/docs/ja/devcontainer)、[サンドボックス環境](https://code.claude.com/docs/ja/sandbox-environments#choose-an-approach)、ネットワークの設定（許可するドメインの一覧のもと）。
- 公式の参考例（`anthropics/claude-code` の `.devcontainer/`）を、考え方の手本にしました。ファイアウォールのしくみ（iptables と ipset、既定で拒否、起動のたびに `postStartCommand` から入れる）は同じです。参考例のリポジトリは「All rights reserved」なので、ファイアウォールのスクリプトとイメージの手順書は写さず、このツールで独自に書きました。参考例との違いは、許可するドメインの一覧を今の公式の一覧に合わせたこと、SSH（TCP 22）の規則を外したこと、DNS を Docker の内部の DNS に絞ったこと、IPv6 なしのネットワークにしたこと、開発環境ごとの `allowed_domains` を足したことです。
- VS Code の文書（Dev Containers・WSL・Alternative Docker options）。
- 設計の記録は DESIGN.md、実機で確かめたことは VERIFY.md と TEST.md にあります。
