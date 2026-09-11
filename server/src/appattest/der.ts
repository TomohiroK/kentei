/**
 * 最小限の DER 走査。
 *
 * Node の X509Certificate は任意の拡張領域を公開しないため、
 * Apple が nonce を埋め込む拡張（1.2.840.113635.100.8.2）だけを自前で取り出す。
 * 汎用の DER パーサは作らない。必要な形だけを厳密に読む。
 */

/** OID 1.2.840.113635.100.8.2 の DER 表現（タグ 0x06 + 長さ + 本体）。 */
const APP_ATTEST_NONCE_OID = Buffer.from([
  0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x63, 0x64, 0x08, 0x02,
]);

const TAG_OCTET_STRING = 0x04;

type Header = { tag: number; contentStart: number; contentLength: number };

/** 範囲外を undefined ではなく null として扱い、以降の判定を一箇所に寄せる。 */
function byteAt(der: Buffer, offset: number): number | null {
  const value = der[offset];
  return value === undefined ? null : value;
}

/** offset 位置の TLV ヘッダを読む。読めなければ null。 */
function readHeader(der: Buffer, offset: number): Header | null {
  const tag = byteAt(der, offset);
  const first = byteAt(der, offset + 1);
  if (tag === null || first === null) return null;
  if (first < 0x80) {
    return { tag, contentStart: offset + 2, contentLength: first };
  }
  const lengthBytes = first & 0x7f;
  // 長さフィールドが4バイトを超える値は、この用途では現れない。
  if (lengthBytes === 0 || lengthBytes > 4) return null;
  let length = 0;
  for (let i = 0; i < lengthBytes; i += 1) {
    const part = byteAt(der, offset + 2 + i);
    if (part === null) return null;
    length = length * 256 + part;
  }
  return { tag, contentStart: offset + 2 + lengthBytes, contentLength: length };
}

/**
 * 証明書に埋め込まれた App Attest の nonce を取り出す。
 *
 * 構造は Extension ::= SEQUENCE { extnID OID, extnValue OCTET STRING }
 * で、extnValue の中身がさらに SEQUENCE { [1] { OCTET STRING nonce } }。
 * ここでは extnValue を特定したうえで、その内側にある32バイトの
 * OCTET STRING を取り出す。
 */
export function extractAppAttestNonce(certificateDer: Buffer): Buffer | null {
  const oidAt = certificateDer.indexOf(APP_ATTEST_NONCE_OID);
  if (oidAt < 0) return null;

  const oidHeader = readHeader(certificateDer, oidAt);
  if (!oidHeader) return null;

  const extnValueAt = oidHeader.contentStart + oidHeader.contentLength;
  const extnValue = readHeader(certificateDer, extnValueAt);
  if (!extnValue || extnValue.tag !== TAG_OCTET_STRING) return null;

  const body = certificateDer.subarray(
    extnValue.contentStart,
    extnValue.contentStart + extnValue.contentLength,
  );
  return findNonceOctetString(body);
}

/** 入れ子を降りて、32バイトの OCTET STRING を探す。 */
function findNonceOctetString(body: Buffer): Buffer | null {
  let offset = 0;
  while (offset < body.length) {
    const header = readHeader(body, offset);
    if (!header) return null;
    const content = body.subarray(
      header.contentStart,
      header.contentStart + header.contentLength,
    );
    if (header.tag === TAG_OCTET_STRING && header.contentLength === 32) {
      return content;
    }
    // 構造型（SEQUENCE や文脈依存タグ）は中を見る。
    if ((header.tag & 0x20) !== 0) {
      const nested = findNonceOctetString(content);
      if (nested) return nested;
    }
    offset = header.contentStart + header.contentLength;
  }
  return null;
}
