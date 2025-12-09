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

## Database Optimizations (SHOULD)
- [ ] Use integer foreign keys instead of full paths in tracks table
  - Add `id INTEGER PRIMARY KEY` to `live_sets` table
  - Change `liveSetPath TEXT` to `liveSetId INTEGER` in tracks table
  - Saves ~2.5MB per 25K tracks (full paths stored repeatedly)
