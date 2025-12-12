//
//  AppState.swift
//  Sordello
//
//  Modern @Observable state. Inject via .environment() at app root.
//

import Foundation
import SwiftUI

/// App-wide state using @Observable.
/// Inject at root: .environment(appState)
/// Access in views: @Environment(AppState.self) var appState
@Observable
final class AppState {

    // MARK: - Selection State (drives NavigationSplitView columns)

    /// Selected project path (drives content column)
    var selectedProjectPath: String?

    /// Selected LiveSet (drives detail column via List selection binding)
    var selectedLiveSet: LiveSet? {
        didSet {
            // Sync path for inspector and clear track selection
            selectedLiveSetPath = selectedLiveSet?.path
            if oldValue?.path != selectedLiveSet?.path {
                selectedTrack = nil
                // Clear any drill-down navigation when selection changes
                detailNavigationPath = NavigationPath()
            }
        }
    }

    /// Selected LiveSet path (for inspector queries)
    var selectedLiveSetPath: String?

    /// Selected track within current LiveSet
    var selectedTrack: LiveSetTrack?

    // MARK: - Detail Drill-Down Navigation

    /// Navigation path for drill-down within detail column (e.g., LiveSet → Subproject)
    var detailNavigationPath = NavigationPath()

    /// Push a route onto the detail navigation stack
    func pushDetail(_ route: AppRoute) {
        detailNavigationPath.append(route)
    }

    /// Pop back one level in detail navigation
    func popDetail() {
        if !detailNavigationPath.isEmpty {
            detailNavigationPath.removeLast()
        }
    }

    /// Pop to root of detail navigation
    func popDetailToRoot() {
        detailNavigationPath = NavigationPath()
    }

    // MARK: - UI Preferences

    var isInspectorVisible = false
    var liveSetSortOrder: SortOrder = .ascending
}
