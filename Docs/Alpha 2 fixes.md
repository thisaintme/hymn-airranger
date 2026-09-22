# v0.1.0-alpha.2 — arrangement workflow and Settings fixes

## Changed behavior

Clicking **Create a traditional AI arrangement** now immediately shows a prominent spinner and a processing-stage message above the score. The message progresses from requesting the AI harmony plan to arranging/checking the voices and saving the draft. There is no invented percentage. Cancel is available in this banner and in the status bar.

A successful arrangement becomes a new editable draft automatically. It no longer leaves the app in the blocking Keep/Discard proposal state. The previous complete score remains in Versions. A non-blocking **Restore previous** button returns to it without deleting the newer draft. Listen and edit before explicitly approving a rehearsal version; generation never approves it for you.

Success, service failure and cancellation clear the generation state. Cancel unlocks immediately. A late response from a cancelled operation cannot alter the score or clear the busy state of a newer request. Cancellation propagates to the detached harmonization worker. Score-changing model entry points are also guarded while busy, not only their toolbar buttons.

**Save settings** closes the Settings window only after validation and Keychain saving succeed. Failures appear within Settings and leave it open. Unsaved settings are local to the form; Cancel does not alter the active configuration. Reopening reloads the saved values. The save result is no longer inferred from unrelated errors in the main window. The close action targets the Settings window specifically.

## Automated regression coverage

`Tests/HymnAppTests/WorkflowTests.swift` runs on macOS alongside the existing 18 shared-core tests. The 12 app-model/form tests cover progress, automatic draft persistence, subsequent editing, preserved approval/history, failures, cancellation and stale responses, project changes, invalid generated melodies, and Settings success/failure/cancel behavior. Tests use temporary projects, isolated preferences and fake services; no live API requests or real credentials are involved.

Consult the GitHub Actions run for actual results. These tests do not replace a manual check of window appearance, actual Keychain prompts, microphone access, audio devices, PDF printing or live AI.

## Retest after downloading this version

1. Quit the old app, replace it with this release, and reopen it. Existing `.hymn` project format and Keychain service are unchanged. Back up important projects before alpha testing.
2. Open Settings, make a valid change and save. Settings should close and the main window should remain open. Reopen Settings and check the values. Also try Cancel without saving.
3. Generate a traditional AI arrangement. The progress banner should be visible while the existing score remains unchanged. When the draft appears, the spinner should disappear and editing, another AI request, Practice and Print should be available without a Keep action.
4. Use Restore previous and confirm that the generated version is still in Versions. Generate again, cancel, and check that the controls are immediately usable and no delayed result replaces the score.
5. Check both the minimum supported window size and a larger window. Assistant content scrolls, and the Settings save/cancel buttons stay outside its scrolling content.

The alpha is still development-signed, not Apple-notarized. It remains a test build, not a choir-ready release.
