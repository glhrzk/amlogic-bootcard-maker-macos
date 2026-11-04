# BootcardMaker for macOS — Design

Date: 2026-11-05. Owner: Galih Rizki. Target machine: Mac with Apple M5,
macOS Tahoe, arm64 only. No Windows, no VM (Mac disk full). Code will be
open-sourced later; no remote is known yet, so the code lives in a new
local git repo at `~/workspace/bootcardmaker-macos/` and is not pushed
anywhere.

## Intent and why

Recreate the result of the Windows tool BootcardMaker V1.0.1-130918_Beta
(SDcardMaker 1.0.0.2, MFC 32-bit, 2013) on macOS: choose a disk, choose
one bootloader `.bin` file, optionally partition and format the card,
then write the bin to the card so an Amlogic S905X3 T95 Max Plus box can
boot from it. The Windows tool cannot run on macOS, and a VM is ruled
out by disk space. The port must produce a card byte-equivalent to the
Windows result for the same bin and the same Yes/No choice, within the
limits stated below.

## Ground truth (REA, verified on disk)

Report: `~/workspace/bootcardmaker-rea/analysis/MAKE-HANDLER.md`.
Evidence: Ghidra decompilations of the Make handler (RVA `0x3800`) and
the partition helper (RVA `0x3020`); assembly agrees. Constants below
were spot-checked against the binary (IOCTL values and the
`0xF0CCF0CC` signature each appear at the expected places).

Make handler order, bin chosen through Open (branch B):
1. Partition helper, if Yes is ticked. On failure, show
   `fail to partition the disk` and stop.
2. Show `Partition has been finished,start to format the disk!`.
3. Find the first SD/MMC-type drive letter on that physical disk.
4. `SHFormatDrive(hwnd, driveIndex, 0xFFFF, 1)`. Return −1/−2/−3 stops
   with a message; any other value continues.
5. Read sector 0 of the disk (512 bytes).
6. Read the whole bin file (read-only, no size or format check).
7. Copy bytes 446–511 (66 bytes: MBR partition entries + signature)
   from the live sector 0 over the same offsets in the bin image.
8. Write the buffer to the disk from byte offset 0 in one write, length
   `(fileLength + 1) >> 9 + 1` sectors. Show `Success!`.

If Yes is not ticked, steps 5–8 only. If no bin was chosen through the
Open dialog, the original only partitions/formats and never writes the
bin, even if a path was typed by hand. That is a quirk; the port must
not reproduce it.

Partition helper: zero sector 0; `IOCTL_DISK_CREATE_DISK` (MBR style,
signature `0xF0CCF0CC`, remaining struct bytes zeroed — the original
left bytes 8–23 uninitialised; the port must zero them);
`IOCTL_DISK_UPDATE_PROPERTIES`; geometry query; one MBR entry, type
`0x0B` (FAT32), boot flag 1, start = 2 cylinders
(`2 × SectorsPerTrack × TracksPerCylinder × BytesPerSector`), length =
total disk bytes − start, entries 1–3 deleted (RewritePartition only);
`IOCTL_DISK_SET_DRIVE_LAYOUT_EX`; update properties again; sleep 300 ms.

The bin write has no other special handling: bytes 0–445 verbatim, no
442-byte handling, no `aml_sdc_burn.ini`, no extra file, no read-back
verification, no progress, no cancellation. The supplied bin is opaque
(4,194,304 bytes, sector 0 zero, data 0x200–0x1b67ff, entropy 8.0):
copy it verbatim except for the 66-byte partition-table overwrite.

## Goals

- One native macOS `.app` window that mirrors the Windows dialog:
  Choose disk, Choose your bin file (Open button), To Partition and
  Format SD-card: Yes checkbox, Make button. English UI only.
- Same on-disk result as Windows for the same inputs: same MBR entry
  (type `0x0B`, boot flag, 2-cylinder start, signature `0xF0CCF0CC`),
  same FAT32 format, same bin bytes from offset 0 with bytes 446–511
  taken from the live sector 0 after partitioning/formatting.
- Zero-padded write: exactly the file length rounded up to whole
  512-byte sectors per the formula above, with zeros — never the
  original's 511-byte heap over-read past the allocation.
- Wrong-disk protection stronger than the original: list only
  external whole disks, never the boot/internal disk; show disk name,
  identifier, and size at selection and again on a confirmation sheet;
  require an explicit confirmation before any write; abort fail-closed
  on any error with a plain message. Never show `Success!` unless the
  write completed and was verified by re-reading.
- Dry-run mode: write to a regular disk-image file instead of a disk,
  so the result can be inspected byte by byte on the Mac without
  risking a card.
- Small footprint: no VM, no Wine, no Electron, no bundled runtime
  beyond what macOS Tahoe already provides. Buildable on the owner's
  Mac with Command Line Tools only (no full Xcode install required).
- Open-source ready: clean-room rewrite (no copied Amlogic code, no
  copied binary), MIT license, README with build/run/test steps,
  safety warnings, and the known limits below. No secrets, no personal
  data, no test accounts in the repo.

