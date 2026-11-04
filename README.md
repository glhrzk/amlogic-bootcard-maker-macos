# BootcardMaker for macOS

A native macOS port of the Windows tool BootcardMaker V1.0.1-130918_Beta.
It writes a bootloader `.bin` file to an SD card so an Amlogic S905X3
TV box (for example the T95 Max Plus) can boot from the card.

Target: Apple Silicon (arm64), macOS Tahoe. Buildable with Command Line
Tools only. No VM, no Wine, no bundled runtime.

## Safety warning

This tool erases the disk you choose. It writes from byte offset 0 and
replaces the partition table. Choose the wrong disk and the data on
that disk is lost. The app lists whole disks, excludes the boot disk,
and asks for confirmation before any write, but always check the disk
name, identifier, and size before you confirm.

## Build

On a Mac with Command Line Tools installed:

```sh
scripts/build-app.sh
```

The built app is at `dist/BootcardMaker.app`. It is ad-hoc signed.
To run an unsigned build, right-click the app, choose Open, then Open
again.

## Known limits (honest status)

- The Swift code and this build script have not yet been run on a Mac.
  macOS verification is owner-gated: the owner builds and runs the
  dry-run image checks on their M5 / Tahoe Mac.
- FAT32 format equivalence with a Windows-produced card is unverified.
  The port uses `newfs_msdos -F 32` with default settings; this must
  be compared against a Windows-produced card before it is claimed
  equivalent.
- The card result is unverified on hardware until a physical card is
  written and the T95 Max Plus boots from it.
- The bundle identifier `com.example.bootcardmaker` and the copyright
  holder line in `LICENSE` are placeholders. Change both before
  publishing.

The full design, the implementation plan, and the REA ground-truth
report are in `docs/` and in `~/workspace/bootcardmaker-rea/`.
