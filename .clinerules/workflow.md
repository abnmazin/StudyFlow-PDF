# Workflow — StudyFlow PDF

The routine around an edit, the questions that must be asked, and how the result
is reported. Read with `AGENTS.md`, which holds the four rules this file expands.

## Before touching anything

1. `git status`. This user works with uncommitted edits on purpose; leave them
   alone, and never "tidy" them or commit them.
2. Ask the graph before reading more than two files for an architecture or
   dependency question (`.clinerules/graphify.md`). The graph is for navigation;
   the answer is confirmed in the file before it is reported.
3. Before changing a number or a colour, find **every** reader of it. The
   dashboard's navbar height came from one shared constant read by three widgets,
   while the sidebar's own height was a bare `64` in two other files — that is how
   the two drifted 16px apart in the first place.
4. If the request is ambiguous, ask now, with concrete options. This is the
   cheapest moment in the whole task: one short question against a wrong guess, a
   review cycle, and the tokens to undo it. Words that are ambiguous in this app:
   "the header" (sidebar header / viewer toolbar / dashboard navbar), "the bar",
   "the main colour" (sidebar background / blue accent / icon blue), "the
   sidebar" (which also means the file-and-folder panel the user is looking at).
5. State the plan in one or two plain sentences before editing when the change
   touches more than one file.

## While editing

- The smallest change that fixes the reported behaviour. No refactor the user did
  not ask for, no "while I was here".
- A shared constant or a palette colour instead of a new literal.
- Keep the file's own voice: the comments around the edit explain *why*, with the
  same density as their neighbours.
- Read the file back after editing. A diff preview is not the file.
- Do not reformat, re-indent or reorder code the change does not need.

## After editing: pay only the cost the change deserves

| Kind of change | What to run |
|---|---|
| Colour, size, spacing, font, shape, shadow — anything judged by eye | **Nothing.** Ask the user to look at it. Their eye is the instrument; a test here would spend tokens and prove nothing. |
| Logic, data, state, sync, parsing | The one test file that covers it, then the full suite if the run is cheap |
| A layout contract (a height that must equal another, an overflow, a clamp) | One focused test, or say plainly that it was not verified |
| Everything, always | `flutter analyze --no-pub` — cheap, and it catches typos |

Then delete every scratch file, temp test and log the task created.

## Reporting shape (the only accepted one)

Short, in Arabic, in human words, in this order:

1. What changed, in the user's terms — one or two sentences.
2. Why it was wrong before — the cause, not the symptom.
3. What proves it — the command and its real output, as numbers; or "لم أتحقق"
   when nothing was run.
4. What is left — risks, stale comments, and things deliberately not touched.
5. What is next — options, so the user can answer in one word.

No code blocks, no diffs, no file-and-line lists unless the user must open
something. Details can stay in the conversation.

## Environment notes that cost real time

- PowerShell 5.1: `&&` is not a statement separator. Use `;`.
- A command is killed at 30 seconds. Start `flutter analyze` / `flutter test` as a
  background process with its output redirected to a file and poll that file;
  re-running a killed command wastes more than polling.
- The full test suite takes 30–75s cold and about 8s warm; one file is much
  cheaper while iterating.
- A scratch test is justified when it answers a question no amount of reading can
  (a font's real line height, where a row actually places its children). It is not
  justified to confirm something already visible, and it must be deleted before
  reporting.
- Prefer `grep` for a literal string over reading a whole file.
- Never run `flutter pub get`, `build_runner` or a build unless the user asked:
  each one costs minutes and tokens.
