# ShadowVM-CE

ShadowVM-CE is a macOS 12+ (Apple Silicon) virtual machine manager that ships with a native UI and a command-line interface (CLI).
It builds a signed macOS app bundle and supports provisioning VMs from IPSW images.
The CLI and UI share the same app bundle; CLI start/stop requests can forward to a running UI instance.

## Features
- Create, install, start, stop, and query Apple Virtualization-based VMs.
- UI workflow for VM lifecycle and configuration.
- IPSW-based OS installation.
- Clipboard sync toggles and agent install support.
- vsock configuration for host/guest communication.

## Requirements
- macOS 12.0+.
- Apple Silicon (arm64).
- Xcode (for `xcodebuild`).

## Required third-party artifacts
ShadowVM-CE depends on binaries/interfaces stored in `3rd_party/`:
- `3rd_party/libShadowVMCore.a`
- `3rd_party/ShadowVMCore.swiftinterface`
- `3rd_party/ShadowVMAgent-*.img`

If any of these are missing, build/install will fail.

## Quick Start (UI)
```bash
make ShadowVM-CE
open output/bin/debug/ShadowVM-CE.app
```

Build outputs:
- Debug app: `output/bin/debug/ShadowVM-CE.app`
- Release app (after signing step): `output/bin/release/ShadowVM-CE.app`

You can override build configuration and output root with `SWIFT_BUILD_CONFIG=release` and `OUTPUT_DIR=<path>`.

## CLI usage
The CLI is embedded in the app bundle. After building:
```bash
output/bin/debug/ShadowVM-CE.app/Contents/MacOS/ShadowVM-CE --help
```
By default, `vm create` stores bundles under `~/.shadowvm-ce/<name>.vmapple` and `--bundle` will auto-append
the `.vmapple` extension when missing.

Commands and options (from the CLI usage output):
- `vm create --name <name> [--bundle <path>] [--cpu <n>] [--memory <mb>] [--width <px>] [--height <px>] [--scale <n>] [--json]`
- `vm install --bundle <path> --ipsw <path> --disk <gb> [--json]`
- `vm start --bundle <path> [--json]`
- `vm stop --bundle <path> [--json]`
- `vm status --bundle <path> [--json]`

Examples:
```bash
# Create a VM bundle (defaults to <name>.vmapple when --bundle is omitted)
output/bin/debug/ShadowVM-CE.app/Contents/MacOS/ShadowVM-CE \
  vm create --name Demo

# Install macOS from an IPSW image into a 64 GB disk
output/bin/debug/ShadowVM-CE.app/Contents/MacOS/ShadowVM-CE \
  vm install --bundle ~/VMs/Demo.vmapple --ipsw ~/Downloads/VM.ipsw --disk 64

# Start the VM
output/bin/debug/ShadowVM-CE.app/Contents/MacOS/ShadowVM-CE \
  vm start --bundle ~/VMs/Demo.vmapple

# Inspect status as JSON
output/bin/debug/ShadowVM-CE.app/Contents/MacOS/ShadowVM-CE \
  vm status --bundle ~/VMs/Demo.vmapple --json
```

## Release packaging, signing, notarization
Release builds are driven by `scripts/releaseShadowVMCE` via Makefile targets.
The script loads environment variables from `.env` in this repo (or from the monorepo root if present).

Required environment variables:
- `CE_VERSION` (e.g. `1.0.1`) or pass `<version>` to the Makefile target.
- `CE_SIGN_IDENTITY` (or `SIGN_IDENTITY` as an alias).
- `NOTARY_PROFILE` (for notarization).

Optional:
- `CE_AGENT_IMG` to override which `ShadowVMAgent-*.img` is injected.

Release flow (all-in-one):
```bash
make ShadowVM-CE-release 1.0.1
```

Or run individual steps:
```bash
make ShadowVM-CE-release-build 1.0.1
make ShadowVM-CE-release-sign
make ShadowVM-CE-release-dmg 1.0.1
make ShadowVM-CE-release-notarize 1.0.1
```

Release outputs:
- App bundle: `output/bin/release/ShadowVM-CE.app`
- DMG: `output/ShadowVM-CE-<version>.dmg`

## Data & logs
- Data/config root: `~/.shadowvm-ce` (configured at app startup).
- Settings file: `~/.shadowvm-ce/settings.json`.
- Default VM bundle location: `~/.shadowvm-ce/*.vmapple`.
- Logs are written to the `shadowvm-ce.log` file under the configured logs directory
  (use the app menu item **Debug → Open Log Directory** to locate it).

## Troubleshooting
- Missing `ShadowVMAgent-*.img`: add one under `3rd_party/` or set `CE_AGENT_IMG`.
- Missing `libShadowVMCore.a` or `ShadowVMCore.swiftinterface`: ensure these are present in `3rd_party/`.
- Build failures: confirm macOS 12+ and Apple Silicon, and that `xcodebuild` is available.

## License
See `LICENSE` (Apache-2.0).
