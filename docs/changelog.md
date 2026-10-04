# Changelog

## [2026-10-03] The streak card became a rotating quote panel, and the three figures shrank to pay for it

### The decision
The dashboard's fourth reading-statistic card — "سلسلة الالتزام" — is gone, and
the row it held is now a full-width quote panel. The three figures above it went
from 130px to 96px ([kStatCardHeight](lib/widgets/dashboard/dashboard_palette.dart)),
and the panel is 190px ([kQuotesPanelHeight]). `statCardWidth`'s doc went from
"four across" to "three across" in the same edit, because the row it divides no
longer holds four cards.

### Why the rotation is a local timer and not a shared clock
Every reader turns the page on their own `kQuoteHold` (12s), so two people looking
at two dashboards are reading two different sentences. A shared clock would make
the panel an announcement, and the admin already has one. What *is* shared is the
list: `dashboard_quotes` is one Firestore collection read by everyone, because a
quotation typed by an admin has to reach every other device, which is the same
split the timetable and the folder announcements made.

### Why the pin is a batch and not a field write
"Only one quote is pinned" is a claim about *every other document*, so it cannot
be one `update`. Two separate writes that half-succeeded would leave two pinned
quotes and a panel with no rule about which one wins, so `QuoteService.setPinned`
reads the collection and applies one `WriteBatch`. This is the expensive-to-reverse
part: `firestore.rules` section 20 deliberately does **not** enforce it, because a
rule cannot ask "is any other document pinned" and a half-answer there would have
been worse than none.

### Added
- **`lib/models/dashboard_quote.dart`** — `DashboardQuote`, with
  `validationMessage` as the single wording for the editor and the service, and a
  `fromFirestore` that tolerates a missing body rather than throwing inside a
  stream.
- **`lib/services/quote_service.dart`** — `watchQuotes()` for the shared list,
  `saveQuote` / `deleteQuote` / `setPinned` for the admin writes, and the
  `_assertAdmin` that turns a mistake into an Arabic sentence. The Firestore rule
  is still the boundary; this one is the courtesy.
- **`lib/widgets/dashboard/dashboard_quotes_card.dart`** — the panel. Rotation,
  the fade, the pinned override, and a right-click that opens the manager for an
  admin and does nothing at all for anyone else.
- **`lib/widgets/dashboard/quote_manager_dialog.dart`** — the admin's page:
  list, pin, edit, delete with a confirmation, and one form for both adding and
  editing.
- **`firestore.rules` section 20** — `dashboard_quotes/{quoteId}`, read by any
  signed-in user, written by an admin, with the 280/80 ceilings mirrored field
  for field from `DashboardQuote`.
- **`AppProvider` quote section** — the same shape as the timetable's, including
  `_beginQuotesSession` on both auth paths and `_disposeQuotes` in `dispose`.
- **`test/dashboard_quotes_test.dart`** — 5 cases: the author stays on the card, a
  quotation at the Firestore ceiling shrinks but never past `kQuoteMinFontSize`,
  the rotation turns the page while a pinned one does not, an empty list says so
  instead of inventing a quotation, and the model's own refusal of an
  unattributed sentence.

### Failed attempts worth not repeating
- **Arming the rotation from `initState`.** The first version called
  `_scheduleNext()` there, and `_scheduleNext` reads the quote list — which comes
  from `context.watch<AppProvider>`. Reading an inherited widget before `initState`
  has finished throws `dependOnInheritedWidgetOfExactType was called before
  initState() completed`. It surfaced by running the app, not in the tests: the
  tests inject `quotes` and never reach the provider, so a `pump` was perfectly
  happy while the real dashboard threw on the launch frame. The arming now happens
  in `build` through `_syncRotation`, deferred by one post-frame callback.
- **`widget.quotes ?? context.watch<AppProvider>().quotes`.** Correct-looking, and
  it reads the provider even when the prop is supplied, because `??` evaluates
  its right side only on null — the injected list short-circuits the *value*, not
  the *read*. Every widget test that injected quotations still threw
  `ProviderNotFoundException`. The two paths are separate `if`s now.
- **Inserting new top-level classes with a line number.** Three times, an insert
  landed *inside* the class above it rather than after it, and the analyzer's
  cascade (`'class' can't be used as an identifier`, then forty lines of noise
  pointing at unrelated symbols) made each fix worse than the last. Reading the
  file before inserting, and appending at EOF after truncating the tail, was the
  reliable path. A structural error is worth reading, not patching.

### Changed
- `kStatCardHeight` 130 → 96, plus new named constants `kQuotesPanelHeight`,
  `kQuoteHold`, `kQuoteFadeDuration`, `kQuoteFontSize`, `kQuoteMinFontSize`,
  `kStatFigureFontSize`, `kStatLabelFontSize`. The stat figure dropped 26 → 22 to
  match the shorter card; `height: 1.0` is still what keeps it inside.
- `DashboardReadingStats` gained a `quotes` prop, and the streak's `_StreakCard`,
  `_StreakCardData`, `_StreakDayChip` and the `_streak()` derivation are deleted.
  `ReadingStatsService.currentStreak` and `lastSevenDays` are left in place — other
  callers exist and deleting a service method is not this change's business.

## [2026-10-03] Added: a separate 104 KB downloader, and the link moved into Firestore

### The decision
The installer is published in its own tiny application, and the application reads
the download link from Firestore after sign-in instead of from GitHub. The link is
in one document so that the hosting can change later without rebuilding anything.

### Why the link is in Firestore at all, given it is public today
Because it is not public *because* of Firestore — it is public because the asset
sits in `abnmazin/StudyFlow-PDF`, which is a public repository. A separate
document does not hide a link that anyone can reach by browsing a releases page.
What it buys is the switch: the document carries `path` beside `url`, and when
`path` is filled in the downloader stops using `url` and mints a 10-minute signed
URL from a private bucket. That day the change is one Firestore edit — no rebuild,
and nobody who was already handed the downloader downloads it again. Writing the
indirection now, while the link is still public, is what makes that edit cheap
later.

