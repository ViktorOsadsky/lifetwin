# Band file intake handoff — October 24, 2026

Track / task: C native/data intake, #67. Daniel retains UI ownership.

Result: strict daily/hourly `lifetwin.band_day.v0` parser, synthetic contract examples, atomic/idempotent in-memory store import, fake-picker coverage, native iOS Files/Open-in bridge, and shared root session. See [format and route integration](../wearable-file-format.md). The real user-supplied file was read locally and passed parser consistency checks; it is not in Git.

PR: [#73](https://github.com/ViktorOsadsky/lifetwin/pull/73), draft; not merged at this handoff. No server/model version change. The app-only `lifetwin.band_days.v0` wrapper supports multiple dated daily reports. The obsolete proposed minute format is removed.

Validation actually run:

- 51 band tests passed, including existing screen/confirmation tests and new malformed, low-wear, unknown-time, calendar, repeated-import, cancellation, startup and demo-isolation cases.
- Dart analysis of band code, main bootstrap, new unit tests and device test passed.
- Unsigned physical-iOS-target debug build of `integration_test/band_file_device_test.dart` passed, including native Swift compilation.
- Xcode project and Info.plist passed `plutil -lint`; `git diff --check` passed.
- Local verification uses Flutter 3.47.0/Dart 3.13.0 in a temporary validation copy with its SDK floor adjusted only there. Repository SDK constraints remain unchanged.

Unavailable acceptance: the connected iPhone was detected, but signing failed because this Mac has no valid Apple development identity/account or provisioning profile for the isolated `com.danielqi.lifesim.bandacceptance` test app. The unsigned build cannot be installed. The user was asked to configure Xcode Accounts. **No physical-device acceptance pass is claimed.** The test expects a local-only copy of the provided report in that test app's `Documents/Inbox`; do not commit or attach it. Automated Inbox delivery, manual Files selection and Share/Open-in interaction must be recorded separately when tested.

Known limits: no Bluetooth implementation; one real day does not provide a measured weekly estimate; shifted demo days are marked synthetic and isolated. Unknown posture is not sitting, and sitting/lying is not awake sitting. Legacy combined-MVPA-to-recreational-moderate confirmation behavior is preserved, with its unresolved calibration/context limitation documented. The new importer does not resolve that mapping.

Next dependency: Daniel uses `BandFileSession.instance.store` and `.intake` in approved band screens, calls `importFromFiles()` for Files selection, presents outcome/replacement controls, and calls `forgetImports()` from deletion/unpair. Those screens were not changed. After signing is ready, install the isolated test target, copy the local report into its Inbox, and run the real-device test. Then verify the final designed route manually before closing #67.
