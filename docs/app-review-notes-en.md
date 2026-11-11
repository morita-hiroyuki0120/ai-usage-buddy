# App Review Notes candidate

Draft prepared 2026-11-09. Not entered in App Store Connect or submitted.
The text below is a candidate, not a statement that the Store build is ready.

## Candidate text

AI Usage Buddy (macOS, Apple ID 6826562310) is being prepared as a free menu bar utility displaying remaining Codex quota for 5-hour and weekly windows, reset times, and a cat status indicator. The app has no ads or in-app purchases. Free pricing has not yet been configured in App Store Connect.

The app does not create a separate AI Usage Buddy account. It connects to an existing OpenAI ChatGPT account using the official browser login through the OpenAI Codex app-server helper. An account with access to the relevant Codex quota is needed to inspect live quota data. The app is not an OpenAI product.

Suggested walkthrough, to be checked against the final build:
1. Launch the app and click its menu bar cat. Setup can be skipped; without a connection, live quota is unavailable.
2. Open Settings… > Accounts > Add Account… (or Connect Account… in setup). Authentication takes place in the browser. Do not share personal passwords or authentication secrets with the developer.
3. After login, return to the app and click Refresh Now. Inspect 5-hour limit, Weekly limit, remaining quota and reset times. Settings > Menu bar limit selects which window drives the menu bar indicator. Account switching requires multiple connected accounts.
4. Inspect Notifications, language and Auto refresh interval. Notification thresholds default to 20% and 10%, adjustable from 5% to 100% in steps of five. Delivery requires macOS permission and eligible fresh data; actual low-quota delivery has not been demonstrated in a review video.
5. Default shortcuts: Control-Option-U opens quick usage; Control-Option-R refreshes. Right-click the cat for Refresh Now, Switch Account, Settings… and Quit.
6. With an explicitly approved test account, check relaunch and Delete account. Store deletion attempts official logout and owned-helper shutdown before local removal. It does not delete the OpenAI account or guarantee remote credential revocation.

The planned App Sandbox configuration uses network.client for OpenAI communication and network.server for the local browser-authentication callback listener. The child helper is configured with app-sandbox and inherit to run within the parent's sandbox, with isolated per-account workspaces. Plugins and analytics are disabled by fixed launch settings and OTEL exporters are set to none; this is not a claim that the helper makes no other network requests. Final signed entitlements remain unverified.

Review access is unresolved. Developer Support case 103007143655 provided general submission and attachment guidance, not advance approval of this app, a demo, or guideline 4.8 eligibility. We do not assume that a reviewer's own account or a video alone satisfies review-access requirements. A built-in sample data mode was implemented on 2026-11-11 (Store build only; see the section below). Apple has not given advance approval for it; the prior-approval condition described in guideline 2.1(a) has not been resolved for this proposal. No personal credentials or fictitious review account are supplied here.

No video has been recorded or attached. A local Sandbox validation build has human-reported login/quota display, relaunch persistence and post-deletion non-display checks; these are not final Store-build verification. The final Store archive is incomplete and the packaging manifest remains not-ready. This draft must be revised after final-build and review-access decisions, before any separately authorized submission.

## Sample data mode walkthrough (added 2026-11-11, candidate)

Implemented in source and covered by unit tests and an unsigned Store build. Not yet checked visually in a running app, and not verified in a signed Store build.

1. Launch the app. A cat icon appears in the menu bar. No account is required to review the app.
2. In the first-run setup (step 2, "Connect"), or in Settings > Accounts, click "Try with sample data". The button is shown only while no account is connected.
3. Click the cat icon. A "Showing sample data" banner states that the numbers are not actual usage. No network requests, sign-in, or notifications occur in this mode.
4. Use the "Sample state" menu in the banner to switch between "Plenty left", "Running low", and "Nearly depleted". The cat's state and the 5-hour / weekly remaining percentages and reset times change accordingly.
5. Use the account picker to switch between "Sample account A" and "Sample account B". Settings lets you change the displayed limit and notification thresholds.
6. Click "Exit sample data" in the banner (or in Settings > Accounts) to return to the normal, not-connected state. Sample data is never saved and does not persist across restarts.
7. To use the real feature, choose "Add Account…" and sign in with an existing ChatGPT account through the official browser login.
