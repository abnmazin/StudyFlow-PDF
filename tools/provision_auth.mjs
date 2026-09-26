/**
 * Creates the Firebase Auth accounts that back the existing `users` documents.
 *
 * Why this is needed: every rule in firestore.rules resolves the caller as
 * users/{request.auth.uid}, and the project had no sign-in call at all, so the
 * app could never reach Firestore. With email/password auth the uid is minted
 * by Firebase, which would be random and would not match any users document.
 * This script therefore creates each account with an explicit uid equal to the
 * document id, and writes the derived address back onto the document.
 *
 * It runs once, locally, against the Admin SDK. No Cloud Functions, no billing.
 *
 * Usage:
 *   node tools/provision_auth.mjs --key ./service-account.json --generate
 *   node tools/provision_auth.mjs --key ./service-account.json --csv accounts.csv
 *   node tools/provision_auth.mjs --key ./service-account.json --dry-run
 *
 * The key stays on this machine. Do not commit it; .gitignore already covers
 * *service-account*.json.
 */
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { randomBytes } from "node:crypto";
import { cert, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore, FieldValue } from "firebase-admin/firestore";

const args = process.argv.slice(2);
const flag = (name) => args.includes(`--${name}`);
const value = (name) => {
  const i = args.indexOf(`--${name}`);
  return i !== -1 && args[i + 1] ? args[i + 1] : null;
};

const keyPath = value("key");
const domain = value("domain") || "users.studyflow.app";
const csvPath = value("csv");
const outPath = value("generate");
const dryRun = flag("dry-run");

if (!keyPath) {
  console.error(
    "Missing --key <path to service account json>.\n" +
      "Firebase Console > Project settings > Service accounts > Generate new private key.",
  );
  process.exit(1);
}
if (!existsSync(keyPath)) {
  console.error(`Service account file not found: ${keyPath}`);
  process.exit(1);
}

initializeApp({
  credential: cert(JSON.parse(readFileSync(keyPath, "utf8"))),
});

const auth = getAuth();
const db = getFirestore();

/** Passwords must satisfy Firebase's minimum: 6 characters. */
function generatePassword() {
  const alphabet =
    "abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789@#%+=_";
  const bytes = randomBytes(14);
  let out = "";
  for (const b of bytes) out += alphabet[b % alphabet.length];
  return out;
}

function readCsv(file) {
  const map = new Map();
  const text = readFileSync(file, "utf8");
  for (const line of text.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const [username, password] = trimmed.split(",").map((s) => (s || "").trim());
    if (username && password) map.set(username.toLowerCase(), password);
  }
  return map;
}

const supplied = csvPath ? readCsv(csvPath) : new Map();
const generated = [];

console.log(`domain        : ${domain}`);
console.log(`passwords     : ${supplied.size ? `from ${csvPath}` : outPath ? "generated" : "none supplied"}`);
console.log(`dry run       : ${dryRun}`);
console.log("");

const users = await db.collection("users").get();
console.log(`Found ${users.size} users document(s).\n`);

let created = 0;
let already = 0;
let skipped = 0;
let failed = 0;

for (const doc of users.docs) {
  const data = doc.data();
  const uid = doc.id;
  const username = String(data.username || "").trim();
  if (!username) {
    console.log(`  SKIP  ${uid}  (no username field)`);
    skipped++;
    continue;
  }

  const email = `${username.toLowerCase()}@${domain}`;
  let password = supplied.get(username.toLowerCase());

  let exists = false;
  try {
    await auth.getUser(uid);
    exists = true;
  } catch (e) {
    if (e.code !== "auth/user-not-found") {
      console.log(`  FAIL  ${username}  lookup: ${e.code || e.message}`);
      failed++;
      continue;
    }
  }

  if (!password) {
    if (!outPath) {
      console.log(`  SKIP  ${username}  (no password supplied, account ${exists ? "exists" : "not created"})`);
      skipped++;
      continue;
    }
    password = generatePassword();
    generated.push({ username, email, password });
  }

  if (dryRun) {
    console.log(`  WOULD ${exists ? "UPDATE" : "CREATE"}  ${username}  uid=${uid}  ${email}`);
    continue;
  }

  try {
    if (exists) {
      await auth.updateUser(uid, { email, password, emailVerified: true });
      console.log(`  UPDATE  ${username}  uid=${uid}  ${email}`);
      already++;
    } else {
      await auth.createUser({
        uid,
        email,
        password,
        emailVerified: true,
        displayName: data.displayName || username,
      });
      console.log(`  CREATE  ${username}  uid=${uid}  ${email}`);
      created++;
    }

    await doc.ref.update({
      email,
      authProvisioned: true,
      authProvisionedAt: FieldValue.serverTimestamp(),
    });
  } catch (e) {
    console.log(`  FAIL  ${username}  ${e.code || e.message}`);
    failed++;
  }
}

if (outPath && generated.length && !dryRun) {
  const csv = ["username,password", ...generated.map((g) => `${g.username},${g.password}`)].join("\n");
  writeFileSync(outPath, `${csv}\n`, "utf8");
  console.log(`\nWrote ${generated.length} generated password(s) to ${outPath}`);
  console.log("Hand these out privately, then ask each user to change them.");
}

console.log(
  `\nDone. created=${created} updated=${already} skipped=${skipped} failed=${failed}`,
);
if (failed > 0) process.exit(2);
