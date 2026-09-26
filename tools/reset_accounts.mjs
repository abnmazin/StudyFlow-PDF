// Resets account and session state so the project can start from one admin.
//
// Deliberately does NOT touch content: the university tree, pdf mutations and
// app_config survive, because deleting those would throw away the library the
// accounts are meant to own.
//
//   node reset_accounts.mjs --key <sa.json>            # dry run, prints counts
//   node reset_accounts.mjs --key <sa.json> --confirm  # actually deletes
import { cert, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";

const args = process.argv.slice(2);
const keyPath = args[args.indexOf("--key") + 1];
const confirm = args.includes("--confirm");

if (!args.includes("--key") || !keyPath) {
  console.error("usage: node reset_accounts.mjs --key <service-account.json> [--confirm]");
  process.exit(1);
}

initializeApp({ credential: cert(keyPath) });
const db = getFirestore();
const auth = getAuth();

// Flat documents, and documents whose subcollections must go with them.
const FLAT = [
  "users",
  "library_file_sessions",
  "blacklisted_devices",
  "security_events",
  "announcements",
  "university_file_progress",
];
const RECURSIVE = ["sync_sessions", "master_sessions"];

// Kept on purpose, listed so the output proves it.
const KEEP = [
  "universities",
  "university_folders",
  "university_files",
  "university_videos",
  "pdfs",
  "app_config",
];

const topLevel = async (name) => {
  const snap = await db.collection(name).get();
  return snap.docs;
};

async function survey() {
  const plan = { flat: {}, recursive: {} };
  for (const name of FLAT) {
    const docs = await topLevel(name);
    plan.flat[name] = docs.map((d) => d.ref);
  }
  for (const name of RECURSIVE) {
    const docs = await topLevel(name);
    const refs = [];
    for (const d of docs) {
      const subs = await d.ref.listCollections();
      for (const sub of subs) {
        const subDocs = await sub.get();
        for (const sd of subDocs.docs) {
          refs.push(sd.ref);
          const deep = await sd.ref.listCollections();
          for (const s2 of deep) {
            const d2 = await s2.get();
            for (const x of d2.docs) refs.push(x.ref);
          }
        }
      }
    }
    plan.recursive[name] = { parents: docs.length, leaves: refs.length };
  }
  return plan;
}

const authUsers = [];
let page = await auth.listUsers(1000);
authUsers.push(...page.users);
while (page.pageToken) {
  page = await auth.listUsers(1000, page.pageToken);
  authUsers.push(...page.users);
}

const plan = await survey();

console.log("=== WILL DELETE (Firestore) ===");
for (const [name, refs] of Object.entries(plan.flat)) {
  console.log(`  ${name.padEnd(24)} ${refs.length} doc(s)`);
}
for (const [name, info] of Object.entries(plan.recursive)) {
  console.log(
    `  ${name.padEnd(24)} ${info.parents} session(s) + ${info.leaves} subcollection doc(s)`,
  );
}
console.log(`  ${"firebase auth accounts".padEnd(24)} ${authUsers.length} user(s)`);

console.log("\n=== WILL KEEP ===");
for (const name of KEEP) {
  const docs = await topLevel(name);
  console.log(`  ${name.padEnd(24)} ${docs.length} doc(s)`);
}

if (!confirm) {
  console.log("\nDry run. Re-run with --confirm to delete the above.");
  process.exit(0);
}

console.log("\n=== DELETING ===");
for (const [name, refs] of Object.entries(plan.flat)) {
  let batch = db.batch();
  let n = 0;
  for (const ref of refs) {
    batch.delete(ref);
    n += 1;
    if (n === 400) {
      await batch.commit();
      batch = db.batch();
    }
  }
  if (n % 400 !== 0) await batch.commit();
  console.log(`  deleted ${n} from ${name}`);
}
for (const name of RECURSIVE) {
  let n = 0;
  for (const ref of plan.recursive[name] ? [] : []) void ref;
  for (const doc of await topLevel(name)) {
    await db.recursiveDelete(doc.ref);
    n += 1;
  }
  console.log(`  deleted ${n} session tree(s) from ${name}`);
}
let a = 0;
for (const u of authUsers) {
  await auth.deleteUser(u.uid);
  a += 1;
}
console.log(`  deleted ${a} firebase auth account(s)`);

console.log("\nDone. Project has no accounts and no sessions.");
