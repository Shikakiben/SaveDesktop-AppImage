#!/bin/sh
# Test the SaveDesktop Flatpak restore script without a real Flatpak install.
#
# It uses a fake `flatpak` and a fake `gsettings` and checks that the script
# installs missing apps, removes extra ones, cleans stale data, talks to the
# host gsettings (clean env) and removes its autostart entry.
#
# Usage: sh tests/test-flatpak-installer.sh /path/to/flatpaks_installer.py
set -eu

INSTALLER="${1:?usage: $0 <flatpaks_installer.py>}"
[ -f "$INSTALLER" ] || { echo "ERROR: $INSTALLER not found" >&2; exit 1; }

PYTHON="${PYTHON:-python3}"
ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

HOME_DIR="$ROOT/home"
WORKSPACE="$ROOT/workspace"
BIN="$ROOT/bin"
LOG="$ROOT/calls.log"
mkdir -p "$HOME_DIR/.config/autostart" "$HOME_DIR/.local/share/flatpak/app" \
         "$HOME_DIR/.var/app/org.test.Extra" "$WORKSPACE/Flatpak_Apps" "$BIN"

# Fake flatpak: just log the calls.
cat > "$BIN/flatpak" <<'EOF'
#!/bin/sh
echo "flatpak $*" >> "$FAKE_FLATPAK_LOG"
exit 0
EOF

# Fake gsettings: log the call and the GSettings environment.
cat > "$BIN/gsettings" <<'EOF'
#!/bin/sh
echo "gsettings $* (BACKEND=${GSETTINGS_BACKEND:-unset} SCHEMA_DIR=${GSETTINGS_SCHEMA_DIR:-unset})" >> "$FAKE_FLATPAK_LOG"
if [ "$1" = "get" ]; then echo "true"; fi
exit 0
EOF
chmod +x "$BIN/flatpak" "$BIN/gsettings"

# Workspace contents, as extracted from a backup.
echo 'flatpak install --system org.test.New -y' > "$WORKSPACE/Flatpak_Apps/installed_flatpaks.sh"
echo 'flatpak install --user org.test.User -y' > "$WORKSPACE/Flatpak_Apps/installed_user_flatpaks.sh"
cat > "$WORKSPACE/flatpak-prefs.json" <<'EOF'
{"keep-flatpaks": false, "disabled-flatpaks": [], "install-flatpaks": true, "copy-data": false}
EOF

# One extra user app already installed, with stale data.
mkdir -p "$HOME_DIR/.local/share/flatpak/app/org.test.Extra"

# Pre-existing autostart entry: the script must remove it when done.
: > "$HOME_DIR/.config/autostart/io.github.vikdevelop.SaveDesktop.Flatpak.desktop"

HOME="$HOME_DIR" \
PATH="$BIN:$PATH" \
XDG_CURRENT_DESKTOP=GNOME \
FAKE_FLATPAK_LOG="$LOG" \
SAVEDESKTOP_FLATPAK_WORKSPACE="$WORKSPACE" \
GSETTINGS_BACKEND=keyfile \
GSETTINGS_SCHEMA_DIR="$ROOT/fake-schemas" \
"$PYTHON" "$INSTALLER" > "$ROOT/output.log" 2>&1

fail() {
	echo "FAIL: $1" >&2
	echo "--- fake calls ---" >&2
	cat "$LOG" >&2
	echo "--- installer output ---" >&2
	cat "$ROOT/output.log" >&2
	exit 1
}

grep -Fq 'flatpak install --system flathub org.test.New -y' "$LOG" || fail "system app not installed"
grep -Fq 'flatpak install --user flathub org.test.User -y' "$LOG" || fail "user app not installed"
grep -Fq 'flatpak uninstall --user org.test.Extra --delete-data -y' "$LOG" || fail "extra app not removed"
grep -Fq 'gsettings get org.gnome.shell disable-user-extensions (BACKEND=unset SCHEMA_DIR=unset)' "$LOG" || fail "gsettings did not use a clean host environment"
grep -Fq 'gsettings set org.gnome.shell disable-user-extensions false' "$LOG" || fail "gsettings set not called"
[ ! -e "$HOME_DIR/.config/autostart/io.github.vikdevelop.SaveDesktop.Flatpak.desktop" ] || fail "autostart file not removed"
[ ! -d "$HOME_DIR/.var/app/org.test.Extra" ] || fail "stale Flatpak data not removed"

echo "Flatpak installer test: OK"
