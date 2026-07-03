# LeftIO

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
├── OneHandInputController.swift
├── OneHandKey.swift
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
-> OneHandRimeSession.apply(...)
-> librime / client text commit
```

Keep `OneHand` and `OneHandKeyboard` as the pure, tested layers. Let `OneHandAppKit` and the future Squirrel adapter stay thin.
