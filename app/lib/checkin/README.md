# Frequent check-ins (`lib/checkin/`)

This folder holds the logic for Mochi's quick daily check-in and the weekly check-in. It has no screens. The server runs the conversation (`POST /api/checkin/start` and `/turn`, kind `quick`, `daily` or `weekly`, see `contracts/README.md`). This folder decides which check-in is due and what it asks, moves voice in and out, saves the confirmed answers on the phone, plans reminders, and assembles `daily_logs` and `weekly_summaries` for the on-device model.

## Design rules

- The quick check-in takes 30–60 seconds: one to three questions, chosen from what the stored days are missing (`CheckinScheduler.quickPlan`).
- Each day is one `daily_logs` row: `sleep_hours` is the night before the row's date, plus that day's activity and sitting. Before 17:00 the activity and sitting questions are about yesterday, which is a whole day. From 17:00, they are about today. With a 10:00 reminder, each morning completes yesterday's row and starts today's.
- A day counts for the model only when all four values are known and within the package's limits.
- A missed day is unknown, never zero. A window is 7, 14, 21 or 28 real, complete, consecutive days ending yesterday.
- No guilt and no streaks:
  - Progress is "good weeks": Monday–Sunday weeks with at least 4 different days with a finished check-in of any kind, counted over all time, not in a row (`weekProgress`). It counts days, not check-ins.
  - Nothing says "missed".
  - The only catch-up is one optional last question: "Yesterday was a bit of a blank. How did you sleep the night before?" It is asked only when yesterday had no check-in and that answer would complete yesterday's row.
- Apple Health:
  - Health can suggest last night's sleep, the night before's sleep, and the day's Apple Exercise minutes.
  - Mochi reads each one back once as "Looks right?", and nothing is kept without a yes.
  - Exercise minutes can't say which were out of breath, so Mochi asks only the pace.
- No direct edits: answers reach history only from a finished conversation (`CheckinStore.applyFinishedCheckin`). To change an answer, the person goes back in the conversation or tells Mochi.
- Daily history stays separate from the profile. Only a weekly check-in's `profile_update` changes the profile, and `unknown` never replaces a known value.
- One day's report never changes the forecast by itself. The forecast is reassessed only through a supported window. An animation may acknowledge a check-in, but nothing may claim a health improvement.
- Reminders:
  - A reminder is a scheduled local notification, and the app does its work when it is opened. Nothing runs in the background.
  - Reminders are offered once: at the end of onboarding (`TwinRepository.shouldOfferReminders`, then `acceptReminders(hour:, minute:)` or `declineReminders()`), or after the first finished check-in if they weren't offered yet (`CheckinController.offerReminder`). Notification permission is asked only after a yes. It is separate from Apple Health access and from consent to process answers.
  - Reminders are planned 7 days ahead and planned again at app start (`TwinRepository.open`), on every app open (`repo.refresh()`) and after every check-in. The 7th, last planned one says "I'll pause reminders until you're back. I'm here whenever you like.", so a week away ends kindly instead of in silence; the next app open plans a new week.
  - Reminder lines are invitations: never missed days, streaks, guilt or health claims.

## Question rotation (verbatim, from `server/lifetwin/checkin/scripts.py`)

Greeting: "Hi, it's Mochi! Just a quick check-in, under a minute. You can skip anything."

`{day}` is "yesterday" or "today".

1. **Sleep:** "How did you sleep last night? About how many hours?"
   - With a last answer: "Last time you slept {value}. How about last night? About how many hours?"
   - Apple Health: "Apple Health says you slept about {value} last night. Looks right?"
2. **Activity:** "Did you get out and about {day}? Tell me if anything got you out of breath, like brisk walking uphill, or if it was easy, like a gentle walk, and for about how long."
   - Follow-ups for the part not mentioned:
     - "And anything easier {day}, like an easy walk or pottering about? About how long?"
     - "And did anything {day} get you out of breath, like brisk walking uphill? If so, for about how long?"
   - A time without a pace: "Did that get you out of breath, like brisk walking uphill, or was it at an easy pace?"
   - Apple Health: "Apple Health shows about {value} of exercise {day}. Did any of it get you out of breath, or was it all at an easy pace?"
3. **Sitting** (everyday examples, rotating by date):
   - "About how many hours did you spend sitting {day}? Count reading, TV, meals and time in the car."
   - "Thinking of {day}, about how many hours were you sitting down, like watching TV, reading or at the table?"
   - "Roughly how many hours did you sit {day}, all together? Things like TV, puzzles, meals or driving all count."
4. **Feeling**, when there is room: "And how are you feeling today: good, okay, or not great?"
5. **Catch-up** (optional, last): "One more, only if you like. Yesterday was a bit of a blank. How did you sleep the night before? If you can't remember, just say skip."

Which topics: sleep if today's row has no sleep, activity if the activity day's row lacks either pace, and sitting if it lacks sitting. Feeling fills a free place (at most three). If everything is known and feeling is done, no check-in is due.

