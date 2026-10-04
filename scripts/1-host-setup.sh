#!/usr/bin/env bash
# Step 1 (inside WSL Ubuntu 24.04): build dependencies, repo, git identity, ccache.
set -euo pipefail

sudo apt-get update
sudo apt-get install -y \
    bc bison build-essential ccache curl flex g++-multilib gcc-multilib git git-lfs \
    gnupg gperf imagemagick lib32readline-dev lib32z1-dev libdw-dev libelf-dev \
    libgnutls28-dev libsdl1.2-dev libssl-dev libxml2 libxml2-utils lz4 lzop \
    pngcrush protobuf-compiler python3-protobuf python-is-python3 rsync schedtool \
    squashfs-tools xsltproc zip zlib1g-dev android-sdk-libsparse-utils

git lfs install

# repo launcher
mkdir -p ~/bin
curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o ~/bin/repo
chmod a+x ~/bin/repo
grep -q 'HOME/bin' ~/.profile || echo 'export PATH="$HOME/bin:$PATH"' >> ~/.profile

# ccache is opt-in per build (CCACHE=1 3-build.sh); it lives in ~/.ccache
mkdir -p ~/.ccache
CCACHE_DIR=~/.ccache ccache -M 30G

# repo refuses to run without a git identity
if ! git config --global user.email >/dev/null; then
    read -rp "git name for commits: " n;  git config --global user.name  "$n"
    read -rp "git email for commits: " e; git config --global user.email "$e"
fi
git config --global color.ui false

echo "Host ready. Next: ~/gvwifi-los23/scripts/2-sync.sh"
