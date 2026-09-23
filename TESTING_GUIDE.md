# Pancake Release Testing Guide

## Permission Flow

- [ ] Launch the watch companion with Health access undecided.
- [ ] Confirm no Health system prompt appears automatically.
- [ ] Tap `Continue` on the Health setup screen and confirm the Health system prompt appears.
- [ ] Send a plan from iPhone, tap `Start Workout` on the watch companion, and confirm location is requested only when needed.
- [ ] Confirm iPhone Health history import is optional and appears only after tapping `Continue` in Profile.
- [ ] Tap `Send run plan` with iPhone Health undecided. Confirm the plan is queued and Health workout access is requested to open the watch app. Deny it and confirm the queued plan can still be opened manually on the watch without Apple Music access.

## Workout Flow

- [ ] Create a multi-segment workout plan on iPhone.
- [ ] With Pancake closed on the paired watch, tap `Send run plan` on iPhone. Confirm Pancake opens on the watch and shows the plan; tap `Start Workout` when ready.
- [ ] Confirm `Start adaptive playlist?` appears with Yes and No. Choose either and confirm a large 3, 2, 1 appears for one second each, with a haptic on each number, before workout tracking starts. The countdown must not add time or distance to the run.
- [ ] Choose Yes with iPhone connected and Apple Music available. Confirm Adaptive Mix starts after the workout begins. Choose No on a subsequent run and confirm music stays off; the in-run Music page can still start it later.
- [ ] Cancel the prompt or countdown, then try again. Confirm no workout or music starts from the cancelled attempt and the plan remains available. Rapidly tap Start or a choice and confirm only one run starts. Leaving the app during preparation must cancel the countdown.
- [ ] With no plan received, confirm the watch asks for a plan from iPhone and offers no Quick Run or other workout-start shortcut. With a received plan, iPhone disconnected or Apple Music unavailable, confirm the run still starts. Reconnecting after more than 30 seconds must not unexpectedly start music from the old request.
- [ ] Send while the watch is unreachable, then reconnect it. Confirm the newest unstarted plan appears once and survives a watch app relaunch. A consumed or expired plan must not return.
- [ ] Start and complete the outdoor workout from the watch companion.
- [ ] Verify GPS distance, pace, heart rate, segment progress, and haptics.
- [ ] Verify the completed run appears in local iPhone history.

## Optional Music Flow

- [ ] Choose No at the watch's adaptive-playlist prompt and confirm music stays off when the workout starts.
- [ ] Grant Apple Music playback access after tapping `Continue`.
- [ ] Request a song from the watch companion and confirm playback starts.
- [ ] Test play, pause, stop, and another user-initiated suggestion.
- [ ] Open Song Check from Profile and tap `Generate And Play Mix`. Confirm one song begins playing and the screen shows three verified upcoming songs.
- [ ] Keep Song Check open for at least 30 seconds. Confirm the countdown reaches zero, resets, and the three upcoming songs change without interrupting the active song.
- [ ] Adjust Song Check heart rate or target zone. Confirm the upcoming playlist refreshes after a short debounce while the active song continues.
- [ ] Tap Next in Song Check. Confirm the queued song becomes active and the upcoming playlist refills to three verified songs.
- [ ] Verify a run still works if Apple Music authorization is denied.

## Adaptive Mix Flow

