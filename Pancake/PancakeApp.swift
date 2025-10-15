//
//  PancakeApp.swift
//  Pancake
//
//  Created by Matthew Lucas on 8/7/25.
//

import SwiftUI

@main
struct PancakeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    // Request MusicKit authorization when app starts
                    Task {
                        await MusicKitService.shared.requestAuthorization()
                    }
                }
        }
    }
}
