import Foundation
import XCTest

@testable import BootcardCore

final class DiskEnumerationTests: XCTestCase {
    private func fixtureData() throws -> Data {
        let testFile = URL(fileURLWithPath: #file)
        let fixtureURL = testFile
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/diskutil-list-sample.plist")
        return try Data(contentsOf: fixtureURL)
    }

    func testParseFixtureYieldsThreeWholeDisks() throws {
        let disks = try parseDiskList(fixtureData())
        XCTAssertEqual(disks.map(\.identifier), ["disk0", "disk2", "disk3"])
    }

    func testParseFixtureFlagsAreVisible() throws {
        let disks = try parseDiskList(fixtureData())

        let boot = disks[0]
        XCTAssertEqual(boot.name, "disk0")
        XCTAssertEqual(boot.sizeBytes, 500277790720)
        XCTAssertFalse(boot.isRemovable)
        XCTAssertFalse(boot.isExternal)
        XCTAssertEqual(boot.protocolName, "PCI-Express")

        let usbCard = disks[1]
        XCTAssertEqual(usbCard.sizeBytes, 31914983424)
        XCTAssertTrue(usbCard.isRemovable)
        XCTAssertTrue(usbCard.isExternal)
        XCTAssertEqual(usbCard.protocolName, "USB")

        let builtinCard = disks[2]
        XCTAssertEqual(builtinCard.sizeBytes, 15931539456)
        XCTAssertTrue(builtinCard.isRemovable)
        XCTAssertFalse(builtinCard.isExternal)
        XCTAssertEqual(builtinCard.protocolName, "SD")
    }

    func testSelectableDisksExcludesBootDiskAndPartitions() throws {
        let parsed = try parseDiskList(fixtureData())
        let partitions = [
            DiskInfo(identifier: "disk0s1", name: "EFI", sizeBytes: 209715200, isRemovable: false, isExternal: false, protocolName: "PCI-Express"),
            DiskInfo(identifier: "disk2s1", name: "BOOTCARD", sizeBytes: 31914983424, isRemovable: true, isExternal: true, protocolName: "USB"),
            DiskInfo(identifier: "disk3s1", name: "CARD", sizeBytes: 15931539456, isRemovable: true, isExternal: false, protocolName: "SD"),
        ]
        let selectable = selectableDisks(all: parsed + partitions, bootDiskIdentifier: "disk0")
        XCTAssertEqual(selectable.map(\.identifier), ["disk2", "disk3"])
    }

    func testSelectableDisksSortsRemovableExternalFirst() throws {
        let disks = try parseDiskList(fixtureData())
        // Input deliberately in reverse order: built-in reader, boot, USB.
        let selectable = selectableDisks(all: [disks[2], disks[0], disks[1]], bootDiskIdentifier: "disk0")
        XCTAssertEqual(selectable.map(\.identifier), ["disk2", "disk3"])
    }

    func testParseInvalidDataThrows() {
        XCTAssertThrowsError(try parseDiskList(Data("not a plist".utf8)))
    }

    func testParseEmptyDiskListReturnsEmpty() throws {
        let empty = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>AllDisksAndPartitions</key>
                <array/>
            </dict>
            </plist>
            """
        let disks = try parseDiskList(Data(empty.utf8))
        XCTAssertTrue(disks.isEmpty)
    }
}
