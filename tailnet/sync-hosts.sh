#!/bin/sh
# Run on the viewing Mac (the one whose Whiteboard Desktop shows the boards).
# Puts this Desktop's exact Whiteboard version on each host and lists the
# hosts in Desktop's settings. Run it again after Desktop updates itself:
# Desktop only attaches hosts that run its own version.
#
#   tailnet/sync-hosts.sh mac cachy zephyr   # these hosts
#   tailnet/sync-hosts.sh                    # the hosts already in settings
#
# Hosts are SSH aliases from ~/.ssh/config (tailnet names). macOS hosts get
# a copy of this Mac's signed Whiteboard.app plus tailnet/whiteboard-macos-host
# as ~/.local/bin/whiteboard. Linux hosts get the remote server tarball that
# this Desktop pins in its product.json, checked against its sha256, using the
# install.sh bundled in the app. Nothing is downloaded from anywhere else and
# nothing listens on the network: Desktop reaches each host over SSH.
set -eu

APP="${WHITEBOARD_APP:-/Applications/Whiteboard.app}"
HERE=$(cd "$(dirname "$0")" && pwd)
SETTINGS="$HOME/Library/Application Support/Whiteboard/User/settings.json"
PRODUCT="$APP/Contents/Resources/app/product.json"
INSTALL_SH="$APP/Contents/Resources/app/review-runtime/remote/install.sh"
SSH="ssh -o BatchMode=yes -o ConnectTimeout=10"

[ -d "$APP" ] || { echo "No Whiteboard at $APP." >&2; exit 1; }
[ -f "$INSTALL_SH" ] || { echo "No bundled install.sh in $APP." >&2; exit 1; }

pin() { # pin <linux-x64|linux-arm64> <version|url|sha256>
	/usr/bin/python3 -c 'import json,sys
p=json.load(open(sys.argv[1]))["whiteboardRemote"]
print(p["version"] if sys.argv[3]=="version" else p[sys.argv[2]][sys.argv[3]])' "$PRODUCT" "$1" "$2"
}

if [ $# -eq 0 ]; then
	set -- $(/usr/bin/python3 -c 'import json,sys
try: print(" ".join(json.load(open(sys.argv[1])).get("review.remote.hosts", [])))
except FileNotFoundError: pass' "$SETTINGS")
fi
[ $# -gt 0 ] || { echo "usage: $0 <ssh-alias>..." >&2; exit 2; }

for alias in "$@"; do
	os=$($SSH "$alias" uname -s) || { echo "$alias: ssh failed" >&2; continue; }
	case "$os" in
	Darwin)
		echo "$alias: macOS, copying $APP"
		# The host's server runs out of the bundle being replaced.
		$SSH "$alias" '[ -x ~/.local/bin/whiteboard ] && ~/.local/bin/whiteboard server stop >/dev/null 2>&1; true'
		rsync -a --delete "$APP" "$alias:/Applications/"
		$SSH "$alias" 'mkdir -p ~/.local/bin'
		scp -q "$HERE/whiteboard-macos-host" "$alias:.local/bin/whiteboard"
		$SSH "$alias" 'chmod 755 ~/.local/bin/whiteboard && ~/.local/bin/whiteboard --version'
		;;
	Linux)
		case "$($SSH "$alias" uname -m)" in
		x86_64) target=linux-x64 ;;
		aarch64) target=linux-arm64 ;;
		*) echo "$alias: unsupported CPU" >&2; continue ;;
		esac
		version=$(pin "$target" version)
		echo "$alias: Linux $target, installing Whiteboard remote $version"
		$SSH "$alias" sh -s -- install --version "$version" \
			--sha256 "$(pin "$target" sha256)" --url "$(pin "$target" url)" <"$INSTALL_SH" | tail -n 1
		;;
	*) echo "$alias: $os is not supported" >&2 ;;
	esac
done

# Desktop's probe refuses macOS hosts and would offer to install over a
# Linux one, so it must use the Whiteboard each host already has.
/usr/bin/python3 - "$SETTINGS" "$@" <<'EOF'
import json, os, sys
path, aliases = sys.argv[1], sys.argv[2:]
try:
    settings = json.load(open(path))
except FileNotFoundError:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    settings = {}
hosts = settings.get("review.remote.hosts", [])
settings["review.remote.hosts"] = hosts + [a for a in aliases if a not in hosts]
settings["review.remote.install"] = "never"
json.dump(settings, open(path, "w"), indent=4)
print("hosts in Desktop settings:", ", ".join(settings["review.remote.hosts"]))
EOF
