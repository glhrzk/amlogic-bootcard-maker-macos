import Foundation

/// The disk operation: validate, elevate, unmount, optionally
/// partition and format, read the live sector 0, write the
/// bootloader buffer from byte offset 0, and verify by re-reading.
///
/// Order follows the Windows Make handler (REA report §4, branch B),
/// with two macOS additions that the original did not have: the disk
/// is unmounted before the raw write, and the written bytes are
/// verified by re-reading. No step is skipped when an earlier step
/// fails: any failure aborts with the failing step's
/// `DiskOperationError`, and success is reported only when the
/// re-read comparison matches.
///
/// The 66-byte rule is the one place where byte-exact fidelity
/// matters most, and it is implemented exactly once, in
/// `buildWriteBuffer` (Task 2): bytes 446–511 of the written buffer
/// come from the live sector 0 read in this file, bytes 0–445 come
/// from the bin file verbatim. Bytes 440–445 therefore come from the
/// bin file, exactly as the original tool behaves — even though
/// `buildMBR` writes the disk signature `0xF0CCF0CC` at offset 440
/// for the intermediate MBR step below. Nothing in this file widens
/// the copy to 440–511. Do not "fix" that: widening it would change
/// the on-disk result away from the Windows tool's.
///
/// Elevation: physical disks run every command through
/// `AuthorizationRunner` (admin rights obtained once, in its
/// initializer). Dry-run images run through `ProcessRunner` with no
/// elevation at all: an attached user-owned image is writable
/// without admin rights, and asking for elevation in dry-run mode
/// would be a bug.
///
/// Raw reads and writes go through `dd` with argument arrays built by
/// `BootcardCore` (see `DiskCommandBuilders.swift`), via temporary
/// files: the buffer is written to a temporary file and `dd` copies
/// it to the raw device, and sector reads go the other way. The
/// temporary files are created with mode 0600, hold only the
/// bootloader image and disk sectors, and are deleted when the step
/// finishes. Swift never opens `/dev/rdiskN` directly in this file,
/// so the privileged path needs no file-descriptor passing between
/// the unprivileged app process and the privileged tools.
///
/// Mac-gated: nothing in this file has run on a Mac or against a real
/// disk from this Linux VM. In particular, whether the partition
/// device node (`diskNs1`) appears promptly after the raw MBR write
/// on Tahoe is unverified; if it does not, the format step fails
/// cleanly with `formatFailed` and the operation must gain a
/// re-probe step before it can succeed. That step must not be
/// invented here without Mac evidence.
///
/// - Parameters:
///   - disk: The selected whole disk. When `dryRunDevice` is set,
///     `disk` must describe the attached image node (its identifier
///     and size), not the physical disk it stands in for; Task 5's
///     dry-run mode supplies that description.
///   - bin: The whole bootloader file, read by the caller.
///   - partitionAndFormat: The Yes checkbox. When false, the MBR and
///     format steps are skipped and the card's existing partition
///     table is preserved through the live sector 0 copy.
///   - dryRunDevice: A whole-disk identifier for an attached image
///     (for example `disk4`), or `nil` for a physical disk.
public func makeDiskOperation(
    disk: DiskInfo,
    bin: Data,
    partitionAndFormat: Bool,
    dryRunDevice: String?
) async throws {
    // 1. Validate before anything is written or elevated. The guards
    // are Task 2's: empty bin, disk too small for the 2-cylinder
    // gap, or a bin image longer than the gap all refuse here.
    guard validateWrite(diskTotalBytes: disk.sizeBytes, fileLength: bin.count) else {
        throw DiskOperationError.invalidInput
    }
    let targetIdentifier = dryRunDevice ?? disk.identifier
    guard let rawDevicePath = rawDevicePath(for: targetIdentifier),
          let wholeDevicePath = devicePath(for: targetIdentifier)
    else {
        throw DiskOperationError.invalidInput
    }
    let isDryRun = dryRunDevice != nil
    // 2. Elevation, once per operation, physical disks only.
    // `AuthorizationRunner.init` throws `elevationDenied` when admin
    // rights are refused or unavailable; nothing has been written.
    let runner: any DiskCommandRunner
    if isDryRun {
        runner = ProcessRunner()
    } else {
        runner = try AuthorizationRunner()
    }

    // 3. Unmount the whole disk so the raw write does not fight an
    // automounted volume.
    try runStep(
        try buildCommand { try unmountDiskCommand(devicePath: wholeDevicePath) },
        with: runner,
        failure: .unmountFailed
    )

    if partitionAndFormat {
        // 4a. Write the MBR through the raw device, using only
        // `buildMBR` output. The MBR is never re-derived here: the
        // signature, entry, CHS fields, and start/length all come
        // from Task 2's builder, which is the unit-tested code.
        let partitionLengthBytes =
            disk.sizeBytes - partitionStartSectors * Int64(sectorSize)
        let mbr = buildMBR(
            totalBytes: disk.sizeBytes,
            startSectors: partitionStartSectors,
            partitionLengthBytes: partitionLengthBytes
        )
        try writeToDevice(
            mbr,
            devicePath: rawDevicePath,
            runner: runner,
            failure: .partitionFailed
        )
        // The original helper sleeps 300 ms after applying the
        // layout; keep the pause so the system can notice the new
        // partition table before the format step runs.
        try await Task.sleep(nanoseconds: 300_000_000)
        // Verify the MBR landed before formatting on top of it.
        let mbrBack = try readFromDevice(
            rawDevicePath,
            sectorCount: 1,
            runner: runner,
            failure: .partitionFailed
        )
        guard mbrBack == mbr else {
            throw DiskOperationError.partitionFailed
        }
        // 4b. Format the partition as FAT32 with default parameters.
        guard let partitionDevicePath = partitionDevicePath(for: targetIdentifier),
              let rawPartitionDevicePath = rawPartitionDevicePath(for: targetIdentifier)
        else {
            throw DiskOperationError.invalidInput
        }
        try runStep(
            try buildCommand { try newfsMsdosCommand(partitionDevicePath: partitionDevicePath) },
            with: runner,
            failure: .formatFailed
        )
        // Unmount again: formatting may have automounted the new
        // FAT32 volume, and the raw write below must not fight it.
        try runStep(
            try buildCommand { try unmountDiskCommand(devicePath: wholeDevicePath) },
            with: runner,
            failure: .unmountFailed
        )
        // Verify the format produced a FAT32 boot sector before the
        // bin write overwrites the gap in front of the partition.
        let bootSector = try readFromDevice(
            rawPartitionDevicePath,
            sectorCount: 1,
            runner: runner,
            failure: .formatFailed
        )
        guard isFAT32BootSector(bootSector) else {
            throw DiskOperationError.formatFailed
        }
    }

    // 5. Read the live sector 0 after partitioning/formatting (or
    // the card's existing sector 0 when Yes was unticked). This read
    // is never cached or assumed: it is the source of bytes 446–511.
    let liveSector0 = try readFromDevice(
        rawDevicePath,
        sectorCount: 1,
        runner: runner,
        failure: .readFailed
    )

    // 6. Build the buffer: bin verbatim for bytes 0–445, live
    // partition table for bytes 446–511, zero padding to whole
    // sectors. See the file header: do not widen the copy.
    let buffer = buildWriteBuffer(bin: bin, liveSector0: liveSector0)

    // 7. Write the buffer from byte offset 0.
    try writeToDevice(
        buffer,
        devicePath: rawDevicePath,
        runner: runner,
        failure: .writeFailed
    )

    // 8. Verify by re-reading the written sectors and comparing the
    // whole buffer. Success is reported only on a match.
    let writtenBack = try readFromDevice(
        rawDevicePath,
        sectorCount: writeLengthSectors(fileLength: bin.count),
        runner: runner,
        failure: .verificationFailed
    )
    guard writtenBack == buffer else {
        throw DiskOperationError.verificationFailed
    }
}

