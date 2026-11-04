# Final verification report — BootcardMaker for macOS

Date: 2026-11-05. Repo: `~/workspace/bootcardmaker-macos/`, branch
`main`, no remote configured (`git remote -v` prints nothing), nothing
pushed. This report is Task 7 of
`docs/superpowers/plans/2026-11-05-bootcardmaker-macos.md`.

Nothing in this report claims a Mac run that did not happen. No Swift
code was compiled or run anywhere in this project: Swift is not
installed on the Linux VM where the code was written, and no Mac run
has been reported. Every Swift test, the build script past its
preflight, the dry-run image inspection, and the UI checklist items
marked Mac-only are unproven until the owner runs them on the M5 /
Tahoe Mac. No physical disk or device was written at any point.

## 1. Requirement traceability

Each row names the design requirement (from
`docs/superpowers/specs/2026-11-05-bootcardmaker-macos-design.md`),
the plan task that implements it, the files, and the evidence or the
Mac-gated status.

### Goals

| Requirement | Task | Implementation | Evidence / status |
|---|---|---|---|
| One native macOS `.app` window mirroring the Windows dialog: Choose disk, Choose bin file with Open, Yes checkbox, Make; English UI only | 5 | `Sources/BootcardMakerApp/App.swift`, `MainView.swift` (SwiftUI) | Static only: `docs/ui-checklist.md`, 9 of 18 items checked statically on Linux. Mac-gated: build, run, rendering, keyboard focus, contrast. |
| Same on-disk result: MBR entry type `0x0B`, boot flag, 2-cylinder start, signature `0xF0CCF0CC`; FAT32 format; bin bytes from offset 0 with bytes 446–511 from the live sector 0 | 2, 4, 5 | `CoreLogic.swift`, `DiskOperation.swift`, `DryRun.swift` | Simulation: 23 checks PASS (§4). Swift tests: Mac-gated. FAT32 equivalence: unverified (§5). |
| Zero-padded write, length `(fileLength + 1) >> 9 + 1` sectors; never the original 511-byte heap over-read | 2 | `CoreLogic.swift` (`writeLengthSectors`, `buildWriteBuffer`) | Simulation: 4,194,304-byte bin → 8,193 sectors; 100-byte bin → 1 sector; trailing bytes zero. Swift tests: Mac-gated. |
| Wrong-disk protection: whole disks only, boot disk excluded, name/identifier/size at selection and on the confirmation sheet, explicit confirmation, fail-closed errors, `Success!` only after re-read verification | 3, 4, 5 | `DiskEnumeration.swift`, `DiskOperation.swift`, `MainView.swift` | Fixture parsing tests: Mac-gated. Static: confirmation-sheet rows and disabled states checked in `docs/ui-checklist.md`. Re-read verification is implemented in `DiskOperation.swift` (step 8) but never executed. |
| Dry-run mode writing to a disk-image file, inspectable byte by byte | 4, 5 | `DryRun.swift`, `DiskOperation.swift` (`dryRunDevice`) | Mac-gated: `hdiutil create` / `hdiutil attach` spellings, attach/detach, image inspection. Dry-run never requests elevation (stated in code; never executed). |
| Small footprint: no VM, no Wine, no Electron, no bundled runtime; CLT-only build | 1 | `Package.swift` (no dependencies), `scripts/build-app.sh` | Static: no dependencies declared. Build script: `sh -n` passes; on Linux it exits 1 at the Command Line Tools preflight as designed (§4). The build, assembly, and signing steps never ran. |
| Open-source ready: clean-room rewrite, MIT license, README, safety warnings, known limits, no secrets, no personal data, no copied binaries | 6, 7 | `LICENSE`, `README.md`, `docs/RECOVERY-NOTES.md`, `docs/VERIFICATION.md`, this report | Forbidden-content greps: clean after the Task 7 fix commit (§4). No `.exe`/`.bin` tracked. Placeholder bundle identifier and copyright line remain owner-gated (§5). |

### Non-goals (implemented by absence)

| Requirement | Task | Evidence / status |
|---|---|---|
| No Burn Card Maker v2 behaviour (erase_bootloader / erase_flash / reboot, `.img` packages, `aml_sdc_burn.ini`) | — | No such code in the file inventory (§4). Confirmed by reading the source file list; no test asserts absence. |
| No USB Burning Tool behaviour, no USB flashing, no eMMC install | — | Same as above. |
| No Intel Macs, older macOS, Windows, or Linux support | 1 | `Package.swift` targets macOS 14; build script targets arm64 Macs. Never built. |
| No automatic card detection loop, background service, update mechanism, telemetry | 5 | No such code in the file inventory. Disk list refreshes only from the UI. |
| No parsing, decryption, or modification of the bin beyond the 66-byte partition-table overwrite | 2 | `buildWriteBuffer` copies bytes 0–445 verbatim; only 446–511 are replaced. Simulation-checked. |

