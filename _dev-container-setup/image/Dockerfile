# =============================================================================
# dcs-image — 開発環境のコンテナのイメージ（DESIGN.md の 6.5a。D29）
#
# 土台（dcs-base）の dcs が、Windows 側の lib/Base.ps1 の Build-DcsImage から作ります。
#   docker build --label dcs=1 --build-arg DCS_UID=<土台の id -u dcs> -t dcs-image /opt/dcs/image
# 前半が守りの部分（非 root のユーザー、sudo はファイアウォールだけ、ファイアウォール、managed settings、apt は https）、
# 後半が道具の部分（Claude Code、git、uv、Rust、ステータスライン、delzonei）。
# 実機での確かめ: VERIFY.md の V5（ベースのイメージ）、V6（Claude Code の入れ方）、V7（ファイアウォール）。
# =============================================================================
FROM ubuntu:26.04
# コンテナのユーザー dev の UID。土台の dcs とそろえる（work/・relay.git/ を両方から読み書きするため）
ARG DCS_UID
LABEL dcs=1
SHELL ["/bin/bash", "-Eeuo", "pipefail", "-c"]

RUN [[ ${DCS_UID:-} =~ ^[1-9][0-9]*$ ]] || { echo 'DCS_UID（土台の dcs の UID）を --build-arg で渡してください。' >&2; exit 1; }

# ---- 守りの部分 ----

# apt の取得先を https にする（V5: ca-certificates が無いので、http のままでそれだけを入れてから切り替える）
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && sed -Ei 's!http://((([a-z]+\.)?archive|security)\.ubuntu\.com)!https://\1!g' /etc/apt/sources.list.d/ubuntu.sources \
    && if grep -Eq '^[[:space:]]*URIs:.*http://' /etc/apt/sources.list.d/*.sources; then echo 'apt の取得先に、https でないものが残っています。' >&2; exit 1; fi \
    && rm -rf /var/lib/apt/lists/*

# 守りの部分のパッケージ（ファイアウォールと sudo。iproute2 はゲートウェイを ip route で読むため。V7）と、道具の部分のパッケージ。
# ベースのイメージに入っているものも、更新があれば入れる（土台と同じく、conffile の質問では止めない）
# カスタマイズ（README の「カスタマイズ」）: 2 行目（git build-essential … の行）に、道具のパッケージを足してよい。
# 1 行目（sudo iptables …）は守りの部分なので、変えないでください。
RUN apt-get update \
    && apt-get upgrade -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold \
    && apt-get install -y --no-install-recommends \
        sudo iptables ipset dnsutils aggregate jq curl iproute2 \
        git build-essential pkg-config libssl-dev python3 \
    && rm -rf /var/lib/apt/lists/*

# ベースのイメージの UID 1000 のユーザー（ubuntu。sudo グループにいる）を消して、dev を作る（V5）。
# ~/.claude と ~/.dcs-git はボリュームの取り付け先。ボリュームは、初めてつなぐときにこの持ち主とモードを受け継ぐ
RUN userdel -r ubuntu \
    && useradd -m -u "$DCS_UID" -s /bin/bash dev \
    && install -d -m 700 -o dev -g dev /home/dev/.claude /home/dev/.dcs-git

# 置き場所のフォルダは先に作っておく（COPY --chmod は、新しく作る親のフォルダにも同じモードを付けるので、
# 644 だと dev がフォルダに入れず、Claude Code が managed settings を読めなくなる）
RUN install -d -m 755 /etc/claude-code /usr/local/share/dcs /etc/dcs
COPY --chmod=755 init-firewall.sh /usr/local/bin/init-firewall.sh
COPY --chmod=644 firewall-domains.txt /etc/dcs/firewall-domains.txt
COPY --chmod=644 managed-settings.json /etc/claude-code/managed-settings.json
COPY --chmod=644 claude-settings.json /usr/local/share/dcs/claude-settings.json
COPY --chmod=755 statusline.sh /usr/local/share/dcs/statusline.sh
COPY --chmod=644 gitconfig /etc/gitconfig
COPY --chmod=440 sudoers-dcs-firewall /etc/sudoers.d/dcs-firewall
COPY --chmod=755 delzonei.sh /usr/local/bin/delzonei
COPY --chmod=755 dcs-settings.sh /usr/local/bin/dcs-settings
COPY --chmod=755 dcs-verify.sh /usr/local/bin/dcs-verify
COPY --chmod=755 dcs-check-forwarding.sh /usr/local/bin/dcs-check-forwarding
COPY --chmod=755 dcs-github.sh /usr/local/bin/dcs-github
RUN visudo -cf /etc/sudoers.d/dcs-firewall

ENV CLAUDE_CONFIG_DIR=/home/dev/.claude
# dev が書けるフォルダ（Claude Code・uv・Rust の置き場所）は、システムのフォルダの後ろに置く。前に置くと、
# Claude が ~/.local/bin に sudo や dcs-verify と同じ名前のものを置いて、ファイアウォールや検証を差し替えられる
ENV PATH=$PATH:/home/dev/.local/bin:/home/dev/.cargo/bin
# 日本語の表示と入力のため（ベースのイメージには LANG が無い）
ENV LANG=C.UTF-8

# ---- 道具の部分（dev として入れる） ----

USER dev
# Claude Code（ネイティブのインストーラー。~/.local/bin/claude。V6）
RUN curl -fsSL https://claude.ai/install.sh | bash \
    && claude --version
# uv（~/.local/bin に入る。~/.bashrc などは書き換えさせない）
RUN curl --proto '=https' --tlsv1.2 -LsSf https://astral.sh/uv/install.sh | env UV_NO_MODIFY_PATH=1 sh \
    && uv --version
# Rust（rustup。~/.cargo と ~/.rustup に入る。リンクに使う C コンパイラーは build-essential）
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --no-modify-path --profile default --default-toolchain stable \
    && rustc --version

# カスタマイズ（README の「カスタマイズ」）: ここに足してよい。コンテナのユーザー（dev）として道具を入れる RUN の行
# （sudo は使えません）。イメージを作るときの通信は、コンテナのファイアウォールの対象外です（コンテナの中で使うときの
# 通信は対象なので、必要なら allowed_domains に足してください）。
# ENV で PATH・LD_PRELOAD などを変えないでください（Claude が書けるフォルダが PATH の前に来ると、守りが外れます。
# 検証では見つけられません）。入れた道具を PATH に通すときは、~/.local/bin にリンクを置いてください（RUN ln -s …）。

# 開発環境の作業フォルダは /workspaces/<リポジトリ名>（D49。注文書がつなぐ）
WORKDIR /workspaces
