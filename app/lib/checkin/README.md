# Frequent check-ins (`lib/checkin/`)

This folder holds the logic for Mochi's quick daily check-in and the weekly check-in. It has no screens. The server runs the conversation (`POST /api/checkin/start` and `/turn`, kind `quick`, `daily` or `weekly`, see `contracts/README.md`). This folder decides which check-in is due and what it asks, moves voice in and out, saves the confirmed answers on the phone, plans reminders, and assembles `daily_logs` and `weekly_summaries` for the on-device model.

## Design rules

- The quick check-in takes 30–60 seconds: one to three questions, chosen from what the stored days are missing (`CheckinScheduler.quickPlan`).
- Each day is one `daily_logs` row: `sleep_hours` is the night before the row's date, plus that day's activity and sitting. Before 17:00 the activity and sitting questions are about yesterday, which is a whole day. From 17:00, they are about today. With a 10:00 reminder, each morning completes yesterday's row and starts today's.
- A day counts for the model only when all four values are known and within the package's limits.
- A missed day is unknown, never zero. A window is 7, 14, 21 or 28 real, complete, consecutive days ending yesterday.
- No guilt and no streaks:
  - Progress is "good weeks": Monday–Sunday weeks with at least 4 check-in days, counted over all time, not in a row (`weekProgress`).
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
  - Notification permission is asked once, after the first finished check-in, and only if the person says yes. It is separate from Apple Health access and from consent to process answers.

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

The weekly check-in (on the person's weekly day, Sunday by default; quietly still ready afterwards) now asks the model's own inputs: `vigorous_recreation_min_week` and `moderate_recreation_min_week` as one plain question with a follow-up, and `sedentary_min_day` on a usual day.

## What the UI calls

`CheckinController` is a `ChangeNotifier`. Bind it with `ListenableBuilder`.

| Member | Use |
|---|---|
| `CheckinController({guide, input, output, store, reminders, healthSamples, onFinished, clock, voiceUsable})` | `guide: HttpCheckinClient()`, `store`: see below, `reminders: CheckinReminders(LocalNotificationPort())`, `healthSamples`: `() => HealthReader().read(now: DateTime.now(), days: 3)` when Apple Health is connected, `onFinished`: hand a weekly turn to `TwinRepository.applyCheckin` |
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
| `offerReminder`, `acceptReminders(hour:, minute:)`, `declineReminders()` | the one-time reminder offer after the first check-in (default 10:00) |

To decide what to show on the home screen, call `CheckinScheduler().due(localNow: DateTime.now(), history:, days:, settings:)`. It returns `DueCheckins.quick` (a plan, or null) and `.weekly`. Offer the weekly check-in after the quick one, never instead of it. On every app open, call `CheckinReminders.reschedule(settings, localNow:, history:)`.

## Storage: `CheckinStore` and the on-device-model repository

| `CheckinStore` | `TwinRepository` / `TwinStore` (codex/c-on-device-model) |
|---|---|
| `checkins()` → `CheckinEntry{kind, date, answers}` | `store.checkins` → `CheckinRecord{kind, date, answers}` (same JSON) |
| `dayLogs()` → `DayLog` rows, possibly partial | `store.dailyLogs` (its windows code already skips incomplete rows) |
| `applyFinishedCheckin(response, localDate:)` | `applyCheckin(response)`, extended as below |
| `settings()` / `saveSettings()` | new: a non-health `checkin_settings` key in the store document, with its own write method (a preference, like `saveTwinLook`) |

What `applyCheckin` needs for this branch:

1. Accept `kind: 'quick'`. Today `applyCheckinResponse` returns early for anything except `daily` and `weekly`. Record it as a `CheckinRecord` like `daily`.
2. Handle `daily_logs`. When `complete` is true, call `readFinishedCheckin(response, localDate:)` (in `checkin_store.dart`), then `mergeDayLogs(store.dailyLogs, parts)`. Each non-null value goes into its date's row, and the row gets `workday: weekdayNight(date)`. Write it with a new private `TwinStore._putDailyLogs(rows)`. Never write a missing value as 0.
3. Weekly `profile_update` now uses the package names `vigorous_recreation_min_week`, `moderate_recreation_min_week` and `sedentary_min_day`, which are already in `updatableProfileFields`. Its weekly summary rule then makes a row whenever all four are confirmed. `DailyLogsAssembler.weeklySummaries` uses the same week rule, so keep one of the two.
4. Skip `unknown`. The server already leaves `smoking_status: unknown` out of `profile_update`; the applier should skip it too.
5. Recompute after the write, as it does now, so the window code picks up a newly completed 7-day run.

Overlap: `twin_history.dart` already has `dailyWindows` and `weeklyWindow`. `DailyLogsAssembler` does the same over `DayLog`s and adds the package's limits per row. When both land, keep one: either `assessWithHistory` uses `DailyLogsAssembler.dailyWindow`, or this folder drops its copy.

## Forecast refresh

After a finished check-in or on app open:

```dart
final request = const DailyLogsAssembler().assessRequest(
  modelProfile: toModelProfile(profile), // profile_mapping.dart
  asOf: isoDay(dayOf(DateTime.now())),
  days: await store.dayLogs(),
  checkins: await store.checkins(),
);
final assessment = twin.assess(request); // LifeTwinEngine
```

`request` holds `weekly_summaries` if the latest 1–4 completed weeks have weekly check-ins with all four fields. Otherwise it holds `daily_logs`, the longest 28-, 21-, 14- or 7-day complete run ending yesterday. Otherwise it holds the profile alone. This is the same order as `candidateWindows`. Catch `FormatException` and fall back to the next window. Keep `profile_used` and `input_provenance` visible. Without a window, the forecast is the profile snapshot, unchanged by the day's answers.

## Tests

- `test/checkin_scheduler_test.dart`: rotation, missed days, catch-up, evenings, time zones, daylight saving, weekly.
- `test/checkin_daily_logs_test.dart`: exact package shapes, checked by calling the package's own `LifeTwinEngine.assess`.
- `test/checkin_controller_test.dart`: the controller with fake speech and a fake server.
- `test/checkin_reminders_test.dart`: notification planning with a fake, and the HTTP client.
