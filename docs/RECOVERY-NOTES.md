# Recovery notes — what the Windows program actually does

These notes summarise what reverse engineering proved about the
Windows tool BootcardMaker V1.0.1-130918_Beta (SDcardMaker 1.0.0.2,
MFC 32-bit, 2013), and what this macOS port takes from it. The full
evidence is the REA report:

`~/workspace/bootcardmaker-rea/analysis/MAKE-HANDLER.md`

That report is outside this repo. It is based on Ghidra decompilation
of the Make button handler (RVA `0x3800`) and the partition helper
(RVA `0x3020`), corroborated by Capstone/objdump disassembly. Nothing
in the report is taken from the supplied `.bin` file or from Burn Card
Maker v2 tutorials. No code was executed and no disk was written
during the analysis; the behaviour below is proven from code, not from
an observed card.

## What was proved

### The Make handler

The Make button (control 1006) runs one handler. It reads the disk
selection from combobox 1002 (`GetCurSel() + 1` as the PhysicalDrive
number), the Yes checkbox (control 1018), the bin path from edit
control 1004, and a dialog flag that records whether the bin file was
chosen through the Open button. With a bin file chosen and Yes ticked,
the order is:

1. Partition the disk (partition helper, below). On failure, show
   `fail to partition the disk` and stop.
2. Show `Partition has been finished,start to format the disk!`.
3. Find the first SD/MMC-type drive letter on that physical disk
   (enumeration helper, below).
4. Call `SHFormatDrive(hwnd, driveIndex, 0xFFFF, 1)`. Return values
   −1, −2, and −3 stop with a message; any other value continues.
5. Read sector 0 of the disk (512 bytes).
6. Read the whole bin file, read-only. No size or format check.
7. Copy bytes 446–511 (66 bytes) from the live sector 0 over the same
   offsets in the in-memory bin image.
8. Write the buffer to the disk from byte offset 0 in a single write,
   length `(fileLength + 1) >> 9 + 1` sectors. Show `Success!`.

With Yes unticked, only steps 5–8 run: the existing partition table
is preserved into the image and no partition or format happens.

### The bin write

- Write start: byte offset 0 (sector 0). One `WriteFile` call, no
  chunking.
- Write length: `(fileLength + 1) >> 9 + 1` sectors. For the supplied
  4,194,304-byte bin file that is 8,193 sectors (4,194,816 bytes).
  The original buffer held only `fileLength + 1` bytes, so the last
  sector was read 511 bytes past the end of the allocation — a heap
  over-read by construction. This port writes exactly the file length
  rounded up to whole sectors, zero-padded, and never over-reads.
- The only special handling is the 66-byte copy at offsets 446–511:
  the four 16-byte MBR partition entries (446–509) plus the 2-byte
  boot signature (510–511), taken from the live sector 0. Bytes 0–445
  are the bin file verbatim. There is no 442-byte handling and no
  other modification of the first sector.
- No verification or read-back after the write. The only check is the
  write helper's return value, and the `WriteFile` return value itself
  is not checked. This port adds re-read verification and only then
  reports success.
- No extra file is written. No `.ini` file and no other file is
  created on the card on the Make path. The `GetPrivateProfile*` /
  `WritePrivateProfileStringA` imports belong to dialog and language
  code, not to this path.

### The partition helper

In order: zero sector 0; `IOCTL_DISK_CREATE_DISK` with MBR partition
style and disk signature `0xF0CCF0CC`; `IOCTL_DISK_UPDATE_PROPERTIES`;
geometry query (`IOCTL_DISK_GET_DRIVE_GEOMETRY`); build a
`DRIVE_LAYOUT_INFORMATION_EX` with one entry and three deleted
entries; `IOCTL_DISK_SET_DRIVE_LAYOUT_EX`;
`IOCTL_DISK_UPDATE_PROPERTIES` again; sleep 300 ms.

The single entry: partition style MBR, partition number 1, rewrite
flag set, MBR partition type `0x0B` (FAT32), boot indicator 1,
recognised partition 1, hidden sectors 0, starting offset 2 cylinders
(`2 × SectorsPerTrack × TracksPerCylinder × BytesPerSector`), length
equal to total disk bytes minus that start. Entries 1–3 carry only
the rewrite flag and are otherwise zero (deleted). The `0x0B` type
byte is the only FAT32 marker the program itself writes; the FAT32
filesystem is created by `SHFormatDrive`, not by this helper.

