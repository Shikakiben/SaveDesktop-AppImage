# Why this hook exists

`00-default-locale.hook` is sourced by `AppRun.sh` before the app starts.

Upstream `savedesktop/globals.py:55` runs at import time:

```python
language = locale.getlocale()[0].split("_")[0]
```

With no `LANG`, or `LANG=C`/`LC_ALL=C`, Python's `locale.getlocale()` returns
`(None, None)` and the app dies with:

```
AttributeError: 'NoneType' object has no attribute 'split'
```

quick-sharun bundles locale data (`C.utf8`, `en_US.UTF-8` — `quick-sharun.sh` around
the `localedef`/`_try_cp /usr/lib/locale/C.utf8` lines) but does **not** choose a
default locale: forcing `LANG`/`LC_ALL` for every launch would override the user's
language. `anylinux.so` only repairs *broken* locales; its `init_locale()` returns
early when `setlocale(LC_ALL, "")` succeeds, and with no `LANG` or `LANG=C` it
succeeds as `"C"` (`lib/anylinux.c`). Setting a default locale is therefore an
application policy decision, and the official extension point is a custom hook
(see also `.env`; we use a hook because it can be conditional).

The hook sets `C.UTF-8` **only** when the locale is unset/`C`/`POSIX`, so a real
user locale (`fr_FR.UTF-8`, …) is preserved.

Verified A/B on Alpine against the AppImage (same AppDir, only the hook differs):

| Case | Without hook | With hook |
|---|---|---|
| no `LANG`/`LC_ALL` | crash (`globals.py`) | starts |
| `LANG=C` | crash | starts |
| `LC_ALL=C` | crash | starts |
| `LANG=C.UTF-8` | starts (control) | starts |