### A private GitHub repository would not have done it
Worth recording, because the first attempt at this split assumed it would. A private
repository's releases cannot be read by a client without a token, so the choice is
between a downloader that downloads nothing and a token shipped inside the
executable — and `strings` on that executable is the whole attack. This is the same
premise that commit `a0862f5` was built on and that `559a056` had to walk back.
This is the second time that assumption has cost a rebuild; the check that settles
it is one unauthenticated `GET /repos/<owner>/<repo>`, which prints
`"private": false`.

### Added
- **`E:\Programing\flutter\downloader`** — a standalone C# WinForms project, own
  repository. One portable `.exe`, **106,496 bytes** built 2026-10-02, no installer
  and no runtime to fetch. Sign in → `users/{uid}` checked for `isBanned` /
  `isActive` → `app_config/installer` → download with progress → size and SHA-256 →
  Setup with the same five switches the in-app updater uses → the downloader
  deletes itself.
- **`tools/publish_installer_doc.mjs`** — writes `app_config/installer` through
  `firebase-admin`, finding the service account key in the repo root by itself. It
  refuses a `--sha256` that is not 64 hex characters rather than warning about it,
  and raises `app_config/version.latest_version` only when the version is genuinely
  higher — the `min_version` trap this changelog already records once, where a
  release nobody is offered looks exactly like a working updater.
- **`tools/publish_release.ps1`** now ends with that script, and gained `-SkipDoc`.
  The step warns rather than throws, because the release is already public by then
  and failing the script would throw away a successful publish.

### Unchanged on purpose
- **`lib/` is untouched.** The in-app updater still reads `releases/latest` from
  GitHub. Switching it is a separate decision, and while the asset is public it
  would change nothing about the leak.
- **`firestore.rules` is untouched.** Section 13 already reads `app_config` for any
  authenticated request, which is exactly what a signed-in downloader needs.

### Verified
- `build.ps1` → compiles clean, 106,496 bytes.
- The window opens and stays open (`Start-Process`, 4 s, no exit).
- **The happy path was then run on a real account, and it failed — the first bug
  this entry records.** Sign-in, the `users/{uid}` check and the document read all
  succeeded (the window showed the version, the size and the Arabic notes), then the
  download threw `An error occurred while sending the request.` Measured cause, not a
  guess: a plain .NET Framework process on this machine starts with
  `ServicePointManager.SecurityProtocol` = **`Ssl3, Tls`**, TLS 1.2 switched off, and
  github.com answers that with `SecureChannelFailure` /
  `WebExceptionStatus.SecureChannelFailure`. The reason the symptom points nowhere
  useful is that `identitytoolkit.googleapis.com` and `firestore.googleapis.com` still
  accept TLS 1.0, so every request except the one to GitHub works from the same
  window, in the same second. `tools/publish_release.ps1` already sets the same flag
  for the same reason, one layer down.
- Fixes: `Account.EnableModernTls()` is called from **both** `HttpClient` factories
  (one per class, since a static constructor may not run first in a given path), and
  `DownloaderForm.Describe()` walks to the innermost `InnerException`, because the
  outer message of a network failure names no cause at all — that English sentence is
  what made this cost an afternoon rather than a minute.
- Re-verified after the fix, through the app's own code: 23,481,887 bytes streamed,
  on-disk length equal, SHA-256 `410ba237…15d0` equal to the Firestore document. The
  same probe fails on `SecureChannelFailure` when `EnableModernTls` is not called,
  which is what makes this a fix and not a coincidence.
- The email derivation is right: `accounts:signInWithPassword` with
  `abnmazin@users.studyflow.app` and a deliberately wrong password answers
  `INVALID_LOGIN_CREDENTIALS`, not `EMAIL_NOT_FOUND` — so the address is well formed
  and the account exists. `EMAIL_NOT_FOUND` would have meant the derivation drifted
  from `provision_auth.mjs`.
- Firestore answers `403 PERMISSION_DENIED` on `app_config/installer` without a
  token, which is the rule working.
- `integerValue` is an int64 **string** in the REST representation (Google's
  `Value` reference), which is why `Account.ReadLongField` parses text.

### Still open
- **The download is proven; the install is not.** Bytes, length and hash are
  verified against the real document, and Setup is started with the in-app updater's
  five switches — but nobody has watched the hand-off finish on a machine that does
  not already have the app installed, so `/VERYSILENT /CLOSEAPPLICATIONS` and the
  self-delete are still unproven.
- **The Supabase signing branch is dead and unverified.** No bucket named
  `app-installers` exists and no `select` policy on `storage.objects` is deployed,
  so `path` can never be non-empty today. It is written and shipped disabled so the
  switch is a document edit; it has never executed.
- **The downloader is not in git.** `E:\Programing\flutter\downloader` has a
  `.gitignore` and a README but no repository, and no release on GitHub.
- **`docs/architecture_map.md:233` and `docs/AGENTS.md:87` both call the
  `university-pdfs` bucket private.** It is `public: true`
  (`supabase_setup.sql:11`) and read with `getPublicUrl()`, so every PDF in it is
  downloadable by anyone who knows the path. That is a separate, larger leak than
  the installer, and it was left alone because nobody asked for it to change.

## [2026-10-02] Fixed: a forced launch showed two pages and installed itself

### The decision
A forced update is **one page**, and nothing on it happens until the reader
presses «تحديث الآن». That press then turns the button into the download
progress where it stood, and the run ends in Setup exactly as before.

