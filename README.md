# LeftIO

[![CI](https://github.com/CST-Cat/left-io/actions/workflows/ci.yml/badge.svg)](https://github.com/CST-Cat/left-io/actions/workflows/ci.yml)

LeftIO is a macOS one-hand T9-style Chinese input method experiment.

The current repository contains a testable Swift input controller core, a physical-key adapter for macOS keyboard events, an InputMethodKit host, and a lightweight dictionary-backed candidate engine that reads Rime-style T9 dictionary data. The host is still not wired to librime yet, but it now shows candidates, supports paging, and commits dictionary matches. The distributable DMG exposes a single `LeftIO.app`; when launched from `/Applications`, that app installs or updates the embedded input method into `/Library/Input Methods`.

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
├── OneHandContext.swift
├── OneHandHandleResult.swift
├── OneHandInputController.swift
├── OneHandKey.swift
├── OneHandLexicon.swift
├── OneHandLexiconSession.swift
├── OneHandRecordingSession.swift
├── OneHandRimeBridge.swift
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

data/
├── onehand_t9.schema.yaml
├── onehand_t9.dict.yaml
├── onehand_t9.custom.yaml
└── onehand_symbols.yaml

scripts/
├── generate_onehand_t9_dict.py
└── sample_pinyin.tsv

Tests/OneHandTests/
├── OneHandInputControllerTests.swift
├── OneHandLexiconSessionTests.swift
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
make test
make xcodebuild-test
```

`make test` runs XCTest only and disables Swift Testing discovery. The package currently uses XCTest, and this avoids a SwiftPM testing-helper code-signing issue on this macOS/Xcode setup.

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

The DMG contains a single `LeftIO.app`. Drag it to `/Applications`, then launch it once from `/Applications` to install or update the input method and open Keyboard settings. No extra installer script is required for normal use.

The `make install-input-method` and `make install-input-method-system` commands below are only developer shortcuts for local testing from the repo checkout.

Install for the current user:

```sh
make install-input-method
```

Install system-wide, with a visible macOS administrator authorization prompt:

```sh
make install-input-method-system
```

The actual input method host lives at `/Library/Input Methods/LeftIO.app` or `~/Library/Input Methods/LeftIO.app`. The visible app in `/Applications` is only the installer/updater shell that places the embedded input method bundle into the correct macOS input-method directory.

The current host is a functional IMK shell wired to the one-hand key state machine and a lightweight in-process lexicon session. It reads `data/onehand_t9.dict.yaml`, shows candidates in the system candidate window, supports paging with `F/G`, and commits candidates with `Space` or `1-4`. It does not yet use librime, so advanced segmentation and user-dictionary behavior are still future work. If macOS does not immediately show LeftIO in System Settings after installation, log out and back in to force Text Input Sources to rescan `/Library/Input Methods`.

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
}
```

Current session implementations:

```text
OneHandLexiconSession
-> loads entries from a Rime-style dictionary file
-> keeps the current numeric composition
-> pages visible candidates
-> emits client actions such as insertText/deleteBackward

OneHandRecordingSession
-> test double used by unit tests
-> records actions without AppKit or candidate UI
```

The future librime bridge can conform to the same protocol and replace `OneHandLexiconSession` without changing the state machine.

## Rime Dictionary Generation

Input rows are tab-separated:

```text
word<TAB>pinyin with spaces<TAB>weight
```

Generate a dictionary:

```sh
python3 scripts/generate_onehand_t9_dict.py scripts/sample_pinyin.tsv > data/onehand_t9.dict.yaml
```

Example:

```text
你好    ni hao    1000
```

becomes:

```text
你好    64'426    1000
```

The apostrophe is kept as the syllable delimiter.

## Current Adapter Boundary

```text
InputMethodKit key event
-> OneHandMacKeyMapper.event(from:)
-> OneHandInputController.handle(...)
-> if result.isConsumed, consume original key event
-> OneHandSession.apply(...)
-> IMK marked text / candidate window / client text commit
```

The next backend phase is still to add a real librime session behind `OneHandSession`. Keep `OneHand` and `OneHandKeyboard` as the pure, tested layers. Let `OneHandAppKit` and any future Squirrel/librime adapter stay thin.
