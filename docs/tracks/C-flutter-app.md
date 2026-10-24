# Track C: Flutter App

**Owner:** _TBD_ · **Master doc:** §2, §3, §4, §10, §11, §12 phases 2–3, §17 product criteria

Flutter / Dart replaces the master doc's Next.js frontend (§7). Pick your own chart and animation packages. Everything else in
these sections applies as written.

## Screens (master doc §10)

| Screen | Master doc | Must have |
|---|---|---|
| Landing | §2.1, §10 p1 | Headline, subheading and CTA copy as written; animated example curve; dark, premium, scientific |
| Onboarding | §2.2, §10 p2 | Under **60 seconds**; multi-step, sliders and selections, progress indicator; input checks; units converted to metric for the API |
| Dashboard | §3, §10 p3 | Large 10-year number (20-year if returned); curve with tooltips, labeled horizon, cohort comparison; top risk factors; lifestyle sliders; previous curve muted, new curve contrasting, animated change; persistent "modeled, not causal" label; advisor panel |
| Compare | §4, §10 p4 | Split layout: current future left, alternative right, both curves in the center; deltas from `/api/compare`; saving scenarios on the device |

Dashboard and Compare are the highest priority (§10).

## Rules

- **Every number comes from the API** (§3.1). The app computes no probabilities or deltas.
- `status: "unsupported"` → show `limitation.message`, draw no curve (§3.1).
- `ignored_fields` → show those inputs as informational (§2.2).
- Colors from §11: background `#080B12`, accent `#7C8CFF`, positive `#39D5A0`, baseline `#8C95A8`, text `#F4F6FB`.
- Scenarios stay on the device; no account (§15).
- API base URL comes from `--dart-define=API_BASE_URL=…`; see [ios-testing.md](../ios-testing.md).

## Work against the stub

Run `python3 contracts/stub_server.py` and build the whole flow on its fake numbers (`model_version: "stub-0"`). The sample
responses in `contracts/fixtures/` cover every state you need to render: a typical profile, risk factors, a minor, an
out-of-range age and the §4.1 demo futures.
