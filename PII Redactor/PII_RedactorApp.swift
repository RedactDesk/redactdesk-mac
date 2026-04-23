//
//  PII_RedactorApp.swift
//  PII Redactor
//
//  Created by Selvam S on 23/04/26.
//

import SwiftUI
import CoreData

@main
struct PII_RedactorApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
