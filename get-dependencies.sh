#!/bin/sh

set -eu

ARCH=$(uname -m)

echo "Installing package dependencies..."
echo "---------------------------------------------------------------"
# pacman -Syu --noconfirm PACKAGESHERE

echo "Installing debloated packages..."
echo "---------------------------------------------------------------"
get-debloated-pkgs --add-common --prefer-nano

# The AUR package provides savedesktop and pulls its runtime dependencies.
echo "Installing savedesktop from the AUR..."
echo "---------------------------------------------------------------"
make-aur-package savedesktop
