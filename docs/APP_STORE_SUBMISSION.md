# Pancake App Store Submission Notes

Last updated: September 20, 2026

## Product Positioning

Pancake is a running assistant that:

- guides structured runs with watch workout context
- adapts an optional three-song music queue to workout intensity and live runner state
- learns music taste from the user's library, saved favorites, and imported playlist taste samples
- previews the optional Adaptive Mix on iPhone against simulated run metrics without requiring a live run

## Manual Tasks Before Submission

- Upload a new archive with build number 10 or later. Do not resubmit build 7.
- Remove `Apple Watch` from the subtitle in every App Store Connect localization. Suggested subtitle: `Guided run planner`.
- Check promotional text, description, keywords, screenshots, and review notes for unnecessary Apple product trademark references.
- Keep paid-app metadata centered on guided run planning, workout metrics, history, and the watch companion. Describe Adaptive Mix as optional because App Review Guideline 4.5.2 prohibits indirectly monetizing access to Apple Music.
- The iPhone declares only the `remote-notification` background mode for permission-checked Cheer Squad alerts. Adaptive Mix plays through app-scoped players (`ApplicationMusicPlayer` and `MPMusicPlayerController.applicationQueuePlayer`), so playback runs while Pancake is in the foreground and the app keeps the display awake for the duration of an active run.
- Add the public privacy-policy URL and support URL in App Store Connect.
- Complete the App Privacy questionnaire in App Store Connect.
- Add current screenshots for iPhone and the watch companion.
- Record and host a short App Review demo video showing the user-initiated Adaptive Mix start and playback during an active run.
- Record App Review notes that explain the watch companion flow and the explicit Adaptive Mix start action.

## Recommended App Privacy Responses

This is an engineering recommendation based on the current codebase and should be rechecked before submission.

- Tracking: No
- Third-party advertising: No
- Third-party analytics: No
- Data sold: No
- Data shared with data brokers: No
- App-collected data sent to developer-controlled servers: None found in the current codebase

If you add crash reporting, analytics, cloud sync, push notifications, or account features later, these answers need to be updated.

## Suggested Review Notes

Pancake pairs with its watch companion for guided outdoor runs.

- The guided workout experience is driven from the watch companion during a run.
- Health access on the watch companion is requested only after the reviewer taps Continue.
- Location access is requested when the reviewer starts an outdoor workout.
- iPhone Health history import is optional and is requested only after the reviewer taps Continue in Profile.
- Apple Music library import and catalog playback are optional.
- The paid app provides structured run planning, watch-guided workouts, live workout progress, local run history, and profile controls without Apple Music authorization. The optional Apple Music integration has no separate charge, in-app purchase, advertising, or required user-information exchange.
- Music does not start automatically. During an active workout, the reviewer can tap `Start Adaptive Mix` in the watch companion music control. That explicit action starts catalog playback.
- The reviewer can also open Profile > Song Check on iPhone and tap `Generate And Play Mix` to verify the same user-initiated catalog playback without starting a workout.
- While Adaptive Mix is active, Pancake refreshes three upcoming songs against the current run metrics about every 30 seconds. Each queued song is resolved to a playable Apple Music catalog listing before it enters the queue. If a generated candidate is unavailable, Pancake fills that slot with a different song. The active song is not interrupted. The queue advances only when the active song completes or the runner taps Next. Songs that actually play are excluded for the remainder of the workout; queued songs that never play are not permanently excluded.
- About ten seconds before a planned interval transition, Pancake refreshes the upcoming queue against the next interval goal without automatically changing the active song.
- At each interval change, the watch offers music controls in the foreground prompt or system notification. Next Song changes playback only when selected; old interval actions are rejected.
- Time-based interval pre-curation is deterministic. Distance-based interval pre-curation uses a live pace estimate and is best effort.
- Tapping `Send run plan` on iPhone opens the Pancake watch app on the paired watch via `HKHealthStore.startWatchApp(with:)`, with the plan already in flight. The watch never starts the workout by itself — the runner still taps Start Run there. This is why the iPhone asks for permission to write workouts to Health; the phone itself does not save workouts.
- The iPhone app declares `remote-notification` solely to fetch authorized shared run status for Cheer Squad alerts. The watch companion declares `workout-processing`, which watchOS requires both for the launch above and for keeping the live workout session running when the watch app is not frontmost. Adaptive Mix plays only while Pancake is in the foreground; the app keeps the display awake during an active run and releases that as soon as the run completes. Demo video: ADD URL BEFORE SUBMISSION.

