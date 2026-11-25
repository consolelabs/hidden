# Arrivals 24 hour lapse timer

Backlog row: "Arrivals 24 hour lapse is checked only at launch and when the prompt opens, not on a timer." Contract: `docs/megagoals/next-features/goals/05-f2-arrivals.md` and the Arrivals boards; the 24 hour rule itself (`ArrivalsInbox.expiry`, `expire`) is unchanged.

This file is force-added: `.gitignore` keeps `docs/implementation-notes/` local.

## Delta

- `ArrivalsInbox.nextLapse(firstSeen:)` (pure): the time the oldest waiting question lapses, or nil when nothing waits or no waiting app has a first-seen time.
- `ArrivalsController` keeps one timer, set for that time, and re-arms it after every change (`apply`). When it fires it runs the existing `refresh()`, so the lapse, the default section, the stored queue and the `.arrivalsChanged` notification (arrow dot, Icons list) are the same code path as before.
- The timer is injected (`schedule`), default a one-shot `Timer` on the main run loop in common modes.
- A wake (`NSWorkspace.didWakeNotification`, injected as `wakeCenter`) also runs `refresh()`: a run loop timer may not count the time a Mac sleeps, so a question that came due in sleep would otherwise wait for the timer's remaining time.
- No new string, no new preference, no new UI. An app the catalog has no first-seen time for never lapses, as before.

## Decisions

- One timer for the first due question, not one per question: the queue is short and every change re-arms.
- The delay is floored at 1 s so a timer that fires a hair early cannot spin.
- No CHANGELOG line: the file has no Unreleased section and the task forbids inventing one.

## Tests

`HiddenBarTests/ArrivalsInboxTests` (nextLapse, 2 cases) and `HiddenTests/ArrivalsControllerTests` (timer lapses a question, timer follows the oldest, answer cancels, lapse on wake, 4 cases). Run in the mac-ui VM with `-only-testing` for both classes. Red and green lines: see the PR body.

## Proof (pending the VM)

| Run | Production state | Command | Result |
|---|---|---|---|
| red | arm call and wake observer removed, `nextLapse` returns nil | `xcodebuild test-without-building -scheme "Hidden Bar" -configuration Debug-Direct -only-testing:HiddenTests/ArrivalsControllerTests -only-testing:HiddenBarTests/ArrivalsInboxTests` in the mac-ui guest | pending |
| green | as committed, merged with develop | same | pending |

Not run yet: the guest could not compile asset catalogs, so no build ran.
