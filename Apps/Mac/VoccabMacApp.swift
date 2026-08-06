import AppKit
import SwiftUI

@main
struct VoccabMacApp: App {
    @NSApplicationDelegateAdaptor(VoccabMacAppDelegate.self) private var appDelegate

    @StateObject private var env = MacEnvironment()
    @StateObject private var store = DraftStore()

    var body: some Scene {
        // `Window`, not `WindowGroup`: there is exactly one draft, so there is
        // exactly one workspace. Two windows over one file would be a race
        // over the thing this app promises never to lose.
        Window("Voccab Workspace", id: "workspace") {
            WorkspaceView(store: store)
                .environmentObject(env)
        }
        .defaultSize(width: 1_020, height: 680)
        .windowResizability(.contentMinSize)
        .commands {
            WorkspaceCommands(store: store)
        }
    }
}

/// Save-on-quit, the reliable way.
///
/// `applicationWillTerminate` is synchronous, so a flush here is guaranteed to
/// finish before the process goes away — unlike anything scheduled on a queue
/// or in a `Task`. `DraftStore` stages the document on every keystroke, so the
/// delegate never needs to reach into the view layer to find the current text.
final class VoccabMacAppDelegate: NSObject, NSApplicationDelegate {

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        DraftPersistence.shared.flush()
    }
}

/// Menu-bar commands. They talk to the same store the window does, so ⌘N lands
/// a row below the caret rather than at the bottom of the page.
struct WorkspaceCommands: Commands {
    @ObservedObject var store: DraftStore

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Row") {
                store.newRow()
            }
            .keyboardShortcut("n", modifiers: .command)
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save Draft") {
                store.saveNow()
            }
            .keyboardShortcut("s", modifiers: .command)
        }

        CommandMenu("Draft") {
            Button("Move Row Up") {
                if let id = store.focusedRowID { store.move(id: id, by: -1) }
            }
            .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            .disabled(store.focusedRowID == nil)

            Button("Move Row Down") {
                if let id = store.focusedRowID { store.move(id: id, by: 1) }
            }
            .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            .disabled(store.focusedRowID == nil)

            Divider()

            Button("Remove Blank Rows") {
                store.removeBlankRows()
            }
        }
    }
}
