#!/bin/sh
# devenv-device's installer (published with every release, the release key filled in):
#   curl -fsSL https://raw.githubusercontent.com/vidklopcic/devenv-artifacts/main/install.sh | sudo sh -s -- <url> <code> [--user U]
# It takes the newest release, checks release.json's signature with the release key and the build's hash against it,
# puts the build in /usr/local/bin and links this computer (devenv-device link <url> <code>): the link asks, on the
# terminal, whether the passkeys' code it prints is the one the page shows.
set -eu
BASE="https://raw.githubusercontent.com/vidklopcic/devenv-artifacts/main"
RELEASE_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBfK5mNIPSH6cOdjZdlJk0w9qz9sXGkl2B6bXCScThat devenv-device-release"
die() { echo "devenv-device install: $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || die "run it as root (… | sudo sh -s -- <url> <code>)"
[ $# -ge 2 ] || die "usage: … | sudo sh -s -- <url> <code> [--user U]   (the command Resources → Devices shows)"
case "$(uname -s)" in Linux) os=linux ;; Darwin) os=darwin ;; *) die "$(uname -s) isn't supported" ;; esac
case "$(uname -m)" in
  x86_64|amd64) arch=amd64 ;; aarch64|arm64) arch=arm64 ;; armv7*|armv8l) arch=armv7 ;; armv6*) arch=armv6 ;;
  *) die "$(uname -m) isn't supported" ;;
esac
command -v ssh-keygen >/dev/null 2>&1 || die "ssh-keygen is needed to check the release's signature (apt install openssh-client)"
command -v curl >/dev/null 2>&1 || die "curl is needed"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fetch() { curl -fsSL -H 'Cache-Control: no-cache' "$BASE/$1" -o "$tmp/$1" || die "couldn't download $1"; }
fetch release.json
fetch release.json.sig
printf 'devenv-device %s\n' "$RELEASE_KEY" > "$tmp/allowed"
ssh-keygen -Y verify -f "$tmp/allowed" -I devenv-device -n devenv-device -s "$tmp/release.json.sig" < "$tmp/release.json" >/dev/null 2>&1 \
  || die "release.json isn't signed with the release key: not installing"
name="devenv-device-$os-$arch"
want=$(sed -n "s/.*\"$name\": *\"\([0-9a-f]\{64\}\)\".*/\1/p" "$tmp/release.json")
[ -n "$want" ] || die "the release has no build for $os/$arch"
fetch "$name"
if command -v sha256sum >/dev/null 2>&1; then got=$(sha256sum "$tmp/$name" | cut -d' ' -f1); else got=$(shasum -a 256 "$tmp/$name" | cut -d' ' -f1); fi
[ "$got" = "$want" ] || die "$name isn't the build the signed release names: not installing"
mkdir -p /usr/local/bin
install -m 0755 "$tmp/$name" /usr/local/bin/devenv-device.new
mv -f /usr/local/bin/devenv-device.new /usr/local/bin/devenv-device
echo "devenv-device $(/usr/local/bin/devenv-device version) installed (signature checked)."
exec /usr/local/bin/devenv-device link "$@"   # (it asks on /dev/tty itself; --code for none)
