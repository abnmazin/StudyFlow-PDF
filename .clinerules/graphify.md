# Graphify Knowledge Graph (StudyFlow PDF)

The project has a local, deterministic code knowledge graph at
`graphify-out/graph.json` (built with `graphify extract . --code-only` — no API
key, no vector store, every edge tagged `EXTRACTED`).

## Use the graph before reading files one by one

Before reading more than two files to answer an architecture / dependency
question, query the graph instead:

- MCP tools (preferred, no shell needed) — the server exposes 10:
  `query_graph`, `get_node`, `get_neighbors`, `get_community`, `god_nodes`,
  `graph_stats`, `shortest_path` (read-only, auto-approved),
  plus `list_prs`, `get_pr_impact`, `triage_prs` (PR tooling, not auto-approved)
- CLI fallback:
  - `graphify query "who writes reading progress to Firestore"`
  - `graphify path "app_state.dart::AppProvider" "file_manager_service.dart::FileManagerService" --undirected`
  - `graphify explain "lib/services/university_service.dart::UniversityService"`
- Human-readable audit: `graphify-out/GRAPH_REPORT.md`, visual: `graphify-out/graph.html`

The CLI needs its absolute path on this machine — `graphify` only resolves after
a terminal refresh, so the bare name is not reliable:

```powershell
& "C:\Users\Asus\.local\bin\graphify.exe" query "who writes reading progress to Firestore"
& "C:\Users\Asus\.local\bin\graphify.exe" explain "lib/services/university_service.dart::UniversityService"
& "C:\Users\Asus\.local\bin\graphify.exe" affected "SyncService" --depth 2
& "C:\Users\Asus\.local\bin\graphify.exe" update .
```

Notes earned by using it: `query` is a BFS and goes noisy fast, so pass
`--budget 1500` or narrow the wording instead; `affected` is the one command that
rejects the qualified `<path>::<Symbol>` form and wants the bare name; run the
`update` above after a pull, and `update . --force` after a refactor that deletes
code, since the rebuild otherwise refuses to shrink the node count. For a real
count, parse `graphify-out/graph.json` directly — `query "anything" --budget 1`
prints no count at all, because "anything" matches no node.

## Rules

1. Trust `EXTRACTED` edges as facts from source; treat `INFERRED` / `AMBIGUOUS`
   as leads that must be confirmed in the file.
2. Names repeat across files (e.g. `UniversityService` matches 7 nodes). Always
   qualify with `<path>::<Symbol>` or the full node id when a lookup is ambiguous.
3. Edges can be direction-biased: use `--undirected` for `graphify path` when a
   "no directed path found" result looks wrong.
4. Keep it current: run `graphify update .` after `git pull`; after big edits run
   `graphify extract . --code-only`. A stale graph gives confident wrong answers.

## Known coverage limits (verified on this repo)

- **Dart is parsed with a regex extractor, not tree-sitter.** `imports`,
  `calls`, `references`, `inherits` are extracted, but verify `part` / `part of`
  files (`pdf_viewer_widget_w.dart` + its 6 parts), mixins, and extensions by hand.
- `pubspec.yaml` is **not** a recognized package manifest, so Flutter dependency
  edges are absent — use `pubspec.lock` / `dart pub deps` for that.
- `firestore.rules` is not parsed; Firestore schema and roles live in
  `docs/architecture_map.md`.
- Excluded on purpose (`.graphifyignore`): `lib/models/isar_models.g.dart`
  (generated), platform boilerplate (`android/ ios/ macos/ linux/ windows/ web/`),
  `assets/`, `firestore.rules`, `installer.iss`, binaries.
- Docs (`docs/*.md`) are skipped by `--code-only`; making them graph nodes needs
  a semantic pass: `graphify extract ./docs --backend gemini` (uses API credits).