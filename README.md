# LeftIO

[![CI](https://github.com/CST-Cat/left-io/actions/workflows/ci.yml/badge.svg)](https://github.com/CST-Cat/left-io/actions/workflows/ci.yml)

LeftIO is a macOS one-hand T9-style Chinese input method experiment.

The current repository contains a testable Swift input controller core, a physical-key adapter for macOS keyboard events, an InputMethodKit host, and both a real librime-backed session bridge and a lightweight lexicon fallback session. The host prefers librime when it can be loaded at runtime and falls back to the bundled dictionary-backed session otherwise. The distributable is a direct InputMethodKit `LeftIO.app` bundle, not an embedded `.appex`; opening it from the DMG runs the self-install flow that copies the app to `~/Library/Input Methods` and registers it with TIS.

## License

LeftIO's original source code and documentation are licensed under the BSD 3-Clause License. The bundled/generated Rime dictionary data is derived from Rime `luna_pinyin` and `essay` data and is licensed under LGPL-3.0-only. See [LICENSE](LICENSE), [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), and [LICENSES/](LICENSES/).

## Keyboard Layout

```text
Q          W ABC      E DEF
tap / hold
layer control

A GHI      S JKL      D MNO

Z PQRS     X TUV      C WXYZ
```

## Implemented Core Behavior

`Q` distinguishes a tap from a 0.45-second hold:

```text
tap Q while idle               -> enter the configured tap layer (symbol by default)
hold Q for 0.45 seconds        -> toggle the configured hold layer (numeric by default)
tap Q while composing          -> insert a syllable delimiter
tap Q inside the symbol layer  -> exit the symbol layer
tap Q inside the numeric layer -> digit 1
```

The numeric layer preserves the physical nine-key grid and remains active until
another long `Q`, `Esc`, or another transient-state reset exits it:

```text
Q W E -> 1 2 3
A S D -> 4 5 6
Z X C -> 7 8 9
```

`Space` no longer starts a numeric chord. Its key-down immediately commits the
first candidate/current composition, or inserts an ordinary space while idle.

`Esc` cancels transient input state:

```text
pending Q gesture        -> cancel pending Q
inside symbol layer      -> exit symbol layer
inside numeric layer     -> exit numeric layer
composing text           -> clear current composition
idle                     -> pass through to the client
```

Auxiliary keys:

```text
R       -> delete backward
F / G   -> candidate page up / down
1-4     -> select candidates 1-4
V       -> commit composition
```

## Project Layout

```text
Sources/OneHand/
├── OneHandAction.swift
├── OneHandClientAction.swift
├── OneHandConfiguration.swift
├── OneHandConfigurationLoader.swift
├── OneHandContext.swift
├── OneHandHandleResult.swift
├── OneHandInputController.swift
├── OneHandKey.swift
├── OneHandLexicon.swift
├── OneHandLexiconSession.swift
├── NumericLayerController.swift
├── OneHandRecordingSession.swift
├── OneHandRimeBridge.swift
├── OneHandRimeDataProvider.swift
├── OneHandStateMachine.swift
├── OneHandSymbolCustomization.swift
├── OneHandT9Encoder.swift
└── SymbolLayerController.swift

Sources/OneHandKeyboard/
├── OneHandANSIKeyCode.swift
├── OneHandKeyboardModifierFlags.swift
└── OneHandPhysicalKeyMapper.swift

Sources/OneHandAppKit/
└── OneHandMacKeyMapper.swift

Sources/CRimeBridge/
├── CRimeBridge.c
└── include/CRimeBridge.h

Sources/LeftIOInputMethod/
├── LeftIOInputController.swift
├── LeftIOInputMethodApp.swift
└── SymbolLayerSettingsWindowController.swift

Sources/LeftIOLauncher/
└── LeftIOLauncher.swift

data/
├── prebuild/default.custom.yaml
├── onehand_t9_phrases.tsv
├── onehand_t9.schema.yaml
├── onehand_t9.dict.yaml
├── onehand_t9.custom.yaml
└── onehand_symbols.yaml

scripts/
├── build_dmg.sh
├── build_input_method_app.sh
├── build_release_dmg.sh
├── build_vendored_librime.sh
├── generate_onehand_t9_dict.py
├── install_input_method_app.sh
├── install_input_method_app_system.sh
├── repair_input_method_sources.sh
├── sample_pinyin.tsv
├── test_install_transactions.sh
├── test_prebuilt_rime_startup.sh
├── test_rime_abi_guard.sh
├── test_rime_trait_lifetime.sh
├── uninstall_input_method_app.sh
├── verify_distribution.sh
└── verify_input_method_install.sh

Tests/OneHandTests/
├── OneHandConfigurationLoaderTests.swift
├── OneHandDictionaryGeneratorTests.swift
├── OneHandInputControllerTests.swift
├── OneHandLexiconSessionTests.swift
├── OneHandRimeDataProviderTests.swift
├── OneHandRimeIntegrationTests.swift
├── OneHandRimeSessionTests.swift
├── OneHandStateMachineTests.swift
├── QGestureAndNumericLayerTests.swift
├── SymbolLayerTests.swift
└── T9EncoderTests.swift

Tests/OneHandKeyboardTests/
└── OneHandPhysicalKeyMapperTests.swift

Tests/LeftIOInputMethodTests/
└── InputLayerSettingsStoreTests.swift
```

`OneHandRimeSession` lives in `Sources/OneHand/OneHandRimeBridge.swift`. The app `Info.plist` and icons are generated into `.build/input-method/LeftIO.app` by `scripts/build_input_method_app.sh`; they are not checked in under `Sources/`.

## Open In Xcode

Open this package directly:

```sh
open Package.swift
```

The command-line developer directory on this machine may still point to Command Line Tools. The Makefile uses the full Xcode app locally without changing global `xcode-select`:

```sh
make build-vendored-librime
make test
make xcodebuild-test
```

`make test` runs XCTest only and disables Swift Testing discovery. The package currently uses XCTest, and this avoids a SwiftPM testing-helper code-signing issue on this macOS/Xcode setup.

`make test-rime-traits` guards the C bridge contract that caller-owned trait strings may expire immediately after bridge creation. In particular, it catches regressions where librime/glog keeps Swift `withCString` storage past its lifetime.

`make build-vendored-librime` checks out the exact librime 1.17.0 source commit recorded by the build script, initializes its pinned submodules, verifies Boost's SHA-256, and builds `arm64` plus `x86_64`. It refuses tracked modifications in the checkout. CMake must already be installed; the build does not run an unpinned `pip install`.

`make build-input-method` requires that pinned engine by default. Set `LEFTIO_AUTO_BOOTSTRAP_LIBRIME=1` to explicitly allow the build to fetch it, or `LEFTIO_ALLOW_LEXICON_ONLY=1` for a deliberate fallback-only development build. The normal app and DMG contain universal binaries and target macOS 13 or newer.

The GitHub Actions workflow builds the real pinned engine, treats Swift warnings as errors, runs both SwiftPM and Xcode tests, reproduces the production dictionary, then builds, mounts, and inspects the universal DMG.

## Local Installation

Build the experimental InputMethodKit host:

```sh
make build-input-method
```

Build a development installer image:

```sh
make build-dmg
```

The DMG is not an `/Applications` drag installer. Open `LeftIO.app` or `Install LeftIO.command` from the image; the app stages and signature-checks a clean copy in `~/Library/Input Methods`, atomically activates it, verifies TIS registration/enablement, and rolls back the previous bundle if registration fails.

For a public release, provide a Developer ID Application identity and a stored `notarytool` keychain profile:

```sh
LEFTIO_VERSION="0.1.0" \
LEFTIO_BUILD_NUMBER="1" \
LEFTIO_SIGNING_IDENTITY="Developer ID Application: Example (TEAMID)" \
LEFTIO_NOTARY_PROFILE="leftio-notary" \
make build-release-dmg
```

This path requires explicit three-component `LEFTIO_VERSION` and monotonically increasing `LEFTIO_BUILD_NUMBER` values plus universal binaries. It discards incremental dependency outputs and re-extracts Boost from the SHA-256-verified archive, signs the nested engine and app with hardened runtime, signs and notarizes the DMG, rejects an accepted submission if its notary log still contains issues, staples the ticket, mounts the result, checks bundled license notices, and runs Gatekeeper assessment. Development builds remain locally signed and are not represented as notarized releases.

For development, install the input method for the current user. This copies the app to `~/Library/Input Methods/LeftIO.app` and asks TIS to register and enable it. If LeftIO is already selected during an update, the installer temporarily selects the ASCII fallback before replacing the live endpoint, starts the new bundle, and restores LeftIO afterward. Other current input sources are left unchanged.

```sh
make install-input-method
```

After the copy finishes, log out of macOS and log back in if this is the first install or the input source list looks stale. Then open System Settings -> Keyboard -> Text Input -> `编辑...` and add `LeftIO 单手九宫格` manually.

Verify the installed bundle and TIS discovery state:

```sh
make verify-input-method
```

System-wide installation is still available for release-style testing, but it is no longer the default development flow:

```sh
make install-input-method-system
```

If the administrator authorization dialog does not appear from an automation or IDE session, run the system installer from your own terminal with a visible `sudo` password prompt:

```sh
LEFTIO_INSTALL_WITH_SUDO=1 make install-input-method-system
```

Uninstall the user-level development copy:

```sh
make uninstall-input-method
```

To also remove a system-level copy, run:

```sh
LEFTIO_UNINSTALL_SYSTEM=1 make uninstall-input-method
```

The install and uninstall scripts use TIS registration APIs and do not write `com.apple.HIToolbox`. A normal install leaves the current input source alone. The only exception is updating LeftIO while LeftIO itself is selected: the user-level installer temporarily selects an enabled ASCII fallback before stopping the old endpoint, then restores LeftIO only after the new endpoint is running. It never restores an arbitrary sampled source such as WeType or ABC. A user-only uninstall does not disable the TIS source while a system copy remains. Lifecycle logs live under `~/Library/Application Support/LeftIO`; no shared writable log path is used. Per-key event logging is disabled by default because it can contain typed characters. For an explicit debugging session, enable `LeftIOEnableInputEventLogging` in the app defaults (or launch with `LEFTIO_ENABLE_INPUT_EVENT_LOG=1`) and disable it again afterward. The installed input-method app is a direct InputMethodKit app bundle generated by `scripts/build_input_method_app.sh`; no embedded `.appex` is produced.

See [docs/leftio-input-method-lifecycle.md](docs/leftio-input-method-lifecycle.md) for the full install, registration, verification, and uninstall lifecycle.

The current host is a functional IMK shell wired to the one-hand key state machine. It reads `data/onehand_symbols.yaml`, prefers a real librime session when `librime` can be loaded at runtime, and falls back to the bundled `data/onehand_t9.dict.yaml` lexicon session when librime is unavailable. The build precompiles a complete production workspace into `Contents/Resources/Rime/build`; the first session resolves compiled resources directly from that immutable workspace, so a legacy or partially-written `user-data/build` cannot override it. Rime's user dictionary remains in the user data directory. The host also prewarms Rime (or the indexed fallback) off the first-key path. Both backends drive LeftIO's candidate panel, support paging with `F/G`, accept mouse selection and expansion, and commit candidates with `Space` or `1-4`.

## macOS Key Mapping

The keyboard adapter is split into two layers:

```text
OneHandKeyboard
-> pure Swift physical ANSI key-code mapping
-> tested without AppKit

OneHandAppKit
-> converts NSEvent keyDown/keyUp events
-> maps NSEvent.ModifierFlags into OneHandKeyboardModifierFlags
-> delegates to OneHandPhysicalKeyMapper
```

The physical mapper ignores events using `Command`, `Option`, or `Control`. `Shift` and `Caps Lock` are allowed because the one-hand layout is based on physical keys rather than typed characters.

## Session Contract

`OneHandInputController.handle(_:)` applies actions to the provided session and returns `OneHandHandleResult`:

```swift
if let event = OneHandMacKeyMapper.event(from: nsEvent) {
    let result = controller.handle(event)
    return result.isConsumed
}
```

The InputMethodKit adapter uses `isConsumed`, not action count, to decide whether to swallow the original key event. `Q` key-down deliberately returns an empty action list while the host waits for key-up or the 0.45-second long-press timer, but the original event is still consumed. `Space` resolves immediately on key-down and has no numeric-chord state. Idle `Esc` and other pass-through events remain available to the client even when the process-wide event tap is active.

`OneHandSession` is the host boundary:

```swift
public protocol OneHandSession {
    var context: OneHandContext { get }
    var compositionText: String { get }
    var displayedCandidates: [String] { get }
    var expandedCandidates: [String] { get }
    func expandedCandidateWindow(startingAt startIndex: Int, limit: Int) -> [String]
    func apply(_ action: OneHandAction)
    func takeClientActions() -> [OneHandClientAction]
    func commitCurrentComposition()
    func commitDisplayedCandidate(at index: Int)
    func commitDisplayedCandidate(matching text: String)
    func commitExpandedCandidate(at index: Int)
    func setAsciiMode(_ enabled: Bool)
    func reset()
}
```

Current session implementations:

```text
OneHandRimeSession
-> dynamically loads librime at runtime
-> bounds-checks every required C API member before use
-> deploys each schema once per process/data layout and reuses the runtime
-> drives schema selection, candidate lookup, paging, and commit through Rime C API
-> reports initialization failure so the host can select the indexed fallback

OneHandLexiconSession
-> loads entries from a Rime-style dictionary file
-> keeps the current numeric composition
-> pages visible candidates
-> emits client actions such as insertText/deleteBackward

OneHandRecordingSession
-> test double used by unit tests
-> records actions without AppKit or candidate UI
```

## Input Layer Configuration

When LeftIO is selected, open the macOS input-source menu in the top-right menu bar and choose `自定义输入层…`. The settings window independently selects whether an idle `Q` tap and a `Q` long press enter the symbol or numeric layer. It also edits the eight physical symbol slots `W/E/A/S/D/Z/X/C`. Saving applies the new trigger choices and symbols to every active LeftIO controller immediately and stores only values that differ from the bundled defaults. `恢复默认` removes those overrides, and saved values survive a LeftIO restart.

The bundled defaults remain in `data/onehand_symbols.yaml`:

`data/onehand_symbols.yaml` supports both literal text and a small built-in action set:

```yaml
symbols:
  W: "，"
  E: action:page_down
  A: "action:delete_backward"
auto_return: true
q_tap_layer: symbol
q_long_press_layer: numeric
```

Supported action names:

```text
delete_backward
page_up
page_down
commit_first_candidate
commit_composition
cancel_composition
insert_space
insert_newline
```

## Rime Dictionary Generation

Input rows are tab-separated:

```text
word<TAB>pinyin with spaces<TAB>weight
```

Generate a dictionary:

```sh
python3 scripts/generate_onehand_t9_dict.py scripts/sample_pinyin.tsv > data/onehand_t9.dict.yaml
```

For the bundled Rime data, generate the production table from `luna_pinyin`:

```sh
python3 scripts/generate_onehand_t9_dict.py \
  vendor/librime/data/minimal/luna_pinyin.dict.yaml \
  --supplement data/onehand_t9_phrases.tsv \
  > data/onehand_t9.dict.yaml
```

The production table is derived from upstream Rime `luna_pinyin` and `essay`
data and is distributed under LGPL-3.0-only. Keep the generated header comments
intact when redistributing `data/onehand_t9.dict.yaml`.

When `essay.txt` exists next to the input dictionary, the generator uses its real
Rime frequencies for weights. It derives an essay-only phrase only when every
character has one unambiguous T9 code. Phrase pronunciations involving
polyphonic characters must come from an explicit source-dictionary row or
`--supplement`; the generator never invents them from a character's most common
reading. Pass `--no-essay-phrases` to keep only explicit dictionary rows.

The generated table dictionary includes explicit `text/code/weight` columns so it can be consumed by `table_translator`.

Example:

```text
你好    ni hao    1000
```

becomes:

```text
你好    64'426    1000
```

The apostrophe is kept as the syllable delimiter. The encoder also normalizes `ü` and `u:` to `v` before generating T9 codes so the runtime encoder and dictionary generator stay consistent.

## Current Adapter Boundary

```text
InputMethodKit key event
-> OneHandMacKeyMapper.event(from:)
-> OneHandInputController.handle(...)
-> if result.isConsumed, consume original key event
-> OneHandSession.apply(...)
-> IMK marked text / candidate window / client text commit
```

Keep `OneHand` and `OneHandKeyboard` as the pure, tested layers. Let `OneHandAppKit` and the IMK host stay thin wrappers around backend selection and client UI synchronization.
