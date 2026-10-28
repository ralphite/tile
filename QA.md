# Verification status

This record separates actual native UI checks from geometry tests and unfinished acceptance checks. Local evidence is kept under the ignored `qa-artifacts/` directory; it is not included in the public repository because it can contain local window information.

## Environment

- Apple silicon Mac; 3840 × 2160 display.
- Usable display frame in Accessibility coordinates: `(0, 30, 3840, 2052)`.
- Native AppKit configuration window and its shared arrangement menu.
- Dedicated Chrome-Agent test windows. Existing personal browser windows were not used for the capture test.

## v0.3.0 — 2026-10-28

| Check | Result | Evidence / boundary |
| --- | --- | --- |
| Capture window picker | Passed | Native UI lists eligible windows, supports deselection, and previews selected regions. |
| Reject overlapping selection | Passed | Overlap shown in the preview and message; Save disabled. |
| Capture manually placed rectangles | Passed | Selected three test windows; saved a new preset without overwriting existing presets. |
| Save → restart → apply | Passed | Moved all test windows, restarted Tile, applied the saved layout, and read actual Chrome bounds. |
| Captured geometry | Passed | Restored the set `(50,80,900,850)`, `(1000,80,1400,420)`, `(1000,520,1400,500)` exactly. Window identities can occupy different regions, as intended. |
| Configuration contents | Passed | Saved geometry only; no application bindings or window titles. |
| Accessibility after rebuild | Passed | Stable signing retained existing permission. |
| Automated geometry and store checks | Passed before final English text update | Capture precision, negative-origin displays, empty space, overlap rejection, move/resize classification, legacy migration, backups, and persistence. |
| Final English build | Built and signed | Reopened for normal use. No final English UI acceptance pass yet. |
| Real-mouse drag snapping | **Pending** | The UI automation's app-directed drag generated no events in the global monitor; a physical-mouse gesture was not available. Do not count the simulated drag as a successful test. |
| Manual resize while snapping is enabled | **Pending** | Classification logic tested; native interaction remains unverified. |
| Snapping-enabled continuous layout switching | **Incomplete** | Session paused before the full sequence completed. Earlier v0.2.0 normal switching results are below. |

Window-interaction testing was paused at the user's request so the computer could be used. Only task-created Chrome test windows were closed; Tile was reopened for normal use. Remaining interaction checks were scheduled once for after 02:00 local time. No repeating test or polling loop was created.

Local evidence: `capture-layout.png`, `capture-roundtrip.json`.

## v0.2.0 — 2026-10-27

- Created and saved the left-half / upper-right-third / lower-right-two-thirds layout through the native editor.
- Edited dimensions, added a fourth region, and saved a separate copy. The original three-region preset stayed intact.
- Restarted the app and verified that both presets persisted.
- Entered an overlapping region, observed the disabled Save state, then corrected it.
- With 12 real Chrome test windows, continuously applied: custom three-region → 2×3 → 3×3 → 3×4 → custom four-region → custom three-region.
- Verified actual positions and sizes, zero internal gaps, unchanged overflow windows, menu results, and restoration of the preceding arrangement.
- Found Chrome refusing some resizes at the Dock edge; a single conditional 1-point bottom-edge retry fixed the observed behavior. This outer reserve is documented.
- Verified version-2 configuration migration preserved old presets and IDs, wrote an exact backup, and changed gap to zero.

Local evidence: `regions-zero-gap-fixed.json`, `regions-editor.png`.

## Earlier baseline

- 2×3, 3×3, 3×4 and 1×2 arrangement, capacity overflow, and restore passed with real Chrome windows.
- Nine consecutive 2×3 → 3×3 → 3×4 selections passed after moving menu rebuilding to `menuNeedsUpdate` and removing deferred arrangement commands.
- Position → size → position writes fixed window expansion being clipped at the old origin.

## Still unverified

- Creating a separate ordinary Space and proving cross-Space isolation end to end.
- Multiple physical displays, display removal during an open capture picker, and display scaling changes.
- Direct menu-bar icon activation by the automation tool. Tested arrangement commands used the same menu from the editor.
- Physical-mouse drag preview, dropping into different regions, dropping into blank space, disabling snapping, and resize exclusion.
- Gatekeeper installation on a clean Mac, Intel runtime behavior, and notarization (not provided).

## Next native acceptance pass

1. Use only task-created windows and preserve the user's existing windows.
2. Enable snapping and physically drag a window to two differently sized regions. Check actual bounds and restore.
3. Resize without snapping, disable the mode, and verify a free move.
4. Capture a non-overlapping selection, restart, and apply the saved preset.
5. Continuously choose 2×3, 3×3 and 3×4 with enough test windows; inspect each result.
6. Close only task-created windows. Leave Tile running for the user, with no test overlay or unintended test mode.

If the available tool cannot deliver physical/global mouse events, record that limitation and finish the other checks; do not manufacture a passing result or repeatedly replay the same ineffective gesture.