## Cheer Squad (CloudKit) — Before It Ships

Cheer Squad lets a runner invite specific Apple Accounts using Apple's sharing controller. Supporters can receive a run-start alert after a background push and a fresh authorized read of the shared run status, and can send short text cheers that are read aloud over the runner's music. Background delivery is best effort. It uses CloudKit and the user's iCloud identity, with no Pancake accounts or developer server.

### Developer portal and CloudKit Console

- Enable the iCloud capability with CloudKit for the iPhone App ID and create the container `iCloud.com.Matthew-Lucas.Hello-World.Pancake` (must match `CheerSquadManager.containerIdentifier` and the entitlements file).
- Enable Push Notifications for the App ID. CloudKit subscription pushes are delivered by Apple; no APNs key or certificate is needed.
- Confirm the built iPhone plist contains `CKSharingSupported = true` and `UIBackgroundModes = [remote-notification]`.
- Run the app against Development to create `SquadInfo`, `RunStatus`, and `RunCheer` in the private/shared zone. `RunStatus` now includes `runID` (String) and `alertsEnabled` (Int64/Boolean) in addition to `status` and `startedAt`. Deploy these fields and the shared-database `RunStatus` subscription type to Production before releasing.
- Confirm `RunCheer.sentAt` is queryable in Production. Current clients do not create public run announcements or public query subscriptions.
- For existing deployments, retain the legacy `RunAnnouncement.squadID` query index so clients can delete old public records. Existing public shares are converted to private sharing, which removes public participants; the UI explicitly asks the runner to re-invite specific accounts. Cleanup of old announcements/subscriptions retries when online.
- Before rollout, audit and remove remaining legacy public announcements in CloudKit Console and retire older app versions that can still publish them. An updated client cannot remove another iCloud user's subscription or prevent an older installation from creating public records. No CloudKit production schema or permission changes are performed by the source changes alone.

### App Privacy questionnaire changes

The earlier "no data collected" posture changes when this ships. Data stored in the app's CloudKit container counts as collection:

- User Content: cheer messages (linked to identity via iCloud, not used for tracking).
- Identifiers/Name: the runner's display name and private squad identifier are shared with explicitly invited squad members. Current run status and run identifiers remain in the private/shared zone. Disclose legacy public announcements and their best-effort deletion as described in the privacy policy.
- Update the privacy policy to describe Cheer Squad data flow before submission.

### User-generated content compliance (Guideline 1.2)

- Filtering: `CheerContentPolicy` blocks abusive terms and caps length on both send and receive; preset cheers are the primary path.
- Blocking: the runner can remove any squad member (revokes their share access) from Profile > Cheer Squad.
- Reporting: "Report a problem" in Cheer Squad opens a support email; respond within 24 hours per guideline expectations.
- Mention all three mechanisms in the review notes when this feature ships.

### Review notes additions

- Cheer Squad is optional and off until the user sets it up in Profile.
- Invites require a selected Apple Account. Apple's sharing controller is restricted to `.allowPrivate` and `.allowReadWrite`; there is no anyone-with-link option.
- A shared-database subscription sends a content-free background push. The app displays a local run-start alert only after successfully fetching the private shared run status. Removed supporters cannot fetch new status or receive new run-start content. Alerts may be delayed or omitted by the system; they are not a safety or tracking service.

## Final QA Pass

- Verify a full watch-guided run on a real iPhone and paired watch.
- Verify watch Health and location prompts appear only after the related user action.
- Verify `Send run plan` opens the watch app on a paired watch, and that denying the iPhone workout-write prompt still sends the plan (with a message telling the runner to open Pancake on the watch).
- Verify a run plan can be sent and completed without Apple Music authorization.
- Verify Apple Music library import and user-initiated catalog playback on a real device.
- Verify the watch companion Adaptive Mix start, play, pause, stop, and next controls.
- Verify foreground Adaptive Mix playback and the current limitation that locking or backgrounding iPhone can stop playback.
- Verify profile reset and run-history deletion.
- With two real iCloud accounts, verify invitation acceptance on cold/warm launch, reject a forwarded invitation on a third account, then remove a supporter and verify they cannot fetch later run status or receive later alerts.
- Verify migrating a public share removes its old participants and shows the re-invitation notice. Verify legacy public record/subscription cleanup, including offline failure and retry.
- Verify duplicate background pushes produce one alert, disabled runner alerts produce none, ended/stale runs produce none, and finishing offline eventually writes the ended status after relaunch.
- Verify app icons, launch, and screenshots match the shipping build.
