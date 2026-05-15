import SwiftUI

@main
struct PancakeSongCheckApp: App {
    var body: some Scene {
        WindowGroup {
            PromptLabView()
                .frame(minWidth: 760, idealWidth: 980, minHeight: 560, idealHeight: 820)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
