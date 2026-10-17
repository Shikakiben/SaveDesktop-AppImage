#!/bin/sh
# Test create_flatpak_autostart() end-to-end without a real Flatpak install:
# it must copy the installer, write the prefs, create a launcher that calls
# $APPIMAGE, run that launcher (fake AppImage + fake flatpak/gsettings) and
# clean up the autostart entry and the launcher.
#
# Usage: sh tests/test-flatpak-autostart.sh /path/to/share/savedesktop
set -eu

PKGDIR="${1:?usage: $0 <package dir containing the savedesktop/ python package>}"
[ -d "$PKGDIR/savedesktop" ] || { echo "ERROR: $PKGDIR/savedesktop not found" >&2; exit 1; }

PYTHON="${PYTHON:-python3}"
ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

export HOME="$ROOT/home"
export XDG_CACHE_HOME="$ROOT/cache"
export XDG_DATA_HOME="$ROOT/data"
mkdir -p "$HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME"

FAKE_APPIMAGE="$ROOT/fake.AppImage"
FAKE_APPIMAGE_LOG="$ROOT/fake-appimage.log"
cat > "$FAKE_APPIMAGE" <<EOF
#!/bin/sh
echo "fake AppImage \$*" >> "$FAKE_APPIMAGE_LOG"
if [ "\$1" = "--run-flatpak-installer" ]; then
    exec python3 -u "\$SAVEDESKTOP_FLATPAK_WORKSPACE/flatpaks_installer.py"
fi
EOF
chmod +x "$FAKE_APPIMAGE"

export APPIMAGE="$FAKE_APPIMAGE"
export GSETTINGS_BACKEND=keyfile
export XDG_CURRENT_DESKTOP=GNOME
export PYTHONPATH="$PKGDIR"

"$PYTHON" -c 'from savedesktop.core import de_config; de_config.create_flatpak_autostart()'

DATA="$XDG_DATA_HOME/io.github.vikdevelop.SaveDesktop"
CACHE="$XDG_CACHE_HOME/io.github.vikdevelop.SaveDesktop"
AUTOSTART="$HOME/.config/autostart/io.github.vikdevelop.SaveDesktop.Flatpak.desktop"
LAUNCHER="$DATA/savedesktop-flatpak-installer.sh"

[ -f "$CACHE/workspace/flatpaks_installer.py" ] || { echo "FAIL: installer not copied" >&2; exit 1; }
[ -f "$CACHE/workspace/flatpak-prefs.json" ] || { echo "FAIL: prefs not written" >&2; exit 1; }
[ -f "$LAUNCHER" ] || { echo "FAIL: launcher not written" >&2; exit 1; }
[ -f "$AUTOSTART" ] || { echo "FAIL: autostart not written" >&2; exit 1; }

grep -Fq "$FAKE_APPIMAGE" "$LAUNCHER" || { echo "FAIL: launcher does not use the AppImage path" >&2; cat "$LAUNCHER" >&2; exit 1; }
grep -Fq -- '--show-flatpaks-installer' "$LAUNCHER" || { echo "FAIL: launcher does not launch the UI" >&2; cat "$LAUNCHER" >&2; exit 1; }

# Fake flatpak/gsettings for the launcher run.
mkdir -p "$ROOT/bin"
cat > "$ROOT/bin/flatpak" <<'EOF'
#!/bin/sh
echo "flatpak $*" >> "$FAKE_FLATPAK_LOG"
exit 0
EOF
cat > "$ROOT/bin/gsettings" <<'EOF'
#!/bin/sh
echo "gsettings $*" >> "$FAKE_FLATPAK_LOG"
echo false
exit 0
EOF
chmod +x "$ROOT/bin/flatpak" "$ROOT/bin/gsettings"
export PATH="$ROOT/bin:$PATH"
export FAKE_FLATPAK_LOG="$ROOT/calls.log"
: > "$FAKE_FLATPAK_LOG"

sh "$LAUNCHER"

grep -Fq -- '--show-flatpaks-installer' "$FAKE_APPIMAGE_LOG" || { echo "FAIL: AppImage UI not launched" >&2; exit 1; }
grep -Fq -- '--run-flatpak-installer' "$FAKE_APPIMAGE_LOG" || { echo "FAIL: installer not run through the AppImage" >&2; cat "$FAKE_APPIMAGE_LOG" >&2; exit 1; }
[ ! -f "$AUTOSTART" ] || { echo "FAIL: autostart not removed" >&2; exit 1; }
[ ! -f "$LAUNCHER" ] || { echo "FAIL: launcher not removed" >&2; exit 1; }

# Second scenario: when a synchronization script already exists, the installer
# must be appended to it instead of creating a separate autostart entry.
SYNC_SCRIPT="$DATA/savedesktop-synchronization.sh"
: > "$SYNC_SCRIPT"
"$PYTHON" -c 'from savedesktop.core import de_config; de_config.create_flatpak_autostart()'
[ ! -f "$AUTOSTART" ] || { echo "FAIL: autostart created even though a sync script exists" >&2; exit 1; }
grep -Fq 'SAVEDESKTOP_FLATPAK_WORKSPACE' "$SYNC_SCRIPT" || { echo "FAIL: installer not appended to the sync script" >&2; cat "$SYNC_SCRIPT" >&2; exit 1; }
grep -Fq -- '--run-flatpak-installer' "$SYNC_SCRIPT" || { echo "FAIL: installer not appended to the sync script" >&2; cat "$SYNC_SCRIPT" >&2; exit 1; }

echo "Flatpak autostart test: OK"
