# AGENTS.md — StudyFlow PDF

Local code knowledge graph at `graphify-out/graph.json` (roughly 2.5k nodes,
~100 communities — a snapshot, not a contract; it drifts on every code change,
so never quote these numbers as current).
Built with `graphify extract . --code-only`: no API key, no embeddings, every edge `EXTRACTED`.
Full protocol and coverage limits: `.clinerules/graphify.md` — read it before trusting the graph.

## Query the graph before reading files one by one

Before reading more than two files to answer an architecture, dependency, or
"what touches what" question, query the graph. It is one process against a
local JSON and returns a scoped subgraph, which is far cheaper than grepping
or reading files until the answer appears.

Run these from the repo root (PowerShell 5.1 — no `&&` separators):

```powershell
& "C:\Users\Asus\.local\bin\graphify.exe" query "who writes reading progress to Firestore"
& "C:\Users\Asus\.local\bin\graphify.exe" path "app_state.dart::AppProvider" "file_manager_service.dart::FileManagerService" --undirected
& "C:\Users\Asus\.local\bin\graphify.exe" explain "lib/services/university_service.dart::UniversityService"
& "C:\Users\Asus\.local\bin\graphify.exe" affected "SyncService" --depth 2
& "C:\Users\Asus\.local\bin\graphify.exe" god-nodes --top 12
```

The absolute path is deliberate: `graphify` only resolves after a terminal
refresh, so do not rely on the bare name.

Practical notes earned by using it:

- `query` is a BFS and goes noisy fast. Pass `--budget 1500` and narrow the
  wording, or use `explain` / `affected` for a single symbol.
- Qualify symbols as `<path>::<Symbol>` for `explain` and `path`. Bare names
  repeat: `UniversityService` matches 7 distinct nodes. `affected` is the
  exception — it rejects the qualified form and wants the bare name.
- `path` is direction-biased. Add `--undirected` when "no directed path found"
  looks like a wrong answer.
- The graph is for navigation, never for proof. Every finding gets confirmed
  in the file before it is reported or acted on.

## Keep it current

```powershell
& "C:\Users\Asus\.local\bin\graphify.exe" update .
```

Run after `git pull` or a batch of refactors. A stale graph gives confident
wrong answers. Add `--force` after a refactor that deletes code, since the
rebuild otherwise refuses to shrink the node count.

To read the real counts instead of trusting the figure in this file:

```powershell
$j = Get-Content 'graphify-out\graph.json' -Raw | ConvertFrom-Json
"nodes=$($j.nodes.Count) communities=$(($j.nodes | Group-Object community).Count)"
```

Do not use `query "anything" --budget 1` for this — "anything" matches no
node, so the command prints "No matching nodes found" and no count at all.
Communities are only recomputed on extract, so `update` can also print a
"community set changed since labeling" notice — that is informational, not a
failure.

## Coverage limits (verified on this repo, not assumed)

- **Dart is parsed by a regex extractor, not tree-sitter.** `imports`,
  `references`, `inherits`, `defines` are extracted, but partial and mixin
  structure is not understood.
- **Import edges into a `part` owner are unreliable.**
  `pdf_viewer_widget_w.dart:34` imports `university_hub.dart`, yet the graph
  shows `UniversityHub` with no incoming edge. For any symbol living in or
  referenced from `pdf_viewer_widget_w.dart` and its 6 parts, check the file.
- `pubspec.yaml` is not a recognised manifest, so Flutter dependency edges are
  absent. Use `dart pub deps` for those.
- `firestore.rules` is not parsed. Firestore schema, roles, and the current
  deployed rules are documented in `docs/architecture_map.md` instead.
- Excluded on purpose via `.graphifyignore`: `lib/models/isar_models.g.dart`
  (generated), `android/ ios/ macos/ linux/ windows/ web/`, `assets/`,
  `installer.iss`, binaries. Zero nodes for each — that is intended.
- Docs are skipped by `--code-only`. Making them graph nodes needs a semantic
  pass (`graphify extract ./docs --backend gemini`) and spends API credits.
