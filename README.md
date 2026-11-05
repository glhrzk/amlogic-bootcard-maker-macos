# BootcardMaker for macOS

A native macOS port of the Windows tool BootcardMaker V1.0.1-130918_Beta
(SDcardMaker 1.0.0.2, 2013). It writes a bootloader `.bin` file to an SD
card so an Amlogic S905X3 TV box (for example the T95 Max Plus) can boot
from the card.

This is a clean-room rewrite. No code was copied from the Windows tool,
and no Amlogic binary is in this repo. The card layout was recovered by
reading the Windows program with reverse-engineering tools. The findings
are in `docs/RECOVERY-NOTES.md`.

## Safety warning

This tool erases the disk you choose. It writes from byte offset 0 and
replaces the partition table. If you choose the wrong disk, the data on
that disk is lost. There is no undo.

The app lists whole disks only, excludes the boot disk, and shows a
confirmation sheet before any write. Before you confirm, check all three
of these: the disk name, the disk identifier (for example `disk4`), and
the disk size. If any of them does not match the card you inserted, press
Cancel. Do not remove the card while the app is writing. The app shows
`Success!` only after it re-reads the card and verifies the write.

## Requirements

- Apple Silicon Mac (arm64). Intel Macs are not supported.
- macOS Tahoe (macOS 14 or later is the build target; Tahoe is the
  tested target).
- Command Line Tools only. A full Xcode install is not required.
- A spare SD card for the first physical test. Test on a spare card
  first, never on a card that holds data you need.

## Build

On a Mac with Command Line Tools installed:

```sh
scripts/build-app.sh
```

The script checks for Command Line Tools first. If they are missing, it
stops and prints the install command. The built app is at
`dist/BootcardMaker.app`.

The build is ad-hoc signed. It is not signed with a developer
certificate and it is not notarised. To run it the first time,
right-click (or Control-click) the app, choose Open, then choose Open
again in the dialog. After that, the app opens normally.

> **Honest status:** the Swift code and this build script have not been
> run on a Mac yet. They were written and statically reviewed on a
> Linux machine. Building and running them on a Mac is the next step.
> See `docs/VERIFICATION.md`. Do not treat this README as proof that
> the build works.

## Releases

Every push to the `main` branch runs the GitHub Actions workflow in
`.github/workflows/release.yml`: it runs `swift test`, builds the app
with `scripts/build-app.sh`, and publishes `BootcardMaker-macos.zip`
to the `continuous` prerelease. Each run replaces the zip, so the
prerelease always holds the latest `main` build. The workflow can also
be run by hand from the Actions tab.

Releases carry the bundle identifier `com.glhrzk.bootcardmaker`.

## Run

1. Insert the SD card.
2. Open `BootcardMaker.app`.
3. Choose the disk. The list shows whole disks as
   `Name — size (diskN)`. Nothing is selected by default.
4. Choose the bin file with the `Open…` button. The file picker takes
   one file of any extension. The original Windows filter was `*.bin`.
5. Leave `To Partition and Format SD-card: Yes` ticked to partition
   and format the card first. Untick it to keep the card's existing
   partition table and write only the bin file.
6. Press `Make`. Check the disk name, identifier, and size on the
   confirmation sheet. Press `Erase and Make` only if they match your
   card.
7. Wait until the app reports success or an error. Do not remove the
   card while it is working. If an error names a step, the disk is left
   in the state that step left it. The app does not claim a rollback.

## Dry run (no card needed)

Dry-run mode writes to a disk-image file instead of a physical disk, so
you can inspect the result without risking a card. It uses the same
partition, format, and write code path as a physical disk.

1. Open the app and turn on dry-run mode.
2. Choose the image size: the default (partition start + 64 MiB),
   1 GiB, 4 GiB, or 16 GiB. The images are sparse, so they use only
   the space that is actually written.
3. Choose the bin file and press `Make`. The confirmation sheet shows
   the image size and states that a new image file will be created
   and left for inspection.
