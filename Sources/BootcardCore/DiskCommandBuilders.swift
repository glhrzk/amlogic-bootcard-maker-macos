import Foundation

/// Builders for the external commands the privileged disk writer runs.
///
/// Every command in the disk operation is built by one of these
/// functions and is executed as an argument array only: the runners
/// pass `DiskCommand.executablePath` and `DiskCommand.arguments` to
/// `Process` (dry-run) or to `AuthorizationExecuteWithPrivileges`
/// (physical disk) directly. There is no shell anywhere in this code
/// path, and no path or identifier is ever interpolated into a
/// command string. (`dd`'s `if=`/`of=` arguments carry a path inside
/// one argument value; that is `dd`'s own syntax, not shell syntax,
/// and the value is still a single array element.)
///
/// The builders live in `BootcardCore` so they can be unit-tested
/// without a Mac or a real disk. The app target cannot be imported by
/// a test target, so anything that must be tested belongs here.
///
/// Device identifiers are validated strictly: only an exact
/// `disk<N>` whole-disk identifier (for example `disk2`) becomes a
/// device path. Partition identifiers (`disk2s1`), relative paths,
/// and anything containing characters outside `[0-9]` after `disk`
/// are rejected. The partition device paths are derived from the
/// validated whole-disk identifier by appending `s1`, never by
/// trusting caller-supplied text.

/// One external command: a fixed executable path plus an argument array.
public struct DiskCommand: Equatable {
    public let executablePath: String
    public let arguments: [String]

    public init(executablePath: String, arguments: [String]) {
        self.executablePath = executablePath
        self.arguments = arguments
    }
}

/// Failures building a disk command from untrusted input.
public enum DiskCommandError: Error, Equatable {
    /// The device path is not an exact `/dev/disk<N>` or
    /// `/dev/rdisk<N>` whole-disk path, or a partition path is not an
    /// exact `/dev/disk<N>s1` path.
    case invalidDevicePath
    /// A file path is not absolute.
    case invalidFilePath
    /// A sector count is not positive.
    case invalidSectorCount
}

/// Block device path (`/dev/disk2`) for a whole-disk identifier, or
/// `nil` when the identifier is not exactly `disk<N>`.
public func devicePath(for identifier: String) -> String? {
    guard isWholeDiskIdentifier(identifier) else { return nil }
    return "/dev/\(identifier)"
}

/// Raw device path (`/dev/rdisk2`) for a whole-disk identifier, or
/// `nil` when the identifier is not exactly `disk<N>`. Raw devices
/// are used for `dd` reads and writes.
public func rawDevicePath(for identifier: String) -> String? {
    guard isWholeDiskIdentifier(identifier) else { return nil }
    return "/dev/r\(identifier)"
}

/// Block partition device path (`/dev/disk2s1`) for a whole-disk
/// identifier, or `nil` when the identifier is not exactly `disk<N>`.
/// Used for `newfs_msdos`, which is documented with block devices.
public func partitionDevicePath(for identifier: String) -> String? {
    guard isWholeDiskIdentifier(identifier) else { return nil }
    return "/dev/\(identifier)s1"
}

/// Raw partition device path (`/dev/rdisk2s1`) for a whole-disk
/// identifier, or `nil` when the identifier is not exactly `disk<N>`.
/// Used for `dd` reads of the formatted partition's boot sector.
public func rawPartitionDevicePath(for identifier: String) -> String? {
    guard isWholeDiskIdentifier(identifier) else { return nil }
    return "/dev/r\(identifier)s1"
}

/// `diskutil unmountDisk <devicePath>`: unmount every volume on the
/// whole disk so the raw write is not fighting an automounted volume.
public func unmountDiskCommand(devicePath: String) throws -> DiskCommand {
    guard isWholeDiskDevicePath(devicePath) else {
        throw DiskCommandError.invalidDevicePath
    }
    return DiskCommand(
        executablePath: "/usr/sbin/diskutil",
        arguments: ["unmountDisk", devicePath]
    )
}

/// `newfs_msdos -F 32 <partitionDevicePath>`: create a FAT32
/// filesystem with the default cluster size and the FAT default
/// volume label. No cluster-size, sector-size, or label argument is
/// passed, matching the design choice; the format parameters are
/// unverified against a Windows-produced card (see the design doc).
public func newfsMsdosCommand(partitionDevicePath: String) throws -> DiskCommand {
    guard isPartitionDevicePath(partitionDevicePath) else {
        throw DiskCommandError.invalidDevicePath
    }
    return DiskCommand(
        executablePath: "/sbin/newfs_msdos",
        arguments: ["-F", "32", partitionDevicePath]
    )
}

