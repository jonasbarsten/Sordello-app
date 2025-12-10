//
//  GRDBTestView.swift
//  Sordello
//
//  Simple GRDB test using only async/await
//

import SwiftUI
import GRDB
import GRDBQuery

// MARK: - Shared Database (for cross-window access)

@Observable
class SharedTestDatabase {
    static let shared = SharedTestDatabase()
    var dbQueue: DatabaseQueue?
}

// MARK: - Test Model

struct TestItem: Codable, Identifiable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "test_items"

    var id: Int64?
    var name: String
    var createdAt: Date

    init(name: String) {
        self.name = name
        self.createdAt = Date()
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Query Request (for @Query)

struct AllTestItemsRequest: ValueObservationQueryable {
    static var defaultValue: [TestItem] { [] }

    func fetch(_ db: Database) throws -> [TestItem] {
        try TestItem.order(Column("createdAt").desc).fetchAll(db)
    }
}

// MARK: - Test View

struct GRDBTestView: View {
    @State private var newItemName = ""
    
    let dbQueue = SharedTestDatabase.shared.dbQueue

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Connection status
                HStack {
                    Circle()
                        .fill(dbQueue != nil ? Color.green : Color.red)
                        .frame(width: 12, height: 12)
                    Spacer()
                }
                .padding(.horizontal)

                // Select folder button
                Button {
                    selectDirectory()
                } label: {
                    Label(dbQueue != nil ? "Change Location" : "Select Database Location", systemImage: "folder")
                }
                .buttonStyle(.bordered)

                if dbQueue != nil {
                    Divider()

                    // Add item
                    HStack {
                        TextField("New item name", text: $newItemName)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { addItem() }

                        Button("Add") { addItem() }
                            .buttonStyle(.borderedProminent)
                            .disabled(newItemName.isEmpty)
                        
                        Button("Add concurrent") {
                            let tempName = newItemName
                            newItemName = ""
                            Task {
                                do {
                                    try await addItemConcurrent(newItemName: tempName)
                                } catch {
                                    print(error)
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(newItemName.isEmpty)
                        
                        Button("Add async") {
                            let tempName = newItemName
                            newItemName = ""
                            Task {
                                do {
                                    try await addItemAsync(newItemName: tempName)
                                    newItemName = ""
                                } catch {
                                    print(error)
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(newItemName.isEmpty)
                    }
                    .padding(.horizontal)

                    Button("Delete All", role: .destructive) { deleteAll() }
                        .buttonStyle(.bordered)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("GRDB Test (async/await)")
        }
    }

    // MARK: - Actions

    private func selectDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            openDatabase(at: url)
        }
    }

    private func openDatabase(at directoryURL: URL) {
        let dbURL = directoryURL.appendingPathComponent("grdb_test.db")

        do {
            let db = try DatabaseQueue(path: dbURL.path)

            try db.write { db in
                try db.create(table: TestItem.databaseTableName, ifNotExists: true) { t in
                    t.autoIncrementedPrimaryKey("id")
                    t.column("name", .text).notNull()
                    t.column("createdAt", .datetime).notNull()
                }
            }

            SharedTestDatabase.shared.dbQueue = db  // Share for observer window

        } catch {
            print("Failed to open database: \(error)")
        }
    }

    private func addItem() {
        guard let db = SharedTestDatabase.shared.dbQueue, !newItemName.isEmpty else { return }

        do {
            try db.write { db in
                let item = TestItem(name: newItemName)
                try item.insert(db)
            }
            newItemName = ""
        } catch {
            print("Failed to add item: \(error)")
        }
    }
    
    private func addItemAsync(newItemName: String) async throws {
        guard let db = SharedTestDatabase.shared.dbQueue, !newItemName.isEmpty else { return }
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        
        do {
            try await db.write { db in
                let item = TestItem(name: newItemName)
                try item.insert(db)
            }
        } catch {
            print("Failed to add async item: \(error)")
            throw(error)
        }
    }
    
    @concurrent
    private func addItemConcurrent(newItemName: String) async throws {
        guard let db = await SharedTestDatabase.shared.dbQueue, !newItemName.isEmpty else { return }
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        
        do {
            try await db.write { db in
                let item = TestItem(name: newItemName)
                try item.insert(db)
            }
        } catch {
            print("Failed to add concurrent item: \(error)")
            throw(error)
        }
    }

    private func deleteItem(_ item: TestItem) {
        guard let db = dbQueue, let id = item.id else { return }

        do {
            _ = try db.write { db in
                try TestItem.deleteOne(db, key: id)
            }
        } catch {
            print("Failed to delete item: \(error)")
        }
    }

    private func deleteAll() {
        guard let db = dbQueue else { return }

        do {
            _ = try db.write { db in
                try TestItem.deleteAll(db)
            }
        } catch {
            print("Failed to delete all: \(error)")
        }
    }
}

// MARK: - Observer Window (uses @Query)

struct GRDBObserverWindow: View {
    
    let db = SharedTestDatabase.shared.dbQueue

    var body: some View {
        VStack(spacing: 16) {
            Text("Observer Window (@Query)")
                .font(.headline)

            if let dataBase = db {
                Text("Using @Query - updates automatically!")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ObserverItemsList()
                    .databaseContext(.readOnly { dataBase })
            } else {
                Spacer()
                Text("Open main window and select a database first")
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding()
        .frame(minWidth: 350, minHeight: 400)
    }
}

/// Uses @Query to reactively fetch items
struct ObserverItemsList: View {
    @Query(AllTestItemsRequest()) var items: [TestItem]

    var body: some View {
        List {
            ForEach(items) { item in
                VStack(alignment: .leading) {
                    Text(item.name)
                    Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

#Preview {
    GRDBTestView()
}
