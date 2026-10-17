#!/bin/sh

set -eu

ARCH=$(uname -m)

# The AUR package pulls the real dependencies (gtk4, libadwaita,
# python-gobject, 7zip, dconf, gvfs, ...). Build and install it FIRST:
# makepkg runs pacman -S for its dependencies, so running get-debloated-pkgs
# before it would just reinstall the full packages over the debloated ones.
make-aur-package savedesktop

echo "Installing debloated packages..."
echo "---------------------------------------------------------------"
get-debloated-pkgs --add-common --prefer-nano
