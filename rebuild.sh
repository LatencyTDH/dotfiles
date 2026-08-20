#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ln -sfn "$DIR" "$HOME/.dotfiles"

find_darwin_rebuild() {
  local candidate

  if command -v darwin-rebuild >/dev/null 2>&1; then
    command -v darwin-rebuild
    return 0
  fi

  for candidate in \
    /run/current-system/sw/bin/darwin-rebuild \
    /nix/var/nix/profiles/system/sw/bin/darwin-rebuild
  do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

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

DARWIN_REBUILD="$(find_darwin_rebuild || true)"
if [ -n "$DARWIN_REBUILD" ]; then
  exec sudo --set-home "$DARWIN_REBUILD" switch --flake "$HOME/.dotfiles#mac"
fi

NIX_BIN="$(find_nix || true)"
if [ -z "$NIX_BIN" ]; then
  echo "error: could not find nix or darwin-rebuild" >&2
  exit 1
fi

exec sudo --set-home "$NIX_BIN" --extra-experimental-features 'nix-command flakes' \
  run github:nix-darwin/nix-darwin/nix-darwin-26.05#darwin-rebuild -- \
  switch --flake "$HOME/.dotfiles#mac"
