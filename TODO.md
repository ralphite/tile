# Follow-up work

- [x] Create a reusable global Codex skill for local macOS app development and permissions. Cover a dedicated persistent signing identity, stable bundle identity and designated requirement, retaining Accessibility permission across rebuilds, keychain prompts, safe staged app updates, launching the updated binary, verifying real AX results, and full-desktop screenshot QA. Include the Enhanced UI animation regression discovered in Tile. Never include private keys, passwords, or machine-specific certificates. Requested by Yadong on 2026-10-28; installed as the global `macos-local-app` skill. Contains no signing credentials.
- [x] Repair the basic grid path and simplify the menu and layout-creation flow. Verified the New Layout → 1×3 → save path without moving work windows.
- [x] Publish the public 0.3.1 preview release with accurate verification status and installation notes.
- [ ] Finish physical-mouse drag-snapping acceptance when a suitable input path is available. Do not replay the known ineffective automated drag or repeat the completed grid matrix. Any future desktop interaction is restricted to Desktop 2.
