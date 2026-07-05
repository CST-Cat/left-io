# LeftIO

[![CI](https://github.com/CST-Cat/left-io/actions/workflows/ci.yml/badge.svg)](https://github.com/CST-Cat/left-io/actions/workflows/ci.yml)

LeftIO is a macOS one-hand T9-style Chinese input method experiment.

The current repository contains a testable Swift input controller core, a physical-key adapter for macOS keyboard events, an InputMethodKit host, and both a real librime-backed session bridge and a lightweight lexicon fallback session. The host prefers librime when it can be loaded at runtime and falls back to the bundled dictionary-backed session otherwise. On macOS 26, the distributable is a single `LeftIO.app` container with an embedded input-method extension, and the DMG exposes that app together with an `Applications` shortcut for direct drag-and-drop installation.

## Keyboard Layout

```text
Q          W ABC      E DEF
symbol /
delimiter

A GHI      S JKL      D MNO

Z PQRS     X TUV      C WXYZ
```

## Implemented Core Behavior

`Q` is context-sensitive:

```text
empty composition       Q -> enter symbol layer
composing pinyin        Q -> insert syllable delimiter
inside symbol layer     Q -> exit symbol layer
```

`Space` is handled as a chord, not as a long press:

```text
Space down + QWE/ASD/ZXC -> digits 1-9
Space down + V           -> newline
Space up alone           -> first candidate, or ordinary space
```

`Esc` cancels transient input state:

```text
pending Space chord      -> cancel pending Space
inside symbol layer      -> exit symbol layer
composing text           -> clear current composition
idle                      -> pass through to the client
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
├── OneHandRecordingSession.swift
├── OneHandRimeBridge.swift
├── OneHandRimeDataProvider.swift
├── OneHandStateMachine.swift
├── OneHandT9Encoder.swift
├── SpaceChordController.swift
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

data/
├── onehand_t9.schema.yaml
├── onehand_t9.dict.yaml
├── onehand_t9.custom.yaml
└── onehand_symbols.yaml

scripts/
├── build_vendored_librime.sh
├── generate_onehand_t9_dict.py
└── sample_pinyin.tsv

Tests/OneHandTests/
├── OneHandInputControllerTests.swift
├── OneHandConfigurationLoaderTests.swift
├── OneHandLexiconSessionTests.swift
├── OneHandRimeIntegrationTests.swift
├── OneHandRimeSessionTests.swift
├── OneHandStateMachineTests.swift
├── SpaceChordTests.swift
├── SymbolLayerTests.swift
└── T9EncoderTests.swift

Tests/OneHandKeyboardTests/
└── OneHandPhysicalKeyMapperTests.swift
```

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

`make build-vendored-librime` clones and builds a local `vendor/librime` checkout when you want the real Rime backend instead of the lexicon fallback.

`make build-input-method` bootstraps `vendor/librime` automatically on local builds when the vendored dylib or minimal Rime data is missing. Set `LEFTIO_SKIP_LIBRIME_BOOTSTRAP=1` if you explicitly want a fallback-only build.

The GitHub Actions workflow runs both commands above and a dictionary-generator smoke test on macOS.

## Local Installation

Build the experimental InputMethodKit host:

```sh
make build-input-method
```

Build a distributable installer image:

```sh
make build-dmg
```

For development, install the input method for the current user. This copies the app to `~/Library/Input Methods/LeftIO.app`, asks TIS to register and enable it, and leaves the current input source unchanged.

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

The install and uninstall scripts use TIS registration APIs and do not write `com.apple.HIToolbox` or switch the current input source. The installed input-method app is a direct InputMethodKit app bundle, not an embedded `.appex`.

See [docs/leftio-input-method-lifecycle.md](docs/leftio-input-method-lifecycle.md) for the full install, registration, verification, and uninstall lifecycle.

The current host is a functional IMK shell wired to the one-hand key state machine. It reads `data/onehand_symbols.yaml`, prefers a real librime session when `librime` can be loaded at runtime, and falls back to the bundled `data/onehand_t9.dict.yaml` lexicon session when librime is unavailable. Both backends show candidates in the system candidate window, support paging with `F/G`, and commit candidates with `Space` or `1-4`.

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

The future Squirrel/InputMethodKit adapter should use `isConsumed`, not action count, to decide whether to swallow the original key event. `Space` key-down deliberately returns an empty action list because the controller is waiting to determine whether the user is starting a chord or pressing Space alone, but that key event is still consumed.

`OneHandSession` is the host boundary:

```swift
public protocol OneHandSession {
    var context: OneHandContext { get }
    var compositionText: String { get }
    var displayedCandidates: [String] { get }
    func apply(_ action: OneHandAction)
    func takeClientActions() -> [OneHandClientAction]
    func commitCurrentComposition()
    func commitDisplayedCandidate(matching text: String)
    func reset()
}
```

Current session implementations:

```text
OneHandRimeSession
-> dynamically loads librime at runtime
-> prepares and deploys the requested schema before opening a session
-> drives schema selection, candidate lookup, paging, and commit through Rime C API
-> falls back cleanly when librime is unavailable

OneHandLexiconSession
-> loads entries from a Rime-style dictionary file
-> keeps the current numeric composition
-> pages visible candidates
-> emits client actions such as insertText/deleteBackward

OneHandRecordingSession
-> test double used by unit tests
-> records actions without AppKit or candidate UI
```

## Symbol Layer Configuration

`data/onehand_symbols.yaml` supports both literal text and a small built-in action set:

```yaml
symbols:
  W: "，"
  E: action:page_down
  A: "action:delete_backward"
auto_return: true
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
python3 scripts/generate_onehand_t9_dict.py vendor/librime/data/minimal/luna_pinyin.dict.yaml > data/onehand_t9.dict.yaml
```

When `essay.txt` exists next to the input dictionary, the generator uses its real
Rime frequencies for weights and derives phrase rows from single-character Rime
readings. Pass `--no-essay-phrases` to keep only dictionary rows.

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
