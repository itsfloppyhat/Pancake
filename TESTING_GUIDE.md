# Pancake Release Testing Guide

## Permission Flow

- [ ] Launch the watch companion with Health access undecided.
- [ ] Confirm no Health system prompt appears automatically.
- [ ] Tap `Continue` on the Health setup screen and confirm the Health system prompt appears.
- [ ] Send a plan from iPhone, tap `Start Workout` on the watch companion, and confirm location is requested only when needed.
- [ ] Confirm iPhone Health history import is optional and appears only after tapping `Continue` in Profile.
- [ ] Confirm a run plan can be sent without granting iPhone Health or Apple Music access.

## Workout Flow

- [ ] Create a multi-segment workout plan on iPhone.
- [ ] Send the plan to the paired watch.
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
- [ ] On a fartlek-style plan (short alternating segments), confirm the queue is not re-curated before segments shorter than 90 seconds and the queue energy follows the lookahead zone.
- [ ] Return the iPhone to the Home screen during Adaptive Mix playback and confirm audible playback continues.
- [ ] Record the background-audio verification for the App Review notes.

Distance-based interval pre-curation uses a live pace estimate, so its ten-second timing is best effort. Time-based intervals should be used for deterministic verification.

## Watch In-Run UI

- [ ] During a workout, swipe vertically between the Controls, Metrics, Plan, and Music pages.
- [ ] On the Metrics page, confirm heart rate is color-coded against the target zone (blue below, green in zone, red above) with the target range and gauge shown.
- [ ] On the Plan page, confirm the remaining time or distance for the current segment counts down and the next segment is previewed.
- [ ] On a zone increase, confirm the "direction up" haptic plays; on a zone decrease, the "direction down" haptic.
- [ ] Pause from the Controls page. Confirm the elapsed time freezes, metrics stop accruing, and Resume continues without losing segment progress.
- [ ] Tap Water Lock and confirm the screen locks until the crown is turned.
- [ ] Complete the final planned segment on a real run. Confirm the haptic plays and the "Plan complete" chip appears while the workout keeps running.
- [ ] End the workout. Confirm the summary screen shows time, distance, average pace, and calories before returning to the start screen.
- [ ] With no plan received, tap `Quick Run` and confirm a 30-minute easy run starts and music suggestions still work.
- [ ] Cover the heart-rate sensor mid-run (or remove the watch briefly). Confirm the heart-rate reading changes to `--` with a signal warning instead of freezing at a stale value.

## Cheer Squad Flow

Requires two devices signed into different iCloud accounts, with the CloudKit container provisioned (see docs/APP_STORE_SUBMISSION.md).

- [ ] On device A, open Profile > Cheer Squad and tap `Set up my squad`. Confirm an invite link can be shared via Messages.
- [ ] On device B, open the invite link. Confirm Pancake opens, accepts the share, and the squad appears under "Squads I cheer for".
- [ ] On device B, tap `Enable run alerts` and accept the notification prompt.
- [ ] Start a workout on device A (watch). Confirm device B receives a "\<name\> is out for a run" notification within a minute.
- [ ] On device B, open the squad and send a preset cheer. Confirm device A speaks the cheer over the music (music ducks, then recovers) within ~30 seconds and the watch shows the cheer chip with a haptic.
- [ ] Send a free-text cheer containing a blocked word. Confirm it is rejected on send.
- [ ] On device A, remove device B from the squad. Confirm device B can no longer send cheers.
- [ ] End the run on device A. Confirm no further run notification exists for device B and the public announcement is gone.
- [ ] With iCloud signed out, open Cheer Squad. Confirm a clear "sign in to iCloud" message and no crashes.
- [ ] With the CloudKit container not yet provisioned, confirm Cheer Squad reports itself unavailable and runs/music are unaffected.

## Local Simulator Run Loop

Run the local iPhone/watch simulator loop:

```bash
scripts/simulated_run_loop.sh
```

The script creates or reuses an `iPhone Air` simulator and an `Apple Watch Series 11` simulator, pairs them, builds and installs both apps, starts a Central Park GPS loop with `simctl location`, launches both apps with DEBUG-only simulator flags, sends a time-based run plan from iPhone to watch, starts a simulated watch workout, starts Adaptive Mix from the watch, sends two Next commands, and validates the captured playlist logs.

The loop asserts:

- each generated upcoming playlist has three non-duplicate songs
- played songs do not repeat during the workout
- skipped or replaced but unplayed songs remain eligible for later playlists
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

- [ ] Confirm the iPhone bundle has `UIBackgroundModes` with the `audio` value.
- [ ] Confirm the iPhone bundle has no location usage description.
- [ ] Confirm the iPhone entitlements do not include Sign in with Apple.
- [ ] Confirm the watch companion retains Health and location usage descriptions.
- [ ] Confirm App Store Connect subtitle localizations do not contain `Apple Watch`.