The weekly check-in (on the person's weekly day, Sunday by default; quietly still ready afterwards; filed under the Monday–Sunday week holding most of the seven days before it, `weekDescribedBy`) now asks the model's own inputs: `vigorous_recreation_min_week` and `moderate_recreation_min_week` as one plain question with a follow-up, and `sedentary_min_day` on a usual day.

## What the UI calls

`CheckinController` is a `ChangeNotifier`. Bind it with `ListenableBuilder`.

| Member | Use |
|---|---|
| `CheckinController({guide, input, output, store, reminders, healthSamples, onFinished, clock, voiceUsable})` | `guide: HttpCheckinClient()`, `store: TwinCheckinStore(repo)`, `reminders: repo.reminders`, `healthSamples`: `() => HealthReader().read(now: DateTime.now(), days: 3)` when Apple Health is connected. `onFinished` is optional (e.g. an animation); the store already saved the check-in, so don't pass it to `applyCheckin` again |
| `Future<bool> start({kind = 'quick'})` | false when nothing is due today |
| `phase` (`CheckinPhase`), `mascotLine`, `caption`, `notice`, `turn.mascotState` | what to show |
| `startTalk()`, `stopTalk()`, `cancelTalk()`, `listenSecondsLeft` | the Talk button |
| `submitTyped(text)`, `setTyping(bool)`, `typing` | typing |
| `quickAnswers` → `submitQuick(words)` | tap answers (feeling, sitting hours, pace, "Nothing") |
| `confirming`, `confirmingHealth`, `confirm()`, `change()`, `keepAnswer()` | the read-back. Label it "Looks right" / "Not quite" when `confirmingHealth` |
| `skip()`, `goBack()` / `canGoBack`, `cancel()` | Skip, Go back, Stop |
| `emergency`, `emergencyCallUri` (`tel:911`), `continueAfterEmergency()` | paused: Mochi concerned, a "Call 911" button the person taps, and Continue |
| `canRetry` / `retry()`, `hearAgain()`, `stopSpeaking()`, `screenReader` | as in onboarding |
| `questionNumber` → `(n, of)` | "Question 2 of 3" |
| `progress` (`goodWeeks`, `daysThisWeek`) | after it finishes, e.g. "3 good weeks so far" |
| `offerReminder`, `acceptReminders(hour:, minute:)`, `declineReminders()` | the one-time reminder offer after the first check-in, if onboarding didn't already offer it (default 10:00) |

To decide what to show on the home screen, call `CheckinScheduler().due(localNow: DateTime.now(), history:, days:, settings:)`. It returns `DueCheckins.quick` (a plan, or null) and `.weekly`. Offer the weekly check-in after the quick one, never instead of it. On every app open, call `repo.refresh()`: it also plans the reminders again (`repo.replanReminders()`). At the end of onboarding, show the reminder offer when `repo.shouldOfferReminders` is true.

## Storage: `CheckinStore` over `TwinRepository`

`TwinCheckinStore(repo)` (`lib/twin/twin_checkin_store.dart`) implements `CheckinStore` over the phone's protected store:

| `CheckinStore` | `TwinRepository` |
|---|---|
| `checkins()` | `store.checkins` (`CheckinEntry{kind, date, answers}`) |
| `dayLogs()` | `store.dayLogs` (`DayLog` rows, possibly partial) |
| `applyFinishedCheckin(response, localDate:)` | `applyCheckin(response, localDate:)`: records the check-in and its history entry, merges a quick one's `daily_logs` (`readFinishedCheckin` + `mergeDayLogs`, values type-checked, never written as 0), applies a weekly `profile_update` under the write rules (`unknown` never replaces a known value), and recomputes |
| `settings()` / `saveSettings()` | `checkinSettings` / `saveCheckinSettings` (a non-health `checkin_settings` key) |

There is one window assembler: `DailyLogsAssembler`. `TwinRepository.assess` uses it through `candidateWindows` (`lib/twin/twin_history.dart`), and weekly summaries are worked out from the stored weekly check-ins with its week rule. `InMemoryCheckinStore` stays for tests and previews.

## Forecast refresh

After a finished check-in or on app open:

`TwinRepository` does this itself after every check-in; on app open call `repo.refresh()`. The request it builds is the same as:

```dart
final request = const DailyLogsAssembler().assessRequest(
  modelProfile: toModelProfile(profile), // profile_mapping.dart
  asOf: isoDay(dayOf(DateTime.now())),
  days: await store.dayLogs(),
  checkins: await store.checkins(),
);
```

`request` holds `weekly_summaries` if the latest 1–4 completed weeks have weekly check-ins with all four fields. Otherwise it holds `daily_logs`, the longest 28-, 21-, 14- or 7-day complete run ending yesterday. Otherwise it holds the profile alone. This is the order of `candidateWindows`; a window the package refuses falls back to the next. Keep `profile_used` and `input_provenance` visible. Without a window, the forecast is the profile snapshot, unchanged by the day's answers.

## Tests

- `test/checkin_scheduler_test.dart`: rotation, missed days, catch-up, evenings, time zones, daylight saving, weekly.
- `test/checkin_daily_logs_test.dart`: exact package shapes, checked by calling the package's own `LifeTwinEngine.assess`.
- `test/checkin_controller_test.dart`: the controller with fake speech and a fake server.
- `test/checkin_reminders_test.dart`: notification planning with a fake, and the HTTP client.