## Non-goals

- No Burn Card Maker v2 behaviour: no erase_bootloader / erase_flash /
  reboot options, no `.img` package handling, no `aml_sdc_burn.ini`.
- No USB Burning Tool behaviour, no flashing over USB, no eMMC install.
- No support for Intel Macs, older macOS versions, or Windows/Linux.
- No automatic card detection loop, no background service, no update
  mechanism, no telemetry.
- No attempt to parse, decrypt, or modify the bin file contents beyond
  the 66-byte partition-table overwrite.

## Anti-goals (a failure even if it technically works)

- Writing to the boot disk, an internal disk, or a disk the user did
  not confirm by name, identifier, and size.
- A card that looks formatted but does not boot because the partition
  start is inside the written bin image, or because the MBR table was
  not preserved from the live sector 0.
- Silent partial success: formatting done but bin not written (or the
  reverse) reported as success.
- A `.app` that only builds with a paid developer account, full Xcode,
  or a multi-gigabyte download on a disk that is already full.
- Claiming macOS verification without evidence from a Mac.

## Constraints

- This VM is Linux. No macOS SDK, no Xcode, no Mac hardware here. The
  Swift/AppKit code cannot be compiled or run here. Verification on
  macOS is the owner's run on their Mac, plus the dry-run image checks
  in the plan. Never claim a macOS build passed here.
- Target: arm64, macOS Tahoe, Swift with AppKit or SwiftUI (builder's
  choice, one window, one codebase). System font only (SF Pro); do not
  bundle Google Fonts. Semantic system colours so light and dark mode
  both work; destructive Make action in the system red, with a
  confirmation sheet.
- Raw disk access on macOS needs admin rights. The GUI must obtain
  elevation once per Make operation through a supported Security
  framework path available on Tahoe, and fail loudly with a plain
  message if elevation is unavailable. The privileged surface is
  exactly: unmount the chosen disk, write the MBR/bin, format the
  partition. No shell-string construction from user input: use
  argument arrays only, never interpolate paths into a shell command.
- Partition start: use legacy geometry 255 heads × 63 sectors/track ×
  512 bytes, so start = 32,130 sectors (16,450,560 bytes). Abort if
  the disk is smaller than start + one partition, or if the computed
  start is not strictly greater than the bin write length in sectors;
  never silently move the partition start to fit a small disk.
- FAT32 format parameters are not recoverable from the exe beyond
  `SHFormatDrive` defaults (`fmtID 0xFFFF`, full format). Port choice:
  FAT32 via `newfs_msdos -F 32` (or the `diskutil` equivalent) on the
  partition device, default cluster size, no volume label unless the
  tool requires one (then the FAT default). This choice must be
  verified against a Windows-produced card; until then it is labelled
  unverified in the README.
- MBR signature `0xF0CCF0CC` must be written in both the create-disk
  step and the layout, exactly as the original.
- The 66-byte copy must read sector 0 after partitioning/formatting
  (Yes ticked) or from the existing card (Yes unticked), never from a
  cached or assumed table.
- UI copy is English only. Error messages name the step that failed
  and the next safe action. The Windows messages above are behaviour
  references, not copy to reuse verbatim except `Success!` semantics:
  show success only after verification.
- ui-ux-pro-max is the UI rulebook for this design (see below). Its
  design-system search for this tool returned a landing-page pattern
  (Hero + Features) that does not fit a single-window utility; that
  pattern is rejected. Its SwiftUI stack search returned no match;
  stack guidance below is general default, labelled as such. The
  `pro-rules.md` checklist is mobile/native scoped: apply its
  contrast, labelling, focus-order, and disabled-state checks, adapted
  to a mouse-driven desktop window; do not apply 44pt touch targets
  literally.

## UI design (ui-ux-pro-max)

Style: Minimalism & Swiss Style (from the design-system search):
clean, spacious, functional, clear type hierarchy, sharp or no shadows,
subtle transitions only. Density: spacious. Motion: subtle; respect
reduced motion (no animation needed beyond progress feedback).
Colours (tokens from the search, as semantic roles, not raw hex in
components): primary navy `#1E3A5F`, background `#F8FAFC`, foreground
`#0F172A`, card white, border `#E4E7EB`, destructive `#DC2626` with
white text, focus ring visible. Text contrast at least 4.5:1 for body
text in both light and dark mode; verify, do not assume.

Window layout, one window, top to bottom:
1. Title `BootcardMaker` with a one-line plain description of what it
   does and that it erases the chosen disk.
2. `Choose disk:` labelled pop-up button listing external whole disks
   as `Name — size (diskN)`. No disk selected by default. A disk that
   disappears is removed and selection is cleared.
3. `Choose your bin file:` read-only text field showing the chosen
   path, plus an `Open…` button opening a file picker (single file,
   any extension; the original filter was `*.bin`). Make is disabled
   until a disk and an existing bin file are both chosen.
