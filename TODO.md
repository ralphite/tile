# Follow-up work

- [x] Create a reusable global Codex skill for local macOS app development and permissions. Cover a dedicated persistent signing identity, stable bundle identity and designated requirement, retaining Accessibility permission across rebuilds, keychain prompts, safe staged app updates, launching the updated binary, verifying real AX results, and full-desktop screenshot QA. Include the Enhanced UI animation regression discovered in Tile. Never include private keys, passwords, or machine-specific certificates. Requested by Yadong on 2026-10-28; installed as the global `macos-local-app` skill. Contains no signing credentials.
- [x] Repair the basic grid path and simplify the menu and layout-creation flow. Verified the New Layout → 1×3 → save path without moving work windows.
- [ ] Finish real drag-snapping acceptance and publish a release only with accurate verification status.
