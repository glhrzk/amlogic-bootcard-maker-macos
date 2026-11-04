import Foundation

/// Pure sector and MBR math for the BootcardMaker macOS port.
///
/// Ground truth: `~/workspace/bootcardmaker-rea/analysis/MAKE-HANDLER.md`
/// (Ghidra decompilation of the Make handler, RVA 0x3800, and the
/// partition helper, RVA 0x3020, corroborated by assembly).
///
/// - The bin image is written from byte offset 0 in one write, length
///   `(fileLength + 1) >> 9 + 1` sectors. The original read 511 bytes
///   past its allocation on the last sector; this port zero-pads
///   instead and never over-reads.
/// - Bytes 446-511 (66 bytes: the four MBR partition entries plus the
///   boot signature) of the written image come from the live sector 0
///   read from the disk. Bytes 0-445 are the bin file verbatim.
/// - The partition is a single MBR entry: type 0x0B (FAT32), boot
///   flag set, starting 2 cylinders into the disk, running to the end
///   of the disk, MBR disk signature 0xF0CCF0CC.
///
/// This file performs no file or disk access. All values are computed
/// from its arguments so the logic is unit-testable without hardware.

/// Bytes per sector. The original code shifts by 9 everywhere.
public let sectorSize = 512

/// First sector of the partition: 2 cylinders at the legacy geometry
/// 255 heads x 63 sectors/track x 512 bytes/sector.
public let partitionStartSectors: Int64 = 32130

/// MBR disk signature, from the partition helper's CREATE_DISK struct
/// and DRIVE_LAYOUT_INFORMATION_EX header (REA §7). It is written into
/// the MBR at the standard disk-signature offset 0x1B8 (440) by
/// `buildMBR`, and is exposed so the privileged writer in Task 4 can
/// use the same value for the create-disk step.
public let mbrDiskSignature: UInt32 = 0xF0CCF0CC

/// Offset of the first MBR partition entry within sector 0.
private let mbrEntryOffset = 446

/// Bytes copied from the live sector 0: entries (446-509) plus the
/// boot signature (510-511).
private let mbrCopyCount = 66

/// Heads and sectors per track of the legacy geometry used for the
/// partition start and for the CHS fields of the MBR entry.
private let headsPerCylinder = 255
private let sectorsPerTrack = 63

/// Number of 512-byte sectors written for a bin file of `fileLength`
/// bytes, per the original formula.
///
/// - Precondition: `fileLength > 0`. An empty bin file is refused by
///   `validateWrite` before this is ever called.
public func writeLengthSectors(fileLength: Int) -> Int {
    precondition(fileLength > 0, "Bin file must not be empty.")
    return ((fileLength + 1) >> 9) + 1
}

/// The buffer written to the disk from byte offset 0.
///
/// The bin bytes are copied verbatim, the buffer is zero-padded to a
/// whole number of sectors, and bytes 446-511 are replaced with the
/// same bytes from the live sector 0. The live sector 0 is read after
/// partitioning/formatting (or from the existing card when Yes is
/// unticked) by the caller; it is never cached or assumed here.
///
/// - Precondition: `liveSector0` holds at least one full sector
///   (512 bytes). `bin` may be shorter than a sector; it is padded.
public func buildWriteBuffer(bin: Data, liveSector0: Data) -> Data {
    precondition(liveSector0.count >= sectorSize, "Live sector 0 must be 512 bytes.")
    var output = Data(count: writeLengthSectors(fileLength: bin.count) * sectorSize)
    output.replaceSubrange(0..<bin.count, with: bin)
    for i in 0..<mbrCopyCount {
        output[mbrEntryOffset + i] = liveSector0[mbrEntryOffset + i]
    }
    return output
}