### Changed
- **Deleted `lib/widgets/update_screen.dart`.** `DeveloperModal` took over its
  stages (`ready` / `loading` / `downloading` / `verifying` / `installing` /
  `failed`), its release-page link, its retry, and its byte formatting. The
  overlay it provided *was* the second page; two updaters would only have
  restored it.
- `DeveloperModal` takes `service`, `release`, `quit` and `latestVersion` in
  place of `onUpdate`. `service == null` is `main.dart`'s developer panel —
  information, and no update UI at all.
- `VersionCheckGate` no longer opens an updater on `forceUpdate`: the blocking
  screen *is* the modal, so `_isForcedUpdate` and `_openUpdater` went with it.
  The optional update puts the same modal over the running app, which keeps a
  reader's open PDF in place — and keeps waiting for its button.
- `autoInstall` deleted. `_startUpdate` is now the only path into a download and
  runs from the press alone. The forced path used to schedule it one frame after
  the screen appeared, so a reader who wanted nothing got 52 MB arriving anyway,
  and a launch that lost its network at that moment had no button left to press.
- The three contact rows (two Telegram, one WhatsApp) are gone from the modal,
  with `_buildElegantRow` and `_launchUrl`. `url_launcher` stays for the
  release-page button.
- **The two updates are one page and two temperaments.** Forced replaces the app
  and shows the modal with no `onClose` at all, so nothing on it can be
  dismissed: no «تخطّي الآن», no `Close`, no backdrop tap — the exit is a new
  version. Optional lays the same modal over the running app *with* `onClose`,
  which is what draws the «تخطّي الآن» button. The old `Close` is hidden when
  `service != null`, because two buttons that both dismiss the same screen is
  how a reader ends up unsure which one is meant.
- **What the release changed is on the page before anything is pressed.**
  `DeveloperModal._buildReleaseDetails` shows the new version, the download
  size, and the GitHub release body rendered as Markdown
  (`flutter_markdown`, which was already in `pubspec.yaml` and imported nowhere).
  The sheet is built field by field rather than with `MarkdownStyleSheet
  .fromTheme`, which asserts on a theme — and this panel renders above
  `MaterialApp`, where there is no app theme to read. The body is the only copy
  of the notes that exists: no release means the panel says nothing rather than
  inventing a changelog.
- `DeveloperModal` adopts `release` in `initState` and in `didUpdateWidget`
  (ready stage only, so a release cannot swap mid-download). The gate hands over
  what the launch check already fetched; before this the field existed and was
  never read, which cost a second GitHub call and hid the notes until after the
  press.
- **«تخطّي الآن» means *not right now*, and nothing is stored.** No version
  number is saved: the offer returns on the next launch, and the gate's
  `_autoOpened` already limits it to once per session. A skip that hid a version
  permanently would need that number written down, and nothing asked for it.

### Removed
- **«مسح البلوك (للمطورين)»** is gone from the forced screen, along with
  `_clearForceUpdateCache` and this file's only use of
  `shared_preferences`. It cleared the cached `force_update_*` keys, which
  unblocked the launch **only while the network was down** — with a network the
  check writes them again on the next launch, so it was never a way out. What it
  *was* is a button labelled «للمطورين» shipped to every reader, sitting on the
  one page a blocked reader cannot leave. The forced screen now has exactly one
  exit: the new version.

### Still open
- `test/update_flow_test.dart` drives every stage through the modal now, so the
  end-to-end path is covered by tests only. The real one still needs an
  installed older build and `min_version` raised in Firestore.
- `v1.2.0` is already published, so a corrected build needs a new tag (`1.2.1+1`).

## [2026-10-02] Fixed: the updater pointed at a repository that does not exist

### The failed attempt worth not repeating
The updater was split across two repositories on the assumption that the source
repository is private, and that a private repository's releases cannot be read
without a token shipped inside the client. Verified against the GitHub API on
2026-10-02: `abnmazin/StudyFlow-PDF` answers `"private": false`. The premise was
never checked, and it left two halves each wrong in a different direction:

- the app (`kUpdateRepoName`) read `abnmazin/StudyFlow-PDF`, which is public but
  held **zero releases and zero tags** — so the updater could never find anything,
- `tools/publish_release.ps1` published to `abnmazin/StudyFlow-PDF-Releases`,
  which does not exist at all (**404**) — so publishing failed at the first call.

The check that would have caught it costs one unauthenticated `GET
/repos/<owner>/<repo>`: ask what the repository is instead of reasoning about what
it probably is.

### Changed
- `tools/publish_release.ps1` publishes to `abnmazin/StudyFlow-PDF` — the
  repository the app already read.
- The "the source repository is private" claim in `lib/services/update_service.dart`
  and `docs/architecture_map.md` now states the verified fact and the date.
- `pubspec.yaml` `1.1.0+3` -> `1.2.0+1`.

### Still open
GitHub is not the gate. `min_version` in Firestore `app_config/version` is: with
no document there the release repository is never consulted, and publishing
`1.2.0` while `min_version` still reads `1.1.0` updates nobody, because an
installed `1.1.0` is not older than `1.1.0`. This is the version trap that made
the flow look broken when it was working.
## [2026-10-02] Added: a real in-app updater (dead button replaced)

### What existed before
The soft-update offer's «تحديث الآن» did nothing — `_kUpdateUrl` was the empty
string — and the forced-update screen sent the reader to Telegram/WhatsApp to ask
for the installer by hand. That is not an update, it is a support ticket, and it
needed a human on the other end every time.

### The failed attempt worth not repeating
The offer was a `showDialog` from `VersionCheckGate`, and that gate wraps
`MaterialApp` (`main.dart`) rather than living inside it. A dialog opened from
above `MaterialApp` finds no `Navigator` **and** no `MaterialLocalizations` above
it, so the old code's guard returned early and nothing appeared. Anything that
must be shown from the gate has to be a widget in a `Stack` over the app — which
also happens to be the right shape here, because a reader with a PDF open should
not lose it to an update offer.

