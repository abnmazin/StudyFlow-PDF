// Seeds the dashboard's quote panel with a starter set.
//
//   node tools/seed_dashboard_quotes.mjs [--key <sa.json>] [--dry-run]
//
// Why this exists rather than a button in the admin dialog: the panel's own
// empty state says "لا توجد اقتباسات بعد", which is true and useless on a fresh
// install — an admin who has never written a quotation cannot tell whether the
// feature is broken or simply empty. A starter set makes the panel real on first
// run, and every row here can be edited or deleted from the manager exactly
// like a typed one.
//
// Writes through `firebase-admin`, so it does not depend on the app being signed
// in, and it finds the service account key in the repo root by itself for the
// reason `publish_installer_doc.mjs` does: the key's name carries a hash, so
// nobody can spell it on a command line.
//
// `--dry-run` prints what it would write and writes nothing, which is the mode
// to use first: these are attributed quotations, and a misattributed sentence on
// every student's dashboard is the one failure in this feature that no code
// review would catch.
//
// The shape matches `firestore.rules` section 20 field for field — `text` and
// `author` non-empty, 280 and 80 characters — because the rule would refuse
// anything else and the failure would look like a permissions bug.
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
const dryRun = args.includes("--dry-run");

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

// The starter set.
//
// John C. Maxwell on leadership, in English, because the panel is the one place
// on the dashboard that is not Arabic, and a reader who sees only Arabic will
// assume the field is broken rather than bilingual. Imam Ali's sayings in
// Arabic, which is the app's own language.
const QUOTES = [
  {
    text: "Leadership is influence, nothing more, nothing less.",
    author: "John C. Maxwell",
  },
  {
    text: "The task of the leader is to get the task done. The task of the team is to make the leader's job easy.",
    author: "John C. Maxwell",
  },
  {
    text: "People buy into the leader before they buy into the vision or the idea.",
    author: "John C. Maxwell",
  },
  {
    text: "The mediocre teacher tells. The good teacher explains. The excellent teacher inspires.",
    author: "John C. Maxwell",
  },
  {
    text: "Quality is not an act, it is a habit.",
    author: "Will Durant",
  },
  {
    text: "رأس الحكمة مخافة الله.",
    author: "الإمام علي بن أبي طالب عليه السلام",
  },
  {
    text: "قيمة كل امرئ ما يُحسنه.",
    author: "الإمام علي بن أبي طالب عليه السلام",
  },
  {
    text: "الناس نيام، فإذا ماتوا انتبهوا.",
    author: "الإمام علي بن أبي طالب عليه السلام",
  },
  {
    text: "احرث لسانك، فهو أخصب ما تحصد.",
    author: "الإمام علي بن أبي طالب عليه السلام",
  },
  {
    text: "العلم في الصغر كالنقش على الحجر.",
    author: "من الحكم العربي",
  },
  {
    text: "من جدّ وجد، ومن زرع حصد.",
    author: "من الحكم العربي",
  },
];

// Refused before the network is touched, with the same bounds the rules answer
// with. A quotation with no author is the one thing this feature must never
// write: an unattributed sentence on every student's dashboard reads as the
// app's own claim.
const MAX_TEXT = 280;
const MAX_AUTHOR = 80;
for (const q of QUOTES) {
  if (!q.text.trim()) throw new Error("A quotation has no text.");
  if (!q.author.trim()) throw new Error(`'${q.text}' has no author.`);
  if (q.text.length > MAX_TEXT) {
    throw new Error(`'${q.text}' exceeds ${MAX_TEXT} characters.`);
  }
  if (q.author.length > MAX_AUTHOR) {
    throw new Error(`Author '${q.author}' exceeds ${MAX_AUTHOR} characters.`);
  }
}
// Top-level `await` is legal in an ES module, but the writes here are wrapped
// in `main()` anyway: the failure mode it removes is the one that costs an
// afternoon. A rejected `commit()` from a top-level await prints a stack with no
// mention of which quotation failed, and `process.exit(1)` on the catch is what
// turns that into one Arabic-free line the caller can read in CI.
async function main() {
  const key = JSON.parse(readFileSync(findKey(), "utf8"));
  initializeApp({ credential: cert(key) });
  const db = getFirestore();

  console.log(`${QUOTES.length} quotations prepared${dryRun ? " (dry run)" : ""}.`);
  for (const q of QUOTES) {
    console.log(`  — ${q.text}  [${q.author}]`);
  }

  if (dryRun) {
    console.log("\nDry run: nothing was written.");
    return;
  }

  // A batch rather than a loop of writes: the admin opens the manager the moment
  // this finishes, and eleven separate round trips would leave the list visibly
  // filling in. Firestore applies a batch atomically, so the panel goes from
  // "لا توجد اقتباسات بعد" to a full rotation in one step.
  const batch = db.batch();
  const collection = db.collection("dashboard_quotes");
  for (const q of QUOTES) {
    // `batch.create`, not `batch.add`. The two spell the same intent in the
    // client SDKs and only one exists here: `firebase-admin`'s WriteBatch
    // exposes create / set / update / delete and commit, and `add` is not one of
    // them. `create` is also the better fit — it fails if the generated id is
    // somehow taken, where `set` would overwrite whatever was there, and this
    // script must never replace an admin's own quotation.
    batch.create(collection.doc(), {
      text: q.text,
      author: q.author,
      // Nothing is pinned here on purpose: a pinned quotation stops the rotation
      // for every user, and that is an admin's decision to make in the manager,
      // not a default this script should impose on them.
      pinned: false,
      updatedBy: "seed_dashboard_quotes.mjs",
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();

  console.log(`\nWrote ${QUOTES.length} quotations to dashboard_quotes.`);
  console.log(
    "The panel is admin-editable: right-click it on the dashboard to open the manager.",
  );
}

main().catch((error) => {
  console.error(`\nSeeding failed: ${error.message}`);
  console.error(
    "If this is a permission error, check that rules section 20 is deployed.",
  );
  process.exit(1);
});

