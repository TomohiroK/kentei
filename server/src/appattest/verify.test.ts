import assert from "node:assert/strict";
import { createHash, createSign, generateKeyPairSync } from "node:crypto";
import { test } from "node:test";
import { encode as encodeCbor } from "cbor-x";
import { extractAppAttestNonce } from "./der.ts";
import { AppAttestError, verifyAssertion, verifyAttestation } from "./verify.ts";

const TEAM_ID = "MZV3DAL469";
const BUNDLE_ID = "com.tomohirok.kentei";
const APP_ID_HASH = createHash("sha256").update(`${TEAM_ID}.${BUNDLE_ID}`).digest();

function sha256(...parts: Buffer[]): Buffer {
  const hash = createHash("sha256");
  for (const part of parts) hash.update(part);
  return hash.digest();
}

function makeAuthenticatorData(counter: number, rpIdHash: Buffer = APP_ID_HASH): Buffer {
  const head = Buffer.alloc(37);
  rpIdHash.copy(head, 0);
  head[32] = 0x40;
  head.writeUInt32BE(counter, 33);
  return head;
}

function signedAssertion(params: {
  privateKey: ReturnType<typeof generateKeyPairSync>["privateKey"];
  clientData: string;
  counter: number;
  rpIdHash?: Buffer;
}): string {
  const authenticatorData = makeAuthenticatorData(params.counter, params.rpIdHash);
  const clientDataHash = sha256(Buffer.from(params.clientData, "utf8"));
  const nonce = sha256(authenticatorData, clientDataHash);
  const signer = createSign("SHA256");
  signer.update(nonce);
  signer.end();
  const signature = signer.sign(params.privateKey);
  return Buffer.from(encodeCbor({ signature, authenticatorData })).toString("base64");
}

function newKeyPair() {
  return generateKeyPairSync("ec", { namedCurve: "prime256v1" });
}

function errorCode(run: () => unknown): string {
  try {
    run();
  } catch (error) {
    assert.ok(error instanceof AppAttestError, `AppAttestError ではない: ${String(error)}`);
    return error.code;
  }
  assert.fail("エラーになるはずが成功しました");
}

test("正しい assertion は受理され、カウンタを返す", () => {
  const { privateKey, publicKey } = newKeyPair();
  const clientData = '{"taskId":"writing-1"}';
  const result = verifyAssertion({
    assertion: signedAssertion({ privateKey, clientData, counter: 7 }),
    clientData,
    publicKey: publicKey.export({ type: "spki", format: "der" }).toString("base64"),
    teamId: TEAM_ID,
    bundleId: BUNDLE_ID,
    previousCounter: 6,
  });
  assert.equal(result.counter, 7);
});

test("本文を書き換えた要求は署名不一致で拒否される", () => {
  const { privateKey, publicKey } = newKeyPair();
  const assertion = signedAssertion({
    privateKey,
    clientData: '{"taskId":"writing-1"}',
    counter: 1,
  });
  const code = errorCode(() =>
    verifyAssertion({
      assertion,
      clientData: '{"taskId":"writing-2"}',
      publicKey: publicKey.export({ type: "spki", format: "der" }).toString("base64"),
      teamId: TEAM_ID,
      bundleId: BUNDLE_ID,
      previousCounter: 0,
    }),
  );
  assert.equal(code, "signature_invalid");
});

test("別の鍵で署名された assertion は拒否される", () => {
  const signer = newKeyPair();
  const other = newKeyPair();
  const clientData = "{}";
  const code = errorCode(() =>
    verifyAssertion({
      assertion: signedAssertion({ privateKey: signer.privateKey, clientData, counter: 1 }),
      clientData,
      publicKey: other.publicKey.export({ type: "spki", format: "der" }).toString("base64"),
      teamId: TEAM_ID,
      bundleId: BUNDLE_ID,
      previousCounter: 0,
    }),
  );
  assert.equal(code, "signature_invalid");
});