- [ ] Start a multi-segment run with Yes at the adaptive-playlist prompt and confirm Adaptive Mix begins once the run starts. Repeat with No and confirm music remains off until tapping `Start Adaptive Mix` on the watch companion.
- [ ] Tap `Start Adaptive Mix` and confirm the watch Music page shows the current song, the mix guidance line, the next queued song, target zone, and queued/played counts.
- [ ] Within a long interval, keep the current song playing for at least 60 seconds. Confirm the upcoming queue refreshes about every 30 seconds while the current song does not change.
- [ ] Tap Next and confirm the active song advances from the queued Adaptive Mix songs.
- [ ] Let an active song complete naturally and confirm playback advances from the queued Adaptive Mix songs.
- [ ] Use a 60-second Zone 1 interval followed by 60 seconds of Zone 5. Confirm preparation begins around second 15, and a suitable Zone 5 song starts around second 48, including when seated with low heart rate.
- [ ] Confirm preparation leaves the current song playing until the 12-second playback window. At the actual boundary, there must be no second automatic skip. Tap Next at 1:20 and 1:25; every selection must still fit Zone 5.
- [ ] While attached to the Xcode console, confirm each queued entry logs `Adaptive Mix verified Apple Music song` with an Apple Music catalog ID.
- [ ] Confirm unavailable or duplicate catalog candidates are skipped, and energy-ineligible candidates never reach catalog resolution. A partial suitable queue may play while more songs are sought; do not pad it with unassessed favorites.
- [ ] Let at least two 30-second refreshes complete without advancing playback. Confirm the played-song count does not increase when queued songs are replaced before playing.
- [ ] Tap Next or let playback complete. Confirm `Workout recorded played song` appears in the Xcode console and the watch played-song count increases.
- [ ] Confirm a song that played is not queued again during the same workout. Confirm a queued song that was replaced before playing remains eligible for a later queue.
- [ ] Note a song that played in one run. Start three more runs with music and confirm it is never queued in any of them. On the fifth run, confirm it becomes eligible again.
- [ ] Start a run, end it without playing any music, then start another run. Confirm the music-free run did not shorten the rest window for songs from earlier runs.
- [ ] With AI unavailable mid-run, confirm only previously assessed, zone-appropriate saved favorites or imported playlist songs are eligible as fallback. Unknown tracks must not be relabeled as intense. If none qualify, show that suitable songs are still being sought.
- [ ] On repeated one-minute high/low intervals, confirm Adaptive Mix follows each explicit zone and does not bypass changes because the workout is classified as fartlek. For intervals shorter than 12 seconds, the next zone can become due immediately.
- [ ] Delay generation/catalog responses across an interval change. Confirm the old zone's result is discarded and Next cannot consume its remaining queued songs. If the new queue is late, keep the current song until a suitable replacement is ready.
- [ ] Pause music before the transition. Confirm preparation and queue changes do not resume it. End a run while generation is pending, start another, and confirm the old response cannot affect the new run.
- [ ] On an Apple Intelligence-capable phone, inspect the separate recording-energy assessments for the reported tracks. Confirm *All of Me* is recognized as a ballad and excluded from Zone 5. Check several taste profiles; deterministic simulator fixtures do not establish model classification accuracy.
- [ ] Confirm Adaptive Mix plays with Pancake in the foreground and the display staying awake for the whole active run. The build declares no background audio mode, so playback stopping after the phone is locked is expected behaviour, not a bug.

## Run History Durability

- [ ] Complete a watch-guided run with the iPhone app open the whole time. Confirm the run appears in iPhone history with metrics and song history.
- [ ] Force-quit the iPhone app mid-run, then finish the run on the watch. Reopen the iPhone app and confirm the run still reaches history with the segments, data points, and song history recorded before the quit.
- [ ] While attached to the Xcode console, confirm a recovered run logs `♻️ Recovered interrupted run` and then `✅ saveRunEvent: Run event saved successfully`.
- [ ] Confirm a recovered run is saved once, not twice, when the watch completion message arrives after recovery.
- [ ] Force-quit mid-run, then start a brand new run without finishing the first. Confirm the interrupted run is saved before the new one begins rather than being overwritten.
- [ ] Confirm a recovered run is dated when the run happened, not when it was saved.
- [ ] Simulate a history-write failure. Confirm History shows the error, the recovery checkpoint remains, and retry saves the same run once.
- [ ] Start another workout on the watch during a Pancake run. Confirm the interrupted run retains its summary and history, reaches iPhone history once, and a subsequent run starts with cleared metrics.

Distance-based interval pre-curation uses a live pace estimate, so its ten-second timing is best effort. Time-based intervals should be used for deterministic verification.

## Interactive Run History

WatchConnectivity file delivery requires physical paired devices; Apple does not support `transferFile` in Simulator. The simulator loop verifies workout completion, while route analysis and durable inbox staging are covered by `scripts/test_regressions.sh`. A simulator import fixture can verify the history merge, but cannot validate the wireless transfer or acknowledgment.

- [ ] Complete an outdoor watch run with GPS and at least two songs. Open History > run details. Confirm the route arrives even if its file transfer finishes after the summary, and the summary does not duplicate.
- [ ] Trace the three-stripe route. Confirm elapsed time, distance, local pace, song, heart rate, and linked chart cursors update together. Use the slider to select either passage through a crossing.
- [ ] Turn Map off. Confirm only the route remains and tracing still works. Turn it back on and confirm the route stays aligned with the map.
- [ ] Verify pace changes use turquoise (slower) through indigo (faster), song colors match the song list, and heart-rate colors use blue/green/red relative to the recorded target. Missing measurements should be gray.
- [ ] Pause during a run, then resume. Confirm elapsed time excludes the pause and the route has a break, with no line drawn across movement during the pause.
- [ ] Disconnect iPhone for an entire run. Reconnect afterward and confirm the watch's full GPS/heart-rate archive reaches history; music that was not recorded must remain unlabelled.
- [ ] Compare full kilometer split times against the run's cumulative distances. The final partial split must be identified and its pace normalized per kilometer. Incomplete recordings should not invent splits across gaps.
- [ ] Open a run saved by an older build and a summary-only Health import. Confirm they still open with a clear missing-route message and only the measurements actually available.
- [ ] Check light/dark mode, larger text, and VoiceOver. The run-position slider must provide an alternative to tracing the route.

