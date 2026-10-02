# Tests — StudyFlow PDF

## What exists today

Seven files, 111 tests, all green (last full run 2026-10-02). Treat the count as a
snapshot — read `test/` instead of trusting it.

| File | Holds |
|---|---|
| `test/dashboard_layout_test.dart` | Section layout: the lecture row's critical baseline, card sizes, narrow widths |
| `test/dashboard_search_test.dart` | The search panel: suggestion order, matches, and that the panel hangs off the field's bottom |
| `test/folder_announcements_test.dart` | The announcements page and the composer, with no Isar and no Firebase behind them |
| `test/timetable_entry_test.dart` | Parsing and formatting a timetable entry |
| `test/tool_width_limits_test.dart` | The single source of truth for stroke widths |
| `test/university_downloaded_hashes_test.dart` | The rule behind the "downloaded" hash |
| `test/update_flow_test.dart` | Version ordering, which release asset is picked, digest/length verification, that a forced update downloads and hands over to Setup with no button pressed, and that the gate never mutates state while building |

`docs/AGENTS.md` used to claim there were no tests and told agents not to run
them. That was true once and is false now — these files are why this project
stopped shipping unverified UI. Do not repeat that claim.

## When a test is the right answer

**Yes** for a rule that can break silently (a height that must equal another
height, a clamp, an ordering, a parse) or something the eye cannot judge (a row's
baseline, a panel's anchor, a computed text width).

**No** for colour, spacing, radius, font, shadow, animation — anything judged by
looking. Writing a test for those spends the user's tokens, produces a green tick
that proves nothing about whether it looks right, and the user is the only
instrument that can decide. Ask them to check it by eye instead; this is their
explicit instruction, and it is also cheaper.

## How the tests here are written

- Names describe behaviour, not methods: *"the publish bar sits under the list,
  not over it"*, *"a picture-only note is named, not printed as «»"*.
- Fixtures at the top of `main`, so the body reads as behaviour rather than data.
- A short header comment saying which failure the file exists to prevent. Several
  of these files were written after a specific bug and they name it.
- No Isar, no Firebase, no network: build the widget with plain props.
- When the property is positional, assert against the render tree
  (`tester.getRect`) — an `expect` on widget fields passes while the row still
  overflows.
- A widget whose own path touches the filesystem — writing a download, hashing it
  back — **hangs under `pump` alone**. `pump` advances fake time while file I/O
  completes on the real event loop, so the future never resolves and the test
  times out with no failing assertion. Wrap the wait in
  `tester.runAsync(() => Future.delayed(...))`, pump once, then check *after* the
  call: a task entered by a post-frame callback is not running yet when a
  pump-until helper first looks at it, and a helper that checks first steps over
  it and hangs. This cost real time in `update_flow_test.dart` — the note is here
  so the next person does not rediscover it.
- Dispose the widget before deleting a temp directory it wrote to
  (`await tester.pumpWidget(const SizedBox.shrink())`): Windows keeps the file
  locked until then and the delete fails with `ERROR_SHARING_VIOLATION`, which
  reads as a `PathAccessException` in `tearDown` and looks like a test failure in
  an unrelated place.
- Comments inside a test explain *why* the case matters, like the rest of the code.

## Running

```powershell
flutter test test/tool_width_limits_test.dart   # one file while working
flutter test                                    # everything, before reporting
flutter test test/xyz_test.dart --reporter expanded   # when a printed number is wanted
```

A single focused file is 5–10s warm; the whole suite is 30–75s cold. Both exceed
the 30-second command ceiling in this environment, so start them in the background
with the output redirected to a file and poll that file (see
`.clinerules/workflow.md`).
