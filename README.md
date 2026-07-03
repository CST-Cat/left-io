# LeftIO

[![CI](https://github.com/CST-Cat/left-io/actions/workflows/ci.yml/badge.svg)](https://github.com/CST-Cat/left-io/actions/workflows/ci.yml)

LeftIO is a macOS one-hand T9-style Chinese input method experiment.

The current repository contains the first landing layers: a testable Swift input controller core, a physical-key adapter for macOS keyboard events, and Rime schema/dictionary scaffolding. It is intentionally not wired into Squirrel/InputMethodKit yet.

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
├── OneHandConfiguration.swift
├── OneHandContext.swift
├── OneHandHandleResult.swift
├── OneHandInputController.swift
├── OneHandKey.swift
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

`OneHandRimeSession` is the host boundary:

```swift
public protocol OneHandRimeSession {
    var context: OneHandContext { get }
    func apply(_ action: OneHandAction)
}
```

Expected action mapping:

```text
inputT9Code            -> send numeric code to librime composition
insertSyllableDelimiter-> send apostrophe delimiter to librime composition
commitFirstCandidate   -> select/commit candidate 0
selectCandidate        -> select/commit candidate index
pageUp / pageDown      -> candidate page navigation
commitComposition      -> commit current composition
deleteBackward         -> delete in composition, or client delete if empty
insertText             -> commit literal text to client
inputDigit             -> commit literal digit to client
insertSpace            -> commit ordinary space to client
insertNewline          -> commit newline to client
enter/exitSymbolLayer  -> internal state marker; usually no librime call
cancelPendingSpace     -> cleanup marker after focus/input-method reset
```

`OneHandRecordingSession` is included for tests and adapter prototyping; it records actions without depending on librime or AppKit.

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

## Next Integration Step

The next phase is to fork or vendor `rime/squirrel`, then call `OneHandMacKeyMapper.event(from:)` from the Squirrel/InputMethodKit key-event path and apply `OneHandAction` to the Squirrel/librime session.

Current adapter boundary:

```text
InputMethodKit key event
-> OneHandMacKeyMapper.event(from:)
-> OneHandInputController.handle(...)
-> if result.isConsumed, consume original key event
-> OneHandRimeSession.apply(...)
-> librime / client text commit
```

Keep `OneHand` and `OneHandKeyboard` as the pure, tested layers. Let `OneHandAppKit` and the future Squirrel adapter stay thin.