test("カウンタが進んでいない assertion は使い回しとして拒否される", () => {
  const { privateKey, publicKey } = newKeyPair();
  const clientData = "{}";
  const assertion = signedAssertion({ privateKey, clientData, counter: 5 });
  const spki = publicKey.export({ type: "spki", format: "der" }).toString("base64");
  const code = errorCode(() =>
    verifyAssertion({
      assertion,
      clientData,
      publicKey: spki,
      teamId: TEAM_ID,
      bundleId: BUNDLE_ID,
      previousCounter: 5,
    }),
  );
  assert.equal(code, "counter_replay");
});

test("別アプリの assertion は appId 不一致で拒否される", () => {
  const { privateKey, publicKey } = newKeyPair();
  const clientData = "{}";
  const code = errorCode(() =>
    verifyAssertion({
      assertion: signedAssertion({
        privateKey,
        clientData,
        counter: 1,
        rpIdHash: createHash("sha256").update("OTHERTEAM.com.example.other").digest(),
      }),
      clientData,
      publicKey: publicKey.export({ type: "spki", format: "der" }).toString("base64"),
      teamId: TEAM_ID,
      bundleId: BUNDLE_ID,
      previousCounter: 0,
    }),
  );
  assert.equal(code, "app_id_mismatch");
});

test("壊れた assertion は malformed_input として扱われる", () => {
  const { publicKey } = newKeyPair();
  const spki = publicKey.export({ type: "spki", format: "der" }).toString("base64");
  const base = {
    clientData: "{}",
    publicKey: spki,
    teamId: TEAM_ID,
    bundleId: BUNDLE_ID,
    previousCounter: 0,
  };
  assert.equal(errorCode(() => verifyAssertion({ ...base, assertion: "" })), "malformed_input");
  assert.equal(
    errorCode(() => verifyAssertion({ ...base, assertion: "!!!not base64!!!" })),
    "malformed_input",
  );
  assert.equal(
    errorCode(() =>
      verifyAssertion({ ...base, assertion: Buffer.from("plain").toString("base64") }),
    ),
    "malformed_input",
  );
});

test("attestation の入力が壊れていれば検証前に弾かれる", () => {
  const base = {
    challenge: "challenge",
    teamId: TEAM_ID,
    bundleId: BUNDLE_ID,
    allowedEnvironments: ["production"] as const,
  };
  const validKeyId = Buffer.alloc(32, 1).toString("base64");
  assert.equal(
    errorCode(() =>
      verifyAttestation({ ...base, attestation: "", keyId: validKeyId }),
    ),
    "malformed_input",
  );
  assert.equal(
    errorCode(() =>
      verifyAttestation({
        ...base,
        attestation: Buffer.from(encodeCbor({ fmt: "none" })).toString("base64"),
        keyId: validKeyId,
      }),
    ),
    "unexpected_format",
  );
  assert.equal(
    errorCode(() =>
      verifyAttestation({
        ...base,
        attestation: Buffer.from(encodeCbor({ fmt: "apple-appattest" })).toString("base64"),
        keyId: Buffer.alloc(8, 1).toString("base64"),
      }),
    ),
    "malformed_input",
  );
  assert.equal(
    errorCode(() =>
      verifyAttestation({
        ...base,
        attestation: Buffer.from(
          encodeCbor({ fmt: "apple-appattest", attStmt: { x5c: [] } }),
        ).toString("base64"),
        keyId: validKeyId,
      }),
    ),
    "malformed_input",
  );
});

test("nonce 拡張を証明書の DER から取り出せる", () => {
  const nonce = Buffer.alloc(32, 0xab);
  // Extension ::= SEQUENCE { extnID OID, extnValue OCTET STRING }
  const inner = Buffer.concat([Buffer.from([0x04, 0x20]), nonce]);
  const context = Buffer.concat([Buffer.from([0xa1, inner.length]), inner]);
  const sequence = Buffer.concat([Buffer.from([0x30, context.length]), context]);
  const extnValue = Buffer.concat([Buffer.from([0x04, sequence.length]), sequence]);
  const oid = Buffer.from([0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x63, 0x64, 0x08, 0x02]);
  const certificate = Buffer.concat([Buffer.from([0x30, 0x00]), oid, extnValue]);

  assert.deepEqual(extractAppAttestNonce(certificate), nonce);
});

test("nonce 拡張がない証明書では null を返す", () => {
  assert.equal(extractAppAttestNonce(Buffer.alloc(64, 0x11)), null);
});
