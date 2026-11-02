// Builds the encrypted Claude feed that Morning Brief reads.
//   MB_FEED_KEY=... node tools/feed.mjs plain.json out/claude-feed.json
// The repo is public, so the feed is AES-GCM encrypted. Only "updated" is readable without the key.
import { readFileSync, writeFileSync } from "node:fs";
import { webcrypto as crypto } from "node:crypto";

const [, , inFile, outFile] = process.argv;
const pass = process.env.MB_FEED_KEY || "";
function fail(msg) { console.error("feed.mjs: " + msg); process.exitCode = 1; }

if (!inFile || !outFile) fail("usage: node tools/feed.mjs plain.json claude-feed.json");
else if (pass.length < 12) fail("set MB_FEED_KEY (12+ characters)");
else {
  const plain = JSON.parse(readFileSync(inFile, "utf8"));
  const errs = [];
  const str = (v, n) => typeof v === "string" && v.trim() && v.length <= n;
  if (!Array.isArray(plain.suggestions) || !plain.suggestions.length) errs.push("suggestions must be a non-empty array");
  (plain.suggestions || []).forEach((s, i) => {
    if (!str(s.title, 120)) errs.push(`suggestions[${i}].title missing or too long`);
    if (s.priority && !["high", "med", "low"].includes(s.priority)) errs.push(`suggestions[${i}].priority must be high|med|low`);
  });
  if (plain.now && !str(plain.now.title, 120)) errs.push("now.title missing or too long");
  if (plain.activity && !Array.isArray(plain.activity)) errs.push("activity must be an array");
  if (errs.length) fail("feed not written:\n  " + errs.join("\n  "));
  else {
    plain.generated_at = plain.generated_at || new Date().toISOString();
    const enc = new TextEncoder();
    const salt = crypto.getRandomValues(new Uint8Array(16)), iv = crypto.getRandomValues(new Uint8Array(12)), iter = 150000;
    const base = await crypto.subtle.importKey("raw", enc.encode(pass), "PBKDF2", false, ["deriveKey"]);
    const key = await crypto.subtle.deriveKey({ name: "PBKDF2", salt, iterations: iter, hash: "SHA-256" }, base, { name: "AES-GCM", length: 256 }, false, ["encrypt"]);
    const data = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv }, key, enc.encode(JSON.stringify(plain))));
    const b64 = u => Buffer.from(u).toString("base64");
    writeFileSync(outFile, JSON.stringify({ v: 1, updated: plain.generated_at, iter, salt: b64(salt), iv: b64(iv), data: b64(data) }) + "\n");
    console.log(`feed.mjs: wrote ${outFile} (${plain.suggestions.length} suggestions, ${(plain.activity || []).length} activity items)`);
  }
}
