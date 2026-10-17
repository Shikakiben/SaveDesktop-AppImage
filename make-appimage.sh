#!/bin/sh

set -eu

ARCH=$(uname -m)
VERSION=$(pacman -Q savedesktop | awk '{print $2; exit}')
export ARCH VERSION
export OUTPATH=./dist
export ADD_HOOKS="self-updater.hook"
export UPINFO="gh-releases-zsync|${GITHUB_REPOSITORY%/*}|${GITHUB_REPOSITORY#*/}|latest|*$ARCH.AppImage.zsync"
export ICON=/usr/share/icons/hicolor/scalable/apps/io.github.vikdevelop.SaveDesktop.svg
export DESKTOP=/usr/share/applications/io.github.vikdevelop.SaveDesktop.desktop
export STARTUPWMCLASS=io.github.vikdevelop.SaveDesktop
export DEPLOY_PYTHON=1

# The locale hook ships in the repo (AppDir/bin) and is sourced by AppRun.sh
# before the app starts; quick-sharun keeps it in place.
[ -f ./AppDir/bin/00-default-locale.hook ] || {
  echo "ERROR: AppDir/bin/00-default-locale.hook is missing" >&2
  exit 1
}

# The launcher hardcodes pkgdatadir=/usr/share/savedesktop and
# localedir=/usr/share/locale, with no env var to relocate them, so both must
# go through pathmap.
# ${SHARUN_DIR} must NOT be escaped: single quotes keep it literal, and a
# backslash ends up verbatim in .env, which breaks pathmap
# (see MEMO-AppImage §11.11 and the Pitivi §11.15 story).
export PATH_MAPPING='
  /usr/share/savedesktop:${SHARUN_DIR}/share/savedesktop
  /usr/share/locale:${SHARUN_DIR}/share/locale
'

# /usr/share/savedesktop holds the Python package (savedesktop/) AND the
# compiled GResource. Neither is an ELF dependency, so quick-sharun cannot see
# them via ldd: the directory must be passed explicitly, otherwise the app dies
# with ModuleNotFoundError / "GResource not found".
# libadwaita is dlopened through the Adw typelib, also invisible to ldd.
# notify-send is called by the app for its notifications.
#
# 7z: official pkgforge pattern (Protontricks, Varia, RVGL, wine) passes
# /usr/lib/7zip/7z* to quick-sharun. But the full 7z binary resolves 7z.so from
# the directory of argv[0]; once quick-sharun splits it into shared/bin/7z and
# lib/7z.so, compression fails with "Codec Load Error". Arch's /usr/bin/7z is
# itself only a 2-line wrapper doing `exec /usr/lib/7zip/7z "$@"` for exactly
# that reason. Use the standalone 7za (all codecs embedded, no 7z.so) and give
# it the same kind of launcher below.
DEPLOY_GTK=1 GTK_DIR=gtk-4.0 quick-sharun \
  /usr/bin/savedesktop \
  /usr/share/savedesktop \
  /usr/bin/notify-send \
  /usr/lib/7zip/7za \
  /usr/lib/libadwaita-1.so*

# Upstream only knows two run commands: 'savedesktop' (native) and
# 'flatpak run …' (Flatpak). In an AppImage 'savedesktop' is not on the host
# PATH, so the autostart/sync entries written by the app would never start.
# Patch 0001 exposes run_cmd and makes the native one use $APPIMAGE.
patch -p1 -d ./AppDir/share/savedesktop < ./patches/0001-appimage-autostart-path.patch
grep -q 'run_cmd.*APPIMAGE' ./AppDir/share/savedesktop/savedesktop/globals.py
grep -q "'run_cmd'" ./AppDir/share/savedesktop/savedesktop/globals.py
grep -q 'flatpak_available' ./AppDir/share/savedesktop/savedesktop/globals.py

# Patch 0002 makes the Flatpak restore work in a native build too: the
# installer is copied from the package instead of /app, the workspace path is
# passed explicitly, the autostart uses run_cmd, gsettings talks to the host,
# and the Flatpak UI section is shown when the host has the flatpak CLI.
# See patches/0002-appimage-flatpak-restore.patch.
patch -p1 -d ./AppDir/share/savedesktop < ./patches/0002-appimage-flatpak-restore.patch
grep -q 'SAVEDESKTOP_FLATPAK_WORKSPACE' ./AppDir/share/savedesktop/savedesktop/core/flatpaks_installer.py
grep -q 'flatpak_available' ./AppDir/share/savedesktop/savedesktop/gui/items_dialog.py

# Patch 0003 adds --run-flatpak-installer to the launcher so the Flatpak
# restore uses the bundled Python instead of the host's python3.
patch -p1 -d ./AppDir < ./patches/0003-appimage-run-flatpak-installer.patch
grep -q 'run-flatpak-installer' ./AppDir/bin/savedesktop

# All patched files must stay valid Python.
for _py in globals.py core/de_config.py core/flatpaks_installer.py core/synchronization_setup.py gui/items_dialog.py; do
  python3 -c 'import ast, sys; ast.parse(open(sys.argv[1]).read())' "./AppDir/share/savedesktop/savedesktop/$_py"
done
python3 -c 'import ast; ast.parse(open("./AppDir/bin/savedesktop").read())'

# SaveDesktop always invokes "7z"; expose the bundled standalone 7za under
# that name (same approach as the Arch package's /usr/bin/7z wrapper).
cat > ./AppDir/bin/7z <<'EOF'
#!/bin/sh
APPDIR="${APPDIR:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"
exec "$APPDIR/bin/7za" "$@"
EOF
chmod +x ./AppDir/bin/7z

# Smoke-test the launcher and the codec: the app uses 7z for every archive.
_7z_tmp=$(mktemp -d)
echo test > "$_7z_tmp/file"
./AppDir/bin/7z a "$_7z_tmp/test.zip" "$_7z_tmp/file" > /dev/null
./AppDir/bin/7z l "$_7z_tmp/test.zip" > /dev/null
rm -rf "$_7z_tmp"


# Turn AppDir into AppImage
quick-sharun --make-appimage

# Test the app for 12 seconds; if it fails due to the app having issues running
# in the CI, use --simple-test instead
quick-sharun --test ./dist/*.AppImage