The original left bytes 8–23 of the 24-byte `CREATE_DISK` input
struct uninitialised (stack contents). This port zeroes them.

### The format call

`SHFormatDrive(hwnd, driveIndex, fmtID = 0xFFFF, options = 1)`:
`SHFMT_ID_DEFAULT` and `SHFMT_OPT_FULL`. The program passes no
filesystem name, cluster size, volume label, or quick-format choice.
The format parameters are whatever `SHFormatDrive`'s default does for
the media. They cannot be recovered from the program beyond `fmtID`
and `options`. This port uses `newfs_msdos -F 32` with default
settings as the equivalent, and labels FAT32 equivalence unverified
until a Windows-made card is compared. See `docs/VERIFICATION.md`.

### Drive enumeration (the original wrong-disk guard)

For each drive letter, the program keeps the drive only if its device
number matches the selected PhysicalDrive number, its drive type is
not CDROM, and its bus type is SD (12), MMC (13), or 16 and above
(not Unknown, and not 1–11, 14, or 15). That filter plus the user's
combobox selection is the whole guard. There is no confirmation
dialog, no size check, and no re-verification that the selected disk
is still the same disk. This port lists whole disks, excludes the boot
disk, and adds a confirmation sheet; see the design document.

## Quirks that were proved and are NOT reproduced

1. **The Open-dialog flag.** If no bin file was chosen through the
   Open button, the original only partitions and formats and never
   writes the bin — even if a path was typed into the edit box by
   hand. If Yes was unticked it showed `Please choose your bin
   files!` instead. This port writes whenever a valid bin file is
   chosen, however it was chosen.
2. **The heap over-read.** The write length formula reads 511 bytes
   past the allocation on the last sector. This port zero-pads.
3. **The failed-open read.** If opening the disk failed, the sector-0
   read helper showed an error but still called read on the invalid
   handle and returned an uninitialised buffer. This port fails
   closed on any failed open or read.
4. **The geometry check that cannot catch failure.** The geometry
   helper returns the `DeviceIoControl` boolean, which is 0 on
   failure, but the caller tests for `== −1`, so a failed geometry
   query would proceed with an uninitialised buffer. This port
   treats any failed geometry-equivalent input as an error before
   anything is written.
5. **Uninitialised `CREATE_DISK` bytes.** See the partition helper
   above. This port zeroes the struct.

## What was NOT proved

- The exact FAT32 parameters `SHFormatDrive` applies (cluster size,
  FAT type, label). Not recoverable from the program.
- Whether the original tool was ever run against the supplied
  4,194,304-byte `.bin` on a real card. No execution was performed.
- Behaviour for a bin file shorter than 512 bytes. No minimum-size
  check was observed; the length formula and the 66-byte copy apply
  regardless. This port refuses an empty bin file and zero-pads
  shorter ones.
- The exact combobox item-text order. Immaterial to the write
  behaviour.
- Ghidra decompilations of the two sector helpers (`ReadSectors`,
  RVA `0x34A0`; `WriteSectors`, RVA `0x3630`) were not obtained.
  Those two helpers rest on assembly reading only. Nothing in that
  reading contradicts the decompiled caller.

## Files that are not in this repo

The Windows program (`Bootcardmaker_BootcardMaker.exe`, PE32, SHA-256
`ef2b8b3a7b624159cfcaa4ddb010833901dabaf7a6b99c5809c1c7c0971185f6`)
and the supplied bootloader file
(`Bootcardmaker_V5-OS12-2025.bin`, 4,194,304 bytes, SHA-256
`ea27984f3612c65cfa95c9ef3a25007fa75ce5ec004e977a9ecc2f2623e39671`)
are not in this repo. They must never be committed to it. The hashes
above identify the exact files that were analysed, so a reader can
confirm they are looking at the same inputs. The `.bin` file is
opaque data (sector 0 all zero, data at offsets `0x200–0x1b67ff`,
tail zero); it is copied verbatim by the tool except for the 66-byte
partition-table overwrite, and it is never parsed or modified.