/// Run one command; any failure (spawn failure or non-zero status)
/// becomes the calling step's error.
private func runStep(
    _ command: DiskCommand,
    with runner: any DiskCommandRunner,
    failure: DiskOperationError
) throws {
    do {
        let status = try runner.run(command)
        guard status == 0 else { throw failure }
    } catch let error as DiskOperationError {
        throw error
    } catch {
        throw failure
    }
}

/// Build a command, mapping a builder rejection (a malformed path
/// that survived validation) to `invalidInput`.
private func buildCommand(_ builder: () throws -> DiskCommand) throws -> DiskCommand {
    do {
        return try builder()
    } catch {
        throw DiskOperationError.invalidInput
    }
}

/// Write `data` to a raw device from byte offset 0, via a temporary
/// file and `dd`. A vanished device node is `diskDisappeared`; any
/// other failure is the calling step's error.
private func writeToDevice(
    _ data: Data,
    devicePath: String,
    runner: any DiskCommandRunner,
    failure: DiskOperationError
) throws {
    guard FileManager.default.fileExists(atPath: devicePath) else {
        throw DiskOperationError.diskDisappeared
    }
    do {
        try withTemporaryFile(named: "bootcardmaker-write", data: data) { inputPath in
            let command = try ddWriteCommand(inputPath: inputPath, devicePath: devicePath)
            let status = try runner.run(command)
            guard status == 0 else { throw failure }
        }
    } catch is DiskCommandError {
        throw DiskOperationError.invalidInput
    } catch let error as DiskOperationError {
        throw error
    } catch {
        throw failure
    }
}