A DEBUG-only `--pancake-history-preview` launch argument opens an in-memory sample run for UI testing. It does not insert sample GPS into saved history.

## Watch In-Run UI

- [ ] During a workout, swipe vertically between the Controls, Metrics, Plan, and Music pages.
- [ ] On the Metrics page, confirm heart rate is color-coded against the target zone (blue below, green in zone, red above) with the target range and gauge shown.
- [ ] On the Plan page, confirm the remaining time or distance for the current segment counts down and the next segment is previewed.
- [ ] On a zone increase, confirm the "direction up" haptic plays; on a zone decrease, the "direction down" haptic.
- [ ] At an interval change with Pancake visible, confirm the music-control sheet shows the new zone and target. Keep Current Music must leave playback unchanged; Next and play/pause must follow the user's selection.
- [ ] With Pancake in the background and notification permission granted, confirm an interval notification offers Next Song, Play Music, and Pause Music. Opening the notification alone must not skip a song.
- [ ] Deny notification permission and confirm foreground interval controls still work. Disconnect iPhone and confirm a music action explains that iPhone is needed, without queuing a skip for later.
- [ ] Open an old interval notification after the next interval or a new run begins. Confirm its actions cannot affect the new interval/run.
- [ ] Pause from the Controls page. Confirm the elapsed time freezes, metrics stop accruing, and Resume continues without losing segment progress.
- [ ] Tap Water Lock and confirm the screen locks until the crown is turned.
- [ ] Complete the final planned segment on a real run. Confirm the haptic plays and the "Plan complete" chip appears while the workout keeps running.
- [ ] End the workout. Confirm the summary screen shows time, distance, average pace, and calories before returning to the start screen.
- [ ] With no plan received, confirm the watch waits for a plan from iPhone. Send a plan and confirm Start Workout becomes available with the phone's exact segments.
- [ ] Cover the heart-rate sensor mid-run (or remove the watch briefly). Confirm the heart-rate reading changes to `--` with a signal warning instead of freezing at a stale value.

## Cheer Squad Flow

Requires two devices signed into different iCloud accounts, with the CloudKit container provisioned (see docs/APP_STORE_SUBMISSION.md).

- [ ] With a blank profile display name, open Cheer Squad and confirm `Add name or username` is visible and squad setup is disabled. Enter only spaces and confirm Save stays disabled; Cancel must leave the profile unchanged.
- [ ] Save a name or username in Cheer Squad. Confirm Personal Info shows the same name after relaunch and squad setup becomes available. A supporter with no name must also add one from the send-cheer screen before either preset or custom cheers can be sent.
- [ ] On an existing squad labelled "Your friend", set a display name on the owner's device. Refresh on the supporter's device and confirm the squad shows the new name without another invitation. Check the invitation title too. Repeat by changing Display Name in Personal Info.
- [ ] Rename while offline, reconnect, and refresh Cheer Squad. Confirm the shared name updates and existing supporters stay joined. Rapidly save two names while a refresh is in progress and confirm the final name wins.
- [ ] On device A, open Profile > Cheer Squad, tap `Set up my squad`, then `Invite and manage supporters`. Confirm the system sharing sheet invites specific iCloud accounts and does not offer public access.
- [ ] On device B, open the invite link. Confirm Pancake opens, accepts the share, and the squad appears under "Squads I cheer for".
- [ ] On device B, tap `Enable run alerts` and accept the notification prompt.
- [ ] Start a workout on device A (watch). With background delivery available, confirm device B receives one "\<name\> is out for a run" notification after an authorized shared-record fetch. Delivery is best effort; delayed starts older than 15 minutes must not alert.
- [ ] On device B, open the squad and send a preset cheer. Confirm device A speaks the cheer over the music (music ducks, then recovers) within ~30 seconds and the watch shows the cheer chip with a haptic.
- [ ] Send preset and custom cheers after editing device B's name. Confirm the new name appears on device A and its watch and is spoken aloud. Previously received cheers keep the name used when sent.
- [ ] Send a free-text cheer containing a blocked word. Confirm it is rejected on send.
- [ ] On device A, remove device B from the squad. Confirm B can no longer send cheers or fetch new run status, and later runs do not create new alerts on B. Previously received alerts may remain.
- [ ] End the run on device A. Confirm shared status becomes ended and no public announcement is created. Finish while offline, relaunch, then reconnect and confirm the ended status retries.
- [ ] Upgrade an account with an existing public squad. Confirm it becomes private, the runner sees the re-invite notice, and explicitly re-invited supporters regain access. Confirm old public subscriptions and owned announcements are deleted when the service is reachable.
- [ ] With iCloud signed out, open Cheer Squad. Confirm a clear "sign in to iCloud" message and no crashes.
- [ ] With the CloudKit container not yet provisioned, confirm Cheer Squad reports itself unavailable and runs/music are unaffected.

