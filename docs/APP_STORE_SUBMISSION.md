# Pancake App Store Submission Notes

Last updated: May 31, 2026

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
- Confirm the uploaded build has the `audio` value in `UIBackgroundModes`.
- Add the public privacy-policy URL and support URL in App Store Connect.
- Complete the App Privacy questionnaire in App Store Connect.
- Add current screenshots for iPhone and the watch companion.
- Record and host a short App Review demo video showing Adaptive Mix continuing after the iPhone returns to the Home screen.
- Record App Review notes that explain the watch companion flow, explicit Adaptive Mix start action, and background-audio demo video.

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
- Time-based interval pre-curation is deterministic. Distance-based interval pre-curation uses a live pace estimate and is best effort.
- The uploaded build declares the `audio` background mode because the user-started Adaptive Mix continues audible playback while the iPhone is in the background. Demo video: ADD URL BEFORE SUBMISSION.

## Cheer Squad (CloudKit) — Before It Ships

Cheer Squad lets a runner invite supporters with a private iCloud share link. Supporters get a notification when the runner starts a run and can send short text cheers that are read aloud over the runner's music. It rides on CloudKit and the user's iCloud identity — no Pancake accounts, no developer server.

### Developer portal and CloudKit Console

- Enable the iCloud capability with CloudKit for the iPhone App ID and create the container `iCloud.com.Matthew-Lucas.Hello-World.Pancake` (must match `CheerSquadManager.containerIdentifier` and the entitlements file).
- Enable Push Notifications for the App ID. CloudKit subscription pushes are delivered by Apple; no APNs key or certificate is needed.
- Run the app once against the Development environment to create the schema (record types `SquadInfo`, `RunStatus`, `RunCheer` in the private/shared zone; `RunAnnouncement` in the public database), then deploy the schema to Production in CloudKit Console before releasing.
- In CloudKit Console, confirm `RunCheer.sentAt` is queryable and `RunAnnouncement.squadID` is queryable in Production (the runner polls cheers by `sentAt`; supporter alerts subscribe on `squadID`).

### App Privacy questionnaire changes

The earlier "no data collected" posture changes when this ships. Data stored in the app's CloudKit container counts as collection:

- User Content: cheer messages (linked to identity via iCloud, not used for tracking).
- Identifiers/Name: the runner's display name is shared with invited squad members and appears briefly in an opaque public run announcement (random UUID squad key, deleted at run end).
- Update the privacy policy to describe Cheer Squad data flow before submission.

### User-generated content compliance (Guideline 1.2)

- Filtering: `CheerContentPolicy` blocks abusive terms and caps length on both send and receive; preset cheers are the primary path.
- Blocking: the runner can remove any squad member (revokes their share access) from Profile > Cheer Squad.
- Reporting: "Report a problem" in Cheer Squad opens a support email; respond within 24 hours per guideline expectations.
- Mention all three mechanisms in the review notes when this feature ships.

### Review notes additions

- Cheer Squad is optional and off until the user sets it up in Profile.
- Invites are private iCloud share links; there is no public discovery, feed, or profile browsing.
- The "started a run" push is a CloudKit subscription alert; the app declares no push-related background modes.

## Final QA Pass

- Verify a full watch-guided run on a real iPhone and paired watch.
- Verify watch Health and location prompts appear only after the related user action.
- Verify a run plan can be sent and completed without Apple Music authorization.
- Verify Apple Music library import and user-initiated catalog playback on a real device.
- Verify the watch companion Adaptive Mix start, play, pause, stop, and next controls.
- Verify Adaptive Mix playback continues after returning to the iPhone Home screen.
- Verify profile reset and run-history deletion.
- Verify app icons, launch, and screenshots match the shipping build.
