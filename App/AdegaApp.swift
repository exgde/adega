import AdegaCore
import SwiftUI

@main
struct AdegaApp: App {
    @StateObject private var model = AppModel()

    init() {
        // Os atalhos .app gerados pelo Adega executam este binário com
        // `--adega-run --bottle <id> -- <programa>`: abre o programa e sai, sem interface.
        if let request = HeadlessLaunch.parse(Array(CommandLine.arguments.dropFirst())) {
            do {
                _ = try HeadlessLaunch.perform(request)
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("Adega: \(error.localizedDescription)\n".utf8))
                exit(1)
            }
        }
    }

    var body: some Scene {
        WindowGroup("Adega") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 900, minHeight: 560)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Nova bottle…") { model.showingNewBottle = true }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .disabled(model.runtimes.isEmpty)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}