## Local Simulator Run Loop

Run the standalone persistence, music policy, watch state, and private run-alert regressions:

```bash
scripts/test_regressions.sh
```

These use isolated test data and do not require an iCloud account. Real-device checks above are still required for HealthKit launches, interruption callbacks, system notifications, and CloudKit revocation.

Run the local iPhone/watch simulator loop:

```bash
scripts/simulated_run_loop.sh
```

The script creates or reuses an `iPhone Air` simulator and an `Apple Watch Series 11` simulator, pairs them, builds and installs both apps, starts a Central Park GPS loop with `simctl location`, launches both apps with DEBUG-only simulator flags, sends a time-based run plan from iPhone to watch, starts a simulated watch workout, starts Adaptive Mix from the watch, sends two Next commands, and validates the captured playlist logs.

The loop asserts:

- each generated upcoming playlist has three non-duplicate songs
- played songs do not repeat during the workout
- skipped or replaced but unplayed songs remain eligible for later playlists
- interval music actions receive acknowledgment, while an old interval's action is rejected by iPhone
- the watch completes the simulated run and the iPhone saves the run event

For manual watch UI checks, launch the watch app with `--pancake-simulated-run --pancake-manual-start`. It uses synthetic metrics but waits for a phone plan and the actual Start Workout → playlist choice → countdown flow. The automated loop exercises the music opt-in in the workout-start message; the prompt and countdown also need manual UI checks.

Useful overrides:

```bash
PANCAKE_SIM_WAIT_SECONDS=145 \
PANCAKE_SIM_SPEED_MPS=3.15 \
scripts/simulated_run_loop.sh
```

The synthetic playback loop uses deterministic DEBUG-only song and energy-assessment fixtures. It tests orchestration and filtering without Apple Music or Apple Intelligence; it does not validate real song recognition. Run `PANCAKE_SIM_TRANSITION_TEST=1 scripts/simulated_run_loop.sh` to reproduce a seated 60-second Zone 1 → 60-second Zone 5 plan with skips at 1:20 and 1:25. The loop requires a single automatic transition near second 48 and suitable tracks on both skips.

If simulator WatchConnectivity cannot deliver the plan, use the existing virtual watch against the production phone coordinator: `scripts/test_music_transitions.sh <booted-iPhone-simulator-ID>`. This builds both targets, then runs the seated transition and a second scenario paused through the boundary. Logical time runs tenfold. The first must switch once at second 48; the paused scenario must keep the original song paused until resuming at second 65. Both must retain appropriate energy through skips at 80 and 85 seconds.


## Local Data Controls

- [ ] Reset profile data from Profile and confirm personal info, goals, and music preferences are cleared.
- [ ] Clear run history from History and confirm the local records are deleted.

## Archive Inspection

- [ ] Confirm the iPhone bundle has `CKSharingSupported = true` and `UIBackgroundModes = [remote-notification]` for private shared-run alerts.
- [ ] Confirm the iPhone bundle has no location usage description.
- [ ] Confirm the iPhone entitlements do not include Sign in with Apple.
- [ ] Confirm the watch companion retains Health and location usage descriptions.
- [ ] Confirm App Store Connect subtitle localizations do not contain `Apple Watch`.

## Distance units and watch alert duration

- In iPhone **Profile → Distance Units**, select **Miles**. Add a distance segment; its input advances in 0.1-mile steps. Send the plan and confirm the watch displays `mi` and `/mi` in the plan, live metrics, and summary.
- Cross a full mile and check that the distance alert lasts four seconds, then returns to the metrics page. Kilometer crossings must not trigger alerts while Miles is selected.
- Change intervals while viewing the watch plan or music page. Leave the interval prompt untouched; after four seconds it must close onto run metrics. Repeat with a music command still pending or failing; a late reply must not reopen the prompt.
- Change units while the watch is disconnected, reconnect, and verify the preference arrives without losing or reopening a consumed run plan. Relaunch both apps and verify the preference persists.
- Check an existing 5 km / 25 minute run: Miles should show `3.11 mi` and `8:03/mi`, and its replay should use mile split boundaries. Switch back to Kilometers and confirm the original distance and pace.

`scripts/test_regressions.sh` checks conversions against both run model implementations, milestone boundaries and resets, history compatibility, and full/partial mile splits.
