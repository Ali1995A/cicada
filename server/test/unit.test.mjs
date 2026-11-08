// Pure parts of the server, no Worker needed: node --test server/test/unit.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { ipGroup } from "../src/util.js";
import { flagged, ruleHit, BLOCK } from "../src/review.js";

test("IPv6 addresses count per /64; IPv4 per address", () => {
  assert.equal(ipGroup("203.0.113.7"), "203.0.113.7");
  assert.equal(ipGroup("2001:db8:85a3:0042:1000:8a2e:0370:7334"), "2001:db8:85a3:42::/64");
  assert.equal(ipGroup("2001:DB8:85a3:42::1"), "2001:db8:85a3:42::/64");
  assert.equal(ipGroup("2001:db8:85a3:42:ffff::9"), ipGroup("2001:db8:85a3:42::1"));
  assert.equal(ipGroup("2001:db8::1"), "2001:db8:0:0::/64");
  assert.equal(ipGroup("::1"), "0:0:0:0::/64");
  assert.equal(ipGroup(null), "local");
});

test("keys with a fixed shape are caught by the rules alone", () => {
  for (const k of [
    "-----BEGIN OPENSSH PRIVATE KEY-----", "-----BEGIN PRIVATE KEY-----", "AKIAIOSFODNN7EXAMPLE",
    "ghp_" + "a".repeat(36), "xoxb-1234567890-abcdef", "AIza" + "B".repeat(35), "sk-live-4f9a8c21de77b0a1c",
    "sk-proj-abcdefghijklmnop1234",
  ]) assert.ok(ruleHit(`the key is ${k} ok`), k);
  for (const t of ["we put keys in the vault", "risk-management-framework-review", "task-force-for-q4-planning", "sk-short"]) {
    assert.ok(!ruleHit(t), t);
  }
});

test("talking to the reviewer tightens the bar for that piece only", () => {
  const base = { credential: 0.84, confidential: 0.1, crossborder: 0.1, personal: 0.1, harmful: 0.1, manipulation: 0.1 };
  assert.deepEqual(flagged(base, "text"), []); // 0.84 is under BLOCK
  assert.deepEqual(flagged({ ...base, manipulation: 0.99 }, "text"), ["credential"]);
  // "nothing sensitive today" scores high on manipulation but nothing else: no block.
  assert.deepEqual(flagged({ ...base, credential: 0.01, manipulation: 0.9 }, "text"), []);
  // A rule hit blocks whatever the scores say.
  assert.deepEqual(flagged({ ...base, credential: 0.01 }, "key AKIAIOSFODNN7EXAMPLE"), ["credential"]);
  assert.equal(BLOCK, 0.85);
});