### Anti-goals

| Requirement | Task | Evidence / status |
|---|---|---|
| Never write to the boot disk, an internal disk, or an unconfirmed disk | 3, 5 | Boot-disk exclusion is implemented in `selectableDisks` and covered by fixture tests (Mac-gated). Note the builder-check resolution: internal disks are listed with their flags visible (a built-in reader may report a card as internal); the boot-disk exclusion and the confirmation sheet are the safety net, not an external-only filter. |
| Never produce a card that looks formatted but does not boot because the partition start is inside the bin image or the MBR table was not preserved | 2, 4 | `validateWrite` refuses when the partition start is not strictly beyond the write length; the 66-byte copy reads the live sector 0 after partition/format. Simulation-checked; execution Mac-gated. |
| Never report silent partial success | 4, 5 | Every step returns a named `DiskOperationError`; any failure aborts and `Success!` is shown only after re-read comparison. Implemented, never executed. |
| Never require a paid developer account, full Xcode, or a multi-gigabyte download | 1 | Build script uses Command Line Tools only and ad-hoc signing (best-effort). Never run past preflight. |
| Never claim macOS verification without Mac evidence | 6, 7 | `docs/VERIFICATION.md` and this report label every Mac-gated item as unproven. |

### Constraints

| Requirement | Task | Evidence / status |
|---|---|---|
| arm64, macOS Tahoe only | 1 | Declared target; never built. |
| Elevation once per Make operation via a supported Security framework path; fail loudly if unavailable; privileged surface is exactly unmount, write MBR/bin, format | 4 | `PrivilegedDiskWriter.swift` isolates `AuthorizationExecuteWithPrivileges` (deprecated API). Tahoe presence: unverified (§5). If it is gone, only that file needs to change. |
| No shell-string construction from user input; argument arrays only | 4 | `DiskCommandBuilders.swift` builds all commands as argument arrays; 15 builder tests cover this (Mac-gated). Static review on Linux confirmed no interpolation. |
| Partition start 32,130 sectors (255 heads × 63 sectors/track × 512 bytes); abort if the disk is too small or the start is not beyond the write length; never silently move the start | 2 | `partitionStartSectors = 32130`, `validateWrite`. Simulation-checked. |
| FAT32 via `newfs_msdos -F 32`, default cluster size, no label unless the tool requires one; labelled unverified until compared with a Windows card | 4, 6 | Implemented as a command builder; BPB values blank until a Mac dry-run produces them (§5). |
| MBR signature `0xF0CCF0CC` in both the create-disk step and the layout | 2, 4 | `mbrDiskSignature` constant; `buildMBR` writes it at offset 440. See deviation note in §3: the final written sector 0 keeps bytes 440–445 from the bin (the original's 446–511-only copy), so the signature at 440 is present in the intermediate MBR, not in the final sector 0. |
| 66-byte copy reads sector 0 after partition/format (Yes ticked) or from the existing card (Yes unticked), never cached or assumed | 4 | Implemented in `DiskOperation.swift` step order; never executed. |
| English UI only; error messages name the failed step and the next safe action | 5 | Static checklist items checked; runtime wording Mac-gated. |
| ui-ux-pro-max: landing-page pattern rejected; SwiftUI stack fallback labelled; pro-rules adapted for desktop (no literal 44pt touch targets) | 5 | Recorded in the design doc and `docs/ui-checklist.md`. Contrast, focus, reduced motion, larger text: Mac-gated. |
| Builder-check resolutions 1–5 (enumeration, build env, dry-run semantics, no reference card, deferred hardware tests) | 3, 4, 5 | Recorded in the design doc. Resolutions 1 and 3 are implemented in code; 2, 4, 5 are process decisions, owner-gated. |

### UI design (design doc, items 1–8)

| Item | Task | Evidence / status |
|---|---|---|
| 1. Title `BootcardMaker` + one-line description, erases-disk warning | 5 | Static checklist item (Mac-only rendering). |
| 2. `Choose disk:` pop-up, `Name — size (diskN)`, nothing selected by default, disappeared disk clears selection | 3, 5 | Parser tests Mac-gated; picker rendering Mac-gated. |
| 3. `Choose your bin file:` read-only field + `Open…` picker, single file; Make disabled until disk + existing bin | 5 | Static checklist: Make-disabled and read-only field items checked statically; picker behaviour Mac-gated. |
| 4. `To Partition and Format SD-card:` Yes checkbox, ticked by default, unticked note | 5 | Static checklist (Mac-only rendering). |
| 5. `Make` destructive button, disabled until valid; status line | 5 | Static checklist: disabled-state item checked statically. |
| 6. Confirmation sheet: disk name, identifier, size; bin name/size; choice; erase warning; Cancel / `Erase and Make`; the only confirmation step | 5 | Static checklist: sheet rows checked statically from source. |
| 7. Progress, controls disabled, no mid-write cancellation (stated in UI); `Success!` only after verification; errors name the step and the state left behind, no rollback claim | 4, 5 | Static checklist items checked statically; runtime behaviour Mac-gated. |
| 8. Keyboard access, visible focus, labels on all controls, no icon-only buttons, no emoji icons; reduced motion and larger text must not break layout | 5 | Labels and no-emoji items checked statically; focus, contrast, reduced motion, larger text Mac-gated (9 of 18 checklist items). |

### Verification section of the design doc

| Item | Status |
|---|---|
| Unit tests (length formula, 66-byte offsets, MBR fields, gap guard, no-bin-no-write rule) | Written: 31 tests (§2). Never run. The no-bin-no-write rule is enforced in the UI (Make disabled), covered by a static checklist item, not by a unit test. |
| Dry-run image test on the Mac (Yes ticked/unticked, sector 0, bin bytes, zero padding) | Mac-gated, not run (§5). |
| Physical-card test + T95 Max Plus boot test | Owner-gated, not run (§5). README states the result is unverified on hardware. |
| FAT32 equivalence vs a Windows-produced card | Unverified (§5). No reference card assumed available. |
| Pre-delivery UI pass (contrast both themes, keyboard/focus, labels, disabled states, reduced motion, larger text) | 9 of 18 checklist items checked statically; 9 Mac-only items unchecked. |

## 2. Test inventory (counted by grep, 2026-11-05, Linux)

Counts are `grep -c 'func test'` per file. The total in
`docs/VERIFICATION.md` (31) matches these counts exactly; no count
correction was needed.

- `Tests/BootcardCoreTests/CoreLogicTests.swift` — **10 tests**:
  `testWriteLengthForSuppliedBin`,
  `testWriteLengthForTinyBin`,
  `testBuildWriteBufferPreservesMBRFromLiveSector`,
  `testBuildWriteBufferForTinyBin`, `testBuildMBREntry`,
  `testBuildMBRContainsDiskSignature`, `testBuildMBRStartCHS`,
  `testValidateRejectsEmptyBinAndSmallDisk`,
  `testValidateAcceptsSuppliedBinOnLargeDisk`,
  `testValidateRejectsBinLongerThanPartitionGap`.
- `Tests/BootcardCoreTests/DiskEnumerationTests.swift` — **6 tests**:
  `testParseFixtureYieldsThreeWholeDisks`,
  `testParseFixtureFlagsAreVisible`,
  `testSelectableDisksExcludesBootDiskAndPartitions`,
  `testSelectableDisksSortsRemovableExternalFirst`,
  `testParseInvalidDataThrows`, `testParseEmptyDiskListReturnsEmpty`.
  Fixture `Fixtures/diskutil-list-sample.plist` is synthetic test
  data, not a real disk listing.
- `Tests/BootcardCoreTests/DiskCommandBuildersTests.swift` — **15 tests**:
  `testUnmountDiskCommand`, `testNewfsMsdosCommand`,
  `testDdWriteCommand`, `testDdReadCommandReadsExactlyOneSectorByDefault`,
  `testDdReadCommandHonoursSectorCount`, `testHdiutilAttachCommand`,
  `testHdiutilAttachPlistCommand`, `testHdiutilCreateCommand`,
  `testHdiutilDetachCommand`,
  `testParseHdiutilAttachPlistReturnsWholeDisk`,
  `testParseHdiutilAttachPlistRejectsBadInput`,
  `testNewHdiutilBuildersRejectMalformedInput`,
  `testDevicePathDerivationRejectsNonWholeDiskIdentifiers`,
  `testBuildersRejectMalformedDevicePaths`,
  `testNoArgumentContainsShellMetacharacters`.

**Total: 31 tests. Passed: 0 (never run). `swift test` is Mac-gated.**

## 3. Deviations and corrections found during the build

Recorded here so the owner and any reviewer can judge them; no Swift
code was changed by Task 7.

1. **Plan Task 2 test corrected (coordinator, before Task 2).** The
   plan first asserted a 1024-byte bin produces a 1024-byte buffer.
   The REA formula gives `(1024 + 1) >> 9 + 1 = 3` sectors = 1536
   bytes. The simulation exposed this; the plan was corrected and
   the Swift test expects 1536 with the trailing sector zero-padded.
2. **`buildMBR` writes the disk signature at offset 440 and clamped
   CHS fields (Task 2).** The Task 1 simulation leaves those bytes
   zero. The signature at 440 (0x1B8) matches how Windows applies a
   layout carrying that signature; CHS start for LBA 32130 is 2/0/1
   and the end CHS is clamped to 1023/254/63. Consequence, confirmed
   by reading the code: the final written sector 0 still follows the
   original's 446–511-only copy, so bytes 440–445 in the final card
   come from the bin file, not from `buildMBR`. Do not "fix" this by
   widening the copy; that would deviate from the proved behaviour.
3. **Raw writes go through a temporary file and `dd` (Task 4).** The
   plan's Task 4 interface said the MBR is written by Swift code
   rather than by shelling to `dd`. The implementation instead writes
   the buffer to a mode-0600 temporary file and runs `dd` with an
   argument array (`DiskOperation.swift`, `writeToDevice` /
   `readFromDevice`); the same applies to the re-read. The safety
   constraint behind the plan wording — argument arrays, no shell
   interpolation, validated device paths — is satisfied and covered
   by the 15 builder tests, but the mechanism differs from the plan.
   The temporary file is deleted after each step.
4. **Disk parser lives in `BootcardCore`, not the app target
   (Task 3).** The plan allowed this; it makes the parser unit-testable.
5. **Owner-identifying strings in `docs/VERIFICATION.md` (Task 7
   fix).** Line 69 documented a grep command containing the owner's
   real name and username as literal strings. Fixed in commit
   `a0dfbba` ("docs: remove owner-identifying strings from
   verification doc"): the line now describes the check without the
   literal strings. Post-fix greps over tracked files find no name,
   username, or email literals (§4). Git author identity in
   `.git/config` is separate and was not changed.

## 4. Linux checks run for this report (exact outputs)

Run on 2026-11-05 on this Linux VM, working tree clean at HEAD
`a0dfbba`, before this report's commit. No disk was written.

### Core-math simulation

Command: `python3 scripts/simulate-core.py` — exit 0, `RESULT: ALL PASS`
(23 checks):

```text
PASS: write_length_sectors(4194304): got 8193, expected 8193
PASS: write_length_sectors(100): got 1, expected 1
PASS: write_length_sectors(0): refused (empty bin file: refused)
PASS: build_write_buffer length (1024-byte bin): got 1536, expected 1536
PASS: build_write_buffer[0]: got 171, expected 171
PASS: build_write_buffer[445]: got 171, expected 171
PASS: build_write_buffer[446]: got 128, expected 128
PASS: build_write_buffer[510]: got 85, expected 85
PASS: build_write_buffer[511]: got 170, expected 170
PASS: build_write_buffer trailing sector zeroed: got 0, expected 0
PASS: build_write_buffer last byte zeroed: got 0, expected 0
PASS: build_write_buffer length (100-byte bin): got 512, expected 512
PASS: build_write_buffer zero padding: got 0, expected 0
PASS: build_mbr length: got 512, expected 512
PASS: build_mbr boot flag: got 128, expected 128
PASS: build_mbr type: got 11, expected 11
PASS: build_mbr start LBA: got 32130, expected 32130
PASS: build_mbr signature 510: got 85, expected 85
PASS: build_mbr signature 511: got 170, expected 170
PASS: mbr disk signature: got 4039962828, expected 4039962828
PASS: validate_write rejects empty bin: got False, expected False
PASS: validate_write rejects 1 MiB disk: got False, expected False
PASS: validate_write accepts 16 GiB disk + supplied bin: got True, expected True
RESULT: ALL PASS
```

This is a Python mirror of the Swift constants. It does not run the
Swift code and proves nothing about Swift, macOS, or hardware.

### Tracked files

Command: `git ls-files | wc -l` — **24 files** (25 after this report
is committed):

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
docs/RECOVERY-NOTES.md
docs/VERIFICATION.md
docs/superpowers/plans/2026-11-05-bootcardmaker-macos.md
docs/superpowers/specs/2026-11-05-bootcardmaker-macos-design.md
docs/ui-checklist.md
scripts/build-app.sh
scripts/simulate-core.py
```

(`docs/VERIFICATION.md` §5 lists 22 files because that list was taken
at the Task 6 check, before `docs/VERIFICATION.md` and
`docs/RECOVERY-NOTES.md` themselves were committed.)

### Forbidden-content checks

- Owner name/username grep over tracked files: no matches (exit 1).
- Email-address pattern grep over tracked files: no matches (exit 1).
- `git ls-files | grep -Ei '\.(exe|bin)$'`: no matches (exit 1). No
  Windows `.exe` and no bootloader `.bin` are tracked.
- Credential-pattern grep (`password|api_key|apikey|bearer`): no
  matches after the Task 7 fix commit (the only prior match was the
  reworded line 69 itself).
- `LICENSE` exists: MIT License, copyright line "BootcardMaker for
  macOS contributors" (placeholder — see §5).

### Build script static checks

- `sh -n scripts/build-app.sh`: passes (syntax OK).
- `bash scripts/build-app.sh` on Linux: prints the banner, then exits
  1 with `Error: Command Line Tools are not installed.` and the
  `xcode-select --install` instruction, as designed. The build,
  assembly, and signing steps did not run.

### Full git log (through `a0dfbba`, before this report's commit)

```text
a0dfbba docs: remove owner-identifying strings from verification doc
c866016 docs: open-source README and verification notes
3f3000e feat: GUI window, confirmation, and dry-run mode
fd5da38 feat: privileged disk write, format, and verification
6c043d4 feat: disk enumeration with boot-disk exclusion
7887d8e feat: core sector and MBR logic with unit tests
c9dff71 docs: design and implementation plan
6135814 chore: scaffold SwiftPM repo, build script, and core simulation harness
```

## 5. Owner-gated items (nothing below has been done)

These need the owner, their Mac, or hardware. They do not block
delivery of the source, and the README says the card result is
unverified on hardware until the boot test passes.

1. **Run `swift test` on the M5 / Tahoe Mac** and record the exact
   output in `docs/VERIFICATION.md`. Expected: 31 tests (§2). If the
   executable target with no `main` blocks the run, Task 5's app
   sources resolve it; report that plainly if it happens.
2. **Run `scripts/build-app.sh` on the Mac** and record: Command Line
   Tools present or the install command used, free space at build
   time, the `.app` path produced, and whether ad-hoc signing and
   the right-click Open step work (Gatekeeper behaviour for an
   unsigned build). Confirm the Command Line Tools status that has
   been owed since the start.
3. **Run dry-run mode at each offered size** (default, 1 GiB, 4 GiB,
   16 GiB; Yes ticked and unticked at the default size), inspect
   each image (sector 0, bin bytes 0–445, bytes 446–511, zero
   padding), and record the BPB values in `docs/VERIFICATION.md` §3.
   Confirm the `hdiutil create` / `hdiutil attach` spellings work on
   Tahoe.
4. **Complete the 9 Mac-only UI checklist items** in
   `docs/ui-checklist.md` (rendering order, picker format, read-only
   field, Yes default, keyboard focus, contrast in both themes,
   reduced motion, larger text) with screenshots.
5. **Confirm elevation on Tahoe**: whether
   `AuthorizationExecuteWithPrivileges` is still present and working.
   If it is gone, replace only
   `Sources/BootcardMakerApp/PrivilegedDiskWriter.swift`.
6. **Confirm partition-node appearance**: whether the `diskNs1`
   device node appears promptly after the raw MBR write so the format
   step can address it.
7. **Physical-card test** on a spare card, then the **boot test** on
   the T95 Max Plus. Until the boot test passes, the card result is
   unverified on hardware.
8. **FAT32 comparison** against a Windows-produced card of the same
   size, made with the same bin file (BPB values, cluster size,
   label). No reference card is currently available; this stays open
   until one exists.
9. **Confirm the placeholder identifier and copyright** before any
   publication: bundle identifier `com.example.bootcardmaker` in
   `scripts/build-app.sh`, and the MIT copyright line "BootcardMaker
   for macOS contributors" in `LICENSE`. Change both in one edit
   each. Choose the public remote and push; no remote exists yet.

## 6. Bottom line

The source is complete per the plan: 7 tasks, 8 commits (through
`a0dfbba`), 24 tracked files, 31 written-but-never-run Swift tests,
and a simulation that passes 23 checks on Linux. What is proven is
narrow: the sector/MBR arithmetic in a Python mirror, the absence of
shell interpolation and forbidden content in static reads, and the
build script's preflight behaviour. What is not proven is everything
that needs a Mac or a card: compilation, tests, the build, dry-run
images, the UI, elevation, and booting a T95 Max Plus. The next step
is the owner's Mac run in §5, items 1–4.
