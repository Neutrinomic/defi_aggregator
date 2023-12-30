import sha256 from "https://cdn.jsdelivr.net/npm/sha256@0.2.0/+esm";
function hexToBytes(hex) {
  const bytes = new Uint8Array(Math.ceil(hex.length / 2));
  for (let i = 0; i < bytes.length; i++)
    bytes[i] = parseInt(hex.substr(i * 2, 2), 16);
  return bytes;
}

function concatUint8Arrays(...arrays) {
  let totalLength = 0;
  for (const arr of arrays) {
    totalLength += arr.length;
  }
  const result = new Uint8Array(totalLength);
  let length = 0;
  for (const arr of arrays) {
    result.set(arr, length);
    length += arr.length;
  }
  return result;
}

function stringToBytes(str) {
  const arr = new Uint8Array(str.length);
  for (let i = 0; i < str.length; i++) {
    arr[i] = str.charCodeAt(i);
  }
  return arr;
}

export function computeTreasury(principalId, nonce) {
  const DOMAIN = stringToBytes("token-distribution");
  const DOMAIN_LENGTH = new Uint8Array([0x12]);
  const nonceArray = hexToBytes(nonce.toString(16).padStart(16, "0"));

  const data = concatUint8Arrays(
    DOMAIN_LENGTH,
    DOMAIN,
    principalId,
    nonceArray
  );

  const hash = sha256(data);
  return hash;
}

function bytesToHex(bytes) {
  let hex = "";
  for (let i = 0; i < bytes.length; i++) {
    hex += bytes[i].toString(16).padStart(2, "0");
  }
  return hex;
}