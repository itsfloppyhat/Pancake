# Pancake Privacy Policy

Last updated: September 20, 2026

Pancake is a running companion app that helps guide workouts and curate an optional Adaptive Mix that fits the runner's current effort.

## What Pancake Uses

Pancake can request access to:

- Health data on the watch companion, such as workouts and heart rate, to guide runs and save completed workouts.
- Health workout history on iPhone, when the user chooses to import completed runs.
- Location on the watch companion, when an outdoor workout starts, to measure distance and pace.
- Apple Music library data, when the user chooses to import music taste.
- Apple Music playback access, when the user chooses to play generated song suggestions or start an Adaptive Mix from the Apple Music catalog.
- iCloud account access, when the user sets up or joins a Cheer Squad, to store squad data and send run/cheer notifications.

## How Data Is Handled

- Pancake stores run history, profile information, and music preferences on the device.
- Pancake retains this on-device data until the user clears it in the app or deletes the app.
- Pancake does not include third-party advertising SDKs.
- Pancake does not use third-party analytics SDKs.
- Pancake does not sell personal information.
- Pancake does not track users across apps or websites.
- Outside of the optional Cheer Squad feature described below, Pancake does not create a Pancake account or upload profile data to a developer-controlled server.
- Pancake does not share personal data with third-party SDKs or developer-controlled services. Requests made through Apple frameworks are handled by Apple services under the user's account and Apple's applicable privacy terms.

## Cheer Squad (Optional)

Cheer Squad is an optional feature that lets a runner invite friends or family to follow along and send encouragement during a run.

- Cheer Squad requires the user to be signed in to iCloud and uses Apple's CloudKit framework to store and sync squad data under the user's Apple Account, not on a developer-controlled server.
- When a user sets up a squad, Pancake stores the user's display name and a squad identifier in the user's private iCloud database.
- Inviting a supporter uses Apple's sharing controls to select specific Apple Accounts by email address or phone number. Only those accounts can accept the invitation; forwarding the link does not grant access to another account.
- Supporters who join a squad share their display name with the squad owner and other members of that squad, and can see when the runner starts a run.
- Squad members can send short cheer messages that are visible to the runner (and, if enabled, read aloud during the run) and to other squad members. Cheer messages are limited in length and screened against a list of blocked terms before they can be sent.
- The runner can remove a squad member at any time from the Cheer Squad screen, which revokes that member's access to future run status and cheer activity for that squad.
- Run status and notification preferences remain in the private shared zone. A background notification contains no runner name or run details. Before displaying a run-start alert, Pancake fetches the run status using the supporter's current sharing permission. Background delivery can be delayed or unavailable.
- Earlier versions stored public run announcements containing a display name and squad identifier. This version stops publishing those announcements, retires public invitation links, and attempts to delete old announcements and notification subscriptions when online. Cleanup is retried after failures; older installations must be updated to stop their public announcements. Previous supporters need a new invitation to their specific Apple Account.
- Users can flag a concern about received cheer content using the in-app "Report a problem" option, which contacts the developer using the email address below.

## Apple Services

When Pancake searches the Apple Music catalog or requests playback through Apple frameworks, those requests are handled by Apple services under the user's Apple account and Apple Music subscription.

When Pancake reads or writes workout information through Health, that data is managed through Apple's Health framework and the permissions granted by the user.

When Pancake syncs Cheer Squad data or delivers run/cheer notifications, that data is managed through Apple's CloudKit and push notification services under the user's Apple Account.

## User Controls

Users can:

- revoke Health access in the Health app or Settings
- revoke Location access in Settings
- revoke Apple Music library access in Settings
- revoke Apple Music playback access in Settings
- reset stored profile information, goals, and music preferences from the Pancake Profile screen
- clear stored run-history data from the Pancake History screen
- remove a squad member, stop sharing through "Invite and manage supporters," or turn off run-start alerts and spoken cheers, from the Cheer Squad screen
- delete the app to remove remaining Pancake data stored on the device

Cheer Squad data is stored in Apple's CloudKit service. Removing a member or stopping sharing revokes future access but does not erase copies or alerts that a supporter already received. Stopping sharing does not delete the runner's private squad records. Deleting the app removes local app data and does not delete iCloud data or legacy public announcements. For questions about deleting stored Cheer Squad data or legacy announcements, contact the email address below.

## Contact

For privacy questions, contact mattlucascodes@gmail.com.
