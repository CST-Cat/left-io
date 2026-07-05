# LeftIO Input Method Lifecycle

This document defines the intended local install flow for LeftIO.

## Principles

- Prefer user-level development installs at `~/Library/Input Methods/LeftIO.app`.
- Use TIS APIs for registration and enablement.
- Do not write `com.apple.HIToolbox` or `com.apple.inputsources` directly.
- Do not switch the current input source during install.
- Treat log out / log in as the stable cache refresh boundary for first installs and stale input source lists.
- Keep system-level `/Library/Input Methods` installs explicit and release-style.

## Build

```sh
make build-input-method
```

The built app is:

```text
.build/input-method/LeftIO.app
```

## User-Level Install

```sh
make install-input-method
```

The script:

1. Stops old LeftIO processes.
2. Removes old user-level LeftIO app copies.
3. Copies the built app to `~/Library/Input Methods/LeftIO.app`.
4. Removes quarantine/provenance extended attributes from the copied app.
5. Runs the installed app with `--register-installed-input-source`.

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

## Verify

```sh
make verify-input-method
```

Verification checks:

- Installed bundle path.
- Core `Info.plist` IMK fields.
- Code signature validity.
- Quarantine/provenance extended attributes.
- TIS visibility for the LeftIO bundle and input mode.

The selected input source is reported but is not required to be LeftIO.

## Uninstall

```sh
make uninstall-input-method
```

The script:

1. Disables LeftIO input sources through TIS when visible.
2. Stops LeftIO processes.
3. Removes user-level app copies.

To also remove a system-level install:

```sh
LEFTIO_UNINSTALL_SYSTEM=1 make uninstall-input-method
```

If System Settings still shows LeftIO after removal, log out of macOS and log back in.
