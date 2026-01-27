#!/bin/sh

set -eu

ARCH=$(uname -m)
VERSION=$(pacman -Q savedesktop | awk '{print $2; exit}') # example command to get version of application here
export ARCH VERSION
export OUTPATH=./dist
export ADD_HOOKS="self-updater.bg.hook"
export UPINFO="gh-releases-zsync|${GITHUB_REPOSITORY%/*}|${GITHUB_REPOSITORY#*/}|latest|*$ARCH.AppImage.zsync"
export ICON=/usr/share/icons/hicolor/scalable/apps/io.github.vikdevelop.SaveDesktop.svg
export DESKTOP=/usr/share/applications/io.github.vikdevelop.SaveDesktop.desktop
export DEPLOY_SYS_PYTHON=1
export DEPLOY_GTK=1
export GTK_DIR=gtk-4.0
export PATH_MAPPING='
  /usr/share/savedesktop: ${SHARUN_DIR}/share/savedesktop
  /usr/share/locale:${SHARUN_DIR}/share/locale
'
# Deploy dependencies

quick-sharun \
          /usr/bin/savedesktop
          */usr/bin/gtk4*

# Additional changes can be done in between here

# Turn AppDir into AppImage
quick-sharun --make-appimage
