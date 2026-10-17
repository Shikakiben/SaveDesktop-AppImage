#!/bin/sh
# Check that the Flatpak feature detection works in a native build:
# flatpak_available must be False without the flatpak CLI and True with it.
#
# Usage: sh tests/test-flatpak-detection.sh /path/to/share/savedesktop
set -eu

PKGDIR="${1:?usage: $0 <package dir containing the savedesktop/ python package>}"
[ -d "$PKGDIR/savedesktop" ] || { echo "ERROR: $PKGDIR/savedesktop not found" >&2; exit 1; }

if [ -e /.flatpak-info ]; then
	echo "Flatpak detection test: SKIP (running inside a Flatpak sandbox)"
	exit 0
fi

PYTHON="${PYTHON:-python3}"
PYTHON_BIN=$(command -v "$PYTHON")
ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

mkdir -p "$ROOT/bin"
cat > "$ROOT/bin/flatpak" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$ROOT/bin/flatpak"

export PYTHONPATH="$PKGDIR"
export GSETTINGS_BACKEND=keyfile

# No flatpak in PATH, no Flatpak sandbox -> feature must stay hidden.
PATH=/nonexistent "$PYTHON_BIN" -c \
	'import savedesktop.globals as g; assert g.flatpak_available is False, "flatpak_available must be False without flatpak"'

# Host flatpak CLI available -> feature must be exposed.
PATH="$ROOT/bin:$PATH" "$PYTHON_BIN" -c \
	'import savedesktop.globals as g; assert g.flatpak_available is True, "flatpak_available must be True with flatpak"'

echo "Flatpak detection test: OK"
