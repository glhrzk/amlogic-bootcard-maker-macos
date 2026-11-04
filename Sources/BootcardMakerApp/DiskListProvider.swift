import Foundation
import BootcardCore

/// Failures listing disks. Every failure is fail-closed: the GUI
/// shows no disk list at all rather than a list that might include
/// the boot disk.
enum DiskListError: Error, LocalizedError {
    /// `diskutil` could not be run or exited non-zero.
    case diskutilFailed
    /// The boot disk could not be determined, so the boot-disk
    /// exclusion cannot be proven. No list is returned.
    case bootDiskUnknown
    /// The `diskutil` output could not be parsed.
    case parseFailed

    var errorDescription: String? {
        switch self {
        case .diskutilFailed:
            return "The list of disks could not be read. Check that the card is still connected and press Refresh."
        case .bootDiskUnknown:
            return "The startup disk could not be determined, so no disk is listed. Press Refresh to try again."
        case .parseFailed:
            return "The list of disks could not be understood. Press Refresh to try again."
        }
    }
}

/// The live `diskutil` call deferred from Task 3. Both commands use
/// fixed argument arrays only; no user input reaches either command.
/// The process calls block, so callers must run this off the main
/// thread.
///
/// The boot disk is derived from `diskutil info -plist /`: the
/// `ParentWholeDisk` value when present, otherwise the whole-disk
/// part of `DeviceIdentifier` (for example `disk3` from `disk3s1`).
/// If neither yields a whole-disk identifier, listing fails closed
/// with `bootDiskUnknown`.
///
/// Mac-gated: nothing in this file has run on a Mac from this Linux
/// VM. The `ParentWholeDisk` key spelling and the `diskutil info`
/// output shape are unverified on Tahoe; a mismatch fails closed
/// (no list) rather than listing the boot disk.
struct DiskListProvider {
    /// Selectable whole disks, boot disk excluded, removable/external
    /// first — exactly `selectableDisks` from Task 3.
    func loadSelectableDisks() throws -> [DiskInfo] {
        let (listStatus, listOutput) = try runCommandCapturingOutput(
            executablePath: "/usr/sbin/diskutil",
            arguments: ["list", "-plist"]
        )
        guard listStatus == 0 else { throw DiskListError.diskutilFailed }
        let all: [DiskInfo]
        do {
            all = try parseDiskList(listOutput)
        } catch {
            throw DiskListError.parseFailed
        }
        let bootDiskIdentifier = try bootDiskIdentifier()
        return selectableDisks(all: all, bootDiskIdentifier: bootDiskIdentifier)
    }

    /// The whole-disk identifier of the disk the system booted from.
    private func bootDiskIdentifier() throws -> String {
        let (infoStatus, infoOutput) = try runCommandCapturingOutput(
            executablePath: "/usr/sbin/diskutil",
            arguments: ["info", "-plist", "/"]
        )
        guard infoStatus == 0 else { throw DiskListError.diskutilFailed }
        guard let identifier = Self.bootDiskIdentifier(from: infoOutput) else {
            throw DiskListError.bootDiskUnknown
        }
        return identifier
    }

    /// Pure parsing of `diskutil info -plist /` output. Returns the
    /// whole-disk identifier, or `nil` when it cannot be determined.
    /// Untested on this Linux VM (the app target cannot be imported
    /// by a test target); the fail-closed behaviour is the safety
    /// property, and it is verified by reading this function.
    static func bootDiskIdentifier(from plistData: Data) -> String? {
        guard
            let object = try? PropertyListSerialization.propertyList(
                from: plistData, options: [], format: nil
            ),
            let info = object as? [String: Any]
        else {
            return nil
        }
        if let parent = info["ParentWholeDisk"] as? String,
           isWholeDiskIdentifier(parent) {
            return parent
        }
        if let device = info["DeviceIdentifier"] as? String,
           let whole = wholeDiskIdentifier(from: device) {
            return whole
        }
        return nil
    }

    /// `disk3` from `disk3s1`; `nil` for anything that is not a
    /// `disk<N>s<M>` partition identifier.
    private static func wholeDiskIdentifier(from identifier: String) -> String? {
        guard identifier.hasPrefix("disk") else { return nil }
        let rest = identifier.dropFirst("disk".count)
        guard let sIndex = rest.firstIndex(of: "s") else { return nil }
        let diskPart = rest[..<sIndex]
        let partitionPart = rest[rest.index(after: sIndex)...]
        guard !diskPart.isEmpty, !partitionPart.isEmpty,
              diskPart.unicodeScalars.allSatisfy(CharacterSet.decimalDigits.contains),
              partitionPart.unicodeScalars.allSatisfy(CharacterSet.decimalDigits.contains)
        else {
            return nil
        }
        return "disk\(diskPart)"
    }

    private static func isWholeDiskIdentifier(_ identifier: String) -> Bool {
        guard identifier.hasPrefix("disk") else { return false }
        let rest = identifier.dropFirst("disk".count)
        return !rest.isEmpty
            && rest.unicodeScalars.allSatisfy(CharacterSet.decimalDigits.contains)
    }
}

/// Run one fixed command and capture its standard output. No shell:
/// the executable path and argument array go to `Process` directly.
/// Standard error is discarded; success is the exit status.
func runCommandCapturingOutput(
    executablePath: String,
    arguments: [String]
) throws -> (Int32, Data) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executablePath)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
    } catch {
        throw DiskListError.diskutilFailed
    }
    let output = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, output)
}
