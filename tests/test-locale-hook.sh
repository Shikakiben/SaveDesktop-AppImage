#!/bin/sh
# Check the default-locale hook: it must force a bundled UTF-8 locale when the
# host has none (unset or C/POSIX), and never override a real user locale.
#
# Usage: sh tests/test-locale-hook.sh /path/to/00-default-locale.hook
set -eu

HOOK="${1:?usage: $0 <00-default-locale.hook>}"
[ -f "$HOOK" ] || { echo "ERROR: $HOOK not found" >&2; exit 1; }

fail() { echo "FAIL: $1" >&2; exit 1; }

# No locale at all -> LANG and LC_CTYPE must be defaulted.
out=$(env -u LANG -u LC_ALL -u LC_CTYPE sh -c '. "$1"; printf "%s|%s" "${LANG:-}" "${LC_CTYPE:-}"' sh "$HOOK")
[ "$out" = "C.UTF-8|C.UTF-8" ] || fail "no-locale case not handled (got '$out')"

# LANG=C -> must be forced to a UTF-8 locale, otherwise the app crashes.
out=$(env -u LC_ALL -u LC_CTYPE sh -c 'LANG=C; . "$1"; printf "%s|%s" "${LANG:-}" "${LC_CTYPE:-}"' sh "$HOOK")
[ "$out" = "C.UTF-8|C.UTF-8" ] || fail "LANG=C not handled (got '$out')"

# User locale -> must be preserved.
out=$(LANG=fr_FR.UTF-8 sh -c '. "$1"; printf %s "${LANG:-}"' sh "$HOOK")
[ "$out" = "fr_FR.UTF-8" ] || fail "user LANG was overridden (got '$out')"

# LC_ALL=C -> must be forced to a UTF-8 locale, otherwise the app crashes.
out=$(env -u LANG -u LC_CTYPE sh -c 'LC_ALL=C; . "$1"; printf "%s|%s" "${LC_ALL:-}" "${LANG:-}"' sh "$HOOK")
[ "$out" = "C.UTF-8|C.UTF-8" ] || fail "LC_ALL=C not handled (got '$out')"

# Real LC_ALL -> must not be touched.
out=$(env -u LANG -u LC_CTYPE sh -c 'LC_ALL=de_DE.UTF-8; . "$1"; printf "%s|%s" "${LC_ALL:-}" "${LANG:-}"' sh "$HOOK")
[ "$out" = "de_DE.UTF-8|" ] || fail "real LC_ALL was overridden (got '$out')"

echo "locale hook test: OK"
