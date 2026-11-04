import Foundation
import XCTest

@testable import BootcardCore

/// Tests for the disk-command builders in `DiskCommandBuilders.swift`.
///
/// These builders are the only place that turns a disk identifier or a
/// file path into an external-command argument array. Every command
/// the privileged writer runs is built by one of these functions, so
/// the tests pin the exact executable path and the exact arguments,
/// including that a device identifier always travels as one argument
/// and is never interpolated into a shell string. There is no shell
/// anywhere in this code path: the runners pass these arrays to
/// `Process` or to `AuthorizationExecuteWithPrivileges` directly.
///
/// The builders live in `BootcardCore` (not in the app target) for the
/// same reason the disk-list parser does: an executable target cannot
/// be imported by a test target, and these arrays must be unit-tested
/// without a Mac or a real disk.
final class DiskCommandBuildersTests: XCTestCase {
    func testUnmountDiskCommand() throws {
        let command = try unmountDiskCommand(devicePath: "/dev/disk2")
        XCTAssertEqual(command.executablePath, "/usr/sbin/diskutil")
        XCTAssertEqual(command.arguments, ["unmountDisk", "/dev/disk2"])
    }

    func testNewfsMsdosCommand() throws {
        let command = try newfsMsdosCommand(partitionDevicePath: "/dev/disk2s1")
        XCTAssertEqual(command.executablePath, "/sbin/newfs_msdos")
        // FAT32, default cluster size, no volume label (design: the
        // label is the FAT default; the format parameters are
        // unverified against a Windows-produced card).
        XCTAssertEqual(command.arguments, ["-F", "32", "/dev/disk2s1"])
    }

    func testDdWriteCommand() throws {
        let command = try ddWriteCommand(
            inputPath: "/tmp/bootcardmaker-input.tmp",
            devicePath: "/dev/rdisk2"
        )
        XCTAssertEqual(command.executablePath, "/bin/dd")
        XCTAssertEqual(command.arguments, [
            "if=/tmp/bootcardmaker-input.tmp",
            "of=/dev/rdisk2",
            "bs=512",
        ])
    }

    func testDdReadCommandReadsExactlyOneSectorByDefault() throws {
        let command = try ddReadCommand(
            devicePath: "/dev/rdisk2",
            outputPath: "/tmp/bootcardmaker-output.tmp",
            sectorCount: 1
        )
        XCTAssertEqual(command.executablePath, "/bin/dd")
        XCTAssertEqual(command.arguments, [
            "if=/dev/rdisk2",
            "of=/tmp/bootcardmaker-output.tmp",
            "bs=512",
            "count=1",
        ])
    }

    func testDdReadCommandHonoursSectorCount() throws {
        let command = try ddReadCommand(
            devicePath: "/dev/rdisk2",
            outputPath: "/tmp/bootcardmaker-output.tmp",
            sectorCount: 8193
        )
        XCTAssertTrue(command.arguments.contains("count=8193"))
    }

    func testHdiutilAttachCommand() throws {
        let command = try hdiutilAttachCommand(imagePath: "/tmp/bootcard.dmg")
        XCTAssertEqual(command.executablePath, "/usr/bin/hdiutil")
        XCTAssertEqual(command.arguments, ["attach", "-nomount", "/tmp/bootcard.dmg"])
    }

    func testDevicePathDerivation() {
        XCTAssertEqual(devicePath(for: "disk2"), "/dev/disk2")
        XCTAssertEqual(rawDevicePath(for: "disk2"), "/dev/rdisk2")
        XCTAssertEqual(partitionDevicePath(for: "disk2"), "/dev/disk2s1")
        XCTAssertEqual(rawPartitionDevicePath(for: "disk2"), "/dev/rdisk2s1")
        XCTAssertEqual(devicePath(for: "disk10"), "/dev/disk10")
    }

    func testDevicePathDerivationRejectsNonWholeDiskIdentifiers() {
        // Partition identifiers, empty strings, and anything that is
        // not exactly `disk<N>` must never become a device path.
        XCTAssertNil(devicePath(for: "disk2s1"))
        XCTAssertNil(rawDevicePath(for: "disk2s1"))
        XCTAssertNil(partitionDevicePath(for: "disk2s1"))
        XCTAssertNil(rawPartitionDevicePath(for: ""))
        XCTAssertNil(devicePath(for: "disk"))
        XCTAssertNil(devicePath(for: "diskX"))
        XCTAssertNil(devicePath(for: "disk2 "))
        XCTAssertNil(devicePath(for: " disk2"))
        XCTAssertNil(devicePath(for: "../disk2"))
        XCTAssertNil(devicePath(for: "disk2;rm"))
        XCTAssertNil(devicePath(for: "/dev/disk2"))
    }

    func testBuildersRejectMalformedDevicePaths() {
        XCTAssertThrowsError(try unmountDiskCommand(devicePath: "/dev/disk2s1"))
        XCTAssertThrowsError(try unmountDiskCommand(devicePath: "disk2"))
        XCTAssertThrowsError(try unmountDiskCommand(devicePath: "/dev/disk2; rm -rf /"))
        XCTAssertThrowsError(try newfsMsdosCommand(partitionDevicePath: "/dev/disk2"))
        XCTAssertThrowsError(try newfsMsdosCommand(partitionDevicePath: "disk2s1"))
        XCTAssertThrowsError(try ddWriteCommand(
            inputPath: "/tmp/in.tmp", devicePath: "/dev/disk2"))
        XCTAssertThrowsError(try ddWriteCommand(
            inputPath: "relative/in.tmp", devicePath: "/dev/rdisk2"))
        XCTAssertThrowsError(try ddReadCommand(
            devicePath: "/dev/rdisk2", outputPath: "relative/out.tmp", sectorCount: 1))
        XCTAssertThrowsError(try ddReadCommand(
            devicePath: "/dev/rdisk2", outputPath: "/tmp/out.tmp", sectorCount: 0))
        XCTAssertThrowsError(try hdiutilAttachCommand(imagePath: "relative/image.dmg"))
    }

    func testNoArgumentContainsShellMetacharacters() throws {
        let commands = [
            try unmountDiskCommand(devicePath: "/dev/disk2"),
            try newfsMsdosCommand(partitionDevicePath: "/dev/disk2s1"),
            try ddWriteCommand(inputPath: "/tmp/in.tmp", devicePath: "/dev/rdisk2"),
            try ddReadCommand(devicePath: "/dev/rdisk2", outputPath: "/tmp/out.tmp", sectorCount: 1),
            try hdiutilAttachCommand(imagePath: "/tmp/image.dmg"),
        ]
        // `=` is allowed (dd's if=/of= syntax); everything that could
        // split or redirect a shell command is not.
        let forbidden = CharacterSet(charactersIn: ";|&$`\"'<>\\\n\r")
            .union(.whitespaces)
        for command in commands {
            for argument in command.arguments {
                XCTAssertTrue(
                    argument.unicodeScalars.allSatisfy { !forbidden.contains($0) },
                    "Argument contains a shell metacharacter: \(argument)"
                )
            }
        }
    }
}
