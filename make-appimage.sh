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

# The launcher hardcodes pkgdatadir=/usr/share/savedesktop and
# localedir=/usr/share/locale, with no env var to relocate them, so both must
# go through pathmap.
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
DEPLOY_GTK=1 GTK_DIR=gtk-4.0 quick-sharun \
  /usr/bin/savedesktop \
  /usr/share/savedesktop \
  /usr/bin/notify-send \
  /usr/lib/7zip/* \
  /usr/lib/libadwaita-1.so*

# Patch 0001 makes the autostart/sync commands work in an AppImage: upstream
# only knows 'savedesktop' (native) and 'flatpak run …' (Flatpak), and
# 'savedesktop' is not on the host PATH. It exposes run_cmd, uses $APPIMAGE in
# native builds, and adds flatpak_available for the Flatpak UI when the host
# has the flatpak CLI.
patch -p1 -d ./AppDir/share/savedesktop < ./patches/0001-appimage-autostart-path.patch
grep -q 'run_cmd.*APPIMAGE' ./AppDir/share/savedesktop/savedesktop/globals.py
grep -q "'run_cmd'" ./AppDir/share/savedesktop/savedesktop/globals.py
grep -q 'flatpak_available' ./AppDir/share/savedesktop/savedesktop/globals.py

# Patch 0002 makes the Flatpak restore work in a native build too: the
# installer is copied from the package instead of /app, the workspace path is
# passed explicitly, the autostart/sync run it with the AppImage's own Python
# through a "python3" symlink to the AppImage (works even when app managers
# install it under another name, e.g. AM/AppMan's "savedesktop"), gsettings
# talks to the host, and the Flatpak UI section is shown when the host has the
# flatpak CLI.
patch -p1 -d ./AppDir/share/savedesktop < ./patches/0002-appimage-flatpak-restore.patch
grep -q 'SAVEDESKTOP_FLATPAK_WORKSPACE' ./AppDir/share/savedesktop/savedesktop/core/flatpaks_installer.py
grep -q 'flatpak_available' ./AppDir/share/savedesktop/savedesktop/gui/items_dialog.py

# Test the patches (Python syntax) before building.
for _py in globals.py core/de_config.py core/flatpaks_installer.py core/synchronization_setup.py gui/items_dialog.py; do
  python3 -c 'import ast, sys; ast.parse(open(sys.argv[1]).read())' "./AppDir/share/savedesktop/savedesktop/$_py"
done

# Turn AppDir into AppImage
quick-sharun --make-appimage

# Test the app for 12 seconds; if it fails due to the app having issues running
# in the CI, use --simple-test instead
quick-sharun --test ./dist/*.AppImage