/// A 512-byte MBR holding a single partition entry.
///
/// `totalBytes` is kept for interface parity with the simulation and
/// with the original geometry computation (total = bytes per cylinder
/// x cylinders); the entry fields are taken from `startSectors` and
/// `partitionLengthBytes`, which the caller derives from the disk
/// size. The remaining entries are zero (deleted), matching the
/// original layout where entries 1-3 carry only RewritePartition.
///
/// The disk signature is written at offset 0x1B8 (440), little-endian,
/// as Windows does when applying a layout carrying that signature.
/// CHS start/end fields use the legacy 255 x 63 geometry and are
/// clamped to the maximum representable CHS value (1023/254/63) for
/// disks larger than the CHS range, as is standard.
public func buildMBR(totalBytes: Int64, startSectors: Int64, partitionLengthBytes: Int64) -> Data {
    precondition(startSectors >= 0, "Partition start must not be negative.")
    precondition(partitionLengthBytes > 0, "Partition length must be positive.")
    _ = totalBytes

    var mbr = Data(count: sectorSize)
    writeUInt32LE(&mbr, offset: 440, value: mbrDiskSignature)

    let entry = mbrEntryOffset
    mbr[entry] = 0x80 // Boot indicator.
    let startCHS = chs(for: startSectors)
    mbr[entry + 1] = startCHS.head
    mbr[entry + 2] = startCHS.sector | UInt8((startCHS.cylinder >> 2) & 0xC0)
    mbr[entry + 3] = UInt8(startCHS.cylinder & 0xFF)
    mbr[entry + 4] = 0x0B // Partition type: FAT32.
    let endLBA = startSectors + partitionLengthBytes / Int64(sectorSize) - 1
    let endCHS = chs(for: endLBA)
    mbr[entry + 5] = endCHS.head
    mbr[entry + 6] = endCHS.sector | UInt8((endCHS.cylinder >> 2) & 0xC0)
    mbr[entry + 7] = UInt8(endCHS.cylinder & 0xFF)
    writeUInt32LE(&mbr, offset: entry + 8, value: UInt32(startSectors))
    writeUInt32LE(&mbr, offset: entry + 12, value: UInt32(partitionLengthBytes / Int64(sectorSize)))
    mbr[510] = 0x55
    mbr[511] = 0xAA
    return mbr
}

/// Whether a write may proceed, checked before anything is written.
///
/// False when the bin file is empty, when the disk is too small to hold
/// the partition start plus at least one partition sector, or when the
/// partition start does not lie strictly beyond the end of the bin
/// image (the 2-cylinder gap must contain the whole image).
public func validateWrite(diskTotalBytes: Int64, fileLength: Int) -> Bool {
    guard fileLength > 0 else { return false }
    guard diskTotalBytes >= (partitionStartSectors + 1) * Int64(sectorSize) else { return false }
    guard partitionStartSectors > Int64(writeLengthSectors(fileLength: fileLength)) else { return false }
    return true
}

/// Legacy CHS address for an LBA sector, clamped to 1023/254/63.
private func chs(for lba: Int64) -> (head: UInt8, sector: UInt8, cylinder: Int) {
    let sectorsPerCylinder = Int64(headsPerCylinder * sectorsPerTrack)
    var cylinder = Int(lba / sectorsPerCylinder)
    let remainder = lba % sectorsPerCylinder
    var head = Int(remainder / Int64(sectorsPerTrack))
    var sector = Int(remainder % Int64(sectorsPerTrack)) + 1
    if cylinder > 1023 {
        cylinder = 1023
        head = 254
        sector = 63
    }
    return (UInt8(head), UInt8(sector), cylinder)
}

/// Explicit little-endian write. No struct packing is assumed.
private func writeUInt32LE(_ data: inout Data, offset: Int, value: UInt32) {
    data[offset] = UInt8(value & 0xFF)
    data[offset + 1] = UInt8((value >> 8) & 0xFF)
    data[offset + 2] = UInt8((value >> 16) & 0xFF)
    data[offset + 3] = UInt8((value >> 24) & 0xFF)
}
