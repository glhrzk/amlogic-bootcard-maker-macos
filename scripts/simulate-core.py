#!/usr/bin/env python3
"""Linux simulation of the BootcardCore constants and math (Task 2).

This mirrors the Swift functions defined in the implementation plan
(writeLengthSectors, buildWriteBuffer, buildMBR, validateWrite) so the
arithmetic can be checked on this Linux VM, where Swift cannot run.

It is a simulation only. It never proves the Swift code behaves the
same way. The Swift unit tests in Tests/BootcardCoreTests are the real
check, and they run on the owner's Mac (owner-gated).

Ground truth: ~/workspace/bootcardmaker-rea/analysis/MAKE-HANDLER.md
- Write start: byte offset 0.
- Write length: (fileLength + 1) >> 9 + 1 sectors, one write.
- Bytes 446-511 (66 bytes) of the written image come from the live
  sector 0. Bytes 0-445 are verbatim from the bin file.
- One MBR entry: type 0x0B, boot flag 1, start 2 cylinders
  (255 heads x 63 sectors/track x 512 bytes = 32130 sectors),
  signature 0xF0CCF0CC.
"""

SECTOR_SIZE = 512
PARTITION_START_SECTORS = 32130  # 2 cylinders at 255 x 63 x 512
MBR_DISK_SIGNATURE = 0xF0CCF0CC
MBR_ENTRY_OFFSET = 446
MBR_COPY_COUNT = 66


def write_length_sectors(file_length):
    """Sectors written for a bin file. Refuses empty files."""
    if file_length <= 0:
        raise ValueError("empty bin file: refused")
    return ((file_length + 1) >> 9) + 1


def build_write_buffer(bin_data, live_sector0):
    """Bin bytes verbatim, zero-padded, bytes 446-511 from live sector 0."""
    if len(live_sector0) < SECTOR_SIZE:
        raise ValueError("live sector 0 must be 512 bytes")
    total = write_length_sectors(len(bin_data)) * SECTOR_SIZE
    out = bytearray(total)
    out[: len(bin_data)] = bin_data
    out[MBR_ENTRY_OFFSET : MBR_ENTRY_OFFSET + MBR_COPY_COUNT] = live_sector0[
        MBR_ENTRY_OFFSET : MBR_ENTRY_OFFSET + MBR_COPY_COUNT
    ]
    return bytes(out)


def build_mbr(total_bytes, start_sectors, partition_length_bytes):
    """512-byte MBR with one entry. total_bytes is kept for parity with
    the Swift interface; the entry fields come from the other args."""
    _ = total_bytes
    mbr = bytearray(SECTOR_SIZE)
    entry = MBR_ENTRY_OFFSET
    mbr[entry] = 0x80  # boot flag
    mbr[entry + 4] = 0x0B  # partition type: FAT32
    mbr[entry + 8 : entry + 12] = int(start_sectors).to_bytes(4, "little")
    sectors = partition_length_bytes // SECTOR_SIZE
    mbr[entry + 12 : entry + 16] = int(sectors).to_bytes(4, "little")
    mbr[510] = 0x55
    mbr[511] = 0xAA
    return bytes(mbr)


def validate_write(disk_total_bytes, file_length):
    """False when the write must be refused before anything is written."""
    if file_length <= 0:
        return False
    if disk_total_bytes < (PARTITION_START_SECTORS + 1) * SECTOR_SIZE:
        return False
    if PARTITION_START_SECTORS <= write_length_sectors(file_length):
        return False
    return True


def check(name, actual, expected):
    status = "PASS" if actual == expected else "FAIL"
    print(f"{status}: {name}: got {actual}, expected {expected}")
    return actual == expected


def main():
    ok = True

    # Required self-checks from the plan.
    ok &= check(
        "write_length_sectors(4194304)",
        write_length_sectors(4194304),
        8193,
    )
    ok &= check("write_length_sectors(100)", write_length_sectors(100), 1)
    try:
        write_length_sectors(0)
        print("FAIL: write_length_sectors(0): got no refusal, expected refusal")
        ok = False
    except ValueError as exc:
        print(f"PASS: write_length_sectors(0): refused ({exc})")

    # Buffer: verbatim bytes, 66-byte copy, zero padding.
    sector0 = bytearray(SECTOR_SIZE)
    sector0[446] = 0x80
    sector0[510] = 0x55
    sector0[511] = 0xAA
    out = build_write_buffer(bytes([0xAB]) * 1024, bytes(sector0))
    # (1024 + 1) >> 9 + 1 = 3 sectors = 1536 bytes: the formula writes
    # one sector past the file end (zero-padded here, never over-read).
    ok &= check("build_write_buffer length (1024-byte bin)", len(out), 1536)
    ok &= check("build_write_buffer[0]", out[0], 0xAB)
    ok &= check("build_write_buffer[445]", out[445], 0xAB)
    ok &= check("build_write_buffer[446]", out[446], 0x80)
    ok &= check("build_write_buffer[510]", out[510], 0x55)
    ok &= check("build_write_buffer[511]", out[511], 0xAA)
    ok &= check("build_write_buffer trailing sector zeroed", out[1024], 0x00)
    ok &= check("build_write_buffer last byte zeroed", out[1535], 0x00)
    padded = build_write_buffer(bytes([0xAB]) * 100, bytes(sector0))
    ok &= check("build_write_buffer length (100-byte bin)", len(padded), 512)
    ok &= check("build_write_buffer zero padding", padded[100], 0x00)

    # MBR entry.
    total = 16 * 1024 * 1024 * 1024
    mbr = build_mbr(total, PARTITION_START_SECTORS, total - PARTITION_START_SECTORS * 512)
    ok &= check("build_mbr length", len(mbr), 512)
    ok &= check("build_mbr boot flag", mbr[446], 0x80)
    ok &= check("build_mbr type", mbr[450], 0x0B)
    ok &= check("build_mbr start LBA", int.from_bytes(mbr[454:458], "little"), 32130)
    ok &= check("build_mbr signature 510", mbr[510], 0x55)
    ok &= check("build_mbr signature 511", mbr[511], 0xAA)
    ok &= check("mbr disk signature", MBR_DISK_SIGNATURE, 0xF0CCF0CC)

    # Guards.
    ok &= check(
        "validate_write rejects empty bin",
        validate_write(total, 0),
        False,
    )
    ok &= check(
        "validate_write rejects 1 MiB disk",
        validate_write(1024 * 1024, 4194304),
        False,
    )
    ok &= check(
        "validate_write accepts 16 GiB disk + supplied bin",
        validate_write(total, 4194304),
        True,
    )

    print("RESULT: ALL PASS" if ok else "RESULT: FAILURES PRESENT")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
