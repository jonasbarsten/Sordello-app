//
//  GRDBTestView.swift
//  Sordello
//
//  Proof of concept for GRDB with SwiftUI reactive updates
//  Created by Jonas Barsten on 08/12/2025.
//

import SwiftUI
import GRDB
import GRDBQuery

// MARK: - Test Model

/// Simple test item for proof of concept
struct TestItem: Codable, Identifiable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "test_items"

    var id: Int64?
    var name: String
    var createdAt: Date

    init(name: String) {
        self.name = name
        self.createdAt = Date()
    }

    // GRDB: Auto-assign ID after insert
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Database Manager

/// Manages the test database connection
@MainActor
@Observable
class TestDatabaseManager {
    static let shared = TestDatabaseManager()

    private(set) var dbQueue: DatabaseQueue?
    private(set) var databasePath: String?
    private(set) var isConnected = false
    private(set) var lastBackgroundInsert: String?

    private var countObservationTask: Task<Void, Never>?
    private(set) var itemCount = 0

    private init() {}

    /// Open or create database at the specified directory
    func openDatabase(at directoryURL: URL) throws {
        // Close existing connection
        close()

        let dbURL = directoryURL.appendingPathComponent("grdb_test.db")

        var config = Configuration()
        config.foreignKeysEnabled = true

        dbQueue = try DatabaseQueue(path: dbURL.path, configuration: config)
        databasePath = dbURL.path

        // Create table if needed
        try dbQueue?.write { db in
            try db.create(table: TestItem.databaseTableName, ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
        }

        isConnected = true

        // Start observing item count
        startObservingCount()

        print("GRDB Test: Opened database at \(dbURL.path)")
    }

    /// Close database connection
    func close() {
        countObservationTask?.cancel()
        countObservationTask = nil
        dbQueue = nil
        databasePath = nil
        isConnected = false
        itemCount = 0
    }

    /// Add a new test item (MainActor)
    func addItem(name: String) throws {
        guard let db = dbQueue else { throw DatabaseError.notConnected }

        try db.write { db in
            var item = TestItem(name: name)
            try item.insert(db)
        }
    }

    /// Add item from background Task - proves reactive updates work across actors
    func addItemInBackground(name: String) {
        guard let db = dbQueue else { return }

        // Capture db reference for background task
        let dbQueue = db

        Task.detached {
            // Simulate some background work
            try? await Task.sleep(for: .milliseconds(500))

            let itemName = "\(name) (background @ \(Date().formatted(date: .omitted, time: .standard)))"

            print("GRDB Test: Adding item from background thread: \(Thread.current)")

            do {
                try await dbQueue.write { db in
                    var item = TestItem(name: itemName)
                    try item.insert(db)
                }
                print("GRDB Test: Background insert succeeded")

                // Update UI state back on MainActor
                await MainActor.run {
                    TestDatabaseManager.shared.lastBackgroundInsert = itemName
                }
            } catch {
                print("GRDB Test: Background insert failed: \(error)")
            }
        }
    }

    /// Delete an item by ID
    func deleteItem(id: Int64) throws {
        guard let db = dbQueue else { throw DatabaseError.notConnected }

        _ = try db.write { db in
            try TestItem.deleteOne(db, key: id)
        }
    }

    /// Delete all items
    func deleteAllItems() throws {
        guard let db = dbQueue else { throw DatabaseError.notConnected }

        _ = try db.write { db in
            try TestItem.deleteAll(db)
        }
    }

    /// Observe item count for UI updates using async/await
    private func startObservingCount() {
        guard let db = dbQueue else { return }

        countObservationTask?.cancel()
        countObservationTask = Task {
            let observation = ValueObservation.tracking { db in
                try TestItem.fetchCount(db)
            }

            do {
                for try await count in observation.values(in: db) {
                    self.itemCount = count
                }
            } catch {
                // Observation cancelled or error
            }
        }
    }

    enum DatabaseError: Error, LocalizedError {
        case notConnected

        var errorDescription: String? {
            switch self {
            case .notConnected: return "Database not connected"
            }
        }
    }
}

// MARK: - Queryable Request for Items

/// Request that fetches all test items, sorted by creation date
struct AllTestItemsRequest: ValueObservationQueryable {
    static var defaultValue: [TestItem] { [] }

