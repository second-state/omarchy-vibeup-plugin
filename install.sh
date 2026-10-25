#!/usr/bin/env bash
# VibeUp plugin's vendored installer for the vibeup CLI.
#
# Hardened copy of the upstream second-state/vibeup install.sh:
#   - pinned to one reviewed release (VERSION below) — no "latest" mode
#   - the downloaded binary is verified against the pinned sha256 digest
#     before its first execution
#   - no source-build fallback
#
# When vibeup ships a new release, update VERSION and the digest table in a
# new plugin commit so the marketplace re-review covers the new digests.
set -euo pipefail

REPO="second-state/vibeup"
VERSION="v0.2.0"
INSTALL_DIR="${VIBEUP_INSTALL_DIR:-$HOME/.cargo/bin}"
NAME="vibeup"

# --- detect platform -> release asset + pinned digest (sha256) ---
OS="$(uname -s)"
ARCH="$(uname -m)"
ASSET=""
DIGEST=""
case "$OS" in
  Linux)
    case "$ARCH" in
      x86_64 | amd64)
        ASSET="vibeup-linux-x64"
        DIGEST="049f1e5dc573f4d3c5229c8f5f9ea33e1b0693e97aa4c9f9a621db60383448f5" ;;
      aarch64 | arm64)
        ASSET="vibeup-linux-arm64"
        DIGEST="9787992ce0d6bc06587dd08524bb81dee21ee597332a48330f64d4570bf433e5" ;;
      *)
        echo "error: unsupported Linux arch: $ARCH (pinned prebuilts: x86_64, aarch64)" >&2
        exit 1
        ;;
    esac
    ;;
  Darwin)
    case "$ARCH" in
      arm64 | aarch64)
        ASSET="vibeup-macos-arm64"
        DIGEST="8a762535f79d13cf621c45bf70dd8f54f7d3f46cbc158ec5060a12d57dd2d297" ;;
      *)
        echo "error: unsupported macOS arch: $ARCH (pinned prebuilts: arm64 only)" >&2
        exit 1
        ;;
    esac
    ;;
  MINGW* | MSYS* | CYGWIN*)
    echo "error: Windows is not supported by install.sh — download vibeup-windows-x64.exe from:" >&2
    echo "  https://github.com/${REPO}/releases" >&2
    exit 1
    ;;
  *)
    echo "error: unsupported OS: $OS" >&2
    exit 1
    ;;
esac

URL="https://github.com/${REPO}/releases/download/${VERSION}/${ASSET}"

command -v curl >/dev/null 2>&1 || { echo "error: curl is required" >&2; exit 1; }
command -v sha256sum >/dev/null 2>&1 || { echo "error: sha256sum is required" >&2; exit 1; }

mkdir -p "$INSTALL_DIR"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

echo "Downloading $URL"
curl -fL --progress-bar -o "$TMP" "$URL"

# Verify the pinned digest BEFORE anything executes the download.
if ! printf '%s  %s\n' "$DIGEST" "$TMP" | sha256sum -c --status; then
  echo "error: sha256 mismatch for $ASSET — does not match the pinned digest:" >&2
  sha256sum "$TMP" >&2
  exit 1
fi
echo "sha256 verified"

# 版本号直接问二进制(--version 输出如 "vibeup 0.1.3")。
BINVER="$("$TMP" --version 2>/dev/null | awk '{print $2}')"
if [ -z "$BINVER" ]; then
  echo "error: could not read version from the downloaded binary" >&2
  exit 1
fi

# 带版本号命名(vibeup-0.1.3),再软链 vibeup -> 它。升级 = 下新版本 + 改软链;
# ln 原子替换,进程握住的旧 inode 不受影响。
VERSIONED="${NAME}-${BINVER}"

# 已装同一版本且软链完好 → 无事可做,提前退出(保持输出干净)。
if [ -x "$INSTALL_DIR/$VERSIONED" ] && [ "$(readlink "$INSTALL_DIR/$NAME" 2>/dev/null)" = "$INSTALL_DIR/$VERSIONED" ]; then
  echo "vibeup $BINVER is already installed at $INSTALL_DIR/$VERSIONED — nothing to do"
  exit 0
fi

mv "$TMP" "$INSTALL_DIR/$VERSIONED"
trap - EXIT
ln -sfn "$INSTALL_DIR/$VERSIONED" "$INSTALL_DIR/$NAME"

echo "Installed: $INSTALL_DIR/$VERSIONED -> $NAME ($BINVER)"

# --- 旧版本清理:扫描 vibeup-<数字>* 的历史版本文件,询问是否删除(默认 N)。
# rm 对正在运行的二进制是安全的(只是解除目录链接,进程握住的 inode 不受影响)。
OLD_FOUND=()
for old in "$INSTALL_DIR/${NAME}"-[0-9]*; do
  [ -f "$old" ] || continue
  [ "$old" = "$INSTALL_DIR/$VERSIONED" ] && continue
  OLD_FOUND+=("$old")
done
if [ ${#OLD_FOUND[@]} -gt 0 ]; then
  echo "Found old version(s):"
  for old in "${OLD_FOUND[@]}"; do echo "  $old"; done
  ans=""
  if [ -t 0 ]; then
    read -r -p "Delete them? [y/N] " ans
  elif [ -t 1 ] && [ -r /dev/tty ]; then
    printf 'Delete old version(s) listed above? [y/N] ' > /dev/tty
    read -r ans < /dev/tty
  else
    ans="n" # 非交互:默认保留
  fi
  case "$ans" in
    [yY]*)
      for old in "${OLD_FOUND[@]}"; do rm -f "$old" && echo "Removed: $old"; done
      ;;
    *) echo "kept — delete manually if no longer needed" ;;
  esac
fi

# --- PATH check: offer to append INSTALL_DIR to the shell rc file ---
case ":$PATH:" in
  *":$INSTALL_DIR:"*) ;;
  *)
    add_to_rc() {
      local line rc
      line="export PATH=\"$INSTALL_DIR:\$PATH\""
      case "${SHELL:-/bin/sh}" in
        */zsh) rc="$HOME/.zshrc" ;;
        */bash) rc="$HOME/.bashrc" ;;
        */fish)
          echo "fish detected — run this once instead: fish_add_path $INSTALL_DIR"
          return 0
          ;;
        *) rc="$HOME/.profile" ;;
      esac
      if [ -f "$rc" ] && grep -qF "$INSTALL_DIR" "$rc"; then
        echo "note: $rc already references $INSTALL_DIR — 'source $rc' or open a new shell"
        return 0
      fi
      printf '\n# added by vibeup install.sh\n%s\n' "$line" >> "$rc"
      echo "Added to $rc — run 'source $rc' or open a new shell to pick it up"
    }

    prompt="$INSTALL_DIR is not on your PATH. Add it to your shell rc file? [Y/n] "
    ans=""
    if [ -t 0 ]; then
      read -r -p "$prompt" ans
    elif [ -t 1 ] && [ -r /dev/tty ]; then
      # curl | bash: stdin is the script itself, ask on the terminal instead
      printf '%s' "$prompt" > /dev/tty
      read -r ans < /dev/tty
    else
      ans="__noask__" # non-interactive (no tty): don't touch rc files
    fi

    case "$ans" in
      __noask__) echo "note: $INSTALL_DIR is not on your PATH — add it manually" ;;
      [nN]*) echo "skipped — add $INSTALL_DIR to your PATH manually if needed" ;;
      *) add_to_rc ;;
    esac
    ;;
esac
