#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-}"
shift || true

if [[ -z "$ACTION" ]]; then
  echo "usage: $0 current | select <source-id> | select-fallback <excluded-source-id> [...]" >&2
  exit 64
fi

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
  xcrun swift - "$ACTION" "$@" <<'SWIFT'
import Carbon
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
guard let action = arguments.first else {
    exit(64)
}

func stringValue(_ source: TISInputSource, _ property: CFString?) -> String? {
    guard let property,
          let rawValue = TISGetInputSourceProperty(source, property) else {
        return nil
    }
    return String(describing: unsafeBitCast(rawValue, to: CFTypeRef.self))
}

func boolValue(_ source: TISInputSource, _ property: CFString?) -> Bool {
    guard let property,
          let rawValue = TISGetInputSourceProperty(source, property) else {
        return false
    }
    let value = unsafeBitCast(rawValue, to: CFTypeRef.self)
    guard CFGetTypeID(value) == CFBooleanGetTypeID() else {
        return false
    }
    return CFBooleanGetValue(unsafeDowncast(value, to: CFBoolean.self))
}

func sourceIdentifier(_ source: TISInputSource) -> String? {
    stringValue(source, kTISPropertyInputSourceID)
}

func select(_ source: TISInputSource) {
    let status = TISSelectInputSource(source)
    guard status == noErr else {
        fputs("TISSelectInputSource failed with status \(status).\n", stderr)
        exit(1)
    }
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.15))
    print(sourceIdentifier(source) ?? "-")
}

switch action {
case "current":
    guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
          let identifier = sourceIdentifier(source) else {
        exit(1)
    }
    print(identifier)

case "select":
    guard arguments.count == 2 else {
        exit(64)
    }
    let requestedIdentifier = arguments[1]
    let sources = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [AnyObject] ?? []
    for rawSource in sources {
        let source = unsafeBitCast(rawSource, to: TISInputSource.self)
        let sourceID = sourceIdentifier(source)
        let modeID = stringValue(source, kTISPropertyInputModeID)
        guard sourceID == requestedIdentifier || modeID == requestedIdentifier,
              boolValue(source, kTISPropertyInputSourceIsEnabled),
              boolValue(source, kTISPropertyInputSourceIsSelectCapable) else {
            continue
        }
        select(source)
        exit(0)
    }
    fputs("No enabled, selectable input source matched \(requestedIdentifier).\n", stderr)
    exit(1)

case "select-fallback":
    guard arguments.count >= 2 else {
        exit(64)
    }
    let excludedIdentifiers = Set(arguments.dropFirst())
    guard let fallback = TISCopyCurrentASCIICapableKeyboardInputSource()?.takeRetainedValue(),
          excludedIdentifiers.isDisjoint(with: [
              sourceIdentifier(fallback),
              stringValue(fallback, kTISPropertyInputModeID),
              stringValue(fallback, kTISPropertyBundleID)
          ].compactMap { $0 }),
          boolValue(fallback, kTISPropertyInputSourceIsEnabled),
          boolValue(fallback, kTISPropertyInputSourceIsSelectCapable) else {
        fputs("No enabled ASCII-capable fallback input source is available.\n", stderr)
        exit(1)
    }
    select(fallback)

default:
    exit(64)
}
SWIFT
