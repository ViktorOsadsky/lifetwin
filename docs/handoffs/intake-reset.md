# Intake deletion reset follow-up

Track C, branch `codex/c-health-confirmation-flow`, PR #159. This fixes an existing deletion bug exposed while connecting native Health estimates. PR/merge state and final check results are recorded in #159.

Before: a confirmed Health or document import queued before the first Talk survived `resetConversation()`. The next start silently imported those deleted answers. A completed session also retained its old phase, and delayed requests could restore its conversation or retry state.

After: reset clears queued imports, source, last-import UI state, retry and last reply; returns to consent; invalidates the conversation/speech generations; and stops pending audio with bounded cleanup. New sessions wait for reset cleanup. Delayed guide/input continuations cannot write into a newer conversation. Ordinary pause/resume and the user's new consent choices remain separate from deletion.

No provider, server, profile-schema or model contract changes. Raw input is neither logged nor newly persisted. The Health integration's confirmed estimate flags stay on the phone and are cleared with its session source map.

Validation covers queued Health and document deletion, restart after completion, delayed guide success/failure/rejection, pending transcript/permission/microphone callbacks, fresh-request isolation and repeated reset cleanup. All 143 focused tests passed across controller, hands-free, timing, consent, onboarding screen and document upload.
All 14 new deletion regressions failed against the original controller; targeted analysis and diff checks passed. Tests use fakes, with no provider, native audio or physical-device acceptance claim. The temporary validation SDK adjustment is confined to the disposable copy.

Next dependency: Daniel's physical-device intake/Health acceptance; #106 real-source MET availability and #134's remaining accessibility routes are separate open work.
