# Changelog

## 0.3.0 — 2026-10-28

- Add a selectable snap layout and an explicit drag-snapping mode in the menu.
- Add drag-region overlays and release-to-fill behavior; exclude manual resize gestures.
- Add a current-window picker with a region preview, overlap validation, display selection, and refresh.
- Save selected window geometry as a new editable layout without app bindings or overwriting existing presets.
- Preserve captured point coordinates in a proportional base grid.
- Keep the editor's preset list synchronized after capture.
- Use English throughout the application interface, source messages, tests, and project documentation.

Verified before publication: capture through the native UI, persistence across restart, and exact geometry restoration for three Chrome windows; geometry, migration, and persistence tests; successful build and signing. Physical-mouse drag snapping, free resizing while snapping is enabled, and the final English UI pass remain pending. Window-interaction testing was paused at the user's request and scheduled for a later session.

## 0.2.0 — 2026-10-27

- Add editable, non-overlapping rectangular layouts with optional empty space.
- Use zero internal gaps and shared rounded boundaries.
- Preserve legacy presets and back up configuration during migration.
- Add the standard macOS editing menu and improve continuous layout switching.
- Handle Chrome's bottom-edge resize constraint with a bounded retry.

## 0.1.0 — 2026-10-27

- Initial native AppKit menu bar app.
- Configurable grids and recursive weighted layouts.
- Current-Space window matching, per-display arrangement, capacity overflow handling, and restore.
- Dedicated stable local signing identity for Accessibility permission continuity.
