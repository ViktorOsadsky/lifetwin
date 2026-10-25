# Guest entry and twin nickname

Track / task: C — owner-requested guest login screen and editable twin name, October 25.

Result and files changed:

- Production first launch shows `GuestLoginScreen` before the automatic mascot conversation. Continue as guest remembers local entry; it creates no remote account and asks for no email, Google or Apple integration. Provider, microphone, memory and health-import choices remain in their existing consent flows.
- Existing saved profiles, twins, check-ins and history continue to the Room without a migration or loss of data. `guest_entry_accepted` is an optional preference in the existing version-1 protected store. Delete my data removes it and restores first-launch entry.
- Customize now offers Twin name above the existing appearance choices. Use name previews a trimmed nickname of up to 24 characters; Save look commits it through the existing cosmetic persistence path. Cancel discards the dialog edit; Back from Customize discards the draft. A blank name restores My twin. No real name is requested or included in a health profile, history event or API request.
- Existing name-aware banners and twin displays read the saved appearance. The fixed mascot guide name, Mochi, continues to identify the guide.

PR URL / merge state / merge commit: [#210](https://github.com/ViktorOsadsky/lifetwin/pull/210), open pending repository checks and backend deployment [#204](https://github.com/ViktorOsadsky/lifetwin/pull/204). No merge commit yet. This change does not deploy or replace the backend.

Contract or model versions affected: no HTTP or model change. Existing cosmetic `twin.name` is used; the local repository gains `continueAsGuest()` and the optional store preference. See `app/lib/README-model.md`.

Checks actually run and results: full Flutter suite **1,466 passed**; `flutter analyze` reported no issues. Eleven new tests cover nickname persistence through app relaunch, cancel/default/length behavior, legacy-store preservation, first-run intake gating, guest-save retry, consent separation, deletion, small-phone/landscape/tablet layouts with text scales 1–3 and reduced motion, and the rename dialog above a simulated keyboard at text scale 2. Existing Customize, onboarding and full-deletion regressions also passed. Widget screenshots were rendered and inspected for the welcome and keyboard dialog. Validation used an isolated copy with the SDK floor temporarily lowered to installed Dart 3.13.0; repository SDK constraints and lockfile are unchanged. Reproduce screenshots by setting `EVIDENCE_SHOTS` while running `app/test/guest_entry_twin_name_test.dart`.

Real, fixture, or unavailable integrations: guest entry uses local protected storage, not server authentication. Tests use the real bundled on-device model with in-memory storage and fake conversation/forecast clients. Non-iOS platforms retain the existing session-only fallback where protected storage is unavailable. No email or OAuth provider is configured.

Follow-up visual review replaced the nickname field's floating label with a fixed visible label and an explicit input accessibility label. The large-text keyboard screenshot was recaptured and inspected; all eleven focused tests and analysis passed after this presentation change.

Known limits / blockers: no account sync or remote login is implemented or implied. Native physical-iPhone and VoiceOver acceptance remain separate; Daniel owns the physical test device. The UI retains the existing light painted-card theme under either system appearance.

Next dependent task: merge after backend deployment checks and the UI PR's applicable repository checks pass; run the guest → consent → intake flow on the owner's test phone.
