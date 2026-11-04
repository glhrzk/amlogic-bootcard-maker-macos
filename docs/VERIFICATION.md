# Verification status — BootcardMaker for macOS

This file states plainly what was checked, where, and what was not.
Nothing in this file claims a Mac run that did not happen. The Mac run
fills in the blank sections below. Do not fill them in from guesses.

Status key:

- **Checked on Linux** — run or read on a Linux VM. Simulation or
  static reading only. This proves nothing about Swift, macOS, or
  hardware.
- **Mac-gated** — the check exists but can only run on a Mac. It has
  not run yet.
- **Unverified** — no check exists, or the check needs a physical card
  or a Windows-made card that is not available.

## 1. Checked on Linux (simulation / static only)

### Core-math simulation

Command:

```sh
python3 scripts/simulate-core.py
```

Result: 23 checks PASS, `RESULT: ALL PASS`. The simulation mirrors the
Swift constants in `Sources/BootcardCore/CoreLogic.swift`: sector size
512, write length `(fileLength + 1) >> 9 + 1` sectors, the 66-byte copy
at offsets 446–511, MBR entry type `0x0B`, boot flag, start LBA 32130,
disk signature `0xF0CCF0CC`, and the validate-write guards (empty bin
refused, 1 MiB disk refused, 16 GiB disk with the 4,194,304-byte bin
accepted). For the supplied 4,194,304-byte bin, the write length is
8,193 sectors (4,194,816 bytes), zero-padded.

This is a Python mirror. It does not run the Swift code and it does not
prove the Swift code is correct. The Swift tests below are the real
check, and they are Mac-gated.

### Static source reviews

Read on Linux, no execution:

- `Sources/BootcardCore/CoreLogic.swift` performs no file, disk, or
  shell access (checked by searching the file for file, handle,
  process, and device-path access; none found). Little-endian fields
  are written byte by byte. Zero padding uses `Data(count:)`. The
  original 511-byte heap over-read is not reproduced.
- `Sources/BootcardCore/DiskCommandBuilders.swift` builds every
  external command as an argument array. No user input is interpolated
  into a shell string. Device paths are validated before use:
  whole-disk identifiers only, partition paths derived by appending
  `s1` to a validated whole-disk identifier.
- `docs/ui-checklist.md` records the items checked statically from the
  SwiftUI source (labels, disabled states, confirmation-sheet rows,
  progress behaviour, no rollback wording) and the items that are
  Mac-only (rendering, keyboard focus, contrast, reduced motion,
  larger text). The static items are not runtime proof.
- `scripts/build-app.sh` passes a shell syntax check (`sh -n`). On
  Linux it exits as designed at the Command Line Tools preflight.
  The build, assembly, and signing steps have not run.

### Forbidden-content check (Task 6)

Run on 2026-11-05 on this Linux VM, before the Task 6 commit:

- `git ls-files` listed 22 tracked files (see §4). No `.exe` or `.bin`
  file is tracked. `LICENSE` exists.
- A case-insensitive `git grep` over tracked files for owner
  name/username/email patterns plus credential patterns (`password`,
  `api_key`, `secret`, `bearer`)
  matched only the word "secret" in prose ("no secrets") in the design
  and plan documents, plus one occurrence of the owner's real name in
  the design document. The name was removed from the design document
  as part of Task 6, before the Task 6 commit. No email address, no
  username, no credential value appears in any tracked file. Git
  author identity in `.git/config` is separate and was not changed;
  it is not repo content.

## 2. Mac-gated (written, never run)

Run these on the owner's M5 / Tahoe Mac and record the exact outputs
in the blank sections below. Until then, every item here is unproven.

### Swift unit tests

Command:

```sh
swift test
```

Test files and counts (as written; counts to be confirmed by the run):

- `Tests/BootcardCoreTests/CoreLogicTests.swift` — 10 tests: write
  length formula, 66-byte copy, MBR entry, guards, tiny-bin padding,
  disk signature, CHS fields.
- `Tests/BootcardCoreTests/DiskEnumerationTests.swift` — 6 tests:
  fixture parsing, boot-disk exclusion, partition exclusion,
  built-in-reader disk included with its flags, removable/external
  sorting.
- `Tests/BootcardCoreTests/DiskCommandBuildersTests.swift` — 15
  tests: argument arrays for `diskutil unmountDisk`,
  `newfs_msdos -F 32`, and `hdiutil attach`, device-path validation,
  partition-path derivation.

Total: 31 tests. The fixture
`Tests/BootcardCoreTests/Fixtures/diskutil-list-sample.plist` is
synthetic test data, not a real disk listing. It was inspected on
Linux only; the parsing tests that read it are Mac-gated.

**Mac run result (to fill in):**

```text
swift test output: (paste exact output, or "not run yet")
Tests passed / total: ___ / 31
Date and machine: ___
```

### Build script

Command:

```sh
scripts/build-app.sh
```