/// `dd if=<inputPath> of=<devicePath> bs=512`: write a buffer file to
/// a raw device from byte offset 0. The input file holds exactly the
/// bytes to write (a whole number of sectors, built by
/// `buildWriteBuffer` or `buildMBR`), so no `count=` is needed and
/// `dd` stops at end of input.
public func ddWriteCommand(inputPath: String, devicePath: String) throws -> DiskCommand {
    guard isAbsolutePath(inputPath) else {
        throw DiskCommandError.invalidFilePath
    }
    guard isRawWholeDiskDevicePath(devicePath) else {
        throw DiskCommandError.invalidDevicePath
    }
    return DiskCommand(
        executablePath: "/bin/dd",
        arguments: ["if=\(inputPath)", "of=\(devicePath)", "bs=512"]
    )
}

/// `dd if=<devicePath> of=<outputPath> bs=512 count=<sectorCount>`:
/// read an exact number of sectors from a raw device into a file.
public func ddReadCommand(
    devicePath: String,
    outputPath: String,
    sectorCount: Int
) throws -> DiskCommand {
    guard isRawDevicePath(devicePath) else {
        throw DiskCommandError.invalidDevicePath
    }
    guard isAbsolutePath(outputPath) else {
        throw DiskCommandError.invalidFilePath
    }
    guard sectorCount > 0 else {
        throw DiskCommandError.invalidSectorCount
    }
    return DiskCommand(
        executablePath: "/bin/dd",
        arguments: [
            "if=\(devicePath)",
            "of=\(outputPath)",
            "bs=512",
            "count=\(sectorCount)",
        ]
    )
}

/// `hdiutil attach -nomount <imagePath>`: attach a dry-run disk image
/// without mounting it, so the same raw-device code path can run
/// against the attached node. Used by Task 5's dry-run mode; the
/// builder lives here so the argument array is tested with the rest.
public func hdiutilAttachCommand(imagePath: String) throws -> DiskCommand {
    guard isAbsolutePath(imagePath) else {
        throw DiskCommandError.invalidFilePath
    }
    return DiskCommand(
        executablePath: "/usr/bin/hdiutil",
        arguments: ["attach", "-nomount", imagePath]
    )
}

/// True for whole-disk identifiers (`disk0`, `disk2`, `disk10`).
/// False for partition identifiers (`disk0s1`) and for anything else.
private func isWholeDiskIdentifier(_ identifier: String) -> Bool {
    guard identifier.hasPrefix("disk") else { return false }
    let rest = identifier.dropFirst("disk".count)
    return !rest.isEmpty
        && rest.unicodeScalars.allSatisfy(CharacterSet.decimalDigits.contains)
}

/// True for an exact `/dev/disk<N>` block whole-disk path.
private func isWholeDiskDevicePath(_ path: String) -> Bool {
    guard path.hasPrefix("/dev/disk") else { return false }
    return isWholeDiskIdentifier(String(path.dropFirst("/dev/".count)))
}

/// True for an exact `/dev/rdisk<N>` raw whole-disk path.
private func isRawWholeDiskDevicePath(_ path: String) -> Bool {
    guard path.hasPrefix("/dev/rdisk") else { return false }
    return isWholeDiskIdentifier(String(path.dropFirst("/dev/r".count)))
}

/// True for an exact `/dev/rdisk<N>` or `/dev/rdisk<N>s1` raw path.
private func isRawDevicePath(_ path: String) -> Bool {
    if isRawWholeDiskDevicePath(path) { return true }
    guard path.hasPrefix("/dev/rdisk") else { return false }
    let rest = String(path.dropFirst("/dev/r".count))
    guard rest.hasSuffix("s1") else { return false }
    return isWholeDiskIdentifier(String(rest.dropLast(2)))
}

/// True for an exact `/dev/disk<N>s1` block partition path.
private func isPartitionDevicePath(_ path: String) -> Bool {
    guard path.hasPrefix("/dev/disk") else { return false }
    let rest = String(path.dropFirst("/dev/".count))
    guard rest.hasSuffix("s1") else { return false }
    return isWholeDiskIdentifier(String(rest.dropLast(2)))
}

/// True for an absolute path with no embedded NUL. Relative paths are
/// never accepted: every file the runners touch is under a
/// caller-chosen absolute location (a temporary file or a
/// user-chosen image), and a relative path would resolve against an
/// unknown working directory.
private func isAbsolutePath(_ path: String) -> Bool {
    path.hasPrefix("/") && !path.contains("\0")
}
