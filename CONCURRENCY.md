# Swift 6+ Concurrency Guidelines

Modern concurrency rules for targeting macOS 26+ and Swift 6.2+.

## Table of Contents

1. [Philosophy: Progressive Disclosure](#philosophy-progressive-disclosure)
2. [Swift 6.2 Default Isolation](#swift-62-default-isolation)
3. [The Three Phases of Concurrency](#the-three-phases-of-concurrency)
4. [Key Concepts](#key-concepts)
5. [Best Practices](#best-practices)
6. [Anti-Patterns to Avoid](#anti-patterns-to-avoid)
7. [SwiftUI + SwiftData Specifics](#swiftui--swiftdata-specifics)
8. [Migration Checklist](#migration-checklist)

---

## Philosophy: Progressive Disclosure

Swift 6.2 introduces **Approachable Concurrency** - developers only need to understand as much concurrency as they actually use. Data-race safety should feel like a natural part of coding, not a constant battle with the compiler.

The core principle: **Start simple, add concurrency only when needed.**

---

## Swift 6.2 Default Isolation

### MainActor by Default (SE-0466)

In Xcode 26+, new projects have **default MainActor isolation** enabled. This means:

- All code without explicit isolation annotations is assumed to run on `@MainActor`
- You opt INTO concurrency, rather than opting out
- UI code "just works" without sprinkling `@MainActor` everywhere

**Enable in Package.swift:**
```swift
.target(
    name: "MyTarget",
    swiftSettings: [
        .defaultIsolation(MainActor.self)
    ]
)
```

**Enable in Xcode:**
Build Settings → Swift Compiler - Upcoming Features → Default Actor Isolation → MainActor

### When to Use Default MainActor Isolation

| Use Case | Recommendation |
|----------|----------------|
| App targets | ✅ Yes - most code is UI-related |
| SwiftUI views | ✅ Yes - perfect fit |
| Networking packages | ❌ No - should be actor-agnostic |
| Utility libraries | ❌ No - let consumers choose isolation |

---

## The Three Phases of Concurrency

### Phase 1: Single-Threaded Code
Write simple, sequential code. With default MainActor isolation, everything runs on the main thread.

```swift
// Just works - no annotations needed
class UserManager {
    var currentUser: User?

    func updateUser(name: String) {
        currentUser?.name = name
    }
}
```

### Phase 2: Async/Await Without Parallelism
Use `async/await` for suspension (network calls, file I/O) without introducing shared state issues.

```swift
class DataLoader {
    func loadData() async throws -> Data {
        // Suspends, but stays on MainActor
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }
}
```

### Phase 3: True Parallelism
Only when you need performance, introduce explicit concurrency with `@concurrent` or separate actors.

```swift
// Explicitly opt into background execution
@concurrent
func processLargeFile(_ url: URL) async throws -> ProcessedData {
    // Runs off MainActor
    let data = try Data(contentsOf: url)
    return heavyProcessing(data)
}
```

---

## Key Concepts

### @MainActor
Ensures code runs on the main thread. Essential for UI updates.

```swift
@MainActor
class ViewModel: ObservableObject {
    @Published var items: [Item] = []

    func refresh() async {
        items = await fetchItems()  // UI update safe
    }
}
```

### Sendable
Types that can safely cross concurrency boundaries. Value types are implicitly Sendable.

```swift
// ✅ Structs are Sendable by default
struct User: Sendable {
    let id: UUID
    let name: String
}

// ❌ Classes need explicit conformance + immutability
final class Config: Sendable {
    let apiKey: String  // Must be immutable
    init(apiKey: String) { self.apiKey = apiKey }
}
```

### nonisolated
Marks code that doesn't belong to any actor. Useful for computed properties and protocol conformance.

```swift
@MainActor
class ViewModel {
    let id: UUID

    // Can be accessed from anywhere
    nonisolated var identifier: String {
        id.uuidString
    }
}
```

### nonisolated(nonsending) - Swift 6.2 Default
Async functions without isolation now run on the **caller's actor** by default.

```swift
// In Swift 6.2, this runs on caller's actor (e.g., MainActor if called from UI)
nonisolated func fetchData() async -> Data {
    // Inherits caller's isolation
}
```

### @concurrent
Explicitly opts async functions into background execution (Swift 6.2+).

```swift
// Forces execution OFF the caller's actor
@concurrent
func heavyComputation() async -> Result {
    // Always runs in background, never blocks UI
}
```

### Actors
Protect mutable state with automatic serialization. Use when you need thread-safe shared state.

```swift
actor ImageCache {
    private var cache: [URL: UIImage] = [:]

    func image(for url: URL) -> UIImage? {
        cache[url]
    }

    func store(_ image: UIImage, for url: URL) {
        cache[url] = image
    }
}
```

---

## Best Practices

### 1. Start on MainActor, Offload When Needed

```swift
// Default: runs on MainActor
func loadProject() async {
    let projectPath = selectedPath  // UI state access

    // Offload heavy work
    let data = await parseProjectInBackground(projectPath)

    // Back on MainActor for UI update
    self.projectData = data
}

@concurrent
private func parseProjectInBackground(_ path: String) async -> ProjectData {
    // Heavy parsing happens here
}
```

### 2. Use Structured Concurrency

Prefer `TaskGroup` and `async let` over unstructured `Task { }`:

```swift
// ✅ Structured - automatic cancellation, clear lifetime
func loadAllData() async throws -> AllData {
    async let users = fetchUsers()
    async let posts = fetchPosts()
    async let comments = fetchComments()

    return try await AllData(
        users: users,
        posts: posts,
        comments: comments
    )
}

// ❌ Unstructured - must manage lifetime manually
func loadAllData() {
    Task { await fetchUsers() }
    Task { await fetchPosts() }  // No coordination!
}
```

### 3. Favor Value Types for Shared Data

```swift
// ✅ Value types are inherently thread-safe
struct AppState {
    var user: User?
    var settings: Settings
    var isLoading: Bool
}

// ❌ Reference types need careful isolation
class AppState {
    var user: User?  // Data race risk!
}
```

### 4. Use withCheckedContinuation for Legacy Code

Bridge callback-based APIs to async/await:

```swift
func loadFile(at path: String) async -> Data? {
    await withCheckedContinuation { continuation in
        legacyLoader.load(path: path) { data in
            continuation.resume(returning: data)
        }
    }
}
```

### 5. Isolate Entire Types, Not Individual Properties

```swift
// ✅ Entire type is MainActor-isolated
@MainActor
class ViewModel {
    var data: [Item] = []
    var isLoading = false
}

// ❌ Split isolation causes issues
class ViewModel {
    @MainActor var data: [Item] = []
    var isLoading = false  // Different isolation!
}
```

---

## Anti-Patterns to Avoid

### ❌ Task.detached Overuse

```swift
// ❌ Loses priority, task-local values, and parent task relationship
Task.detached {
    await self.doWork()
}

// ✅ Use @concurrent function instead
@concurrent
func doWork() async {
    // Explicit, safe background execution
}
```

### ❌ MainActor.run for Everything

```swift
// ❌ Bypasses type safety
func updateUI() async {
    await MainActor.run {
        self.label.text = "Updated"
    }
}

// ✅ Make the function itself MainActor-isolated
@MainActor
func updateUI() {
    self.label.text = "Updated"
}
```

### ❌ DispatchSemaphore with Async Code

```swift
// ❌ WILL DEADLOCK
let semaphore = DispatchSemaphore(value: 0)
Task {
    await asyncWork()
    semaphore.signal()
}
semaphore.wait()  // Blocks thread async work needs!

// ✅ Use async/await properly
let result = await asyncWork()
```

### ❌ Stateless Actors

```swift
// ❌ Actor with no state to protect
actor NetworkService {
    func fetch(_ url: URL) async -> Data { ... }
}

// ✅ Use nonisolated async function
nonisolated func fetch(_ url: URL) async -> Data { ... }
```

### ❌ Blocking Main Thread for Async Work

```swift
// ❌ Never do this
func loadSync() -> Data {
    var result: Data?
    let group = DispatchGroup()
    group.enter()
    Task {
        result = await loadAsync()
        group.leave()
    }
    group.wait()  // Blocks main thread!
    return result!
}

// ✅ Accept async nature
func load() async -> Data {
    await loadAsync()
}
```

### ❌ Excessive Closure Code

```swift
// ❌ Hard to diagnose concurrency issues
Task {
    let x = await { () async -> Int in
        await { () async -> Int in
            await someAsyncWork()
        }()
    }()
}

// ✅ Extract to named functions
func processWork() async -> Int {
    await someAsyncWork()
}
```

---

## SwiftUI + SwiftData Specifics

### Views Are MainActor by Default

```swift
struct ContentView: View {
    @State private var items: [Item] = []

    var body: some View {
        List(items) { item in
            Text(item.name)
        }
        .task {
            // Runs on MainActor, safe to update @State
            items = await loadItems()
        }
    }
}
```

### SwiftData ModelContext

`ModelContext` is **not Sendable** - always access on MainActor:

```swift
@MainActor
class DataManager {
    private let context: ModelContext

    func save(_ item: Item) {
        context.insert(item)
        try? context.save()
    }

    // Heavy work off MainActor, only write on MainActor
    func importLargeDataset(_ urls: [URL]) async {
        for url in urls {
            // Parse in background
            let parsed = await parseInBackground(url)

            // Write on MainActor (we're already here due to class isolation)
            for item in parsed {
                context.insert(item)
            }
            try? context.save()
        }
    }

    @concurrent
    private func parseInBackground(_ url: URL) async -> [Item] {
        // Heavy CPU work happens here
    }
}
```

### Background Processing Pattern

```swift
// Pattern: Heavy work in background, SwiftData writes on MainActor
func processFiles(_ paths: [String]) async {
    for path in paths {
        // 1. Heavy parsing OFF MainActor
        let result = await parseFileInBackground(path)

        // 2. Quick SwiftData write ON MainActor (automatic if class is @MainActor)
        saveToSwiftData(result)
    }
}

@concurrent
private func parseFileInBackground(_ path: String) async -> ParsedData {
    // CPU-intensive work
    autoreleasepool {
        let parser = HeavyParser()
        return parser.parse(path)
    }
}
```

---

## Migration Checklist

### Enabling Swift 6 Strict Concurrency

1. **Set Swift Language Version to 6** in Build Settings
2. **Enable Strict Concurrency Checking** (Complete)
3. **Fix errors incrementally** - one module at a time

### Common Fixes

| Error | Solution |
|-------|----------|
| "not Sendable" | Make type Sendable, use actor, or isolate to MainActor |
| "actor-isolated property" | Add `await`, use `nonisolated`, or access from same actor |
| "data race" | Use actors, isolation, or make immutable |
| "@MainActor required" | Add `@MainActor` or call with `await` |

### Swift 6.2 Approachable Concurrency Features

Enable individually for controlled migration:

1. **SE-0401**: Disable Outward Actor Isolation Inference
2. **SE-0434**: Global-Actor-Isolated Types Usability
3. **SE-0470**: Global-Actor-Isolated Conformances
4. **SE-0418**: Inferring Sendable for Methods
5. **SE-0461**: nonisolated(nonsending) by Default

---

## References

- [Swift 6.2 Concurrency Changes - SwiftLee](https://www.avanderlee.com/concurrency/swift-6-2-concurrency-changes/)
- [Approachable Concurrency in Swift 6.2 - SwiftLee](https://www.avanderlee.com/concurrency/approachable-concurrency-in-swift-6-2-a-clear-guide/)
- [Default Actor Isolation - SwiftLee](https://www.avanderlee.com/concurrency/default-actor-isolation-in-swift-6-2/)
- [Problematic Swift Concurrency Patterns - massicotte.org](https://www.massicotte.org/problematic-patterns/)
- [Default Isolation Swift 6.2 - massicotte.org](https://www.massicotte.org/default-isolation-swift-6_2)
- [Swift 6.2 Released - Swift.org](https://www.swift.org/blog/swift-6.2-released/)
- [Complete Concurrency - Hacking with Swift](https://www.hackingwithswift.com/swift/6.0/concurrency)
- [Swift 6 Migration Best Practices - byby.dev](https://byby.dev/swift-6-migration-best-practices)
- [Exploring Concurrency Changes in Swift 6.2 - Donny Wals](https://www.donnywals.com/exploring-concurrency-changes-in-swift-6-2/)