4. `To Partition and Format SD-card:` with a `Yes` checkbox, ticked by
   default (matching the tutorial flow). When unticked, show a short
   note: the existing partition table is kept and only the bin is
   written.
5. `Make` primary destructive button, disabled until inputs are valid.
   Below it, a status line: idle, working with progress, success, or
   error text next to the field it concerns.
6. Confirmation sheet on Make: disk name, identifier, size; bin file
   name and size; partition/format choice; a warning that the disk
   will be erased; Cancel and `Erase and Make` buttons. The sheet is
   the only confirmation step.
7. Progress: indeterminate or determinate progress while writing,
   controls disabled, no cancellation mid-write (matching the
   original; state this in the UI so the user does not pull the card).
   On finish: `Success!` only after re-read verification; on error: a
   plain message naming the failed step, with the disk left in the
   state that step left it (state this honestly, do not claim a
   rollback).
8. Keyboard: full keyboard access, visible focus, labels on every
   control, no icon-only buttons, no emoji icons. Reduced-motion and
   larger system text must not break the layout.

## Parts decided by the owner

- GUI `.app` like Windows, not CLI-first.
- Same result as Windows, no VM.
- Mac M5, macOS Tahoe, arm64 only.
- Proceed autonomously once REA results exist (owner sleeping).
- Open-source the code later.
- UI via ui-ux-pro-max.

## Left to the builder

- AppKit vs SwiftUI, and the exact elevation API on Tahoe, within the
  constraints above.
- Exact disk enumeration API (`diskutil` parsing vs DiskArbitration /
  IOKit), as long as only external whole disks are listed and the boot
  disk is excluded.
- File layout and target split (app target + testable core), as long
  as the sector/MBR math is unit-tested.
- Whether the dry-run image mode lives in the same app (preferred) or
  as a separate build flag; the user-facing behaviour must be the
  same either way.
- README wording and screenshots, as long as the known limits are
  stated honestly.
- License file text: MIT (owner may change it in one edit before
  publishing).

## Builder-check resolutions (builder calls, owner may correct in one pass)

The builder check returned five questions. The owner is asleep and
authorised autonomous work, so each is settled here as a builder call
with a fail-safe default. Correct any of them and the plan follows.

1. Card enumeration on the owner's Mac is unknown. Call: list all
   whole disks except the boot disk, sorted with removable/external
   first, showing name, identifier, size, and protocol/removable
   flags from `diskutil`. Do not filter to "external only", so a
   built-in reader reporting a card as internal still lists it, with
   its flags visible. The confirmation sheet and the boot-disk
   exclusion are the safety net, not the external flag.
2. Build environment is unknown (CLT, Swift version, free space,
   Gatekeeper). Call: the build script preflights `xcode-select -p`,
   `swift --version`, and free space, and stops with a plain message
   and the exact install command if CLT is missing. No paid developer
   account is assumed; ad-hoc sign the bundle and document the
   right-click Open step for an unsigned open-source build. No step
   in the plan assumes a signed or notarised app.
3. Dry-run semantics. Call: dry-run creates a sparse image file at a
   size the user chooses (default: partition start + 64 MiB, offered
   sizes 1 GiB / 4 GiB / 16 GiB as sparse files, so disk-full cost is
   only the bytes written), attaches it with `hdiutil attach
   -nomount`, and runs the same partition, format, and write code
   path through the attached device node, then detaches. Dry-run
   needs no admin elevation for a user-owned image. Verification
   inspects the resulting image file.
4. No Windows-produced reference card is assumed available. Call: the
   comparison task is re-scoped to defined BPB/cluster-size
   acceptance criteria recorded from the dry-run image, plus the
   owner boot test. Card sizes supported: any disk larger than the
   partition start plus the written image; test fixtures use 1 GiB,
   4 GiB, and 16 GiB sparse images.
5. Hardware verification availability is unknown. Call: physical-card
   and boot tests are owner-gated deferred tasks. They do not block
   delivery of the source; the README states the card result is
   unverified on hardware until they pass.

## Verification (what counts as done)

- Unit tests for: write length formula (including the 4,194,304-byte
  case = 8,193 sectors with zero padding), 66-byte overwrite offsets,
  MBR entry fields (type, boot flag, start, length, signature),
  start-greater-than-write-length guard, and the no-bin-no-write
  rule (Make disabled without a bin; the original quirk is not
  reproduced).
- Dry-run image test on the Mac: build an image with Yes ticked and
  with Yes unticked, inspect sector 0 (partition table, signature),
  confirm bin bytes 0–445 verbatim, bytes 446–511 equal to the image's
  live table, and bytes after the bin are zero to the end of the
  written length.
- Physical-card test by the owner on a spare card, then a boot test
  on the T95 Max Plus. Until that boot test passes, the README must
  say the card result is unverified on hardware.
- FAT32 format equivalence vs a Windows-produced card: open item,
  labelled unverified until compared.
- Pre-delivery UI pass against the ui-ux-pro-max checks in this
  document (contrast in both themes, keyboard/focus, labels, disabled
  states, reduced motion, larger text).
