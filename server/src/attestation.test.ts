import assert from "node:assert/strict";
import { createHash, createSign, generateKeyPairSync } from "node:crypto";
import { test } from "node:test";
import { encode as encodeCbor } from "cbor-x";
import { authorizeSubmission, clientDataFor, issueChallenge, readAttestationSettings } from "./attestation.ts";
import { InMemoryAttestationStore } from "./attestStore.ts";

const SETTINGS = {
  teamId: "MZV3DAL469",
  bundleId: "com.tomohirok.kentei",
  allowedEnvironments: ["production"] as const,
};
const APP_ID_HASH = createHash("sha256")
  .update(`${SETTINGS.teamId}.${SETTINGS.bundleId}`)
  .digest();

function sha256(...parts: Buffer[]): Buffer {
  const hash = createHash("sha256");
  for (const part of parts) hash.update(part);
  return hash.digest();
}

function device() {
  const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
  return {
    publicKey: publicKey.export({ type: "spki", format: "der" }).toString("base64"),
    sign(clientData: string, counter: number): string {
      const authenticatorData = Buffer.alloc(37);
      APP_ID_HASH.copy(authenticatorData, 0);
      authenticatorData[32] = 0x40;
      authenticatorData.writeUInt32BE(counter, 33);
      const nonce = sha256(authenticatorData, sha256(Buffer.from(clientData, "utf8")));
      const signer = createSign("SHA256");
      signer.update(nonce);
      signer.end();
      return Buffer.from(
        encodeCbor({ signature: signer.sign(privateKey), authenticatorData }),
      ).toString("base64");
    },
  };
}

async function registeredStore(publicKey: string, keyId = "key-1") {
  const store = new InMemoryAttestationStore();
  await store.saveKey({ keyId, publicKey, counter: 0, registeredAt: "2026-08-22T00:00:00Z" });
  return store;
}

async function freshChallenge(store: InMemoryAttestationStore): Promise<string> {
  const challenge = issueChallenge();
  await store.putChallenge(challenge, 300);
  return challenge;
}

test("正しい端末の提出は受理される", async () => {
  const unit = device();
  const store = await registeredStore(unit.publicKey);
  const challenge = await freshChallenge(store);
  const submissionId = "sub-1";

  const outcome = await authorizeSubmission({
    store,
    settings: SETTINGS,
    keyId: "key-1",
    assertion: unit.sign(clientDataFor(challenge, submissionId), 1),
    challenge,
    submissionId,
  });

  assert.ok("ok" in outcome, JSON.stringify(outcome));
  const stored = await store.findKey("key-1");
  assert.equal(stored?.counter, 1, "カウンタが保存される");
});

test("同じチャレンジは二度使えない", async () => {
  const unit = device();
  const store = await registeredStore(unit.publicKey);
  const challenge = await freshChallenge(store);

  const first = await authorizeSubmission({
    store,
    settings: SETTINGS,
    keyId: "key-1",
    assertion: unit.sign(clientDataFor(challenge, "sub-1"), 1),
    challenge,
    submissionId: "sub-1",
  });
  assert.ok("ok" in first);

  const replay = await authorizeSubmission({
    store,
    settings: SETTINGS,
    keyId: "key-1",
    assertion: unit.sign(clientDataFor(challenge, "sub-1"), 2),
    challenge,
    submissionId: "sub-1",
  });
  assert.ok("failure" in replay);
  assert.equal(replay.failure.code, "attest_challenge_invalid");
});

test("カウンタが進まない再送は拒否される", async () => {
  const unit = device();
  const store = await registeredStore(unit.publicKey);
  await store.advanceCounter("key-1", 9);

  const challenge = await freshChallenge(store);
  const outcome = await authorizeSubmission({
    store,
    settings: SETTINGS,
    keyId: "key-1",
    assertion: unit.sign(clientDataFor(challenge, "sub-1"), 9),
    challenge,
    submissionId: "sub-1",
  });

  assert.ok("failure" in outcome);
  assert.equal(outcome.failure.code, "attest_counter_replay");
});

test("別の提出IDに付け替えた assertion は拒否される", async () => {
  const unit = device();
  const store = await registeredStore(unit.publicKey);
  const challenge = await freshChallenge(store);

  const outcome = await authorizeSubmission({
    store,
    settings: SETTINGS,
    keyId: "key-1",
    assertion: unit.sign(clientDataFor(challenge, "sub-1"), 1),
    challenge,
    submissionId: "sub-2",
  });

  assert.ok("failure" in outcome);
  assert.equal(outcome.failure.code, "attest_signature_invalid");
});

test("未登録の鍵は拒否される", async () => {
  const unit = device();
  const store = await registeredStore(unit.publicKey);
  const challenge = await freshChallenge(store);

  const outcome = await authorizeSubmission({
    store,
    settings: SETTINGS,
    keyId: "key-unknown",
    assertion: unit.sign(clientDataFor(challenge, "sub-1"), 1),
    challenge,
    submissionId: "sub-1",
  });

  assert.ok("failure" in outcome);
  assert.equal(outcome.failure.code, "attest_key_unknown");
});

test("assertion がなければ端末確認が必要と返す", async () => {
  const unit = device();
  const store = await registeredStore(unit.publicKey);

  const outcome = await authorizeSubmission({
    store,
    settings: SETTINGS,
    keyId: undefined,
    assertion: undefined,
    challenge: undefined,
    submissionId: "sub-1",
  });

  assert.ok("failure" in outcome);
  assert.equal(outcome.failure.code, "attest_required");
});

test("未知のチャレンジでは検証に進まない", async () => {
  const unit = device();
  const store = await registeredStore(unit.publicKey);

  const outcome = await authorizeSubmission({
    store,
    settings: SETTINGS,
    keyId: "key-1",
    assertion: unit.sign(clientDataFor("made-up", "sub-1"), 1),
    challenge: "made-up",
    submissionId: "sub-1",
  });

  assert.ok("failure" in outcome);
  assert.equal(outcome.failure.code, "attest_challenge_invalid");
});

test("開発ビルドの受け入れは既定で無効", () => {
  const base = { KENTEI_TEAM_ID: "T", KENTEI_BUNDLE_ID: "B" } as NodeJS.ProcessEnv;
  assert.deepEqual(readAttestationSettings(base)?.allowedEnvironments, ["production"]);
  assert.deepEqual(
    readAttestationSettings({ ...base, KENTEI_ALLOW_DEVELOPMENT_ATTESTATION: "true" })
      ?.allowedEnvironments,
    ["production", "development"],
  );
  assert.equal(readAttestationSettings({ KENTEI_TEAM_ID: "T" }), null);
});

test("チャレンジは毎回異なる", () => {
  const values = new Set(Array.from({ length: 50 }, () => issueChallenge()));
  assert.equal(values.size, 50);
});
