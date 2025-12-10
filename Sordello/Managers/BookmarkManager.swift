//
//  BookmarkManager.swift
//  Sordello
//
//  Manages security-scoped bookmarks for sandboxed file access.
//  Bookmarks allow the app to access user-selected folders across app launches.
//
//  Created by Jonas Barsten on 10/12/2025.
//

import Foundation

/// Manages security-scoped bookmarks for file system access in sandboxed apps
final class BookmarkManager {
    static let shared = BookmarkManager()

    /// Store security-scoped bookmarks keyed by path
    private var bookmarks: [String: Data] = [:]

    private init() {}

    // MARK: - Bookmark Management

    /// Save a security-scoped bookmark for a URL
    /// Call this after user selects a folder via NSOpenPanel
    func saveBookmark(for url: URL) {
        do {
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            bookmarks[url.path] = bookmark
            print("BookmarkManager: Saved bookmark for \(url.path)")
        } catch {
            print("BookmarkManager: Failed to create bookmark: \(error)")
        }
    }

    /// Check if we have a bookmark for a path
    func hasBookmark(for path: String) -> Bool {
        bookmarks[path] != nil
    }

    /// Get the bookmark data for a path (used for background operations)
    func getBookmarkData(for path: String) -> Data? {
        bookmarks[path]
    }

    // MARK: - File Access

    /// Access a file/folder using its security-scoped bookmark
    /// The action closure is called with the resolved URL while security access is active
    func accessFile(at path: String, action: (URL) -> Void) {
        guard let bookmark = bookmarks[path] else {
            print("BookmarkManager: No bookmark found for \(path)")
            return
        }

        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                // Bookmark is stale, recreate it
                print("BookmarkManager: Refreshing stale bookmark for \(path)")
                saveBookmark(for: url)
            }

            // Start accessing the security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                print("BookmarkManager: Failed to start accessing security-scoped resource")
                return
            }

            defer {
                url.stopAccessingSecurityScopedResource()
            }

            action(url)
        } catch {
            print("BookmarkManager: Failed to resolve bookmark: \(error)")
        }
    }

    /// Resolve a bookmark to a URL and start security-scoped access
    /// Caller is responsible for calling stopAccessingSecurityScopedResource()
    func startAccess(for path: String) -> URL? {
        guard let bookmark = bookmarks[path] else {
            print("BookmarkManager: No bookmark found for \(path)")
            return nil
        }

        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                saveBookmark(for: url)
            }

            guard url.startAccessingSecurityScopedResource() else {
                print("BookmarkManager: Failed to start accessing security-scoped resource")
                return nil
            }

            return url
        } catch {
            print("BookmarkManager: Failed to resolve bookmark: \(error)")
            return nil
        }
    }

    /// Stop security-scoped access for a URL
    func stopAccess(for url: URL) {
        url.stopAccessingSecurityScopedResource()
    }

    // MARK: - File Operations

    /// Write a file to a bookmarked folder
    func writeFile(to folderPath: String, fileName: String, data: Data) -> URL? {
        var resultUrl: URL?
        accessFile(at: folderPath) { folderUrl in
            let fileUrl = folderUrl.appendingPathComponent(fileName)
            do {
                try data.write(to: fileUrl)
                resultUrl = fileUrl
                print("BookmarkManager: Wrote file: \(fileUrl.path)")
            } catch {
                print("BookmarkManager: Failed to write file: \(error)")
            }
        }
        return resultUrl
    }

    // MARK: - Background Access

    /// Resolve bookmark data to URL for background thread usage
    /// Returns the URL if successful, along with whether access was started
    static func resolveBookmark(_ bookmarkData: Data) -> (url: URL, needsStopAccess: Bool)? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }

        guard url.startAccessingSecurityScopedResource() else {
            return nil
        }

        return (url, true)
    }
}
