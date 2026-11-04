import SwiftUI

/// Entry point. One window, one scene. No menu customisation, no
/// document types, no background work: the app does nothing until
/// the user presses Make and confirms.
///
/// Mac-gated: this file has not been built or run; SwiftUI and the
/// macOS SDK are absent from the Linux VM used to write it.
@main
struct BootcardMakerApplication: App {
    var body: some Scene {
        WindowGroup("BootcardMaker") {
            MainView()
        }
        .windowResizability(.contentSize)
    }
}
