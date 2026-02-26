//
//  eventBuilder360App.swift
//  eventBuilder360
//
//  Created by Matthew Steiner on 26/02/2026.
//

import SwiftUI
import CoreData

@main
struct eventBuilder360App: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
