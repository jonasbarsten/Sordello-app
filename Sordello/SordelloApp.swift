//
//  SordelloApp.swift
//  Sordello
//
//  Created by Jonas Barsten on 07/12/2025.
//

import SwiftUI

@main
struct SordelloApp: App {
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Project...") {
                    ProjectManager.shared.openProject()
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandGroup(after: .newItem) {
                Divider()
                Button("GRDB Test Windows") {
                    openWindow(id: "grdb-test")
                    openWindow(id: "grdb-observer")
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            }
        }

        // Test window for GRDB proof of concept
        WindowGroup("GRDB Test", id: "grdb-test") {
            GRDBTestView()
        }
        .defaultSize(width: 500, height: 600)

        // Observer window - proves reactive updates work across windows
        WindowGroup("GRDB Observer", id: "grdb-observer") {
            GRDBObserverWindow()
        }
        .defaultSize(width: 400, height: 500)
    }
}