### Added
- `lib/utils/semver.dart` — `compareVersions` / `isVersionLessThan`. `1.10.0` vs
  `1.9.0` is the pair a by-eye comparison gets wrong, and it is the pair that
  decides whether a reader is offered an update. A leading `v`, `+build` and
  `-beta` are all ignored; a non-number reads as zero rather than throwing, because
  one side of the comparison is a tag typed by hand into a release.
- `lib/services/update_service.dart` — GitHub Releases client: newest release,
  `.exe` asset, download with progress to `getTemporaryDirectory()`, digest +
  `Content-Length` verification (hashed as a stream), detached start with
  `/VERYSILENT /CLOSEAPPLICATIONS /NORESTART /SUPPRESSMSGBOXES /LOG`, and a
  `Start-Process -Verb RunAs` retry for `ERROR_ELEVATION_REQUIRED` (740). The
  `http.Client` is injectable, like `AnnouncementComposer.pickImage`. The
  `releases/latest` request carries a **10-second timeout**, because it runs on the
  launch path: on a network that black-holes the connection `package:http` waits
  forever, and a launch screen that never finishes is worse than not being told
  about an update. The timeout falls into the same `catch` as "no internet".
- `test/update_flow_test.dart` — 14 tests over the two silent failures above: the
  version ordering (`1.10.0` vs `1.9.0`, `v`-tags, `+build`, a typo'd tag), which
  asset is picked, a release with nothing attached, and the digest/length
  verification against real temp files with a `MockClient`.
- `lib/widgets/update_screen.dart` — one screen for every stage (checking, ready,
  downloading, verifying, installing, failed), rendered by the gate as an overlay.
  `onClose` null means the forced case, where it cannot be dismissed; `quit` is
  injectable so a test does not call `exit(0)`.
- `tools/publish_release.ps1` — the publishing half: version from `pubspec.yaml`,
  `flutter build windows --release`, `ISCC /DAppVersion=<version>`, SHA-256, then
  the GitHub REST calls. `gh` is not installed on this machine, so the two REST
  calls are the whole of it. ASCII only, because PowerShell 5.1 reads a `.ps1` with
  no BOM as ANSI.

### Changed
- `VersionCheckService.check()` takes `latestVersionOverride`. Firestore
  `app_config/version` keeps `min_version` — the policy — while the release
  repository owns `latest_version` when it is higher, because only it can serve a
  file.
- `installer.iss`: fixed `AppId` GUID (otherwise Inno derives one from `AppName`
  and a rename installs *beside* the old build), `CloseApplications=yes` (what
  makes `/CLOSEAPPLICATIONS` work), `RestartApplications=no` (Setup's restart would
  race `[Run]` into a second instance and the "another instance is running"
  screen), and `AppVersion={#AppVersion}` fed by the publish script.
- `DeveloperModal` takes an `onUpdate` callback; null falls back to the release
  page.
- Deleted `lib/widgets/update_dialog.dart`.
- Forced update now installs itself. `VersionCheckGate` opens `UpdateScreen`
  **synchronously from `build`** on `forceUpdate`, in the same frame as the
  blocking screen, so the app never appears usable. The screen takes
  `autoInstall: true`, which means the download starts without a button press —
  the old forced screen showed a button, and a reader who did not press it sat on
  a release page. A failed attempt is shown once and offers the page; it is not
  retried in a loop, because a down network is not fixed by retrying.
- `UpdateScreen` panel `Column` now forces its body to the panel's width
  (`Flexible` + `SingleChildScrollView` + `SizedBox(width: double.infinity)`),
  with a height cap of `window height - 80`. Cause, measured: `Center` hands the
  panel an unbounded width, and `MainAxisSize.min` makes the `Column`
  shrink-wrap to its widest child, so a plain paragraph was laid out unbounded —
  1232px inside a 418px panel, i.e. `RenderFlex overflowed by 708 pixels`. The
  rows were all `Expanded` or controlled and reported 418, which is why only the
  `installing` and `failed` messages exposed it. Action buttons became a `Wrap`
  for the same reason (the ready stage overflowed by 128px sideways).
- Removed `UpdateService.isNewerThan` (no reader) and its now-unused
  `semver.dart` import.
- `VersionCheckGate` no longer mutates state during `build`. `_remember` records
  the result and `_requestUpdater` defers the `setState` to a post-frame callback.
  Cause: the forced path called `_openUpdater(forced: true)` from inside
  `_buildLaunch`, and the framework threw
  `setState() or markNeedsBuild() called during build` on the launch frame — a
  broken launch for every reader below `min_version`. `debugResultOverride` was
  added to `VersionCheckGate` so that path is testable without Firestore.
- `_withUpdater` wraps its `Stack` in a `Directionality`. `Stack` resolves its own
  default `AlignmentDirectional.topStart`, which needs a direction, and the gate
  sits above the `MaterialApp` — so the soft-update offer threw
  `No Directionality widget found` on the frame it appeared.
- `DeveloperModal`: the forced-update banner row and the badge row now wrap their
  text in `Flexible`. At the modal's `dialogWidth` cap (380) minus its header
  padding there is ~272px, and the banner overflowed by 93px while the badge
  overflowed by 3px. The banner is on the one screen a reader cannot scroll away
  from.
- `DeveloperModal.initState` now catches a failing `PackageInfo.fromPlatform()`.
  The unguarded `then` left the rejection unhandled, so a platform channel that
  did not answer produced an uncaught async error on the launch path.
- Header height consolidated: `sidebar_w.dart` and
  `viewer_components/viewer_toolbar.dart` carried a bare `64` while the dashboard
  navbar read `kDashboardNavBarHeight` — the literal pair `.clinerules/style.md`
  names as the cause of the 16px drift. All three bands now read the one constant;
  the value was already 64 in all three, so this is a correctness fix, not a visual
  change.

### Contract that matters
The app reads `abnmazin/StudyFlow-PDF-Releases`, which must exist, be **public**,
and hold no source. A private repository's releases need a token shipped inside the
client, and a token in a client is a token given away. Until a release with an
`.exe` is published there, the updater offers the release page and nothing else.

## [2026-10-01] Fixed: dashboard panels crashed — `CompositedTransformFollower` under an `OverlayPortal`

### Bug
Two red screens, both from the same structural mistake in the three floating
dashboard panels (notifications, search, task menu), each of which opened its
content through an `OverlayPortal`:

1. **Notifications panel + `Tooltip`.** Hovering the panel's publish button threw
   an assertion. `Tooltip` is itself built on
   `OverlayPortal.overlayChildLayoutBuilder` (`raw_tooltip.dart:866`), so the
   tooltip built a second portal *underneath* the panel's
   `CompositedTransformFollower`. `overlay.dart` forbids exactly that — a follower
   between an `OverlayPortal` and its `Overlay` "may result in an incorrect child
   paint transform" — and asserts in debug (`overlay.dart:2753`, checked at
   `1848-1852`). The search panel and the task menu had the same latent trap; any
   `Tooltip`, `MenuAnchor` or `Autocomplete` added inside them would have done it.

