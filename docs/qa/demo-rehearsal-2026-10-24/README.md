# Demo rehearsal evidence

Source: `1a648bd405df4c76b5c1dea3339194c31201913c`. This is a **silent native XCTest UI rehearsal** of the normal Flutter app, using fictional Rosa and the built-in recorded band. It is separate from Daniel's spoken submission recording and from model calibration/clinical validation. The [script](../../submission/demo-video-script.md) contains the result and handoff; [timing.json](timing.json) records the measured route, with deliberate reading holds included. **PASS: 178.00494262500433 seconds**, eight beats; one native test passed in 221.267 seconds including setup. [route.json](route.json) records displayed results and remaining acceptance; [native-result.txt](native-result.txt) preserves the test result excerpt.

**Pin limit:** later main `1a86d9a` changed model artifacts/reference data, sensitivity/lifespan data and the app model service. This evidence accepts only the rehearsed `1a648bd` route. It establishes no score, model behavior or timing for the later build. The native harness intentionally asserts +0.59 for this pinned synthetic fixture; recheck rather than reuse that expected number after a model sync. Further model/build acceptance is pending.

The app and keyless FastAPI server use the same source pin. Server port: 8133, `ONBOARDING_DEMO=1`, `LLM_API_KEY`/`OPENAI_API_KEY` blank, no access logs. No live Muse/Cartesia call, Apple Health import or document upload is claimed. No product code changed. The existing demo seed supplies history; the actual UI prepares earlier answers before the clock starts, then performs the last question, reveal, Home, daily check-in, Experiment, Ideas, band read-back and close on one repository. No profile swap/reset occurs inside that measured segment.

The temporary app copy uses a unique bundle ID (`com.danielqi.lifesim.demo133current`) and display name. **SDK exception:** installed Flutter 3.47.0/Dart 3.13.0 required changing only the temporary copy's SDK floor from `^3.13.7` to `^3.13.0`; the repository floor stays unchanged. Native test instrumentation is copied into that app, rather than shipped as product UI. Simulator: iPhone 17 Pro, iOS 26.4, 402×874 points. Xcode's installed simulator SDK is 27.0; the UI target deployment floor is 15.0.

## Reproduce on an isolated simulator

1. Archive the source pin to a disposable directory. Start its FastAPI service on 8133 using the repository backend guide and the keyless settings above. Copy `app/` separately if needed. Apply the temporary SDK/bundle identity adjustments described above; never use someone's saved profile.
2. Run `flutter pub get`, then build the normal entry point:

   ```sh
   flutter build ios --simulator --debug --no-codesign --dart-define=API_BASE_URL=http://localhost:8133 --dart-define=DEMO_SEED=1
   ```

3. Copy [Demo133UITests.swift](Demo133UITests.swift) into the temporary app's `ios/Demo133UITests/`. With the installed `xcodeproj` Ruby gem (1.27.0 used here), run the helpers against the temporary `ios/` directory:

   ```sh
   ruby setup_native.rb /absolute/path/to/temp/app/ios
   python3 prepare_scheme.py /absolute/path/to/temp/app/ios
   ```

4. From that `ios/` directory, build the native runner and run only the continuous-route test on the chosen isolated simulator. Substitute its UDID and the generated `.xctestrun` path:

   ```sh
   xcodebuild build-for-testing -workspace Runner.xcworkspace -scheme Demo133Acceptance -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/demo133-derived CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES ARCHS=arm64
   xcodebuild test-without-building -xctestrun <generated.xctestrun> -destination 'platform=iOS Simulator,id=<UDID>' -parallel-testing-enabled NO -only-testing:Demo133UITests/Demo133UITests/testPrepareRealIntake
   ```

The harness saves raw screenshots/trees and `timing.json` in its **UI runner's** Documents/demo133 directory as well as XCTest attachments. Repeated takes need a fresh synthetic app installation because a completed daily check-in and reveal flag persist. Consent guard pauses, scrolling and read-backs are real UI actions. The 23-second estimate-caveat hold is included in elapsed time; no waits are cut out.

## Earlier attempts and limits

