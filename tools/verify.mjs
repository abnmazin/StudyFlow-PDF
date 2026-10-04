import { cert, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { readFileSync, readdirSync } from "node:fs";
const key = readdirSync("..").find(n => n.startsWith("pdfreader-") && n.includes("firebase-adminsdk"));
initializeApp({ credential: cert(JSON.parse(readFileSync("../" + key, "utf8"))) });
const snap = await getFirestore().collection("dashboard_quotes").get();
console.log("COUNT:", snap.size);
for (const d of snap.docs) {
  const x = d.data();
  console.log(`- [${x.text.length}ch/${x.author.length}ch pinned=${x.pinned}] ${x.text} | ${x.author}`);
}