4. Inspect the image file afterwards (see `docs/VERIFICATION.md` for
   the checks). Dry-run mode never asks for administrator approval.

## What the app writes

- One MBR partition entry: type `0x0B` (FAT32), boot flag set, start
  32,130 sectors (2 cylinders at 255 heads x 63 sectors per track),
  length to the end of the disk, disk signature `0xF0CCF0CC`.
- A FAT32 filesystem on the partition, made with `newfs_msdos -F 32`
  and default settings.
- The bin file from byte offset 0, length `(fileLength + 1) >> 9 + 1`
  sectors, zero-padded. Bytes 0–445 are the bin file verbatim. Bytes
  446–511 are copied from the card's live sector 0, read after
  partitioning and formatting (or from the existing card when Yes is
  unticked).

The original Windows tool had two quirks that this port does not
reproduce: typing a bin path by hand without using the Open button
wrote nothing, and the last sector was read past the end of its buffer.
This port writes whenever a valid bin file is chosen, and it zero-pads
instead of over-reading. See `docs/RECOVERY-NOTES.md`.

## Known limits

- Swift build, Swift tests, the GUI, and dry-run runs are Mac-gated.
  None of them has been verified on a Mac yet. The code was written on
  a Linux machine, where Swift cannot run. Do not claim macOS
  verification without Mac evidence.
- FAT32 equivalence with a Windows-produced card is unverified. The
  port uses `newfs_msdos -F 32` with default settings. The exact
  parameters the Windows `SHFormatDrive` call applied cannot be
  recovered from the Windows program. Compare the BPB values before
  claiming the cards are equivalent. See `docs/VERIFICATION.md`.
- The card result is unverified on hardware. No physical card has been
  written, and no T95 Max Plus has booted from a card made by this
  app yet.
- The privileged write uses `AuthorizationExecuteWithPrivileges`, a
  deprecated API. Whether it is still present and working on Tahoe
  is unverified. If it is gone, only
  `Sources/BootcardMakerApp/PrivilegedDiskWriter.swift` needs to
  change.
- Whether the partition device node (`diskNs1`) appears promptly after
  the raw MBR write is unverified on Tahoe.

## Before publishing

One placeholder line remains to be confirmed by the owner:

1. The copyright line in `LICENSE`:
   `BootcardMaker for macOS contributors`. Replace it with the real
   copyright holder.

The license is MIT. See `LICENSE`.

## Reporting a problem

The Windows program and the supplied bootloader `.bin` file are not in
this repo, and they must never be committed to it. Do not attach them
to a bug report either. Report only measurements.

### Wrong disk shown or offered

Include: the `diskutil list` output for the card (name, identifier,
size), what the app showed in the disk list, and what you expected.
State whether the card reader is built-in or USB. Do not include any
personal data.

### Format difference from a Windows-made card

Include: the card size, the bin file size, the BPB values from both
cards (bytes per sector, sectors per cluster, reserved sectors, number
of FATs, media type, sectors per FAT), and whether the card boots on
the box. State which card was made by which tool. Do not attach a card
image that contains personal files; a fresh card with only the bin
write is enough.

## Layout

- `Sources/BootcardCore/` — sector and MBR math, disk enumeration
  parsing, and command builders. No file, disk, or shell access.
  Unit-tested (tests are Mac-gated).
- `Sources/BootcardMakerApp/` — the SwiftUI window, the live
  `diskutil` call, the privileged disk write, and dry-run mode.
- `Tests/BootcardCoreTests/` — unit tests and a synthetic
  `diskutil` fixture. The fixture is invented test data, not a real
  disk listing.
- `scripts/build-app.sh` — Command Line Tools build and `.app`
  assembly.
- `scripts/simulate-core.py` — a Python mirror of the core math,
  runnable on Linux. Simulation only; it proves nothing about the
  Swift code.
- `docs/` — design, plan, UI checklist, verification status, and
  recovery notes.