2. **Scrollbar crash on the dashboard.** `routes.dart:1202` gives every route a
   `PrimaryScrollController`, and on Windows `ScrollView.shouldInherit` is false
   (`scroll_view.dart:492`), so the `CustomScrollView` created its own controller
   while the sibling `Scrollbar` watched the route's — two different positions,
   asserted at `scrollbar.dart:1495` ("has no ScrollPosition attached"). Side
   effect: the thumb never painted.

### Fix
- All three panels now use `OverlayPortal.overlayChildLayoutBuilder` and return a
  `Positioned` computed from `OverlayChildLayoutInfo`. The follower's job —
  turning the anchor's position into the panel's — is done by a pure `_geometry`
  helper out of `info.childPaintTransform` / `info.childSize` / `info.overlaySize`.
  `_geometry` runs during layout, so it must not `setState`; every panel opens
  post-layout (tap or focus), so this holds.
- `CompositedTransformTarget`/`Follower`, the `LayerLink`s and the anchor
  `GlobalKey`s (`_link`, `_fieldKey`, `_bellKey`, `_menuButtonKey`, `anchorKey`)
  are gone. The anchor widget is now the portal's own `child`.
- `_TaskMenu` takes the button as `child` and adds a left-edge clamp (margin 12)
  the follower did not have — a behaviour change, flagged below.
- `dashboard_page.dart`: one `ScrollController` shared by the `Scrollbar` and the
  `CustomScrollView`, disposed in `dispose()`.

### Behavior change worth knowing
The task menu right-aligns to its button and grows leftwards; when that would
push it past the window's left edge, it is now pinned to a 12px margin instead of
being clipped. The old follower always right-aligned and could clip.

### Do not repeat
**Never put a `CompositedTransformFollower` between an `OverlayPortal` and its
`Overlay`.** The SDK asserts on it, and the crash surfaces from whatever nested
portal is added later — a `Tooltip` on a button, a `MenuAnchor` in a menu — not
from the follower itself, so it reads as a bug in the innocent widget. Use
`overlayChildLayoutBuilder` + `Positioned`.

### Evidence
`flutter analyze --no-pub`: **0 errors**, 0 findings in the four touched files (175
pre-existing findings elsewhere). `flutter test`: **86 passed** (one guard added to
`test/dashboard_search_test.dart`: the panel stays inside the window and no wider
than its field, via `tester.getRect`). Not verified by test: the notifications and
task panels themselves — `AppProvider` opens Isar/Firebase in its constructor, so
they are not cheaply testable; the user checks those by eye.

## [2026-10-01] Fixed: the schedule card vanished (LayoutBuilder under IntrinsicHeight)

