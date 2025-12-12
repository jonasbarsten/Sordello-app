# Sordello TODO

## Track Editing (Completed)
- [x] Editable track names (double-click or right-click > Rename)
- [x] Track dirty state detection (hasUnsavedChanges on SDLiveSet)
- [x] "Save to new Live Set" button when changes are pending
- [x] AlsModifier class for modifying .als files

## FractionalIndex Improvements
- [ ] Dynamically calculate digit count based on list size `n`, instead of hardcoding 2 or 3 characters
  - Use `ceil(log_base(n))` to determine minimum digits needed
  - Supports arbitrary list sizes without artificial caps

## Performance Optimizations
- [ ] Optimize SwiftData parsing with separate ModelContext + in-memory progress tracking
  - Parse to in-memory structures first
  - Batch insert to SwiftData
  - Show progress without UI lag

- [ ] FileWatcher targeted updates (SHOULD)
  - FileWatcher now reports specific changed paths with change types (created/modified/deleted)
  - Currently still triggers full `incrementalUpdate` scan
  - Should only process the specific files that changed:
    - Created: Create DB record + parse
    - Modified: Update mod date + reparse
    - Deleted: Remove from DB
  - Would significantly reduce unnecessary file system operations

- [ ] Preserve scroll position when switching projects (SHOULD)
  - WholeTreeLazyTestView caches tree state per project (expanded folders preserved)
  - Scroll position resets to top when switching between projects
  - Tried `scrollPosition(id:)` with cached UUIDs but timing issues prevented restoration
  - May need `ScrollViewReader` with explicit `scrollTo()` or different approach

## Database Optimizations (SHOULD)
- [ ] Use integer foreign keys instead of full paths in tracks table
  - Add `id INTEGER PRIMARY KEY` to `live_sets` table
  - Change `liveSetPath TEXT` to `liveSetId INTEGER` in tracks table
  - Saves ~2.5MB per 25K tracks (full paths stored repeatedly)

## Future Enhancements (COULD)
- [ ] Persistent file IDs using extended attributes (xattrs)
  - Store UUID as xattr on each file (`com.sordello.fileId`)
  - Survives renames/moves within project
  - Survives transfer to another computer (if using compatible transfer methods)
  - Would enable tracking files even when paths change
  - Fallback: database detection using content hash + file size + creation date
