#!/usr/bin/env bash
# common/pixi-install.sh — install the pixi binary into /usr/local/bin (all users).
# Portable: a static binary, identical on every Linux. Re-runnable (upgrades).
# Per-user environments and caches stay in each user's home.
set -euo pipefail
ADMINSYS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$ADMINSYS_ROOT/lib/common.sh"

require_root "$@"
command -v curl >/dev/null || die "curl is needed (sys base installs it)"

case "$(uname -m)" in
  x86_64)        ARCH=x86_64 ;;
  aarch64|arm64) ARCH=aarch64 ;;
  *) die "unsupported CPU: $(uname -m)" ;;
esac
NAME="pixi-${ARCH}-unknown-linux-musl.tar.gz"
URL="https://github.com/prefix-dev/pixi/releases/latest/download/${NAME}"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
info "Downloading $NAME"
curl -fsSL "$URL" -o "$TMP/$NAME" || die "download failed: $URL"

# Verify the checksum when the release publishes one; say so when it does not.
if curl -fsSL "${URL}.sha256" -o "$TMP/$NAME.sha256" 2>/dev/null; then
  expected="$(awk '{print $1}' "$TMP/$NAME.sha256")"
  actual="$(sha256sum "$TMP/$NAME" | awk '{print $1}')"
  [[ "$expected" == "$actual" ]] || die "checksum mismatch — refusing to install"
  ok "sha256 verified"
else
  warn "no .sha256 published for this release: binary not verified"
fi

tar -xzf "$TMP/$NAME" -C "$TMP"
install -m 0755 "$TMP/pixi" /usr/local/bin/pixi
ok "pixi $(/usr/local/bin/pixi --version)"

cat > /etc/profile.d/pixi.sh <<'EOF'
# pixi: tools installed with `pixi global` land in ~/.pixi/bin
export PATH="$HOME/.pixi/bin:$PATH"
if [ -n "${BASH_VERSION:-}" ] && command -v pixi >/dev/null 2>&1; then
  eval "$(pixi completion --shell bash)"
fi
EOF
