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
- [ ] With Pancake closed on the paired watch, tap `Send run plan` on iPhone. Confirm Pancake opens on the watch and shows the plan; tap `Start Run` when ready.
- [ ] Send while the watch is unreachable, then reconnect it. Confirm the newest unstarted plan appears once and survives a watch app relaunch. A consumed or expired plan must not return.
- [ ] Start and complete the outdoor workout from the watch companion.
- [ ] Verify GPS distance, pace, heart rate, segment progress, and haptics.
- [ ] Verify the completed run appears in local iPhone history.

## Optional Music Flow

- [ ] Confirm music does not start automatically when the workout starts.
- [ ] Grant Apple Music playback access after tapping `Continue`.
- [ ] Request a song from the watch companion and confirm playback starts.
- [ ] Test play, pause, stop, and another user-initiated suggestion.
- [ ] Open Song Check from Profile and tap `Generate And Play Mix`. Confirm one song begins playing and the screen shows three verified upcoming songs.
- [ ] Keep Song Check open for at least 30 seconds. Confirm the countdown reaches zero, resets, and the three upcoming songs change without interrupting the active song.
- [ ] Adjust Song Check heart rate or target zone. Confirm the upcoming playlist refreshes after a short debounce while the active song continues.
- [ ] Tap Next in Song Check. Confirm the queued song becomes active and the upcoming playlist refills to three verified songs.
- [ ] Verify a run still works if Apple Music authorization is denied.

## Adaptive Mix Flow

- [ ] Start a multi-segment run and confirm music remains off until tapping `Start Adaptive Mix` on the watch companion.
- [ ] Tap `Start Adaptive Mix` and confirm the watch Music page shows the current song, the mix guidance line, the next queued song, target zone, and queued/played counts.
- [ ] Keep the current song playing for at least 60 seconds. Confirm the upcoming queue refreshes about every 30 seconds while the current song does not change.
- [ ] Tap Next and confirm the active song advances from the queued Adaptive Mix songs.
- [ ] Let an active song complete naturally and confirm playback advances from the queued Adaptive Mix songs.
- [ ] Use a time-based interval that is at least 30 seconds long. Confirm the queue refreshes about ten seconds before the next interval starts and the target zone changes to the upcoming interval.
- [ ] Confirm the pre-interval refresh does not interrupt the active song and restarts the 30-second refresh cadence.
- [ ] While attached to the Xcode console, confirm each queued entry logs `Adaptive Mix verified Apple Music song` with an Apple Music catalog ID.
- [ ] Confirm an unavailable, non-playable, or duplicate generated candidate logs a skip and increments the replacement count while the queue still reports three verified upcoming songs.
- [ ] Let at least two 30-second refreshes complete without advancing playback. Confirm the played-song count does not increase when queued songs are replaced before playing.
- [ ] Tap Next or let playback complete. Confirm `Workout recorded played song` appears in the Xcode console and the watch played-song count increases.
- [ ] Confirm a song that played is not queued again during the same workout. Confirm a queued song that was replaced before playing remains eligible for a later queue.
- [ ] Note a song that played in one run. Start three more runs with music and confirm it is never queued in any of them. On the fifth run, confirm it becomes eligible again.
- [ ] Start a run, end it without playing any music, then start another run. Confirm the music-free run did not shorten the rest window for songs from earlier runs.
- [ ] With Apple Music unavailable mid-run, confirm the fallback song comes from the runner's own saved favorites or imported playlist, never from a built-in song list.
- [ ] On a fartlek-style plan (short alternating segments), confirm the queue is not re-curated before segments shorter than 90 seconds and the queue energy follows the lookahead zone.
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
- [ ] With no plan received, tap `Quick Run` and confirm a 30-minute easy run starts and music suggestions still work.
- [ ] Cover the heart-rate sensor mid-run (or remove the watch briefly). Confirm the heart-rate reading changes to `--` with a signal warning instead of freezing at a stale value.

## Cheer Squad Flow

Requires two devices signed into different iCloud accounts, with the CloudKit container provisioned (see docs/APP_STORE_SUBMISSION.md).

- [ ] On device A, open Profile > Cheer Squad, tap `Set up my squad`, then `Invite and manage supporters`. Confirm the system sharing sheet invites specific iCloud accounts and does not offer public access.
- [ ] On device B, open the invite link. Confirm Pancake opens, accepts the share, and the squad appears under "Squads I cheer for".
- [ ] On device B, tap `Enable run alerts` and accept the notification prompt.
- [ ] Start a workout on device A (watch). With background delivery available, confirm device B receives one "\<name\> is out for a run" notification after an authorized shared-record fetch. Delivery is best effort; delayed starts older than 15 minutes must not alert.
- [ ] On device B, open the squad and send a preset cheer. Confirm device A speaks the cheer over the music (music ducks, then recovers) within ~30 seconds and the watch shows the cheer chip with a haptic.
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

Useful overrides:

```bash
PANCAKE_SIM_WAIT_SECONDS=145 \
PANCAKE_SIM_SPEED_MPS=3.15 \
scripts/simulated_run_loop.sh
```

The simulator path uses stored `MusicPreferences` when present. If the simulator has no imported Apple Music taste, it seeds a deterministic DEBUG-only taste profile so queue, skip, refill, and no-repeat behavior can still be tested without Apple Music services.

## Local Data Controls

- [ ] Reset profile data from Profile and confirm personal info, goals, and music preferences are cleared.
- [ ] Clear run history from History and confirm the local records are deleted.

## Archive Inspection

- [ ] Confirm the iPhone bundle has `CKSharingSupported = true` and `UIBackgroundModes = [remote-notification]` for private shared-run alerts.
- [ ] Confirm the iPhone bundle has no location usage description.
- [ ] Confirm the iPhone entitlements do not include Sign in with Apple.
- [ ] Confirm the watch companion retains Health and location usage descriptions.
- [ ] Confirm App Store Connect subtitle localizations do not contain `Apple Watch`.
