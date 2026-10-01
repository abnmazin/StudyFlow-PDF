# Memory files — StudyFlow PDF

Two files remember for the next agent. They only work while they are true, so they
are written on triggers, not after every task. The old rule — "update both at the
end of every interaction" — is why `docs/changelog.md` stopped matching the git
log: the last entry is dated 2026-09-27 while commits continued through 09-30, on
days that also produced real interface work.

## `docs/changelog.md` — write an entry when

- a schema or a contract changed (an Isar model, the Firestore shape, a shared
  identifier),
- a service or a pipeline was added or removed,
- a decision was made that is expensive to reverse,
- an attempt failed in a way worth not repeating. The "Failed Attempts" section is
  the most valuable part of that file — keep it honest and specific.

Do **not** write an entry for a colour, a spacing, a label or a rename. A log that
mentions everything stops being read, and a stale log is worse than no log.

## `docs/architecture_map.md` — write when the structure moved

A new state hub, a new storage layer, a page that replaces another, a service that
changes who owns a responsibility. Keep sections short and dated. Do not re-state a
count as a live fact: node counts, lint counts and test counts drift daily, so say
"as of <date>".

## Rules for both

- No unverifiable claim. A number in these files comes from a command, with the
  date or the commit beside it.
- Do not duplicate what `.clinerules/` already says; link to it instead. The same
  file existing in two places is how the navbar height and the sidebar height
  drifted apart in code, and how the graph's node count drifted apart in docs.
- The three investigation reports in `docs/` — `PRINT_ISSUE_REPORT.md`,
  `TEXT_INPUT_KEYBOARD_CONFLICT_REPORT.md`, `CHAT_SHORTCUT_CONFLICT_REPORT.md` —
  are the deep record for their own problems. Link them; do not paraphrase them
  into the map.
- When a task starts, read `docs/AGENTS.md` if it touches build, boot, services or
  the database. It is not loaded automatically.
