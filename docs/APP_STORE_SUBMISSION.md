# Pancake App Store Submission Notes

Last updated: April 27, 2026

## Product Positioning

Pancake is a running assistant that:

- guides structured runs with Apple Watch workout context
- adapts music suggestions to workout intensity and live runner state
- learns music taste from the user's library, saved favorites, and imported playlist taste samples
- previews generated songs on iPhone without requiring a live run
- includes an optional friends surface for run-sharing setup, notification permission, and spoken comment playback

## Manual Tasks Before Submission

- Enable the MusicKit app service for the iPhone app ID in Apple's developer portal.
- Enable Sign in with Apple for the iPhone app ID before shipping account-backed social features.
- Add Push Notifications and a server/APNs relay before advertising live friend run alerts as a production feature.
- Add a public privacy policy URL in App Store Connect.
- Complete the App Privacy questionnaire in App Store Connect.
- Add App Store screenshots for iPhone and Apple Watch.
- Fill in the App Store description, subtitle, keywords, and support URL.
- Record App Review notes that explain the Apple Watch flow and optional Apple Music setup.

## Recommended App Privacy Responses

This is an engineering recommendation based on the current codebase and should be rechecked before submission.

- Tracking: No
- Third-party advertising: No
- Third-party analytics: No
- Data sold: No
- Data shared with data brokers: No
- App-collected data sent to developer-controlled servers: None found in the current codebase

If you add crash reporting, analytics, cloud sync, push-backed friend activity, or account-backed comments later, these answers need to be updated.

## Suggested Review Notes

Pancake pairs with Apple Watch for guided runs.

- The guided workout experience is driven from the watch during a run.
- Apple Music access is optional but recommended for taste import and catalog playback.
- The iPhone includes a Song Check screen in Profile so the reviewer can generate and play a song without starting a workout outdoors.
- If Apple Music playback is not authorized, Pancake can still work with library-only suggestions when local music is available.
- The Friends tab currently demonstrates client-side setup and spoken comment playback. Production friend alerts require backend/APNs delivery before release marketing should describe them as live.

## Final QA Pass

- Verify Apple Music library import on a real device.
- Verify Apple Music catalog playback on a real device.
- Verify a full watch-guided run with the iPhone screen locked.
- Verify permission prompts are understandable and only requested when needed.
- Verify Sign in with Apple entitlement and developer portal capability are enabled.
- Verify notification permission and spoken comment playback on a real device.
- Verify app icons, launch, and screenshots match the shipping build.
