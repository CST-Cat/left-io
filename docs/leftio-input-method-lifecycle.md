# LeftIO Input Method Lifecycle

This document defines the intended local install flow for LeftIO.

## Principles

- Prefer user-level development installs at `~/Library/Input Methods/LeftIO.app`.
- Use TIS APIs for registration and enablement.
- Do not write `com.apple.HIToolbox` or `com.apple.inputsources` directly.
- Do not switch the current input source during install.
- Stage, signature-check, and atomically activate a new bundle; retain the old
  bundle until TIS verification succeeds.
- Treat log out / log in as the stable cache refresh boundary for first installs and stale input source lists.
- Keep system-level `/Library/Input Methods` installs explicit and release-style.
- Write logs only below `~/Library/Application Support/LeftIO`; keep per-key
  event logging opt-in because it can contain typed characters.

## Build

```sh
make build-vendored-librime
make build-input-method
```

The default build is universal (`arm64` and `x86_64`), targets macOS 13, and
requires the exact librime revision pinned in `build_vendored_librime.sh`.
Network bootstrap is opt-in; the build never installs an unpinned Python
package. A fallback-only developer build must be requested explicitly with
`LEFTIO_ALLOW_LEXICON_ONLY=1`.

The built app is:

```text
.build/input-method/LeftIO.app
```

## DMG

```sh
make build-dmg
```

The DMG contains `LeftIO.app`, `Install LeftIO.command`, a short `README.txt`,
the project license, third-party notices, and dependency license texts. It
intentionally does not include an `/Applications` shortcut: opening the app
from the image runs the same user-level install transaction.

Public releases use `make build-release-dmg` with an explicit Developer ID
Application identity, three-component release version, monotonically increasing
build number, and `notarytool` keychain profile. That target notarizes, checks
the accepted submission log for remaining issues, staples, mounts, and
Gatekeeper-checks the result. A development DMG is not reported as notarized.

## User-Level Install

```sh
make install-input-method
```

The script:

1. Stops old LeftIO processes.
2. Copies the built app to a transaction path outside `Input Methods`.
3. Clears removable download metadata and verifies the staged code signature.
4. Moves the previous bundle to a backup and transactionally activates the staged app.
5. Runs the installed app synchronously with `--register-installed-input-source`.
6. Clears any quarantine or `macl` metadata that macOS attached while starting
   that signed helper, then performs the final strict verification.
7. Verifies the parent and mode sources are unique, enabled, and mode-select-capable.
8. Deletes the backup only after verification; otherwise restores it and re-registers the previous bundle.

`com.apple.quarantine` and `com.apple.macl` are hard failures. Current macOS releases may retain the
protected `com.apple.provenance` attribute even when `xattr` reports successful
removal, so provenance is reported as a warning rather than used as a false
success/failure signal.

The CLI installer, the DMG self-install flow, and the system-level installer all
repeat that normalization after the signed registration helper exits, because
macOS can attach `macl` while launching the otherwise-clean staged bundle.

If `/Library/Input Methods/LeftIO.app` already exists, the user installer stops
instead of creating a second physical bundle with the same TIS identifiers.
Remove or update the system copy first.

The helper only calls:

```text
TISRegisterInputSource
TISEnableInputSource
```

It does not call `TISSelectInputSource`.

After installing, add `LeftIO 单手九宫格` manually in System Settings. If it does not appear, log out of macOS and log back in.

## System-Level Install

```sh
make install-input-method-system
```

This installs to:

```text
/Library/Input Methods/LeftIO.app
```

Use this only when testing a release-style path. If GUI authorization is not visible from the current automation session, run:

```sh
LEFTIO_INSTALL_WITH_SUDO=1 make install-input-method-system
```

The existing user bundle is not moved until administrator authorization and the
staged system copy have succeeded. Registration or verification failure restores
the previous user and system state.

## Verify

```sh
make verify-input-method
```

Verification checks:

- Installed bundle path.
- Core `Info.plist` IMK fields.
- Code signature validity.
- Quarantine or `macl` (hard failure) and protected provenance (warning) metadata.
- Exactly one TIS parent and mode source.
- Parent/mode enabled state and mode select capability.

The selected input source is reported but is not required to be LeftIO.

## Uninstall

```sh
make uninstall-input-method
```

The script:

1. Obtains authorization and removes a requested system copy before changing
   user bundles or TIS state; authorization denial leaves them untouched.
2. Stops LeftIO processes and removes user-level app copies.
3. Disables cached LeftIO sources through TIS only after no system copy remains;
   a user-only uninstall preserves enabled sources owned by a retained system copy.

To also remove a system-level install:

```sh
LEFTIO_UNINSTALL_SYSTEM=1 make uninstall-input-method
```

If System Settings still shows LeftIO after removal, log out of macOS and log back in.
