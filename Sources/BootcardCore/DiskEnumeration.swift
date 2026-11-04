import Foundation

/// Disk enumeration for the BootcardMaker macOS port.
///
/// This file only parses bytes. It performs no disk access and never
/// invokes `diskutil`: the live call (`diskutil list -plist`, fixed
/// arguments, argument array only) lives in a small `DiskListProvider`
/// in the app target and is deferred to Task 5, which owns the app
/// target's sources. The parser is in `BootcardCore` so it can be
/// unit-tested against fixture data without a Mac or a real disk.
///
/// Input shape: the property list printed by `diskutil list -plist`.
/// The top level is a dictionary whose `AllDisksAndPartitions` value
/// is an array of whole-disk dictionaries; each whole-disk dictionary
/// nests its partitions under `Partitions`. Only the top-level
/// (whole-disk) entries are returned; nested partition entries are
/// never returned as disks. `selectableDisks` additionally defends
/// against partition identifiers in case a caller passes a flattened
/// list.
///
/// Safety rule from the design's builder-check resolutions: listing is
/// not filtered to external disks only. A card in a built-in reader
/// may be reported as internal, so every whole disk except the boot
/// disk is listed, with its removable/external/protocol flags visible
/// for the user and the confirmation sheet. The boot-disk exclusion
/// and the confirmation sheet are the safety net, not the external
/// flag.
///
/// Key handling is lenient on purpose: real `diskutil` output varies
/// across macOS versions, and a missing flag must not lose a disk.
/// Unknown disks are treated as internal and non-removable (sorted
/// last), never as external. Flag keys tried, in order:
/// internal: `OSInternal`, `Internal`; removable: `Removable`,
/// `RemovableMedia`; protocol: `BusProtocol`, `DeviceProtocol`,
/// `Protocol`. A whole disk with no `VolumeName` (the usual case in
/// `list -plist` output) falls back to `MediaName`, then to its
/// identifier as its display name.

/// A whole disk as reported by `diskutil`.
public struct DiskInfo: Equatable {
    public let identifier: String
    public let name: String
    public let sizeBytes: Int64
    public let isRemovable: Bool
    public let isExternal: Bool
    public let protocolName: String

    public init(
        identifier: String,
        name: String,
        sizeBytes: Int64,
        isRemovable: Bool,
        isExternal: Bool,
        protocolName: String
    ) {
        self.identifier = identifier
        self.name = name
        self.sizeBytes = sizeBytes
        self.isRemovable = isRemovable
        self.isExternal = isExternal
        self.protocolName = protocolName
    }
}

/// Failures parsing `diskutil list -plist` output.
public enum DiskListParseError: Error {
    /// The data is not a property list at all.
    case invalidPlist
    /// The data is a property list but not the expected shape
    /// (top-level dictionary with an `AllDisksAndPartitions` array).
    case unexpectedFormat
}

/// Parse `diskutil list -plist` output into whole disks, in the order
/// reported. Nested partition entries are not returned.
///
/// - Throws: `DiskListParseError.invalidPlist` when the data is not a
///   property list, `DiskListParseError.unexpectedFormat` when it is
///   a property list of the wrong shape.
public func parseDiskList(_ plistData: Data) throws -> [DiskInfo] {
    let object: Any
    do {
        var format = PropertyListSerialization.PropertyListFormat.xml
        object = try PropertyListSerialization.propertyList(
            from: plistData, options: [], format: &format
        )
    } catch {
        throw DiskListParseError.invalidPlist
    }
    guard
        let top = object as? [String: Any],
        let entries = top["AllDisksAndPartitions"] as? [[String: Any]]
    else {
        throw DiskListParseError.unexpectedFormat
    }
    return entries.compactMap { diskInfo(from: $0) }
}

/// The disks the user may choose: whole disks only, boot disk
/// excluded, removable/external disks first, then by identifier.
///
/// A disk whose identifier carries a partition suffix (`disk2s1`) is
/// never selectable, even if a caller passes it in. The boot disk is
/// identified by `bootDiskIdentifier` (the whole-disk identifier of
/// the disk the system booted from, supplied by the caller); it is
/// never selectable.
public func selectableDisks(
    all disks: [DiskInfo],
    bootDiskIdentifier: String
) -> [DiskInfo] {
    disks
        .filter { isWholeDiskIdentifier($0.identifier) }
        .filter { $0.identifier != bootDiskIdentifier }
        .sorted { lhs, rhs in
            let lhsRank = (lhs.isRemovable ? 0 : 2) + (lhs.isExternal ? 0 : 1)
            let rhsRank = (rhs.isRemovable ? 0 : 2) + (rhs.isExternal ? 0 : 1)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return lhs.identifier < rhs.identifier
        }
}

private func diskInfo(from entry: [String: Any]) -> DiskInfo? {
    guard let identifier = stringValue(entry, keys: ["DeviceIdentifier"]),
          !identifier.isEmpty
    else {
        return nil
    }
    let isInternal = boolValue(entry, keys: ["OSInternal", "Internal"]) ?? true
    return DiskInfo(
        identifier: identifier,
        name: stringValue(entry, keys: ["VolumeName", "MediaName"]) ?? identifier,
        sizeBytes: int64Value(entry, keys: ["Size"]) ?? 0,
        isRemovable: boolValue(entry, keys: ["Removable", "RemovableMedia"]) ?? false,
        isExternal: !isInternal,
        protocolName: stringValue(entry, keys: ["BusProtocol", "DeviceProtocol", "Protocol"]) ?? ""
    )
}

/// True for whole-disk identifiers (`disk0`, `disk2`, `disk10`).
/// False for partition identifiers (`disk0s1`, `disk2s1`) and for
/// anything that is not a `disk<N>` identifier at all.
private func isWholeDiskIdentifier(_ identifier: String) -> Bool {
    guard identifier.hasPrefix("disk") else { return false }
    let rest = identifier.dropFirst("disk".count)
    return !rest.isEmpty
        && rest.unicodeScalars.allSatisfy(CharacterSet.decimalDigits.contains)
}

private func stringValue(_ dict: [String: Any], keys: [String]) -> String? {
    for key in keys {
        if let value = dict[key] as? String, !value.isEmpty {
            return value
        }
    }
    return nil
}

private func boolValue(_ dict: [String: Any], keys: [String]) -> Bool? {
    for key in keys {
        if let value = dict[key] as? Bool {
            return value
        }
    }
    return nil
}

private func int64Value(_ dict: [String: Any], keys: [String]) -> Int64? {
    for key in keys {
        if let value = dict[key] as? NSNumber {
            return value.int64Value
        }
        if let value = dict[key] as? Int {
            return Int64(value)
        }
    }
    return nil
}
