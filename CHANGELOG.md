# Changelog

## v1.2
- **Safe to delete the download** — `Install.bat` now copies the runtime to `%LOCALAPPDATA%\AddToZotero` and points the menu there, so the extracted folder can be removed afterwards. Use `Install.ps1 -InPlace` to keep the old run-in-place behavior. `Uninstall` cleans up the copy.
- **Auto-start feedback** — when Zotero isn't running, the tool shows a "starting Zotero…" notification, waits up to 60 s (was 45 s), and lets only one process launch Zotero during multi-select.

## v1.1
- **Choose target collection** when adding — new "Add to Zotero (choose collection)…" menu item with a searchable picker; multi-select shows the dialog once.
- **Bilingual UI** (English / 中文), auto-detected from OS locale; override with `Install.ps1 -Language zh|en`.
- **Stability hardening**: top-level error dialog (no silent failures), non-blocking parameter handling, surfaced move-failures, safe HTTP-client disposal, resilient concurrent logging, 64-bit timestamps.
- MIT license.

## v1.0
- Right-click **Add to Zotero** for local files via the Zotero connector (`saveStandaloneAttachment`). Auto-retrieves PDF/EPUB metadata. No plugin required.