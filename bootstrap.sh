#!/usr/bin/env bash
# Takes a fresh Mac from nothing to a built nix-darwin config.
# Run this once. After it finishes, use ./rebuild.sh for every later change.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

find_nix() {
  if command -v nix >/dev/null 2>&1; then
    command -v nix
    return 0
  fi

  local candidate
  for candidate in \
    /nix/var/nix/profiles/default/bin/nix \
    "$HOME/.nix-profile/bin/nix"
  do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

prepare_nix_darwin_shell_files() {
  local file backup
  local preserve_bashrc=0 preserve_zshrc=0

  for file in /etc/bashrc /etc/zshrc; do
    [ -e "$file" ] || continue

    # A successful nix-darwin activation may already have installed a
    # generated file (or a symlink to one). Leave that file alone.
    if [ -L "$file" ] || grep -Fq 'DO NOT EDIT -- this file has been generated automatically.' "$file"; then
      continue
    fi

    # The upstream Nix installer prepends this exact block and saves the
    # previous macOS file alongside it. Preserve the whole file before
    # nix-darwin takes ownership of /etc/bashrc and /etc/zshrc.
    if grep -Fq '# Nix' "$file" && grep -Fq '# End Nix' "$file"; then
      backup="${file}.before-nix-darwin"
      if [ -e "$backup" ]; then
        echo "    $backup already exists; refusing to overwrite it."
        echo "    Move $file aside manually, then rerun ./bootstrap.sh."
        return 1
      fi
      case "$file" in
        /etc/bashrc) preserve_bashrc=1 ;;
        /etc/zshrc) preserve_zshrc=1 ;;
      esac
      continue
    fi

    echo "    $file contains unrecognized content; refusing to move it automatically."
    echo "    Review it, preserve it as $file.before-nix-darwin, then rerun ./bootstrap.sh."
    return 1
  done

  if [ "$preserve_bashrc" -eq 1 ]; then
    echo "    Preserving /etc/bashrc as /etc/bashrc.before-nix-darwin"
    sudo mv /etc/bashrc /etc/bashrc.before-nix-darwin
  fi
  if [ "$preserve_zshrc" -eq 1 ]; then
    echo "    Preserving /etc/zshrc as /etc/zshrc.before-nix-darwin"
    sudo mv /etc/zshrc /etc/zshrc.before-nix-darwin
  fi
}

prepare_home_manager_files() {
  local relative file backup link_target

  # The first activation can run an older system generation while the new
  # generation is being promoted. Preserve known Home Manager targets here so
  # that an older activation cannot abort before home-manager.backupFileExtension
  # from the new generation takes effect.
  for relative in \
    .zshenv \
    .zshrc \
    .config/wezterm \
    .config/nvim \
    .config/herdr \
    .config/opencode/AGENTS.md \
    .claude/settings.json \
    .claude/CLAUDE.md \
    .codex/AGENTS.md \
    .pi/agent/themes \
    .pi/agent/extensions \
    .pi/agent/models.json \
    .pi/agent/settings.json
  do
    file="$HOME/$relative"
    if [ ! -e "$file" ] && [ ! -L "$file" ]; then
      continue
    fi

    # Leave links already managed by Nix or this checkout alone. Home Manager
    # can safely replace the latter, including the broken ~/.zshrc link left
    # by an earlier manual setup.
    if [ -L "$file" ]; then
      link_target="$(readlink "$file")"
      case "$link_target" in
        /nix/store/*|"$DIR"/*|"$HOME/.dotfiles"/*)
          continue
          ;;
      esac
    fi

    backup="${file}.before-home-manager"
    if [ -e "$backup" ] || [ -L "$backup" ]; then
      echo "    $backup already exists; refusing to overwrite it."
      echo "    Move $file aside manually, then rerun ./bootstrap.sh."
      return 1
    fi

    echo "    Preserving $file as $backup"
    mv "$file" "$backup"
  done
}

echo "==> Step 1: Nix"
NIX_BIN="$(find_nix || true)"
if [ -n "$NIX_BIN" ]; then
  echo "    nix already installed, skipping"
else
  if [ "$(uname -s)" = "Darwin" ] && [ "$(uname -m)" = "x86_64" ]; then
    echo "    Determinate no longer ships an Intel macOS installer; using upstream Nix"
    curl --proto '=https' --tlsv1.2 -sSf -L https://nixos.org/nix/install \
      | sh -s -- --daemon --yes --no-channel-add
    # shellcheck disable=SC1091
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  else
    curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \
      | sh -s -- install --no-confirm
    # shellcheck disable=SC1091
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  fi
  NIX_BIN="$(find_nix)"
fi

echo "==> Step 2: symlink this repo to ~/.dotfiles"
# home.nix resolves its mkOutOfStoreSymlink paths through ~/.dotfiles, so this
# has to exist before the first switch or the build will fail to find them.
ln -sfn "$DIR" ~/.dotfiles

echo "==> Step 3: personalize the configured username"
# Do this before any sudo call: sudo resets $USER to root, so whoami has to
# run as the real interactive user first.
REAL_USER="$(whoami)"
FLAKE_USER="$(sed -nE 's/^[[:space:]]*user = "([^"]+)";.*/\1/p' "$DIR/flake.nix" | head -n1)"
if [ -z "$FLAKE_USER" ]; then
  echo "    Could not find the single \"user = \" line in flake.nix."
  echo "    Edit flake.nix yourself before continuing."
  exit 1
elif [ "$FLAKE_USER" != "$REAL_USER" ]; then
  echo "    flake.nix is configured for user \"$FLAKE_USER\", but you are \"$REAL_USER\"."
  read -r -p "    Rewrite flake.nix's \"user = \" line to \"$REAL_USER\"? [y/N] " REPLY
  if [ "$REPLY" = "y" ] || [ "$REPLY" = "Y" ]; then
    sed -i '' -E "s/^([[:space:]]*user = \")[^\"]+(\";.*)/\1${REAL_USER}\2/" "$DIR/flake.nix"
    echo "    Updated. Review the change with: git diff flake.nix"
  else
    echo "    Skipped. Edit the single \"user = \" line in flake.nix yourself before continuing."
    exit 1
  fi
else
  echo "    flake.nix already matches \"$REAL_USER\", nothing to do."
fi

echo "==> Step 4: first darwin-rebuild switch (pinned to nix-darwin-26.05)"
prepare_nix_darwin_shell_files
prepare_home_manager_files

# darwin-rebuild doesn't exist yet on a fresh machine, so run it straight
# from the flake this once. After this, rebuild.sh works normally.
# This fetches the darwin-rebuild tool from the nix-darwin-26.05 release branch,
# not the exact flake.lock revision. The system config it applies is still pinned
# by this repo's flake.lock.
# sudo resets PATH to a secure default that excludes /nix/.../bin, so a
# freshly installed `nix` would not be found under sudo even though it's
# on PATH here. Resolve the absolute path first and invoke that instead.
# "mac" is the flake host label - if you renamed it, change it in flake.nix
# and rebuild.sh too.
sudo --set-home "$NIX_BIN" --extra-experimental-features 'nix-command flakes' \
  run github:nix-darwin/nix-darwin/nix-darwin-26.05#darwin-rebuild -- \
  switch --flake ~/.dotfiles#mac
# If this still fails with "nix: command not found", open a new terminal
# (the installer adds nix to new shells' PATH) and re-run ./bootstrap.sh.

echo "==> Done. Use ./rebuild.sh for future changes."
