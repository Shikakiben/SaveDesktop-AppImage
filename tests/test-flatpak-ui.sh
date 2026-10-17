#!/bin/sh
# Check that the "Flatpak apps" section of the items dialog is built in a
# native build when the host provides the flatpak CLI.
#
# Usage: sh tests/test-flatpak-ui.sh /path/to/share/savedesktop
set -eu

PKGDIR="${1:?usage: $0 <package dir containing the savedesktop/ python package>}"
[ -d "$PKGDIR/savedesktop" ] || { echo "ERROR: $PKGDIR/savedesktop not found" >&2; exit 1; }

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
export XDG_CURRENT_DESKTOP=GNOME
export PATH="$ROOT/bin:$PATH"

xvfb-run -a "${PYTHON:-python3}" - <<'EOF'
import gettext
gettext.install("savedesktop", "/usr/share/locale")

import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")

from savedesktop.globals import flatpak_available
assert flatpak_available is True, "flatpak_available should be True with a fake flatpak"

from savedesktop.gui.items_dialog import itemsDialog
dialog = itemsDialog(None)
for name in ("switch_05", "switch_06", "switch_07"):
    assert hasattr(dialog, name), f"Flatpak UI section is missing {name}"
print("Flatpak UI test: OK")
EOF
