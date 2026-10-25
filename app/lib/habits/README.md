# Habits (v1): model, store and client

Pure Dart, no screens. The UI builds on these. The server is stateless: the phone keeps every habit record and result and sends what each call needs. Schemas: `contracts/habits.*.schema.json`. Server: `server/lifetwin/habits/`.

## Rules

- **Adults only.** Every route answers `status: "age_not_supported"` with no habit content when `age < 18`. An emergency line still comes first at any age. Ages 18 to 29 get habits too, but without model levers.
- **At most 2 active habits and 1 proposal.** `HabitStore.upsert` throws `HabitStoreError` when a change would break this, and the server returns 422.
- **A habit never counts toward the health score.** `HealthScoreInput` has no habits in it. Behaviour reaches the twin only through measured inputs (sleep, activity, sitting, smoking). `PendingHealthScore` always answers `notReady`, or `ageNotSupported` under 18.
- **Unknown is not "not today".** A skipped or unclear answer writes nothing. `record(id, day, null)` clears a day back to unknown.
- **Good week:** 4 or more distinct habit days (done or sort of done) in one Monday-to-Sunday week. Good weeks are counted over all time, never in a row, and never reset. Days are phone-local `YYYY-MM-DD` strings (`localDay(DateTime)`). Week math uses UTC calendar days, so DST and the server's time zone never move a day.
- **No streaks**, and no words like "missed" or "behind". Mochi's copy comes from the server's `message`.

## Files

- `habit.dart`: `Habit` (the wire `HabitRecord`, with `toJson` and `fromJson`), `HabitStatus`, and `HabitResult` (`done`, `partly`, `notToday`, wire `not_today`).
- `habit_week.dart`: `habitWeekProgress(results, today)` returns a `HabitWeek` (`weekStart`, `habitDaysThisWeek`, `goodWeekThisWeek`, `goodWeeksTotal`, `ignoredFutureDays`). Also `localDay`, `parseDay`, `weekStartOf` and `addDays`.
- `habit_store.dart`: `HabitStore` holds the records and per-day results. `apply(reply)` saves a returned proposal or changed habit and ignores refusals. `habitWeekProgressFor(id, today:)` gives the weekly card. `toJson`/`fromJson` save and restore it; the app keeps that JSON in its protected store.
- `habits_client.dart`: `HttpHabitsClient` and `HabitsReply`. Errors throw `HabitsFailure`, whose `plain` holds the server's safe message.
- `health_score.dart`: the `HealthScoreSource` boundary. This is only a placeholder.

## API

Every request carries `age`, `local_date` (today on the phone) and `habits` (the phone's records; `week` sends just one `habit`). Every reply carries `status`, `message` (Mochi's words), `mood` (`happy`, `proud`, `celebrate`, `cozy` or `concerned`), `emergency` and `safety`.

| Call | Sends | Returns |
|---|---|---|
| `propose` `POST /api/habits/propose` | `profile` (only `smoking_status`, `exercise_minutes_weekly`, `sleep_hours`), optional `sitting_minutes_daily`, and `own_words` (at most 5, newest first; sent only with `memory_consent`) | `proposed` with `proposal` (`status: proposed`), `supports` ("This supports your Move.") and a source; `pending` (the existing proposal again); `at_limit`; `nothing_new`; `age_not_supported`; `safety` |
| `update` `POST /api/habits/update` | `action` (`accept`, `edit` or `dismiss`), `habit_id`, and for `edit` any of `anchor`, `tiny_action`, `why_words` (at most 80 characters each) | `active` (accept sets `started_on`), `proposed` or `active` after an edit, `dismissed` (sets `dismissed_until` to 14 days on), `at_limit`, `age_not_supported`, `safety` (nothing changed); 404 for an unknown id; 409 for an invalid transition |
| `question` `POST /api/habits/question` | `action: ask` (optional `habit_id`), then `reply` with `text`, or `skip` | `asking` with `question` and `habit_id` (with two habits, they take turns by day); `answered` with `result`; `not_understood` (ask again, no result); `skipped` (unknown); `no_active_habit`; `safety` |
| `week` `POST /api/habits/week` | `habit` and `results` (day to `done`, `partly` or `not_today`; at most 400 days, and the client sends the most recent) | `ok` with `week_start`, `habit_days_this_week`, `good_week_this_week`, `good_weeks_total` and `ignored_future_days`; `age_not_supported` (all counts null) |

The proposal ranking is: the person's own words first, then model levers for ages 30 and over (quit smoking, then vigorous activity, then moderate activity, then +1 h sleep for short sleepers, then less sitting), then general guidelines. Quit-help goes only to people who smoke or who mention smoking. A dismissed habit comes back only on or after `dismissed_until`.

Safety (`safety` field): `emergency` (the shared 911 line; show the call button), `eating_care` (restricting, purging, weight or body worries: a fixed kind reply that suggests a doctor and names no helpline), `supplement` (including energy drinks, pre-workout and caffeine pills), `medical` (medicines and doses) and `alcohol`. Safety replies carry the habit unchanged, and the store's `apply` ignores them.

## Wiring a check-in (for the UI session)

1. After the daily check-in, if `store.active` is not empty, call `question(action: ask)` and say `question`.
2. Send the answer with `reply`, or send `skip`. When the reply is `answered`, call `store.record(habitId, today, result)`. For `skipped`, record nothing. For `not_understood`, say `message` and ask again.
3. To draw the weekly card, use `store.habitWeekProgressFor(id, today: localDay(DateTime.now()))`. To get Mochi's line, call `week`.
4. Map `mood` to Mochi's state: `proud` when a habit is done, `celebrate` for a good week, `happy` when a habit is accepted, `cozy` on quiet days and `concerned` for safety replies.
