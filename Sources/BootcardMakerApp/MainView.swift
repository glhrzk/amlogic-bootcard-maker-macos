import SwiftUI
import UniformTypeIdentifiers
import BootcardCore

/// The single window, in the design doc's layout order: title and
/// description, Choose disk, Choose bin file, Partition and Format,
/// dry-run controls, Make, status line. The confirmation sheet is
/// the only confirmation step.
///
/// System font and semantic colours only: no custom font, no raw hex
/// colour, no icon-only button, no emoji anywhere in this window.
/// Text contrast in both themes, focus order, reduced motion, and
/// larger text are Mac-only checks (see `docs/ui-checklist.md`).
///
/// The operation runs off the main thread: `makeDiskOperation`'s
/// runner calls block, so the view model launches it in a detached
/// task and publishes the result back on the main actor. UI updates
/// happen only on the main actor.
///
/// Mac-gated: this file has not been built or run; SwiftUI and the
/// macOS SDK are absent from the Linux VM used to write it.
struct MainView: View {
    @StateObject private var viewModel = MainViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("BootcardMaker")
                    .font(.largeTitle)
                Text("Write a bootloader image to an SD card for Amlogic TV boxes. This erases the chosen disk.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Picker("Choose disk:", selection: $viewModel.selectedDiskID) {
                    Text("No disk selected").tag(nil as String?)
                    ForEach(viewModel.disks, id: \.identifier) { disk in
                        Text(diskLabel(disk)).tag(disk.identifier as String?)
                    }
                }
                .pickerStyle(.menu)
                .disabled(viewModel.dryRunEnabled || viewModel.isWorking)
                HStack(spacing: 8) {
                    Button("Refresh") {
                        viewModel.refreshDisks()
                    }
                    .disabled(viewModel.isWorking)
                    if let disk = viewModel.selectedDisk {
                        Text(diskDetail(disk))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if viewModel.dryRunEnabled {
                    Text("Dry run: no physical disk is used.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let error = viewModel.diskLoadError {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Choose your bin file:")
                HStack(spacing: 8) {
                    TextField(
                        "No file chosen",
                        text: .constant(viewModel.binURL?.path ?? "")
                    )
                    .disabled(true)
                    .textFieldStyle(.roundedBorder)
                    Button("Open…") {
                        viewModel.showFileImporter = true
                    }
                    .disabled(viewModel.isWorking)
                }
                if let size = viewModel.binSize {
                    Text("Size: \(formattedSize(size))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("To Partition and Format SD-card:")
                Toggle("Yes", isOn: $viewModel.partitionAndFormat)
                    .toggleStyle(.checkbox)
                    .disabled(viewModel.isWorking)
                if !viewModel.partitionAndFormat {
                    Text("The existing partition table is kept, and only the bin file is written.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Toggle(
                    "Dry run: write to a disk image file instead of a disk",
                    isOn: $viewModel.dryRunEnabled
                )
                .toggleStyle(.checkbox)
                .disabled(viewModel.isWorking)
                if viewModel.dryRunEnabled {
                    Picker("Image size:", selection: $viewModel.dryRunSize) {
                        ForEach(DryRunSize.allCases) { size in
                            Text(size.label).tag(size)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(viewModel.isWorking)
                    Text("The image is a sparse file. It is left in the temporary folder for inspection after a successful run.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button("Make") {
                viewModel.showConfirmation = true
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(!viewModel.canMake)

            if viewModel.isWorking {
                ProgressView()
                if let message = viewModel.workingMessage {
                    Text(message)
                }
                Text("Do not remove the card. There is no cancel once writing starts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let status = viewModel.statusMessage {
                Text(status)
                    .foregroundStyle(viewModel.statusIsError ? .red : .green)
            }
        }
        .padding(20)
        .frame(width: 560)
        .fileImporter(
            isPresented: $viewModel.showFileImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            viewModel.handleFileImporterResult(result)
        }
        .sheet(isPresented: $viewModel.showConfirmation) {
            ConfirmationView(viewModel: viewModel)
        }
        .onAppear {
            viewModel.refreshDisks()
        }
    }

    private func diskLabel(_ disk: DiskInfo) -> String {
        "\(disk.name) — \(formattedSize(disk.sizeBytes)) (\(disk.identifier))"
    }

    private func diskDetail(_ disk: DiskInfo) -> String {
        let removable = disk.isRemovable ? "yes" : "no"
        let external = disk.isExternal ? "yes" : "no"
        if disk.protocolName.isEmpty {
            return "Removable: \(removable) · External: \(external)"
        }
        return "Removable: \(removable) · External: \(external) · Protocol: \(disk.protocolName)"
    }

    private func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// The confirmation sheet: the only confirmation step. It repeats
/// the disk (or dry-run image), the bin file, and the partition and
/// format choice, and warns that the disk will be erased. Nothing is
/// written until `Erase and Make` is pressed.
struct ConfirmationView: View {
    @ObservedObject var viewModel: MainViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Confirm")
                .font(.title2)
            if viewModel.dryRunEnabled {
                Text("Dry-run disk image: \(viewModel.dryRunSize.label).")
                Text("A new disk image file will be created in the temporary folder and left there for inspection.")
            } else if let disk = viewModel.selectedDisk {
                Text("Disk: \(disk.name) — \(formattedSize(disk.sizeBytes)) (\(disk.identifier)).")
                Text("Removable: \(disk.isRemovable ? "yes" : "no") · External: \(disk.isExternal ? "yes" : "no")\(disk.protocolName.isEmpty ? "" : " · Protocol: \(disk.protocolName)").")
                Text("This erases the chosen disk. Make sure it is the right disk before continuing.")
                    .foregroundStyle(.red)
            }
            if let binURL = viewModel.binURL, let binSize = viewModel.binSize {
                Text("Bin file: \(binURL.lastPathComponent) — \(formattedSize(binSize)).")
            }
            Text("Partition and format SD-card: \(viewModel.partitionAndFormat ? "Yes" : "No").")
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                Spacer()
                Button("Erase and Make") {
                    dismiss()
                    viewModel.runOperation()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// Window state. All properties are published on the main actor;
/// disk listing and the operation run in detached tasks so their
/// blocking calls never run on the main thread.
@MainActor
final class MainViewModel: ObservableObject {
    @Published var disks: [DiskInfo] = []
    @Published var selectedDiskID: String? = nil
    @Published var binURL: URL? = nil
    @Published var binSize: Int64? = nil
    @Published var partitionAndFormat = true
    @Published var dryRunEnabled = false
    @Published var dryRunSize: DryRunSize = .default
    @Published var isWorking = false
    @Published var workingMessage: String? = nil
    @Published var statusMessage: String? = nil
    @Published var statusIsError = false
    @Published var showConfirmation = false
    @Published var showFileImporter = false
    @Published var diskLoadError: String? = nil

    var selectedDisk: DiskInfo? {
        disks.first { $0.identifier == selectedDiskID }
    }

    /// Make is enabled only with a valid bin file and, in physical
    /// mode, a selected disk. The original tool's quirk — a typed
    /// path that never writes — is not reproduced: a bin file
    /// chosen through the picker always writes.
    var canMake: Bool {
        !isWorking
            && binURL != nil
            && (binSize ?? 0) > 0
            && (dryRunEnabled || selectedDisk != nil)
    }

    /// Reload the disk list off the main thread. A disk that
    /// disappeared clears the selection. A failed load clears the
    /// list: no list is shown without a proven boot-disk exclusion.
    func refreshDisks() {
        Task.detached(priority: .userInitiated) {
            let result = Result { try DiskListProvider().loadSelectableDisks() }
            await MainActor.run { [weak self] in
                guard let self else { return }
                switch result {
                case .success(let disks):
                    self.disks = disks
                    self.diskLoadError = nil
                    if let selected = self.selectedDiskID,
                       !disks.contains(where: { $0.identifier == selected }) {
                        self.selectedDiskID = nil
                    }
                case .failure(let error):
                    self.disks = []
                    self.selectedDiskID = nil
                    self.diskLoadError = error.localizedDescription
                }
            }
        }
    }

    /// A cancelled picker is silent; a chosen file is validated
    /// (must exist, must be a regular non-empty file) before it
    /// counts as a bin file.
    func handleFileImporterResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            selectBinFile(url)
        case .failure:
            break
        }
    }

    private func selectBinFile(_ url: URL) {
        let path = url.path
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let sizeNumber = attributes[.size] as? NSNumber
        else {
            binURL = nil
            binSize = nil
            setStatus("The chosen file could not be read. Choose another bin file.", isError: true)
            return
        }
        let size = sizeNumber.int64Value
        guard size > 0 else {
            binURL = nil
            binSize = nil
            setStatus("The chosen file is empty. Choose a non-empty bin file.", isError: true)
            return
        }
        binURL = url
        binSize = size
        setStatus(nil, isError: false)
    }

    /// Run the operation in a detached task: the runner calls block.
    /// Only value types cross into the detached task; the result is
    /// published back on the main actor. Success is reported only
    /// when `makeDiskOperation` returns (its re-read verification
    /// passed); any error names the failed step and claims no
    /// rollback.
    func runOperation() {
        guard let binURL, (binSize ?? 0) > 0 else {
            setStatus("Choose a bin file first.", isError: true)
            return
        }
        let partitionAndFormat = partitionAndFormat
        let dryRunEnabled = dryRunEnabled
        let dryRunSize = dryRunSize
        let disk = selectedDisk
        isWorking = true
        workingMessage = dryRunEnabled
            ? "Creating the dry-run disk image and writing the bootloader image."
            : "Writing the bootloader image."
        statusMessage = nil
        statusIsError = false
        Task.detached(priority: .userInitiated) { [binURL, partitionAndFormat, dryRunEnabled, dryRunSize, disk] in
            do {
                let bin = try Data(contentsOf: binURL)
                let successMessage: String
                if dryRunEnabled {
                    let imageURL = try await DryRunSession.run(
                        bin: bin,
                        partitionAndFormat: partitionAndFormat,
                        size: dryRunSize
                    )
                    successMessage = "Success! The dry-run disk image is at \(imageURL.path). Inspect it before using a real card."
                } else {
                    guard let disk else { throw DiskOperationError.invalidInput }
                    try await makeDiskOperation(
                        disk: disk,
                        bin: bin,
                        partitionAndFormat: partitionAndFormat,
                        dryRunDevice: nil
                    )
                    successMessage = "Success! The card was written and verified by re-reading."
                }
                await MainActor.run { [weak self] in
                    self?.finishSuccess(successMessage)
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.finishError(error)
                }
            }
        }
    }

    private func finishSuccess(_ message: String) {
        isWorking = false
        workingMessage = nil
        setStatus(message, isError: false)
    }

    private func finishError(_ error: Error) {
        isWorking = false
        workingMessage = nil
        setStatus(error.localizedDescription, isError: true)
    }

    private func setStatus(_ message: String?, isError: Bool) {
        statusMessage = message
        statusIsError = isError
    }
}
