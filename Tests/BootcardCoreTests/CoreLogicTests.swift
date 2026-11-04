import XCTest

@testable import BootcardCore

final class CoreLogicTests: XCTestCase {
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

    func testBuildWriteBufferForTinyBin() {
        let bin = Data(repeating: 0xAB, count: 100)
        var sector0 = Data(repeating: 0, count: 512)
        sector0[446] = 0x80; sector0[510] = 0x55; sector0[511] = 0xAA
        let out = buildWriteBuffer(bin: bin, liveSector0: sector0)
        XCTAssertEqual(out.count, 512)
        XCTAssertEqual(out[99], 0xAB)
        XCTAssertEqual(out[100], 0) // zero padding after the short bin
        XCTAssertEqual(out[446], 0x80); XCTAssertEqual(out[510], 0x55); XCTAssertEqual(out[511], 0xAA)
    }

    func testBuildMBREntry() {
        let mbr = buildMBR(totalBytes: 16 * 1024 * 1024 * 1024, startSectors: 32130, partitionLengthBytes: 16 * 1024 * 1024 * 1024 - 32130 * 512)
        XCTAssertEqual(mbr.count, 512)
        XCTAssertEqual(mbr[446], 0x80); XCTAssertEqual(mbr[450], 0x0B)
        XCTAssertEqual(mbr[510], 0x55); XCTAssertEqual(mbr[511], 0xAA)
    }

    func testBuildMBRContainsDiskSignature() {
        let mbr = buildMBR(totalBytes: 16 * 1024 * 1024 * 1024, startSectors: 32130, partitionLengthBytes: 16 * 1024 * 1024 * 1024 - 32130 * 512)
        // Disk signature 0xF0CCF0CC at the standard MBR offset 0x1B8,
        // little-endian: the layout header signature from REA §7.
        XCTAssertEqual(mbr[440], 0xCC)
        XCTAssertEqual(mbr[441], 0xF0)
        XCTAssertEqual(mbr[442], 0xCC)
        XCTAssertEqual(mbr[443], 0xF0)
        XCTAssertEqual(mbrDiskSignature, 0xF0CCF0CC)
    }

    func testBuildMBRStartCHS() {
        let mbr = buildMBR(totalBytes: 16 * 1024 * 1024 * 1024, startSectors: 32130, partitionLengthBytes: 16 * 1024 * 1024 * 1024 - 32130 * 512)
        // Start LBA 32130 at 255 heads x 63 sectors/track: cylinder 2, head 0, sector 1.
        XCTAssertEqual(mbr[447], 0)
        XCTAssertEqual(mbr[448], 1)
        XCTAssertEqual(mbr[449], 2)
        // Start LBA little-endian at offset 454.
        XCTAssertEqual(mbr[454], 0x82)
        XCTAssertEqual(mbr[455], 0x7D)
        XCTAssertEqual(mbr[456], 0)
        XCTAssertEqual(mbr[457], 0)
    }

    func testValidateRejectsEmptyBinAndSmallDisk() {
        XCTAssertFalse(validateWrite(diskTotalBytes: 16 * 1024 * 1024 * 1024, fileLength: 0))
        XCTAssertFalse(validateWrite(diskTotalBytes: 1024 * 1024, fileLength: 4194304))
    }

    func testValidateAcceptsSuppliedBinOnLargeDisk() {
        XCTAssertTrue(validateWrite(diskTotalBytes: 16 * 1024 * 1024 * 1024, fileLength: 4194304))
    }

    func testValidateRejectsBinLongerThanPartitionGap() {
        // A bin needing more sectors than the 2-cylinder gap must be refused
        // before anything is written.
        let tooLong = (Int(partitionStartSectors) * 512) + 1
        XCTAssertFalse(validateWrite(diskTotalBytes: 16 * 1024 * 1024 * 1024, fileLength: tooLong))
    }
}
