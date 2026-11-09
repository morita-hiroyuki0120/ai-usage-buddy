# Store local runtime validation

This tooling creates local-only App Store sandbox test builds. It does not create distributable artifacts.

Run `bash scripts/validate-store-runtime.sh --prepare` to build the validation harness with bundle ID `com.aiusagebuddy.app.store.validation`. It creates a UUID-scoped runtime home and writes only a status-only `Report.json` when later launched.

Run `bash scripts/validate-store-runtime.sh --prepare-interactive` to build the normal Store UI with bundle ID `com.aiusagebuddy.app.store.localtest` and only the `AI_USAGE_BUDDY_APP_STORE` compile flag. This mode uses a separate `build/store-interactive.*` output and DerivedData, signs the helper and app for local sandbox testing, writes its hash manifest, and adds the local-only notice. It prepares but never launches the app or helper. Login is not started during preparation; a later interactive test must start login only through the user's UI action and a separate parent instruction.

Run `bash scripts/validate-store-runtime.sh --prepare-keyring-interactive` to prepare the current normal Store UI under the separate bundle ID `com.aiusagebuddy.app.store.keyringtest`. It uses `build/store-keyring-interactive.*` and separate DerivedData, sets the display name to `AI Usage Buddy Keychain検証`, and enables only `AI_USAGE_BUDDY_APP_STORE`. The current seven overrides include keyring storage and the direct backend. Preparation does not launch the app, inspect or migrate the older localtest profile, or read authentication data. The parent supplies the new path for a separately authorized human test; UI observations from that test are recorded below, while Keychain item contents and actual deletion remain unverified.

`--launch-after-go` remains limited to the `com.aiusagebuddy.app.store.validation` harness and `store-validation.*` paths. It binds that app/helper to the prepare manifest, rechecks strict signatures, Team IDs, and entitlements, then requires the current run's report to show status `0`, completed shutdown, and no owned helper process. It reads only fixed allowlisted report fields. It does not launch either interactive Store UI build.

All preparation modes use the pinned Codex `rust-v0.163.0` helper. The source artifact hash and upstream signature are checked before copying; the embedded helper is signed with sandbox inheritance and the app with the Store app entitlements. The upstream license and notice accompany each local artifact. Transitive dependency notices are incomplete, so none of these artifacts is redistributable.

Preparation uses `--timestamp=none` only for these local validation artifacts. It is not an acceptable signing procedure for distribution; the eventual Mac App Store build must use the production Apple distribution workflow and its required signing/timestamping.

No mode uses the ChatGPT app, changes global Xcode selection, uploads anything, or contacts App Store Connect.

## Human-confirmed UI evidence, 2026-10-23

For `build/store-keyring-interactive.XCwI1p/AI Usage Buddy.app` (`com.aiusagebuddy.app.store.keyringtest`), the parent relayed human confirmation that the 5-hour and weekly remaining quotas and both reset times were displayed after official login.
The human then reported remaining usage visible after quitting and relaunching without another login, and the target account and its usage absent after account deletion followed by quitting and relaunching.
This is human-confirmed UI evidence, not direct inspection of Keychain storage, deletion of actual Keychain items, old file removal, or remote revocation.
This documentation task did not rebuild or run an app or inspect user authentication data.
