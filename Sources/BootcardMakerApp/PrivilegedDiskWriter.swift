import Foundation
import Security

#if canImport(Darwin)
import Darwin
#endif

/// Failures of a disk operation, one case per step. No step reports
/// success after another step failed: the orchestration in
/// `DiskOperation.swift` aborts with the failing step's case, and the
/// messages name the step and the state it may have left behind.
/// There is no rollback claim anywhere: a failed operation leaves the
/// disk in whatever state the failed step left it in.
public enum DiskOperationError: Error, Equatable {
    /// Administrator approval was refused, cancelled, or unavailable.
    /// Nothing was written.
    case elevationDenied
    /// The device node vanished before or during the operation.
    case diskDisappeared
    /// `diskutil unmountDisk` failed.
    case unmountFailed
    /// Writing or verifying the MBR failed.
    case partitionFailed
    /// Formatting the partition as FAT32 failed, or the formatted
    /// partition's boot sector did not carry a FAT32 BPB.
    case formatFailed
    /// Sector 0 could not be read from the disk.
    case readFailed
    /// Writing the bootloader buffer failed.
    case writeFailed
    /// The bytes read back after the write did not match the buffer.
    case verificationFailed
    /// The disk, bin file, or derived device path is not valid for
    /// this operation (checked before anything is written).
    case invalidInput
}

extension DiskOperationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .elevationDenied:
            return "Administrator approval was not given. No changes were made to the disk."
        case .diskDisappeared:
            return "The disk disappeared before the operation finished. No success is reported; check whether the disk is still connected."
        case .unmountFailed:
            return "The disk could not be unmounted. The operation stopped before writing."
        case .partitionFailed:
            return "Writing the partition table failed. The disk may be left unpartitioned; do not remove it until you have checked its state."
        case .formatFailed:
            return "Formatting the partition as FAT32 failed. The disk may be left unformatted."
        case .readFailed:
            return "Sector 0 could not be read from the disk."
        case .writeFailed:
            return "Writing the bootloader image failed. The disk may be left partly written."
        case .verificationFailed:
            return "The written image did not match when read back. The card must not be trusted."
        case .invalidInput:
            return "The disk or bin file is not valid for this operation."
        }
    }
}

/// Internal failure of a single command run. The orchestration maps
/// this to the failing step's `DiskOperationError`; the numeric status
/// is kept only for the runner's own bookkeeping and is never shown
/// to the user as a substitute for the step message.
enum DiskIOError: Error {
    /// The tool exited with a non-zero status.
    case commandFailed(Int32)
    /// The tool could not be started at all.
    case spawnFailed
}

/// Runs one `DiskCommand` and returns its exit status.
///
/// Two implementations exist, chosen once per operation in
/// `makeDiskOperation`: `ProcessRunner` for dry-run images owned by
/// the user (no elevation), and `AuthorizationRunner` for physical
/// disks (admin rights obtained once, in its initializer).
protocol DiskCommandRunner {
    func run(_ command: DiskCommand) throws -> Int32
}

/// Runs commands as the current user via `Process`. Used only for
/// dry-run images: an attached user-owned image is writable without
/// admin rights, and requesting elevation for a dry-run would be a
/// bug (design resolution 3).
struct ProcessRunner: DiskCommandRunner {
    func run(_ command: DiskCommand) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executablePath)
        process.arguments = command.arguments
        // The runners never parse tool output: success is the exit
        // status plus the orchestration's own re-read verification.
        // Output is discarded so `dd` summaries do not reach the UI.
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw DiskIOError.spawnFailed
        }
        process.waitUntilExit()
        return process.terminationStatus
    }
}

