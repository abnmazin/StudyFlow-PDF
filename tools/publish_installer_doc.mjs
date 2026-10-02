// Writes the one document the standalone downloader app reads: the installer
// link, its hash, and its size.
//
//   node publish_installer_doc.mjs --version 1.2.0 --url <asset url> \
//        --sha256 <64 hex> --size <bytes> [--page-url <url>] [--notes-file <f>]
//        [--path <supabase storage path>] [--key <sa.json>]
//
// `tools/publish_release.ps1` calls this after a successful GitHub upload, so
// one command publishes the release and the document that points at it. Run it
// alone when a release already exists and only the document needs writing.
//
// Why a document and not the app reading GitHub: the downloader must not know
// where releases live. It reads a link, and that is the whole contract — which
// is what makes it possible to move the file behind a private bucket later by
// filling `path` and emptying `url`, with no new build of the downloader and no
// re-sharing of it to anybody.
//
// The document is `app_config/installer`, and the existing rule already covers
// it: `firestore.rules` reads that collection with `isAuthenticated()` and
// writes it as admin, so an account with an id token can read this and nothing
// else has to change.
import { cert, initializeApp } from "firebase-admin/app";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");

const args = process.argv.slice(2);
const val = (flag, fallback) => {
  const i = args.indexOf(flag);
  return i === -1 ? fallback : args[i + 1];
};

// The service account key is named by the Firebase CLI, with a hash in it, so
// the publisher cannot spell it. `publish_release.ps1` does not pass --key
// either, and requiring a filename on the command line would make the one
// command a two-command. The key is gitignored; see `.gitignore`.
function findKey() {
  const explicit = val("--key");
  if (explicit) {
    if (!existsSync(explicit)) throw new Error(`No key file at '${explicit}'`);
    return explicit;
  }
  const found = readdirSync(root).find(
    (name) => name.startsWith("pdfreader-") && name.includes("firebase-adminsdk"),
  );
  if (!found) {
    throw new Error(
      `No service account key in ${root}. Expected a pdfreader-*firebase-adminsdk-*.json, or pass --key.`,
    );
  }
  return join(root, found);
}

const version = (val("--version") || "").trim().replace(/^[vV]/, "");
const url = (val("--url") || "").trim();
const sha256 = (val("--sha256") || "").trim().toLowerCase();
const size = Number(val("--size"));
const pageUrl = (val("--page-url") || "").trim();
const storagePath = (val("--path") || "").trim();
const notesFile = val("--notes-file");

const missing = [];
if (!version) missing.push("--version");
if (!url && !storagePath) missing.push("--url (or --path)");
if (!sha256) missing.push("--sha256");
if (!Number.isSafeInteger(size) || size <= 0) missing.push("--size");
if (missing.length) {
  console.error(`Missing or invalid: ${missing.join(", ")}`);
  console.error(
    "usage: node publish_installer_doc.mjs --version 1.2.0 --url <asset url> " +
      "--sha256 <64 hex> --size <bytes>",
  );
  process.exit(1);
}
if (!/^[0-9a-f]{64}$/.test(sha256)) {
  // Refused rather than warned about: a wrong hash here is a document that
  // refuses to install, and the downloader cannot tell a typo from an attack.
  throw new Error(`--sha256 is not 64 hex characters: '${sha256}'`);
}

// `lib/utils/semver.dart`, which exists because the launch gate and the updater
// must not hold two copies of "which is newer". This is the third reader of the
// same question, in a different language — the one case where a copy is
// unavoidable, and it is why the comparison is written out in full.
function segments(text) {
  let value = String(text ?? "").trim();
  if (value.startsWith("v") || value.startsWith("V")) value = value.slice(1);
  for (const cut of ["+", "-"]) {
    const at = value.indexOf(cut);
    if (at >= 0) value = value.slice(0, at);
  }
  if (!value) return [0];
  return value
    .split(".")
    .slice(0, 4)
    .map((part) => {
      const n = parseInt(part.trim(), 10);
      return Number.isFinite(n) ? n : 0;
    });
}

function compareVersions(a, b) {
  const left = segments(a);
  const right = segments(b);
  for (let i = 0; i < Math.max(left.length, right.length); i++) {
    const l = i < left.length ? left[i] : 0;
    const r = i < right.length ? right[i] : 0;
    if (l !== r) return l < r ? -1 : 1;
  }
  return 0;
}

initializeApp({ credential: cert(findKey()) });
const db = getFirestore();

const installer = {
  version,
  tag: `v${version}`,
  url,
  // Empty while the asset is public. Filled in when the file moves behind a
  // private bucket; the downloader prefers it over `url`, which is the whole
  // switch that turns a public link into a signed one.
  path: storagePath,
  pageUrl,
  sha256,
  size,
  notes: notesFile ? readFileSync(notesFile, "utf8").trim() : "",
  updatedAt: FieldValue.serverTimestamp(),
};

await db.collection("app_config").doc("installer").set(installer, { merge: true });

// `latest_version` is what an installed build compares itself against, and it
// has to move in the same breath as the link or the version trap opens: a
// release published at 1.3.0 that no document names updates nobody, which is
// recorded in docs/changelog.md under 2026-10-02.
//
// It is raised only when it is genuinely higher. A script that overwrites it
// unconditionally would undo a deliberate `latest_version` set by hand, and one
// that lowers it would offer every installed reader a downgrade.
const versionRef = db.collection("app_config").doc("version");
const current = await versionRef.get();
const currentLatest = String(current.get("latest_version") ?? "").trim();
const patch = {};
if (!currentLatest || compareVersions(version, currentLatest) > 0) {
  patch.latest_version = version;
  patch.latest_version_at = FieldValue.serverTimestamp();
}

if (Object.keys(patch).length) {
  await versionRef.set(patch, { merge: true });
}

const written = await db.collection("app_config").doc("installer").get();
const shown = written.data() ?? {};

console.log("=== app_config/installer ===");
console.log(`  version : ${shown.version}`);
console.log(`  url     : ${shown.url || "(empty)"}`);
console.log(`  path    : ${shown.path || "(empty)"}`);
console.log(`  sha256  : ${shown.sha256}`);
console.log(`  size    : ${shown.size} bytes`);
console.log(`  pageUrl : ${shown.pageUrl || "(empty)"}`);
console.log(
  `  notes   : ${shown.notes ? `${String(shown.notes).length} characters` : "(empty)"}`,
);
console.log("=== app_config/version ===");
if (patch.latest_version) {
  console.log(`  latest_version: ${currentLatest || "(unset)"} -> ${version}`);
} else {
  console.log(`  latest_version: ${currentLatest} (kept, ${version} is not higher)`);
}
if (!storagePath) {
  console.log(
    "\nThe link is public: anyone can open the release page without an account.",
  );
  console.log(
    "To close that, upload the file to a private bucket and re-run with --path.",
  );
}