The script preflights Command Line Tools, runs `swift build -c release`,
assembles `dist/BootcardMaker.app`, and ad-hoc signs it. The script has
never run past its preflight. The `hdiutil create` / `hdiutil attach`
spellings used by dry-run mode are also Mac-gated.

**Mac run result (to fill in):**

```text
Build output: (paste exact output, or "not run yet")
App produced at: ___
Command Line Tools present: yes / no (if no, install command used: ___)
Free space at build time: ___
Date and machine: ___
```

### Dry-run image inspection

Run dry-run mode at each offered size, then inspect the image file.
For each size, record the values. Do not invent values; leave a row
blank if the run has not happened.

Checks for each image (Yes ticked and Yes unticked):

- Sector 0: partition entry type `0x0B`, boot flag set, start LBA
  32130, length to the end of the image, boot signature `0x55 0xAA`.
- Written bin bytes 0–445 match the bin file byte for byte.
- Bytes 446–511 match the image's live sector 0.
- Bytes after the bin are zero to the end of the written length.
- BPB values of the formatted partition (see §3).

**Mac run result (to fill in):**

```text
Default size (partition start + 64 MiB), Yes ticked:   (not run yet)
Default size, Yes unticked:                             (not run yet)
1 GiB, Yes ticked:                                      (not run yet)
4 GiB, Yes ticked:                                      (not run yet)
16 GiB, Yes ticked:                                     (not run yet)
```

### GUI checklist

`docs/ui-checklist.md` lists every UI item. The items marked
`Unchecked — Mac only` need the built app running on the Mac:
rendering order, disk-picker format, read-only bin field, Yes default,
keyboard focus, contrast in light and dark mode, reduced motion, and
larger system text. None of them has been checked.

**Mac run result (to fill in):**

```text
UI checklist items checked on the Mac: ___ / 18
Screenshots taken: yes / no
Date and machine: ___
```

## 3. BPB values from dry-run (to fill in on the Mac)

Record the BIOS Parameter Block values of the FAT32 partition produced
by dry-run mode, for one image size. These values are the acceptance
record for the format comparison. They are blank until a Mac run
produces them. The `newfs_msdos -F 32` defaults are whatever the tool
on Tahoe applies; do not copy values from documentation or from
another machine.

```text
Image size:              (not run yet)
Bytes per sector:        ___
Sectors per cluster:     ___
Reserved sectors:        ___
Number of FATs:          ___
Media type:              ___
Sectors per FAT (32):    ___
Total sectors (32):      ___
Volume label:            ___
```

## 4. Unverified

These have no check yet and no Mac run can be claimed for them:

- **FAT32 equivalence with a Windows-produced card.** The Windows
  `SHFormatDrive` parameters (cluster size, FAT type, label) cannot be
  recovered from the Windows program. The port uses
  `newfs_msdos -F 32` with default settings. Equivalence is unverified
  until the BPB values above are compared against a Windows-made card
  of the same size, made with the same bin file.
- **Hardware boot.** No physical card has been written by this app,
  and no T95 Max Plus has booted from a card made by this app. The
  physical-card test and the boot test are owner-gated deferred tasks.
- **Elevation on Tahoe.** The privileged write uses
  `AuthorizationExecuteWithPrivileges`, a deprecated API, isolated in
  `Sources/BootcardMakerApp/PrivilegedDiskWriter.swift`. Whether it is
  still present and working on Tahoe is unverified. If it is gone,
  only that file needs to change.
- **Partition-node appearance.** Whether the partition device node
  (`diskNs1`) appears promptly after the raw MBR write, so the format
  step can address it, is unverified on Tahoe.

## 5. Tracked files at the Task 6 check

`git ls-files` output (22 files):

```text
.gitignore
LICENSE
Package.swift
README.md
Sources/BootcardCore/CoreLogic.swift
Sources/BootcardCore/DiskCommandBuilders.swift
Sources/BootcardCore/DiskEnumeration.swift
Sources/BootcardMakerApp/App.swift
Sources/BootcardMakerApp/DiskListProvider.swift
Sources/BootcardMakerApp/DiskOperation.swift
Sources/BootcardMakerApp/DryRun.swift
Sources/BootcardMakerApp/MainView.swift
Sources/BootcardMakerApp/PrivilegedDiskWriter.swift
Tests/BootcardCoreTests/CoreLogicTests.swift
Tests/BootcardCoreTests/DiskCommandBuildersTests.swift
Tests/BootcardCoreTests/DiskEnumerationTests.swift
Tests/BootcardCoreTests/Fixtures/diskutil-list-sample.plist
docs/superpowers/plans/2026-11-05-bootcardmaker-macos.md
docs/superpowers/specs/2026-11-05-bootcardmaker-macos-design.md
docs/ui-checklist.md
scripts/build-app.sh
scripts/simulate-core.py
```

`docs/VERIFICATION.md` and `docs/RECOVERY-NOTES.md` (this file's
companions) are added by the Task 6 commit and are not in the list
above, which was taken before that commit.