/// Runs fixed system tools with admin rights, obtained once.
///
/// Mechanism: Security framework Authorization Services
/// (`AuthorizationCreate` + `AuthorizationCopyRights` for the
/// `system.privilege.admin` right, then
/// `AuthorizationExecuteWithPrivileges` per tool). This is the only
/// elevation path available to an ad-hoc-signed, CLT-built app with
/// no paid developer account: the modern alternative, SMJobBless
/// with a launchd helper, requires Developer ID signing and is
/// therefore not usable for this open-source build. The deprecated
/// `AuthorizationExecuteWithPrivileges` call is isolated here, in
/// this one type, so replacing it later touches one file.
///
/// Mac-gated and unverified on Tahoe: whether the deprecated call is
/// still present and functional on macOS 26 has not been proven on
/// this Linux VM, and a build or runtime failure here must be
/// reported as `elevationDenied` (or a build failure), never worked
/// around by writing to the disk without elevation. If the call is
/// absent on Tahoe, this file is where the replacement goes.
///
/// Exit status: `AuthorizationExecuteWithPrivileges` reports no exit
/// status directly. The communications pipe is drained to EOF, which
/// signals that the child has exited, and `waitpid` is then tried
/// best-effort to recover the status. When the child cannot be
/// reaped (it is not a child of this process), the status is
/// reported as 0 and the orchestration's own step verification —
/// re-reading the MBR, checking the FAT32 BPB, and comparing the
/// full written buffer — is what catches a failed tool. A failed
/// tool must therefore never produce a false success.
final class AuthorizationRunner: DiskCommandRunner {
    private let authorization: AuthorizationRef

    /// Obtain admin rights once. Throws `elevationDenied` when the
    /// user refuses or cancels, when rights cannot be obtained, or
    /// when Authorization Services is unavailable. Nothing has been
    /// written at this point.
    init() throws {
        var created: AuthorizationRef?
        let createStatus = AuthorizationCreate(nil, nil, [], &created)
        guard createStatus == errAuthorizationSuccess, let createdRef = created else {
            throw DiskOperationError.elevationDenied
        }
        let copyStatus: OSStatus = "system.privilege.admin".withCString { namePointer in
            var item = AuthorizationItem(
                name: namePointer,
                nameLength: 0,
                valueLength: 0,
                value: nil,
                flags: []
            )
            var rights = AuthorizationRights(count: 1, items: &item)
            let flags: AuthorizationFlags = [
                .interactionAllowed, .extendRights, .preAuthorize,
            ]
            return AuthorizationCopyRights(createdRef, &rights, nil, flags, nil)
        }
        guard copyStatus == errAuthorizationSuccess else {
            _ = AuthorizationFree(createdRef, [])
            throw DiskOperationError.elevationDenied
        }
        authorization = createdRef
    }

    deinit {
        _ = AuthorizationFree(authorization, [])
    }

    func run(_ command: DiskCommand) throws -> Int32 {
        // Build a null-terminated C argument vector. The strings are
        // copied with `strdup` (malloc) and freed with `free` below;
        // the vector itself is only valid for the duration of the
        // `AuthorizationExecuteWithPrivileges` call, which copies the
        // arguments when it starts the tool.
        var cStrings: [UnsafeMutablePointer<CChar>?] = command.arguments.map { strdup($0) }
        cStrings.append(nil)
        defer {
            for pointer in cStrings {
                if let pointer {
                    free(pointer)
                }
            }
        }
        var pipe: UnsafeMutablePointer<FILE>?
        let status: OSStatus = command.executablePath.withCString { toolPath in
            cStrings.withUnsafeMutableBufferPointer { buffer in
                AuthorizationExecuteWithPrivileges(
                    authorization,
                    toolPath,
                    [],
                    buffer.baseAddress,
                    &pipe
                )
            }
        }
        guard status == errAuthorizationSuccess else {
            throw DiskIOError.spawnFailed
        }
        // Drain the communications pipe to EOF: the child closes it
        // on exit, so EOF means the tool has finished. Output is
        // discarded; success is the exit status plus verification.
        if let pipe {
            while fgetc(pipe) != -1 {
                continue
            }
            _ = fclose(pipe)
        }
        // Best-effort exit status. `waitpid` reaps the tool only when
        // it is a child of this process; otherwise it fails with
        // ECHILD and 0 is returned (see the class documentation).
        var waitStatus: Int32 = 0
        let waitedPid = waitpid(-1, &waitStatus, 0)
        if waitedPid > 0 {
            // Manual WIFEXITED / WEXITSTATUS: the C macros are not
            // relied on here so the status decode does not depend on
            // their Swift import.
            if (waitStatus & 0x7F) == 0 {
                return (waitStatus >> 8) & 0xFF
            }
            return 1
        }
        return 0
    }
}
