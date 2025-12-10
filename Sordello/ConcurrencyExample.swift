//
//  AsyncTestView.swift
//  Sordello
//
//  Created by Jonas Barsten on 09/12/2025.
//

import SwiftUI


// When we pass data between actors they are copied
// For data ta be copied between actors, they have to be Sendable
// Value crosing into or out of an actor are checked for Sendable type
// Non-Sendable values are only allowed if they are never used again

// Value types are Sendable
// extension URL: Sendable {}

// Collections of Sendable elements
// extension Array: Sendable where Element: Sendable {}

// Struct and enums with Sendable storage
//struct ImageRequest: Sendable {
//    var url: URL
//}

// Main-actor types are implicitly Sendable
// @MainActor class ImageModel: **Sendable** {}

// When ever we call concurrent code with for example await, we both send the data in the arguments, but also an implicitly self if it is an instance method.
// await asyncTest() = await self.asyncTest()
// So, I think that structs or classes that have functions with concurrent code have to be @MainActor since Main-actor types are implicitly Sendable. And in Swift 6.2 all structs and classes by default are in the MainActor, I think

// So let us say the AlsParser, that has some functions that should run in the background, should be @MainActor since self is sent together with the await function call

// Classes are rarely sendable
// Clases are reference types, meaning that they point to the same object in memory.

// nonisolated class MyImage {}
// let image = MyImage()
// let otherImage = image // refers to the same object as image
// image.scale(by: 0.5) // also changes otherImage

// Like classes, closures can create shared state
// Only make a function type Sendable if you need to share it concurrently



// ACTORS:

// If we have a lot of data on the main actor that is causing those async tasks to "check in" with the main thread too often, you might want to introduce actors.
// As the app grows, the amount of state on the main actor also grows
// For example set of open connections handles by a network manager
// If for example a function is trying to run on a background thread, but has to hop over to the main thread because thats where the network managers data is
// This can lead to contention where many tasks are trying to run code on the main actor at the same time.
// The individual operation might be quick, but if you have a lot of tasks doing this, it can add up to UI glitches
// In this case we could introduce our own network manager actor
// Like the main actor, actors isolate their data so you can only access that data when running on that actor
// Along with the main actor, you can define your own actor types. An actor type is similar to a main-actor class. Like a main-actor class, it will isolate its data so only one thread can touch the data at a time.
// An actor type is also Sendable so you can freely share actor objects
// Unlike the main actor, there can be many actor objects in a program. Each of which is independent. Actor instances can run on background threads
// In addition, actor objects are not tied to a single thread like the main actor is
// Use actors when you find that storing data on the main actor i causing too much code to run on the main thread

//actor NetworkManager {
//    var openConnections: [URL: Connection] = [:]
//    func fetchData(from url: URL) async throws -> Data {}
//}

// Most classes are not supposed to be actors
// UI-facing classes should stay on the main actor
// Model classes should be @MainActor or non-Sendable as to not encourage lots of concurrent access to your model

nonisolated struct ConcurrenctTestStruct {
    func someStupidFunction () async -> String {
        print("Hello from some stupid function!")
        return "Lol"
    }
    
    func someStupidFunctionNotAsync () -> String {
        print("Hello from not async")
        return "Lol"
    }
}

struct ConcurrencyExample: View {
    
    @State private var text: String = ""
    
    var body: some View {
        Text("Hello, World!")
        TextEditor(text: $text)
        Button("Load async") {
            Task {
                let asyncRes = await asyncTest()
                print(asyncRes)
            }
            
            Task {
                let concurrentRes = await concurrentTest()
                print(concurrentRes)
            }
            
            Task {
                let nonIsolatedRes = await nonIsolatedTest()
                print(nonIsolatedRes)
            }
        }
    }
    
    // Standard async / await tasks to hide latency as the UI keeps being responsive
    private func asyncTest() async -> String {
        // We CAN access non-static stuff from the Main thread here
        // let parser = AlsParser()
        
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        return "Hello from async!"
    }
    
    // @concurrent can access more threads, I think and it will always run on a background thread
    // And it will always jump off the actor where it was called
    @concurrent
    private func concurrentTest() async -> String {
        
        
        let parser = AlsParser()
        parser.parse(at: URL(string: "https://example.com")!)
        
        // We can not access non-static stuff from the Main thread here
        // Like for example this:
//        let parser = AlsParser()
        // Main actor-isolated initializer 'init()' cannot be called from outside of the actor
        
        // But we can do this:
        let someStruct = ConcurrenctTestStruct()
        _ = await someStruct.someStupidFunctionNotAsync()
        _ = await someStruct.someStupidFunction()
        
        
        try? await Task.sleep(nanoseconds: 7_000_000_000)
        return "Hello from concurrent!"
    }
    
    // nonisolated will make the function stay on what ever actor it was called on
    nonisolated private func nonIsolatedTest() async -> String {
        // We can not access non-static stuff from the Main thread here
        // Like for example this:
//        let parser = AlsParser()
        // Main actor-isolated initializer 'init()' cannot be called from outside of the actor
        
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        return "Hello from non-isolated!"
    }
    
    
    
}

#Preview {
    ConcurrencyExample()
}