    func fetch(_ db: Database) throws -> [TestItem] {
        try TestItem
            .order(Column("createdAt").desc)
            .fetchAll(db)
    }
}


// MARK: - Test Views

/// Main test view with directory picker and item management
struct GRDBTestView: View {
    @State private var dbManager = TestDatabaseManager.shared
    @State private var newItemName = ""
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Connection status
                HStack {
                    Circle()
                        .fill(dbManager.isConnected ? Color.green : Color.red)
                        .frame(width: 12, height: 12)
                    Text(dbManager.isConnected ? "Connected" : "Not Connected")
                        .foregroundColor(.secondary)
                    Spacer()
                    if dbManager.isConnected {
                        Text("\(dbManager.itemCount) items")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)

                // Database path
                if let path = dbManager.databasePath {
                    Text(path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal)
                }

                // Directory picker button
                Button {
                    selectDirectory()
                } label: {
                    Label(
                        dbManager.isConnected ? "Change Database Location" : "Select Database Location",
                        systemImage: "folder"
                    )
                }
                .buttonStyle(.bordered)

                if dbManager.isConnected {
                    Divider()

                    // Add item section
                    HStack {
                        TextField("New item name", text: $newItemName)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                addItem()
                            }

                        Button("Add") {
                            addItem()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(newItemName.isEmpty)

                        Button("Add in Background") {
                            dbManager.addItemInBackground(name: newItemName.isEmpty ? "Background Item" : newItemName)
                            newItemName = ""
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal)

                    // Background insert feedback
                    if let lastBg = dbManager.lastBackgroundInsert {
                        Text("Last background insert: \(lastBg)")
                            .font(.caption)
                            .foregroundColor(.green)
                            .padding(.horizontal)
                    }

                    // Items list (reactive via @Query!)
                    if let dbQueue = dbManager.dbQueue {
                        TestItemListView()
                            .databaseContext(.readWrite { dbQueue })
                    }

                    Divider()

                    // Delete all button
                    Button(role: .destructive) {
                        deleteAll()
                    } label: {
                        Label("Delete All Items", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("GRDB Test")
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }

    private func selectDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Select Database Location"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try dbManager.openDatabase(at: url)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func addItem() {
        guard !newItemName.isEmpty else { return }

        do {
            try dbManager.addItem(name: newItemName)
            newItemName = ""
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func deleteAll() {
        do {
            try dbManager.deleteAllItems()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

/// List view that reactively displays items using @Query
struct TestItemListView: View {
    @Query(AllTestItemsRequest()) var items: [TestItem]

    var body: some View {
        List {
            ForEach(items) { item in
                HStack {
                    VStack(alignment: .leading) {
                        Text(item.name)
                            .fontWeight(.medium)
                        Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button(role: .destructive) {
                        deleteItem(item)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private func deleteItem(_ item: TestItem) {
        guard let id = item.id else { return }

        do {
            try TestDatabaseManager.shared.deleteItem(id: id)
        } catch {
            print("Failed to delete item: \(error)")
        }
    }
}

// MARK: - Second Observer Window (proves cross-view reactivity)

/// A separate window that observes the same database using @Query
/// This proves ValueObservation works across multiple views/windows
struct GRDBObserverWindow: View {
    @State private var dbManager = TestDatabaseManager.shared

    var body: some View {
        VStack(spacing: 16) {
            // Connection status
            HStack {
                Circle()
                    .fill(dbManager.isConnected ? Color.green : Color.red)
                    .frame(width: 12, height: 12)
                Text(dbManager.isConnected ? "Observing Database" : "Not Connected")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)

            if dbManager.isConnected, let dbQueue = dbManager.dbQueue {
                Text("This window subscribes to the same database.\nChanges made in the main window appear here automatically.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Background insert indicator
                if let lastBg = dbManager.lastBackgroundInsert {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Background: \(lastBg)")
                    }
                    .font(.caption)
                    .foregroundColor(.green)
                    .padding(.horizontal)
                }

                Divider()

                // Items list - reactive via @Query!
                ObserverItemsListView()
                    .databaseContext(.readWrite { dbQueue })
            } else {
                Spacer()
                Text("Open the main GRDB Test window\nand select a database location first.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
        }
        .padding()
        .frame(minWidth: 350, minHeight: 400)
    }
}

/// Helper view for observer window that uses @Query
struct ObserverItemsListView: View {
    @Query(AllTestItemsRequest()) var items: [TestItem]

    var body: some View {
        List {
            ForEach(items) { item in
                HStack {
                    VStack(alignment: .leading) {
                        Text(item.name)
                            .fontWeight(.medium)
                        Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Main Test View") {
    GRDBTestView()
}

#Preview("Observer Window") {
    GRDBObserverWindow()
}
