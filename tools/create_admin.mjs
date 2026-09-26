// Creates one account: the Firebase Auth user and the users/{uid} profile
// together, because the rules resolve the caller as users/{request.auth.uid}
// and a profile alone can never sign in.
//
//   node create_admin.mjs --key <sa.json> --username abnmazin [--role admin]
//                         [--university <id>] [--password <pw>]
import { cert, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { randomBytes, createHash } from "node:crypto";

const args = process.argv.slice(2);
const val = (flag, fallback) => {
  const i = args.indexOf(flag);
  return i === -1 ? fallback : args[i + 1];
};

const keyPath = args[args.indexOf("--key") + 1];
if (!args.includes("--key") || !keyPath) {
  console.error("usage: node create_admin.mjs --key <sa.json> --username <name>");
  process.exit(1);
}

const username = val("--username");
if (!username) {
  console.error("--username is required");
  process.exit(1);
}
const role = val("--role", "admin");
const displayName = val("--display-name", username);
const universityId = val("--university");
const domain = val("--domain", "users.studyflow.app");

// 18 chars from an unambiguous alphabet, so it survives being read aloud or
// retyped from a screenshot.
const ALPHABET = "abcdefghijkmnopqrstuvwxyz23456789";
const password =
  val("--password") ??
  Array.from(randomBytes(18))
    .map((b) => ALPHABET[b % ALPHABET.length])
    .join("");

// Same derivation as AuthService.emailForUsername and provision_auth.mjs.
function emailLocalPart(name) {
  const lower = String(name || "").trim().toLowerCase();
  let ascii = lower.replace(/[^a-z0-9._-]/g, "");
  ascii = ascii.replace(/^[._-]+/, "").replace(/[._-]+$/, "");
  ascii = ascii.replace(/\.{2,}/g, ".");
  if (ascii.length < 2) {
    return `u${createHash("sha256").update(lower, "utf8").digest("hex").slice(0, 12)}`;
  }
  return ascii;
}

initializeApp({ credential: cert(keyPath) });
const auth = getAuth();
const db = getFirestore();

const email = `${emailLocalPart(username)}@${domain}`;

// The Auth account is created first so its uid can be used as the profile id.
const created = await auth.createUser({
  email,
  password,
  displayName,
  disabled: false,
});

const profile = {
  username,
  displayName,
  role,
  authProvisioned: true,
  createdAt: FieldValue.serverTimestamp(),
};
if (universityId) profile.universityId = universityId;

await db.collection("users").doc(created.uid).set(profile);

console.log("=== ACCOUNT CREATED ===");
console.log(`  username    : ${username}`);
console.log(`  email       : ${email}`);
console.log(`  uid         : ${created.uid}`);
console.log(`  role        : ${role}`);
console.log(`  universityId: ${universityId ?? "(none)"}`);
console.log(`  password    : ${password}`);
console.log("\nProfile and Auth account share the same uid, so login can resolve it.");
console.log("Change the password, then delete this file if you saved it.");
