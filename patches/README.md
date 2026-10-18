# Why this AppImage patches SaveDesktop

Without these patches the AppImage still works like the native Arch/AUR package:
saving and restoring the desktop configuration (themes, dconf, icons, fonts, ...)
works, but the Flatpak part does not — the Flatpak section is hidden, Flatpak apps
and their data are neither saved nor restored, and the periodic-saving/sync
autostart entries call `savedesktop`, which is not on the host PATH. The patches
below make those features work in the AppImage.

These are **application patches**, not workarounds for quick-sharun. They only cover
things quick-sharun/anylinux cannot change from outside: code paths the app executes
later (autostart/sync files written at runtime), native/Flatpak-sandbox assumptions
(`/app`, `~/.var/app`, `flatpak run`), and UI conditions evaluated in Python.

Upstream references are from `vikdevelop/SaveDesktop` 4.1. Every claim below was
checked against a real build (Alpine container, x86_64 AppImage).

## `0001-appimage-autostart-path.patch`

Upstream `globals.py:21` uses `run_cmd = 'savedesktop'` in native builds, and
`globals.py:45-46` builds the periodic-saving/sync commands from it. Those commands
are written into `~/.config/autostart/…` and `savedesktop-synchronization.sh` at
runtime. In an AppImage, `savedesktop` is not on the host `PATH`, so those entries
would never start. No quick-sharun feature can intercept files the app writes later,
so the patch exports `run_cmd` and makes the native value `"$APPIMAGE"` (quoted, so
paths with spaces work).

Upstream `globals.py:49` also defines `flatpak = (env['type'] == 'flatpak')`, i.e.
"am I running inside a Flatpak sandbox?", not "does the host provide the flatpak
CLI?". In a native/AppImage build the Flatpak UI is hidden even when the host has
flatpak installed. The patch adds
`flatpak_available = flatpak or shutil.which("flatpak") is not None` and uses it for
the UI section and for saving its switches (`items_dialog.py`).

## `0002-appimage-flatpak-restore.patch`

Upstream's Flatpak restore assumes the Flatpak build:

- `de_config.py` (`create_flatpak_autostart`): copies the installer with
  `cp /app/share/savedesktop/savedesktop/core/flatpaks_installer.py …`, and writes an
  autostart that calls `flatpak run io.github.vikdevelop.SaveDesktop …` plus the host
  `python3`.
- `flatpaks_installer.py:5`: workspace hardcoded to
  `~/.var/app/io.github.vikdevelop.SaveDesktop/cache/tmp/workspace`.
- `synchronization_setup.py:113`: appends the installer only `if flatpak:`.
- `items_dialog.py:150`: Flatpak section only `if flatpak and …`;
  `items_dialog.py:160-161`: reads `~/.var/app` with `path.iterdir()` without checking
  that the directory exists (a user with only system Flatpaks has no `~/.var/app`);
  `items_dialog.py:301`: saves the Flatpak switches only `if flatpak:`.

None of those paths exist in a native/AppImage build. The patch:

- copies the installer from its own package directory (`Path(__file__).parent`);
- passes the workspace through `SAVEDESKTOP_FLATPAK_WORKSPACE` (Flatpak fallback
  unchanged);
- runs the installer with the AppImage's own Python through a `python3` symlink
  (`"$CACHE/python3"` → the AppImage): `"$CACHE/python3"
  "$CACHE/workspace/flatpaks_installer.py"`. `AppRun.sh` launches
  `$APPDIR/bin/python3` because the invocation name is `python3`; this keeps
  working when an app manager installs the AppImage under another name (AM/AppMan
  use `"$PROGRAM"`, e.g. `savedesktop`, which otherwise shadows the
  `"$APPIMAGE" python3` first-argument form);
- keeps the Flatpak section visible via `flatpak_available`;
- guards `~/.var/app` with `path.exists()`;
- for `gsettings`, removes `GSETTINGS_BACKEND`/`GSETTINGS_SCHEMA_DIR` so the GNOME
  extension check talks to the host dconf/schemas. Measured: in normal mode the
  AppImage exports no `GSETTINGS_*`; in portable mode the quick-sharun hook sets
  `GSETTINGS_BACKEND=keyfile`, which would otherwise be inherited by the installer.

## Locale hook: deliberately not shipped

A locale hook would be the right fix **if** the AppImage had to start in a session
with no usable locale. Upstream `globals.py:55` runs at import time:

```python
language = locale.getlocale()[0].split("_")[0]
```

When `locale.getlocale()` returns `(None, None)` — no `LANG`/`LC_CTYPE`, or a forced
`LANG=C`/`LC_ALL=C` without Python's C-locale coercion — this raises `AttributeError`
before the window opens. A hook that sets `LANG=C.UTF-8` for unset/C/POSIX locales
would avoid that crash.

That is not the case for SaveDesktop's actual use:

- SaveDesktop is a desktop GUI application; it is started from a desktop session.
- Normal desktop distributions set `LANG` at login. Alpine's login profile also sets
  `LANG=C.UTF-8` through `/etc/profile.d/20locale.sh`.
- A display-manager session that does not source the login profile and has no locale
  configured could still hit the crash (for example Alpine LightDM; not verified
  end-to-end). That is the only plausible case, and it is too narrow to justify a
  custom hook for this application.
- The original crash was reproduced in a `podman exec sh -c` **non-login** shell,
  not in a desktop session.
- The pkgforge AnyLinux documentation and CI do not require an Alpine minimal test:
  the template CI builds and runs `quick-sharun --test` in the Arch container, with
  `LANG`/`LC_ALL` already set. Samueru-sama tests AppImages on Alpine informally, but
  that is not a documented release requirement.

Therefore no locale hook is shipped. If a user reports a real crash in a real desktop
session, add a hook that exports `LANG=C.UTF-8` only when the locale is unset/C/POSIX,
and document the session environment with the report. Users who need it can also
launch the AppImage with `LANG=C.UTF-8` or set the locale in their session.