Historical `9ace866` preparation/attempts found harness mistakes: tapping the AI choice within its 700 ms protection window, using “Back to room” where the reveal exposes “Back,” and assuming “none” leaves the second activity pace unanswered. Those attempts did not complete the route; the unintended daily read-back was not confirmed. The explicit combined activity answer was checked through the real stateless service before the current attempt. The old pin's missing “110+” propagation was already fixed by merged #141 and is not reported as a current bug.

The first tested-pin attempt was interrupted by a **SimRenderServer** EXC_BREAKPOINT/SIGTRAP, with the native session losing its connection; see [compact diagnostics](renderer-interruption.json). It completed intake/reveal/Home, then stopped before daily confirmation. Native timeouts were disabled (default allowance 600 seconds); this was not a measured complete route or evidence of a product-app crash. Only the owned simulator and synthetic app were reset afterward.

No large xcresult, full system diagnostic archive or video is committed. Native screenshots/timestamps are the evidence: the attempted simctl frame capture yielded no usable frames and Simulator.app was not found at the tested paths on this host. No continuous video, human read-aloud, physical phone, reduced-motion matrix, reconnect or failure-path acceptance is claimed here. Daniel retains the spoken recording and remaining acceptance checks. Provider-backed wording remains gated by #124; this run uses the template path.

A subsequent tested-pin run completed four measured beats through 97.005 seconds and reached the moderate-activity preview. Its literal-caption selector did not match the longer accessible confirmation label; [selector-interruption.json](selector-interruption.json) and [selector-failure.txt](selector-failure.txt) preserve that failure. The correction uniquely matches “Use … in my what-if,” checks a nonempty frame in the app viewport and taps its visible center. Navigation checks also verify expected destinations.

The first launch with that corrected harness lost its native session while waiting for initial Home, before preparation or timing; see [untimed session metadata](untimed-session-interruption.json) and [result excerpt](untimed-session-result.txt). No complete timing or specific crash cause is inferred. For the next attempt, we waited for the separately owned iOS 27 check to finish and shut down, then booted only the assigned iOS 26.4 simulator; this does not establish concurrency as the cause.

## Passing take and review links

After the iOS 27 owner restored and shut down that simulator, only the assigned iOS 26.4 device was booted. A clean synthetic installation ran the corrected harness successfully; no concurrency-causation claim follows. The exact tested harness and setup helpers are included above.

Selected screenshots from this passing take (all fictional/synthetic): [import chooser](01-import-choice.png), [full caveat](04-reveal-caveat.png), [actual 110+ result](05-reveal.png), [daily read-back](07-checkin-readback.png), [flat what-if and disclaimer](10-experiment-result.png), [Ideas](11-ideas.png), [cited idea detail](12-idea-detail.png), [recorded band week](13-band-demo-week.png), [band confirmation](15-band-demo-readback.png), [closing Home](16-close-home.png). The daily read-back was verified before confirmation; the band read-back was closed without saving. Closing Home still shows +0.59 and Today done. The +15-minute what-if returned About the same; no improvement was manufactured.

These are native screenshots, not a continuous video. Some actions finish before a beat's planned endpoint; the remaining time is a measured hold on that beat's final screen. The final take explicitly holds the daily read-back for eight seconds, the Ideas list for two seconds and its detail for fourteen seconds. These monotonic intervals are recorded in timing.json; they establish visible dwell, not measured human reading or speech. Daniel should place his spoken explanation and reading holds within the planned budget and time that recording separately.

Handoff: documentation/QA artifacts only, locally committed for parent review; no push, PR or merge performed here. Product contracts and repository SDK remain unchanged. Next dependency is review/CI of the later model sync, a fresh actual-score/route check on the chosen recording build, and Daniel's spoken take plus the remaining checks in route.json.

Readability revision: the [earlier mechanical timing](mechanical-timing.json) and [test excerpt](mechanical-native-result.txt) preserve the first complete route, which finished in 178.006 seconds but held most spare daily/Ideas time after returning Home. The final harness shifts the daily confirmation hold to eight seconds and gives Ideas 26 seconds with two seconds on the list and fourteen on the detail. Band then uses twenty seconds, still including its settled read-back before leaving. The measured total is 178.005 seconds, below the 180-second limit. One final native test passed; the earlier mechanical pass is a separate test take, not an extra final-run test.