### Bug
`DashboardSectionTitle` measured itself with a `LayoutBuilder` so a long title
could shrink toward 12px. Two of its callers sit inside
`DashboardTasksAndSchedule`, which equalises its cards with `IntrinsicHeight` —
and that asks a card for its height *without laying it out*. A `LayoutBuilder`
refuses that question ("LayoutBuilder does not support returning intrinsic
dimensions"), which killed the layout of the whole sliver: the schedule card never
got a size, the dashboard's third section fell off the page, and the failure
cascaded into `RenderBox was not laid out` and null-operator errors in the gesture
handling.

### Fix
- `DashboardSectionTitle` gained `shrinkToFit` (default `true`). The two headings
  inside that row pass `false` and take a plain ellipsised `Text`, which answers
  intrinsics. Nothing is visible: both headings are one short word, so neither
  ever reached the shrink it gives up.
- `statCardWidth` now takes `perRow` rather than `isWide`, and the reading-stat
  grid is four across on a desktop width and **two-up** below it. It used to stack
  one card per row, contradicting the section's own layout note.
- The seven-day strip is wrapped in `Flexible` + `FittedBox`: seven 20px circles
  are 140px of hard width, and a half-width card can have less than that inside
  its padding.
- `kStatCardGap` is new — the 16px gap was a bare literal in two places that had
  to agree.
- Card height stays 130, and `kStatCardHeight`'s comment no longer claims the
  navbar is "the 80px the design calls for" (it has been 64 since 2026-09-30).

### Do not repeat
**Never put a `LayoutBuilder` under an `IntrinsicHeight` / `IntrinsicWidth`.** The
widget that measures cannot itself be measured. If a shared widget needs a
measurement to lay itself out, give it a flag so a caller in an intrinsic context
can take a path that does not measure.

### Evidence
`flutter analyze --no-pub`: 0 errors, 0 findings in the four touched files (175
pre-existing findings elsewhere). `flutter test`: **86 passed**, up from 85. The
guard was checked both ways — with `shrinkToFit: true` in the row's fixture the new
assertion fails with the app's own message at `test/dashboard_layout_test.dart:198`,
and with `false` it passes.

## [2026-09-27] Graphify Knowledge Graph (Local-First Code Graph)

### Feature
Added a **local, deterministic knowledge graph** of the codebase using Graphify
(`graphifyy` v0.9.69 by Graphify-Labs), so an AI coding agent can query
architecture/dependencies instead of reading files one by one. No vector store,
no embeddings, no API key on the code path — every edge is tagged `EXTRACTED`.

### What Was Built
- `graphify-out/graph.json` — **2309 nodes, 3021 edges, 86 communities** (chain: `defines` 1963, `references` 442, `imports` 439, `inherits` 93, `contains` 41, `configures` 11, `exports` 9, `extends` 8, `imports_from` 6, `mixes_in` 4, `reads_from` 2, `implements` 1)
- `graphify-out/GRAPH_REPORT.md` + `graph.html` (visual) + `graphify-out/cache/` (SHA256 incremental cache)
- Extraction stats: detect 0.9s · AST 9.1s · build 2.5s · cluster 0.7s · export 0.3s — **13.7s total**, 0 input/0 output tokens
- Built from commit `001b0cd0`; 78 code files detected, 14 docs skipped by `--code-only`

### Files Added / Modified
- **NEW `.graphifyignore`** — excludes generated `lib/models/isar_models.g.dart` (521 KB of Isar codegen that would dominate the graph), platform boilerplate (`android/ ios/ macos/ linux/ windows/ web/`), `assets/`, `firestore.rules`, `installer.iss`, root binaries
- **NEW `.clinerules/graphify.md`** — graph-first retrieval protocol for Cline + documented coverage limits
- **NEW MCP server** in `%APPDATA%\Code\User\globalStorage\saoudrizwan.claude-dev\settings\cline_mcp_settings.json` → `graphify` (stdio, `graphify-mcp.exe`) with `query_graph`, `get_node`, `get_neighbors`, `shortest_path` auto-approved (read-only)
- `.cursorrules` — new `# === GRAPHIFY KNOWLEDGE GRAPH ===` section (#6 Graph-First Context Retrieval)
- `.gitignore` — `graphify-out/` ignored (machine-local; force-add `graph.json` only to share)
- `docs/AGENTS.md`, `docs/architecture_map.md` — documented the tool and its limits

### Verification (real output, not assumed assumptions)
- `graphify explain "lib/services/university_service.dart::UniversityService"` → degree 7, referenced by `university_cloud_library_w.dart` L622, `college_collection_widget.dart` L55, `university_folder_view.dart` L44, `university_hub.dart` L38, `university_video_dialog.dart` L29, `university_upload_dialog.dart` L29 — correctly proves `university_hub.dart` is still wired in code despite being documented as deprecated
- `graphify path "app_state.dart::AppProvider" "file_manager_service.dart::FileManagerService" --undirected` → `AppProvider --inherits--> ChangeNotifier <--inherits-- FileManagerService` (2 hops)
- Scope audit: 77 source files in graph; `isar_models.g.dart`, `build/`, `.dart_tool/`, `android/`, `windows/`, `node_modules/` → **0 nodes each**

### Known Limitations / Caveats
- **Dart is parsed by a regex extractor, not tree-sitter** (`graphify/extractors/dart.py`). `part`/`part of` files, mixins and extensions are only partially captured — verify manually
- `pubspec.yaml` is not a recognized package manifest → no Flutter dependency edges (`pubspec.lock` / `dart pub deps` instead)
- `firestore.rules` is not a supported extension → Firestore security rules are absent from the graph
- Node names collide across files (e.g. `UniversityService` = 7 nodes) → qualify lookups as `<path>::<Symbol>`
- `graphify path` is direction-biased; `--undirected` is needed for symmetric relationships like a shared superclass
- Docs stay outside the graph under `--code-only`; adding them needs `graphify extract ./docs --backend gemini` (spends API credits)
- Graph is a snapshot: requires `graphify update .` after `git pull` or it answers from stale code

### Failed Attempts (do not repeat)
- `uv tool install` first failed and left a **malformed tool** (`%APPDATA%\uv\tools\graphifyy\Scripts\python.exe` was 0 bytes) because the harness killed the process when uv's progress output hit stderr. Fix: `Remove-Item %APPDATA%\uv\tools\graphifyy -Recurse -Force`, then re-run the install with its output redirected to a file (via `cmd /c ... > log 2>&1`) instead of piping into PowerShell
- `graphify extract --help` is not supported (prints only `Run 'graphify --help' for full usage.`) — flags must be read from source/README
- Diskless `winget install` refreshed PATH only for new shells; use `%LOCALAPPDATA%\Microsoft\WinGet\Links\uv.exe` and `%USERPROFILE%\.local\bin\graphify.exe` absolute paths until the terminal is restarted

---

## [2026-09-11] MCP Integration: Third AI Provider (Personal Gemini Account)

### Feature
Added **`mcp`** as a third AI provider alongside `gemini` and `groq`. MCP bridges the app to `gemini-app-mcp` (Node.js MCP server) via browser automation, using the user's **personal Google account** — **no API key required**.

### Architecture
- **NEW `lib/services/mcp_client_service.dart`** (singleton `McpClientService.instance`):
  - Spawns `npx -y gemini-app-mcp@latest` as a child process (stdin/stdout line-delimited JSON-RPC 2.0)
  - Implements MCP handshake: `initialize` → `notifications/initialized` → `tools/call`
  - Methods: `start()`, `stop()`, `askQuestion()`, `getHealth()`, `setupAuth()`, `resetConversation()`, `isNodeAvailable`, `isRunning`
  - Process watchdog: auto-restart on next call after crash; 90s request timeout (11min for `setup_auth` due to browser login)
  - Keeps `session_id` in memory for multi-turn conversation continuity
  - Detects Windows `npx.cmd` via `where.exe` (Dart's `Process.start` can't resolve `.cmd`)
  - Throws typed `McpException(code, message)` with codes `MCP_UNAVAILABLE`, `MCP_DIED`, `MCP_TIMEOUT`, `MCP_NOT_AUTHENTICATED`

### Files Modified
- `lib/providers/app_state.dart`:
  - Added `mcpModelsList`, `_mcpModel`, `_mcpSessionId`, getters, `setMcpModel()`, prefs key `studyflowpdf_mcp_model`
  - `currentModel` now ternary for all three providers
  - `setAiProvider()` accepts `'mcp'`; warms up MCP server when selected
  - `triggerAiFallback()` fallback ring now: `gemini → groq → mcp` / `groq → gemini → mcp` / `mcp → gemini → groq`
  - `dispose()` stops the MCP server
- `lib/services/translation_service.dart`: `translate()` dispatcher handles `'mcp'` via new `_translateMcp()`
- `lib/widgets/viewer_components/viewer_right_panel.dart`: `_generateAiReply()` dispatcher routes `'mcp'` → new `_generateMcpReply()` (system prompt + 8-message history concatenated into single question); error bubbles distinguish MCP auth/unavailable errors
- `lib/widgets/global_settings_modal.dart`: added `Gemini (الحساب الشخصي)` dropdown item, MCP model list, and a live status card with Node.js status, auth status, "ربط حساب Google" (calls `setupAuth`) and "قطع الاتصال" (calls `stop`) buttons

### Design Decisions
- MCP server starts **lazily** (on selecting provider or on boot if provider is `'mcp'`), never at app startup unless selected
- Chat history is passed inside the single `question` argument (MCP has no system-role support)
- Translation uses the same shared MCP session instance

### Known Limitations / Failed Attempts
- MCP auth expires after ~24h (server stores session on disk); requires re-linking via Settings
- Browser automation is slower than direct API calls (refresh of the web app per turn)
- `gemini-app-mcp` is unofficial/reverse-engineered — Google can change the web UI and break it (mitigated by `@latest` and fallback ring)
- Uses the user's personal Gemini account quota — ToS risk exists
- Requires Node.js + a Chromium browser on the machine; option auto-disables if `isNodeAvailable` is false

---

## [2026-09-11] Project Cleanup: Unused Files, Dead Code, Config Fixes

### Files Deleted (4 orphaned Dart files)
- `lib/screens/admin/dev_dashboard.dart` — empty deprecated placeholder
- `lib/services/python_equation_service.dart` — replaced by `math_engine.dart`, zero imports
- `lib/services/isolate_worker.dart` — `computePdfMetadataIsolate()` never called
- `lib/widgets/viewer_components/join_master_modal.dart` — superseded by inline join UI in `global_settings_modal.dart`

### Root Clutter Removed (~30 files)
- Python scripts (Telegram bots, Instagram scrapers)
- Academic PDFs, Excel data files, JSON artifacts
- Instagram session artifacts (security risk)
- `Final.tex`, `processes.txt`, `log.txt`, `pdf.png`
- `__pycache__/` directory

### Dead Code Removed from `developer_dashboard_v.dart`
- Removed dead duplicate `GlobalSettingsModal` class (lines 13–1664) shadowed by `global_settings_modal.dart`
- Removed dead `_buildAdminSectionHeader`, `_buildClearButton`, `_confirmWipe` methods
- File: 2708 → 974 lines
- Cleaned unused imports (services.dart, gestures.dart, package_info_plus, login_screen)

### Code Deduplication
- `lib/models/enums.dart`: Merged duplicate `ToolTypeExtension` + `ToolTypeX` into single `ToolTypeX` (getters)
- `lib/widgets/pdf_viewer_widget_gestures.dart`: Migrated `.isDrawingTool()` → `.isDrawing`
- `lib/services/auth_service.dart`: Removed deprecated `loginAndBind()` method (never called)

### Config Fixes
- `.gitignore`: Resolved git merge conflict (HEAD vs `55e3659`); added ignore rules for `__pycache__/`, `/*.pdf`, `/*.py`, `/*.xlsx`, `/*.tex`

### New Documentation
- `docs/performance_and_ram.md` — RAM usage research (migrated from `فف/RAM_NAVIGATION_RESEARCH.md`)
- `docs/gesture_conflict.md` — pdfrx vs overlay gesture conflict documentation
- `docs/deploy_guide.md` — GitHub Pages deployment guide (corrected paths)

### Scratch Directory Deleted
- `فف/` folder removed (old analyses, stale function index, code archives)

---

## [2026-05-17] Toolbar Redesign: ToolSelectorButton + Floating DrawingToolbar

### Changes Made

#### `lib/widgets/viewer_components/viewer_toolbar.dart`
- **Added** `floatingToolbarSelectedTool` (ToolType?) and `onFloatingToolbarToggle` (ValueChanged<ToolType?>?) parameters to `StudyFlowToolbar`
- **Added** static helper `StudyFlowToolbar.iconForTool(ToolType)` mapping each tool to its Lucide icon
- **Replaced** the popup menu (`_showToolSelector` / `_buildToolMenuItem`) with a toggle `ToolSelectorButton`:
  - Icon changes dynamically to reflect the currently selected tool in the floating toolbar
  - Highlights blue when active
  - First click → shows floating toolbar + activates Pen tool
  - Second click → hides floating toolbar + resets to Hand (cursor) tool
- **Removed** unused `_toolSelectorKey` GlobalKey, `_showToolSelector()`, `_buildToolMenuItem()`, `isSelectedShapeTool`, `isSelectedHighlightTool` local variables, and `package:flutter/rendering.dart` import

#### `lib/widgets/pdf_viewer_widget_w.dart`
- **Added** `_floatingToolbarSelectedTool` (ToolType?) state variable — null = hidden, non-null = visible with that tool
- **Passed** new params (`floatingToolbarSelectedTool`, `onFloatingToolbarToggle`) to `StudyFlowToolbar`
- **Replaced** `_shouldShowDrawingToolbar(panelTool)` condition with `_floatingToolbarSelectedTool != null` for `DrawingToolbar` visibility
- **Updated** `DrawingToolbar.onToolChanged` callback to also sync `_floatingToolbarSelectedTool`
- **Removed** legacy `_shouldShowDrawingToolbar()` method

#### `lib/widgets/viewer_components/drawing_toolbar.dart`
- **No changes needed** — already uses `SingleChildScrollView` + `Row(mainAxisSize: MainAxisSize.min)` for horizontal scroll

### Architecture
- Top toolbar now shows: sidebar toggle, close PDF, split mode, page counter, hand tool, select tool, **ToolSelectorButton**, zoom controls, search, bookmarks, settings, sync
- Floating `DrawingToolbar` appears at bottom-center when `ToolSelectorButton` is active
- `TextFormattingToolbar` remains unchanged for text editing
- Dark mode supported throughout

### Behavior
- **ToolSelectorButton click (hidden)**: Shows floating toolbar with Pen tool, activates Pen
- **ToolSelectorButton click (visible)**: Hides floating toolbar, resets to Hand tool
- **Tool chip selected in DrawingToolbar**: Updates ToolSelectorButton icon + activates tool
- **No regression** on keyboard focus fix, PDF navigation, or text editing

---

## [2026-05-13] Resolved: Keyboard focus conflict during text editing — prevented Space/Arrows from PDF viewer while editing

### Root Cause
During text editing, the PDF viewer was consuming Space key (page scroll) and Arrow keys (navigation), interfering with normal text input. Additionally, blocking all keys broke TextField functionality entirely.

### Solution
- **`lib/widgets/draggable_text_widget.dart`**: Already correct — `_focusNode` initializes cleanly; `addListener` triggers `setKeyboardLock` when TextField gains focus
- **`lib/widgets/pdf_viewer_widget_w.dart`**: 
  - `Focus.onKeyEvent` now blocks **Space key only** (checked with `LogicalKeyboardKey.space`) when `isKeyboardLocked` is true, preventing PDF page scrolling
  - `enableKeyboardNavigation` includes `!app.isKeyboardLocked` condition to disable Arrow key navigation when editing

### Result
When editing a text annotation:
- Arrow keys, Backspace, Delete, and all other keys work normally in TextField
- Space key is blocked from scrolling the PDF (still not typed in TextField — separate issue to solve via `pdfrx` config)
- Arrow navigation in PDF is disabled via `enableKeyboardNavigation=false`

---

## [2026-05-12] Corrected: Image notes showing LaTeX math toolbar — switched to proper toolbar (TextFormattingToolbar)

### Root Cause
Two floating toolbars exist when editing notes:
1. **`TextFormattingToolbar`** (`pdf_viewer_widget_w.dart` lines 1818-1983) — appears at bottom of screen when text tool is active. Already had `hasAttachedImage`, `onIncreaseImageSize`, `onDecreaseImageSize`, `onRemoveImage` parameters defined but NOT wired.
2. **`_MathOverlayWidget`** (`draggable_text_widget.dart`) — appears as overlay on the note. Should ONLY handle LaTeX math editing.

The bug was that `_MathOverlayWidget` was incorrectly triggered for notes with images (`widget.isLatex || _attachedMediaUrl != null`), and previously I had wrongly added image controls TO `_MathOverlayWidget` instead of wiring the existing `TextFormattingToolbar`.

### Changes Made

#### `lib/widgets/draggable_text_widget.dart`
- **Removed `hasAttachedImage`, `onIncreaseImageSize`, `onDecreaseImageSize`, `onRemoveImage`** from `_MathOverlayWidget` — image controls DO NOT belong here
- **Fixed `_showOverlay()`** — only shows for `widget.isLatex` (removed `|| _attachedMediaUrl != null`)
- **Fixed `initState()`** — only shows math overlay for LaTeX notes
- **Fixed `didUpdateWidget()`** — entering edit mode only shows overlay for LaTeX; exiting LaTeX always removes overlay (no longer keeps it for images)
- **Kept `isLatex` param** in `_MathOverlayWidget` — correctly controls conditional rendering of LaTeX preview and math buttons

#### `lib/widgets/pdf_viewer_widget_overlay.dart`
- **Fixed `onToggleLatex`** — changed from hardcoded `isLatex: false` to proper toggle `isLatex: !(styles['isLatex'] as bool)` (unchanged from before)

### Behavior After Fix
- **LaTeX notes**: `_MathOverlayWidget` shows with formatting + math buttons + live LaTeX preview
- **Text notes with image**: `TextFormattingToolbar` shows at bottom with font controls + image controls — `_MathOverlayWidget` does NOT appear
- **Plain text notes**: `TextFormattingToolbar` shows at bottom with font controls only
- **Toggle LaTeX**: Properly toggles ON/OFF (was always OFF before)