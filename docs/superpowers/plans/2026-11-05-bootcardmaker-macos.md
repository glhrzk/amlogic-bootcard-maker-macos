# BootcardMaker for macOS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS GUI `.app` that reproduces the Windows BootcardMaker V1.0.1 card result on an Apple M5 / macOS Tahoe Mac, from the design doc, as open-source code.

**Architecture:** Swift Package Manager repo: a Foundation-only `BootcardCore` library holding all sector/MBR math and guards (unit-tested), a thin GUI executable target holding the single window, disk enumeration, privileged write, and dry-run paths, and a `scripts/build-app.sh` that assembles the `.app` bundle from the release executable with ad-hoc signing. No Xcode project, no bundled runtime.

**Tech Stack:** Swift (SwiftPM, CLT-only build), AppKit or SwiftUI for the one window (builder's choice in Task 5), `diskutil` / `hdiutil` / `newfs_msdos` via argument-array process calls, Security framework for elevation.

**Spec:** `docs/superpowers/specs/2026-11-05-bootcardmaker-macos-design.md` — the plan argues from the spec, so the spec travels with it; executors read both. Ground truth: `~/workspace/bootcardmaker-rea/analysis/MAKE-HANDLER.md`.

## Global Constraints

- Target is arm64, macOS Tahoe only. No Intel binary, no older macOS support.
- This VM is Linux: Swift/AppKit code cannot be compiled or run here. Never claim `swift build`, `swift test`, or a macOS run passed on this VM. Linux verification is limited to the Python mirror simulation in Task 1 and to file/static checks. Real Swift tests and the build run on the owner's Mac and are owner-gated.
- Write start is byte offset 0. Write length in sectors is `(fileLength + 1) >> 9 + 1`. Zero-pad; never reproduce the original 511-byte heap over-read.
- Bytes 446–511 of the written image are copied from the live sector 0 read after partitioning/formatting (or from the existing card when Yes is unticked). Bytes 0–445 are verbatim from the bin.
- One MBR entry: type `0x0B`, boot flag 1, start 32,130 sectors (2 cylinders at 255 heads × 63 sectors/track × 512 bytes), length = total disk bytes − start, signature `0xF0CCF0CC` in both the create-disk step and the layout. Abort if the disk is smaller than start + one partition or if start is not strictly greater than the write length in sectors.
- The original Open-dialog flag quirk is not reproduced: a valid bin path selected in the file picker always writes. Make is disabled until a disk and an existing bin file are chosen.
- No shell-string construction from user input. Process calls use argument arrays only.
- English UI only. System font only. Semantic colours only; no raw hex in components.
- No copied Amlogic code, no copied binary, no secrets, no personal data in the repo. License is MIT.
- Never show success unless the write completed and re-read verification passed.

## Review Focus

- Wrong disk or boot disk offered for writing: a reasonable person expects the boot/internal disk to be impossible to select and a mistaken click to be caught by the confirmation sheet. Test in Task 3 (boot-disk exclusion with fixtures) and Task 5 (confirmation shows name, identifier, size).
- Empty or tiny bin file: a reasonable person expects an empty file to be refused, not written as a partition-table-only card. Test in Task 2 (empty bin rejected; 100-byte bin pads to 1 sector with the 66-byte copy intact).
- Card smaller than the 2-cylinder partition start, or bin longer than the gap: a reasonable person expects a clear refusal before anything is written. Test in Task 2 (guards).
- Elevation denied or disk removed mid-write: a reasonable person expects failure, no success message, and an honest statement of the state left behind. Test in Task 4 (argument/error handling; real-device behaviour is owner-gated).
- FAT32 format differs from the Windows card: a reasonable person expects the difference to be labelled unverified, with BPB values recorded, not claimed equivalent. Test in Task 4/6 (BPB recording in dry-run verification; README states unverified).

---

### Task 1: Repo scaffold, build script, and core-math simulation harness

**Files:**
- Create: `Package.swift`
- Create: `scripts/build-app.sh`
- Create: `scripts/simulate-core.py`
- Create: `LICENSE` (MIT text, copyright holder: the owner, name to be confirmed in one edit before publishing — use `BootcardMaker for macOS contributors` as the placeholder line and flag it in the commit message)
- Create: `.gitignore`
- Create: `README.md` (skeleton: purpose, safety warning, build steps, known limits — completed in Task 6)
- Test: `scripts/simulate-core.py` self-checks (run on Linux)

**Interfaces:**
- Consumes: design doc constraints above.
- Produces: `scripts/build-app.sh` (preflight + `swift build -c release` + `.app` assembly + ad-hoc codesign, best-effort with warnings); `scripts/simulate-core.py` (mirrors Task 2 constants; used only as a Linux simulation, never as proof of Swift behaviour).

- [ ] **Step 1: Write the failing check**

```bash
ls Package.swift scripts/build-app.sh scripts/simulate-core.py LICENSE .gitignore README.md
```

Expected: files missing.

- [ ] **Step 2: Create `Package.swift`**

Declare a library target `BootcardCore`, an executable target `BootcardMakerApp` depending on it, and a test target `BootcardCoreTests`. Swift tools 5.9, platforms macOS 14. No external dependencies.

- [ ] **Step 3: Create `scripts/build-app.sh`**

Preflight: fail with a plain message and the exact install command if `xcode-select -p` fails or `swift --version` fails; warn and continue if free space is under 500 MB. Run `swift build -c release`, copy the executable into `dist/BootcardMaker.app/Contents/MacOS/BootcardMaker`, write `Info.plist` with `CFBundleExecutable=BootcardMaker`, `CFBundleIdentifier=com.example.bootcardmaker` (flagged as a placeholder the owner changes before publishing), `CFBundleName=BootcardMaker`, `LSMinimumSystemVersion=14.0`, then `codesign --force --deep -s -` best-effort (warn, do not fail the build, if signing fails). Print the `.app` path and the right-click Open step for an unsigned build.

- [ ] **Step 4: Create `scripts/simulate-core.py`**

Mirror the constants from Task 2 (sector 512, start 32130, signature `0xF0CCF0CC`, length formula, 66-byte copy at 446). Self-check: for file length 4,194,304 it must output 8,193 sectors; for 100 it must output 1 sector; for 0 it must output the empty-bin refusal. Run it on this VM and record the output in the step result.

- [ ] **Step 5: Create `LICENSE`, `.gitignore`, and the README skeleton**

`.gitignore` covers `.build/`, `dist/`, `*.app`, and macOS artefacts. README skeleton states the purpose, the safety warning, and that macOS verification is owner-gated.

- [ ] **Step 6: Commit**

```bash
git add Package.swift scripts LICENSE .gitignore README.md
git commit -m "chore: scaffold SwiftPM repo, build script, and core simulation harness"
```

### Task 2: Core sector and MBR logic with unit tests

**Files:**
- Create: `Sources/BootcardCore/CoreLogic.swift`
- Test: `Tests/BootcardCoreTests/CoreLogicTests.swift`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces:
  - `public func writeLengthSectors(fileLength: Int) -> Int` — `(fileLength + 1) >> 9 + 1`, precondition `fileLength > 0`.
  - `public func buildWriteBuffer(bin: Data, liveSector0: Data) -> Data` — length `writeLengthSectors(bin.count) * 512`, bin bytes copied verbatim, zero padding, bytes 446–511 replaced from `liveSector0` (precondition: both inputs are at least 512 bytes for `liveSector0`; `bin` may be shorter and is padded).
  - `public func buildMBR(totalBytes: Int64, startSectors: Int64, partitionLengthBytes: Int64) -> Data` — 512 bytes, one entry type `0x0B`, boot flag 1, start and length fields little-endian, signature bytes 510–511 `0x55 0xAA`, disk signature `0xF0CCF0CC` returned separately by `public let mbrDiskSignature: UInt32 = 0xF0CCF0CC`.
  - `public let partitionStartSectors: Int64 = 32130`
  - `public func validateWrite(diskTotalBytes: Int64, fileLength: Int) -> Bool` — false when `fileLength <= 0`, when `diskTotalBytes < (partitionStartSectors + 1) * 512`, or when `partitionStartSectors <= writeLengthSectors(fileLength)`.

- [ ] **Step 1: Write the failing tests**

```swift
func testWriteLengthForSuppliedBin() {
    XCTAssertEqual(writeLengthSectors(fileLength: 4194304), 8193)
}
func testWriteLengthForTinyBin() {
    XCTAssertEqual(writeLengthSectors(fileLength: 100), 1)
}
func testBuildWriteBufferPreservesMBRFromLiveSector() {
    let bin = Data(repeating: 0xAB, count: 1024)
    var sector0 = Data(repeating: 0, count: 512)
    sector0[446] = 0x80; sector0[510] = 0x55; sector0[511] = 0xAA
    let out = buildWriteBuffer(bin: bin, liveSector0: sector0)
    XCTAssertEqual(out.count, 1536) // (1024 + 1) >> 9 + 1 = 3 sectors; corrected 2026-11-05, plan originally said 1024
    XCTAssertEqual(out[0], 0xAB); XCTAssertEqual(out[445], 0xAB)
    XCTAssertEqual(out[446], 0x80); XCTAssertEqual(out[510], 0x55); XCTAssertEqual(out[511], 0xAA)
    XCTAssertEqual(out[1024], 0); XCTAssertEqual(out[1535], 0) // trailing sector zero-padded
}
func testBuildMBREntry() {
    let mbr = buildMBR(totalBytes: 16 * 1024 * 1024 * 1024, startSectors: 32130, partitionLengthBytes: 16 * 1024 * 1024 * 1024 - 32130 * 512)
    XCTAssertEqual(mbr.count, 512)
    XCTAssertEqual(mbr[446], 0x80); XCTAssertEqual(mbr[450], 0x0B)
    XCTAssertEqual(mbr[510], 0x55); XCTAssertEqual(mbr[511], 0xAA)
}
func testValidateRejectsEmptyBinAndSmallDisk() {
    XCTAssertFalse(validateWrite(diskTotalBytes: 16 * 1024 * 1024 * 1024, fileLength: 0))
    XCTAssertFalse(validateWrite(diskTotalBytes: 1024 * 1024, fileLength: 4194304))
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test` (on the owner's Mac; on this Linux VM record that Swift is unavailable and the failure is the missing implementation, verified by the Task 1 simulation instead). Expected: FAIL, symbols not defined.

- [ ] **Step 3: Implement `CoreLogic.swift`**

Pure Foundation only. No file or disk access. Zero-pad with `Data(count:)`. Little-endian fields with explicit byte writes, no struct packing assumptions.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test` on the Mac and record the output. On this VM, run `scripts/simulate-core.py` and confirm its outputs match the Swift test expectations above; state in the commit message that Swift tests are Mac-gated.

- [ ] **Step 5: Commit**

```bash
git add Sources/BootcardCore Tests/BootcardCoreTests
git commit -m "feat: core sector and MBR logic with unit tests"
```

### Task 3: Disk enumeration (whole disks only, boot disk excluded)

**Files:**
- Create: `Sources/BootcardMakerApp/DiskEnumeration.swift`
- Create: `Tests/BootcardCoreTests/DiskEnumerationTests.swift` (fixture-driven parsing tests; put the parser in `BootcardCore` if the GUI target cannot be tested — builder's choice, but the parser itself must be unit-tested)
- Create: `Tests/BootcardCoreTests/Fixtures/diskutil-list-sample.plist` (synthetic fixture, labelled as such, with one internal boot disk, one external USB disk, and one built-in-reader disk reported internal)

**Interfaces:**
- Consumes: `BootcardCore` guards from Task 2.
- Produces:
  - `public struct DiskInfo: Equatable { public let identifier: String; public let name: String; public let sizeBytes: Int64; public let isRemovable: Bool; public let isExternal: Bool; public let protocolName: String }`
  - `public func parseDiskList(_ plistData: Data) throws -> [DiskInfo]`
  - `public func selectableDisks(all: [DiskInfo], bootDiskIdentifier: String) -> [DiskInfo]` — whole disks only (identifier has no `s` partition suffix, e.g. `disk2` not `disk2s1`), boot disk excluded, sorted removable/external first, then by identifier.

- [ ] **Step 1: Write the failing tests**

Tests assert: the fixture yields 3 disks; `selectableDisks` excludes the boot disk and both partition entries; the built-in-reader disk (internal flag, removable) is included with its flags visible; sorting puts removable/external first.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter DiskEnumeration` on the Mac (Linux: record unavailable). Expected: FAIL.

- [ ] **Step 3: Implement enumeration**

Parse `diskutil list -plist` output with `PropertyListDecoder`. Never invoke `diskutil` with user-supplied arguments beyond the fixed `list -plist` arguments. The live `diskutil` call itself lives in a small `DiskListProvider` in the app target; only the parser is tested.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter DiskEnumeration` on the Mac. Record output.

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "feat: disk enumeration with boot-disk exclusion"
```

### Task 4: Privileged write, partition, format, and verification

**Files:**
- Create: `Sources/BootcardMakerApp/PrivilegedDiskWriter.swift`
- Create: `Sources/BootcardMakerApp/DiskOperation.swift` (orchestration: validate → unmount → partition MBR → format → read sector 0 → build buffer → write → re-read verify; each step returns a named error, no step is skipped on error)

**Interfaces:**
- Consumes: `BootcardCore` (Task 2), `DiskInfo` (Task 3).
- Produces:
  - `public enum DiskOperationError: Error { case elevationDenied, diskDisappeared, unmountFailed, partitionFailed, formatFailed, readFailed, writeFailed, verificationFailed, invalidInput }`
  - `public func makeDiskOperation(disk: DiskInfo, bin: Data, partitionAndFormat: Bool, dryRunDevice: String?) async throws -> Void` — dry-run uses the attached image device node; physical mode uses `/dev/rdiskN`. Elevation is obtained once per operation; every external command uses an argument array; the MBR is written by the Swift code (not by shelling to `dd` with user input); formatting uses `newfs_msdos -F 32` on the partition device; verification re-reads the written sectors and compares bytes 0–445 and 446–511 against the expected buffer.

- [ ] **Step 1: Write the failing checks**

A test asserting the argument arrays for `diskutil unmountDisk`, `newfs_msdos -F 32`, and `hdiutil attach -nomount` contain no interpolated user input (fixed templates with the device node as a single argument). On the Mac these run as unit tests over the command-builder functions; on Linux they are reviewed statically and recorded as such.

- [ ] **Step 2: Run the checks to verify they fail**

Expected: FAIL, functions not defined.

- [ ] **Step 3: Implement the operation**

Order: validate (Task 2 guards) → elevation → unmount whole disk → if partitionAndFormat: write MBR via the core builder through the raw device, then format the partition → read live sector 0 → build buffer → write buffer from offset 0 → fsync/close → re-read and compare → report success only on match. If partitionAndFormat is false: skip MBR/format, read the existing sector 0, then write and verify. Any error aborts with the named error; no partial success is reported.

- [ ] **Step 4: Verify**

On the Mac: dry-run image test (Task 5) exercises this path. On this VM: no disk is ever written; record the static argument-array review in the commit message.

- [ ] **Step 5: Commit**

```bash
git add Sources/BootcardMakerApp
git commit -m "feat: privileged disk write, format, and verification"
```

### Task 5: GUI window, confirmation sheet, progress, and dry-run mode

**Files:**
- Create: `Sources/BootcardMakerApp/App.swift` (entry point)
- Create: `Sources/BootcardMakerApp/MainView.swift` (or AppKit equivalents — builder's choice, one window)
- Create: `Sources/BootcardMakerApp/DryRun.swift` (sparse image creation, `hdiutil attach -nomount`, detach; same core path as Task 4)

**Interfaces:**
- Consumes: Tasks 2–4.
- Produces: a single window implementing the design-doc layout (§UI design), the confirmation sheet, progress/disabled states, status/error text, and a dry-run toggle with image-size choice (1 GiB / 4 GiB / 16 GiB sparse, default partition start + 64 MiB).

- [ ] **Step 1: Write the UI checklist as a testable review**

Create `docs/ui-checklist.md` from the design doc: every control labelled, Make disabled until valid, confirmation shows name/identifier/size/bin, focus visible, contrast checked in both themes, reduced motion and larger text checked. The implementer checks each item by inspection on the Mac and records the result; on this VM the checklist is written but marked unchecked.

- [ ] **Step 2: Implement the window**

Follow the design-doc layout order exactly. No icon-only buttons, no emoji icons, system font, semantic colours. The Open button uses the system file picker (single file). The Yes checkbox defaults to ticked with the unticked note shown. The confirmation sheet is the only confirmation step.

- [ ] **Step 3: Implement dry-run mode**

Dry-run creates the sparse image, attaches it, runs `makeDiskOperation` with the attached node, detaches, and leaves the image file for inspection. Dry-run needs no elevation for a user-owned image; if elevation is requested in dry-run mode, that is a bug.

- [ ] **Step 4: Verify on the Mac**

Owner run: build with `scripts/build-app.sh`, open the app, run dry-run at each offered size, inspect the image (sector 0, bin bytes, BPB), and record screenshots. On this VM: record that the GUI cannot be run here.

- [ ] **Step 5: Commit**

```bash
git add Sources/BootcardMakerApp docs/ui-checklist.md
git commit -m "feat: GUI window, confirmation, and dry-run mode"
```

### Task 6: Open-source readiness and README

**Files:**
- Modify: `README.md`
- Create: `docs/VERIFICATION.md` (what was verified where, what is Mac-gated, BPB values from dry-run, FAT32 unverified label)
- Create: `docs/RECOVERY-NOTES.md` (what the REA report proved, with the report path; no Windows binary or bin file in the repo)

**Interfaces:**
- Consumes: Tasks 1–5.
- Produces: a README a stranger can follow: what the tool does, the safety warning, build steps (CLT only), run steps (including right-click Open for an unsigned build), dry-run steps, how to report a wrong-disk or format difference, and the known limits. `docs/VERIFICATION.md` must state plainly which claims are Linux-verified (simulation), which are Mac-verified (with evidence), and which are unverified (FAT32 equivalence, hardware boot).

- [ ] **Step 1: Write the README and verification docs**

Include the MIT license note and the placeholder identifier/copyright lines flagged for the owner to confirm before publishing. State that the supplied `.bin` and the Windows `.exe` are not in the repo and must never be committed.

- [ ] **Step 2: Check the repo for forbidden content**

Run: `git ls-files` and confirm no `.exe`, `.bin`, secret, or personal data is tracked; confirm `LICENSE` exists. Record the file list in the commit message.

- [ ] **Step 3: Commit**

```bash
git add README.md docs LICENSE
git commit -m "docs: open-source README and verification notes"
```

### Task 7: Final verification report

**Files:**
- Create: `docs/FINAL-REPORT.md`

**Interfaces:**
- Consumes: Tasks 1–6 and the owner's Mac run evidence, if available.
- Produces: a report listing every design requirement, the task that implements it, the verification evidence (or the Mac-gated status), and the remaining owner-gated items (physical card, boot test, FAT32 comparison, CLT/Gatekeeper confirmation).

- [ ] **Step 1: Assemble the report from the task evidence**

Do not invent Mac evidence. Anything not run on a Mac is labelled Mac-gated.

- [ ] **Step 2: Run every check available on the current machine and record the results**

`scripts/simulate-core.py`, file-list check, README/licence presence. Record exact outputs.

- [ ] **Step 3: Commit**

```bash
git add docs/FINAL-REPORT.md
git commit -m "docs: final verification report"
```

## Self-Review

- Spec coverage: every design section maps to a task (UI → Task 5, core math → Task 2, enumeration → Task 3, privileged write → Task 4, dry-run → Tasks 4–5, open source → Task 6, verification → Task 7). The builder-check resolutions are in the design doc and reflected in Tasks 3–5.
- Step scan: each step names one action with a checkable result; Linux-unavailable steps state the Mac-gated alternative instead of pretending.
- Type consistency: `writeLengthSectors`, `buildWriteBuffer`, `buildMBR`, `validateWrite`, `DiskInfo`, `DiskOperationError` are named once here and reused by later tasks.
- Review Focus: each of the five failure modes has a test or a named verification step in its owning task.
- Proportion: the plan is shorter than the design doc and carries no function bodies beyond the test assertions that pin the REA values.