/// Read exactly `sectorCount` sectors from a raw device, via `dd`
/// into a temporary file. A vanished device node is
/// `diskDisappeared`; a short or failed read is the calling step's
/// error.
private func readFromDevice(
    _ devicePath: String,
    sectorCount: Int,
    runner: any DiskCommandRunner,
    failure: DiskOperationError
) throws -> Data {
    guard FileManager.default.fileExists(atPath: devicePath) else {
        throw DiskOperationError.diskDisappeared
    }
    do {
        return try withTemporaryFile(named: "bootcardmaker-read", data: nil) { outputPath in
            let command = try ddReadCommand(
                devicePath: devicePath,
                outputPath: outputPath,
                sectorCount: sectorCount
            )
            let status = try runner.run(command)
            guard status == 0 else { throw failure }
            let data = try Data(contentsOf: URL(fileURLWithPath: outputPath))
            guard data.count == sectorCount * sectorSize else { throw failure }
            return data
        }
    } catch is DiskCommandError {
        throw DiskOperationError.invalidInput
    } catch let error as DiskOperationError {
        throw error
    } catch {
        throw failure
    }
}

/// A temporary file holding `data` (or empty when `data` is `nil`),
/// mode 0600, deleted when `body` returns. Used only to hand bytes
/// to `dd`, which is the tool that touches the raw device.
private func withTemporaryFile<T>(
    named prefix: String,
    data: Data?,
    _ body: (String) throws -> T
) throws -> T {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(prefix)-\(UUID().uuidString).tmp")
    if let data {
        try data.write(to: url, options: [.atomic])
    } else {
        _ = FileManager.default.createFile(atPath: url.path, contents: Data())
    }
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o600],
        ofItemAtPath: url.path
    )
    defer { try? FileManager.default.removeItem(at: url) }
    return try body(url.path)
}

/// True when a sector looks like a FAT32 boot sector: the `FAT32   `
/// filesystem-type label at offset 82 and the `0x55AA` signature.
/// This is a format sanity check only, not a filesystem validation;
/// FAT32 equivalence with a Windows-produced card remains unverified
/// (see the design doc).
private func isFAT32BootSector(_ sector: Data) -> Bool {
    guard sector.count >= sectorSize else { return false }
    return sector[82..<90] == Data("FAT32   ".utf8)
        && sector[510] == 0x55
        && sector[511] == 0xAA
}
