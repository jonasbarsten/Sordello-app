//
//  UIState.swift
//  Sordello
//
//  Non-persisted UI state kept in memory.
//

import Foundation

/// UI state that doesn't need persistence - kept in memory
@Observable
final class UIState {
     static let shared = UIState()

    // MARK: - Selection State (Objects)

    /// Currently selected LiveSet (used by inspector)
    var selectedLiveSet: LiveSet? {
        didSet {
            // Clear track when LiveSet changes
            if oldValue?.path != selectedLiveSet?.path {
                selectedTrack = nil
            }
        }
    }

    /// Currently selected track (used by inspector)
    var selectedTrack: LiveSetTrack?

    // MARK: - Selection State (Paths - for List bindings)

    var selectedProjectPath: String?

    /// Backing store for selectedLiveSetPath
    private var _selectedLiveSetPath: String?

    /// Selected LiveSet path - drives List selection
    /// When set programmatically, the List's onChange should populate selectedLiveSet
    var selectedLiveSetPath: String? {
        get { selectedLiveSet?.path ?? _selectedLiveSetPath }
        set {
            _selectedLiveSetPath = newValue
            if newValue == nil {
                selectedLiveSet = nil
            }
        }
    }

    // MARK: - UI State

    var isInspectorVisible: Bool = false
    var liveSetSortOrder: SortOrder = .ascending
    var expandedLiveSets: Set<String> = []

    private init() {}
}
