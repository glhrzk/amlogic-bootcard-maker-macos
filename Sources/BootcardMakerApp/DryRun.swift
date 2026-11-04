import Foundation
import BootcardCore

/// Failures of dry-run image handling. These happen before the disk
/// operation runs (except detach, which is best-effort and never
/// changes the result). None of them writes to a physical disk.
enum DryRunError: Error, LocalizedError {
    /// The sparse image file could not be created.
    case createFailed
    /// The image could not be attached as a device node.
    case attachFailed
    /// The attached device node could not be identified from the
    /// `hdiutil` output.
    case attachParseFailed
    /// The attached image's size could not be read and no nominal
    /// size was available. (In practice the nominal size is always
    /// available, so this is defensive.)
    case sizeQueryFailed

    var errorDescription: String? {
        switch self {
        case .createFailed:
            return "The dry-run disk image could not be created. No changes were made."
        case .attachFailed:
            return "The dry-run disk image could not be attached. No changes were made."
        case .attachParseFailed:
            return "The dry-run disk image was attached but its device could not be identified. No changes were made; detach the image in Disk Utility if it is still attached."
        case .sizeQueryFailed:
            return "The dry-run disk image size could not be determined. No changes were made."
        }
    }
}

/// The offered dry-run image sizes. All are sparse files: only the
/// bytes actually written occupy space, which matters on a disk
/// that is already full. The default is the smallest image that
/// holds the 2-cylinder gap plus 64 MiB of partition.
enum DryRunSize: String, CaseIterable, Identifiable {
    case `default`
    case oneGiB
    case fourGiB
    case sixteenGiB

    var id: String { rawValue }

    var label: String {
        switch self {
        case .default: return "Default (partition start + 64 MiB)"
        case .oneGiB: return "1 GiB"
        case .fourGiB: return "4 GiB"
        case .sixteenGiB: return "16 GiB"
        }
    }

    /// The `hdiutil create -size` value.
    var sizeString: String {
        switch self {
        case .default: return "80m"
        case .oneGiB: return "1g"
        case .fourGiB: return "4g"
        case .sixteenGiB: return "16g"
        }
    }

    /// The nominal size in bytes, used only when the attached
    /// image's real size cannot be read back. The real size, read
    /// from `diskutil info` after attaching, is preferred.
    var nominalSizeBytes: Int64 {
        switch self {
        case .default: return 80 * 1024 * 1024
        case .oneGiB: return 1024 * 1024 * 1024
        case .fourGiB: return 4 * 1024 * 1024 * 1024
        case .sixteenGiB: return 16 * 1024 * 1024 * 1024
        }
    }
}

/// Dry-run mode: create a sparse disk image, attach it, run the same
/// `makeDiskOperation` as a physical disk through the attached node,
/// then detach and leave the image file for inspection.
///
/// The image's `DiskInfo` describes the attached node (its identifier
/// and its real size), never a physical disk. No elevation is ever
/// requested here: Task 4 runs dry-run operations through
/// `ProcessRunner` with no admin rights, and requesting elevation
/// for a user-owned attached image would be a bug. Nothing in this
/// file touches a physical disk.
///
/// Every command uses an argument array built by `BootcardCore`
/// (`hdiutilCreateCommand`, `hdiutilAttachPlistCommand`,
/// `hdiutilDetachCommand`); there is no shell. The process calls
/// block, so callers must run this off the main thread.
///
/// Mac-gated: nothing in this file has run on a Mac from this Linux
/// VM. In particular the `hdiutil create -layout NONE` spelling, the
/// `-size` suffix meanings, and the `diskutil info` size read-back
/// are unverified on Tahoe; a failure in any of them fails dry-run
/// cleanly before the operation writes anything.
enum DryRunSession {
    /// Run the operation against a fresh dry-run image and return
    /// the image file's location, left in place for inspection.
    /// On a create/attach failure before the operation, the image
    /// file is removed best-effort so a failed dry-run leaves no
    /// litter in the temporary folder.
    static func run(
        bin: Data,
        partitionAndFormat: Bool,
        size: DryRunSize
    ) async throws -> URL {
        let imageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bootcardmaker-dryrun-\(UUID().uuidString).sparseimage")
        let runner = ProcessRunner()

        // 1. Create the sparse image.
        do {
            let status = try runner.run(hdiutilCreateCommand(
                imagePath: imageURL.path, sizeString: size.sizeString
            ))
            guard status == 0 else { throw DryRunError.createFailed }
        } catch let error as DryRunError {
            throw error
        } catch {
            throw DryRunError.createFailed
        }

        // 2. Attach it without mounting and identify the node.
        let attachedIdentifier: String
        do {
            let command = try hdiutilAttachPlistCommand(imagePath: imageURL.path)
            let (status, output) = try runCommandCapturingOutput(
                executablePath: command.executablePath, arguments: command.arguments
            )
            guard status == 0 else { throw DryRunError.attachFailed }
            do {
                attachedIdentifier = try parseHdiutilAttachPlist(output)
            } catch {
                throw DryRunError.attachParseFailed
            }
        } catch let error as DryRunError {
            try? FileManager.default.removeItem(at: imageURL)
            throw error
        } catch {
            try? FileManager.default.removeItem(at: imageURL)
            throw DryRunError.attachFailed
        }

        // 3. Detach best-effort when this function exits, whatever
        // the operation's result. A failed detach never changes the
        // result; the image file is still left for inspection.
        defer {
            if let devicePath = devicePath(for: attachedIdentifier),
               let command = try? hdiutilDetachCommand(devicePath: devicePath) {
                _ = try? runner.run(command)
            }
        }

        // 4. Read the attached image's real size and describe the
        // attached node — never a physical disk.
        let sizeBytes = attachedSizeBytes(
            identifier: attachedIdentifier, fallback: size.nominalSizeBytes
        )
        let imageDisk = DiskInfo(
            identifier: attachedIdentifier,
            name: "Dry-run disk image",
            sizeBytes: sizeBytes,
            isRemovable: true,
            isExternal: true,
            protocolName: "Disk Image"
        )

        // 5. The same operation as a physical disk, through the
        // attached node, with no elevation (Task 4: `dryRunDevice`
        // set selects `ProcessRunner`).
        try await makeDiskOperation(
            disk: imageDisk,
            bin: bin,
            partitionAndFormat: partitionAndFormat,
            dryRunDevice: attachedIdentifier
        )
        return imageURL
    }

    /// The `Size` value from `diskutil info -plist` for the attached
    /// node, or `fallback` when the query fails. A failed size query
    /// must not abort a dry-run whose device exists: the nominal size
    /// is the size that was requested, and `validateWrite` only
    /// needs the disk to be larger than the 2-cylinder gap.
    private static func attachedSizeBytes(identifier: String, fallback: Int64) -> Int64 {
        guard let devicePath = devicePath(for: identifier) else { return fallback }
        guard
            let (status, output) = try? runCommandCapturingOutput(
                executablePath: "/usr/sbin/diskutil",
                arguments: ["info", "-plist", devicePath]
            ),
            status == 0,
            let object = try? PropertyListSerialization.propertyList(
                from: output, options: [], format: nil
            ),
            let info = object as? [String: Any],
            let size = info["Size"] as? NSNumber
        else {
            return fallback
        }
        return size.int64Value
    }
}
