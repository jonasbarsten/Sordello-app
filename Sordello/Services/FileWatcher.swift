//
//  FileWatcher.swift
//  Sordello
//
//  Created by Jonas Barsten on 07/12/2025.
//

import Foundation

/// Watches files for changes using DispatchSource
class FileWatcher {
    static let shared = FileWatcher()

    private var watchers: [String: DispatchSourceFileSystemObject] = [:]

    init() {}

    /// Start watching a directory for changes
    func watchFile(at path: String, onChange: @escaping () -> Void) {
        // Stop existing watcher for this path
        stopWatching(path: path)

        let fileDescriptor = open(path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            print("FileWatcher: Failed to open file: \(path)")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: .write,
            queue: DispatchQueue.main
        )

        source.setEventHandler {
            print("File change detected: \(path)")
            onChange()
        }

        source.setCancelHandler {
            close(fileDescriptor)
        }

        watchers[path] = source
        source.activate()

        print("FileWatcher: Now watching \(path)")
    }

    /// Stop watching a specific file
    func stopWatching(path: String) {
        if let source = watchers[path] {
            source.cancel()
            watchers.removeValue(forKey: path)
            print("FileWatcher: Stopped watching \(path)")
        }
    }

    /// Stop all file watchers
    func stopAll() {
        for (_, source) in watchers {
            source.cancel()
        }
        watchers.removeAll()
    }
}
