# ShadowVM-CE

ShadowVM-CE is a macOS app and CLI for creating, installing, and managing ShadowVM virtual
machines from IPSW restore images. It provides a UI for VM lifecycle tasks and an embedded
CLI for automation.

## Features
- UI VM lifecycle: create, open, start, stop, and view status
- Install a VM from an IPSW bundle
- Host <-> guest clipboard toggle controls
- ShadowVMAgent install via USB
- Vsock port configuration for agent communication
- CLI for create/install/start/stop/status with JSON output

## Requirements
- macOS 12.0+ (deployment target)
- Apple Silicon (arm64)
- Xcode (build tooling)
- Required artifacts in `3rd_party/`:
  - `libShadowVMCore.a`
  - `ShadowVMCore.swiftinterface`
  - `ShadowVMAgent-*.img`

## Quick Start (Build + Run)
```bash
make ShadowVM-CE
open output/bin/debug/ShadowVM-CE.app
```
The built app is copied to `output/bin/debug/ShadowVM-CE.app`.

## CLI Usage
The CLI lives inside the app bundle after a build:
`output/bin/debug/ShadowVM-CE.app/Contents/MacOS/ShadowVM-CE`

Usage:
```
ShadowVM-CE vm <command> [options]

Commands:
  vm create --name <name> [--bundle <path>] [--cpu <n>] [--memory <mb>] \
    [--width <px>] [--height <px>] [--scale <n>] [--json]
  vm install --bundle <path> --ipsw <path> --disk <gb> [--json]
  vm start --bundle <path> [--json]
  vm stop --bundle <path> [--json]
  vm status --bundle <path> [--json]
```

Examples:
```bash
CLI=output/bin/debug/ShadowVM-CE.app/Contents/MacOS/ShadowVM-CE

# Create a VM bundle (defaults to ~/.shadowvm-ce/<name>.vmapple if --bundle is omitted)
"$CLI" vm create --name Demo

# Install from an IPSW with a 64 GB disk
"$CLI" vm install --bundle ~/.shadowvm-ce/Demo.vmapple --ipsw ~/Downloads/Restore.ipsw --disk 64

# Start, check status, and stop
"$CLI" vm start --bundle ~/.shadowvm-ce/Demo.vmapple
"$CLI" vm status --bundle ~/.shadowvm-ce/Demo.vmapple --json
"$CLI" vm stop --bundle ~/.shadowvm-ce/Demo.vmapple
```

## Data & Logs
- Home/config directory: `~/.shadowvm-ce` (configured in `src/ShadowVM/main.swift`).
- Settings file: `~/.shadowvm-ce/settings.json` (last opened VM path + vsock port).
- Default VM bundle location: `~/.shadowvm-ce/<name>.vmapple` when `--bundle` is omitted.
- Logs: `ShadowVMConfig.shared.logsDir/shadowvm-ce.log` (log file is created on startup).

## Release Packaging (Sign + Notarize)
Release automation lives in `scripts/releaseShadowVMCE` and is exposed via Makefile targets.
It loads `.env` from this repo (or the monorepo root if present).

Required environment variables:
- `CE_SIGN_IDENTITY` (or `SIGN_IDENTITY`)
- `NOTARY_PROFILE`
- `CE_VERSION` (if not provided as the positional `<version>`)

Optional:
- `CE_AGENT_IMG` (override ShadowVMAgent image path)

Full release flow:
```bash
make ShadowVM-CE-release 1.0.0
```

Step-by-step:
```bash
make ShadowVM-CE-release-build 1.0.0
make ShadowVM-CE-release-sign
make ShadowVM-CE-release-dmg 1.0.0
make ShadowVM-CE-release-notarize 1.0.0
```

Outputs:
- App bundle: `output/ShadowVM-CE/ShadowVM-CE.app` and `output/bin/release/ShadowVM-CE.app`
- DMG: `output/ShadowVM-CE-<version>.dmg`

The release script will look for `ShadowVMAgent-*.img` in `OUTPUT_DIR` first, then
`3rd_party/`, unless `CE_AGENT_IMG` is set.

## Troubleshooting
- Missing `libShadowVMCore.a` or `ShadowVMCore.swiftinterface`:
  ensure both are present in `3rd_party/`.
- Missing `ShadowVMAgent-*.img`:
  add one to `3rd_party/` or set `CE_AGENT_IMG` for release builds.
- Build failures:
  verify Xcode is installed and the deployment target is macOS 12.0+.

## License
Apache-2.0 (see `LICENSE`).
