# GitHub

本スクリプトで作成したディストリビューションから，GitHubのリポジトリとPATを使って開発するための設定です．

## 自動で設定する場合

部屋を作るときに `room-github.conf`（`room.conf` と同じフォルダ）に記入しておくと，下の「手動で設定する場合」の設定と，コミットの作者（`user.name`，`user.email`）の設定，`~/projects/REPOSITORY` へのクローンが自動で行われます（README の 4 章と 6.6 節）．
PATは `~/.git-credentials` に保存され，認証用のユーザー名には固定の文字列 `pat` が使われます（GitHubはPATだけでアカウントを判別するため，ユーザー名は何でも構いません）．

## 手動で設定する場合（2つ目以降のリポジトリなど）

以下を順番に実行してください．
`room-github.conf` で設定済みの部屋では，最初のブロック（認証情報の保存方法）とコミットの作者の設定は済んでいるので，`git clone` からで構いません．

```bash
# 認証情報を永続保存する
git config --global credential.helper store

# リポジトリ単位で認証情報を分離する
git config --global credential.useHttpPath true

# 認証情報ファイルを作成し、自分だけが読めるようにする
touch ~/.git-credentials
chmod 600 ~/.git-credentials
```

```bash
# コミットの作者（GitHubのアカウントと関係のないダミーでよい）
git config --global user.name "dev-room"
git config --global user.email "dev-room@example.com"
```

```bash
cd ~/projects
git clone https://github.com/OWNER/REPOSITORY.git
```

以降，`git pull`, `git push`やVSCodeのソース管理からプッシュする際に，User名(任意)とPasswordを求められます．Passwordの方にPATを入力して，作業を継続してください．
