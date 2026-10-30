// AWS Signature Version 4 for R2's S3 API with WebCrypto only (cloud-server design E):
// presigned URLs the apps use directly, and signed requests the worker sends itself
// (multipart create, complete, abort). Runs in Workers and in Node 24 alike.

const enc = new TextEncoder();

function hex(buffer) {
  return [...new Uint8Array(buffer)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export async function sha256Hex(data) {
  const bytes = typeof data === "string" ? enc.encode(data) : data;
  return hex(await crypto.subtle.digest("SHA-256", bytes));
}

async function hmac(key, data) {
  const k = await crypto.subtle.importKey("raw", typeof key === "string" ? enc.encode(key) : key,
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return crypto.subtle.sign("HMAC", k, enc.encode(data));
}

// RFC 3986 encoding as S3 expects it: everything but unreserved characters.
export function uriEncode(s, keepSlash = false) {
  let out = "";
  for (const ch of String(s)) {
    if (/[A-Za-z0-9\-._~]/.test(ch) || (keepSlash && ch === "/")) out += ch;
    else for (const b of enc.encode(ch)) out += "%" + b.toString(16).toUpperCase().padStart(2, "0");
  }
  return out;
}

function amzDate(date) {
  const iso = date.toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
  return { stamp: iso, day: iso.slice(0, 8) };
}

function canonicalQuery(params) {
  return Object.keys(params).sort()
    .map((k) => `${uriEncode(k)}=${uriEncode(params[k])}`).join("&");
}

async function signingKey(secret, day, region, service) {
  const kDate = await hmac("AWS4" + secret, day);
  const kRegion = await hmac(kDate, region);
  const kService = await hmac(kRegion, service);
  return hmac(kService, "aws4_request");
}

async function signature({ secret, day, region, service, stamp, canonical }) {
  const scope = `${day}/${region}/${service}/aws4_request`;
  const toSign = ["AWS4-HMAC-SHA256", stamp, scope, await sha256Hex(canonical)].join("\n");
  return hex(await hmac(await signingKey(secret, day, region, service), toSign));
}

/// A presigned URL: method on url (with any query parameters already in it), valid for
/// `expires` seconds. Only the host header is signed, the payload is not.
export async function presign({ method, url, accessKeyId, secret, expires, region = "auto", service = "s3", date = new Date() }) {
  const u = new URL(url);
  const { stamp, day } = amzDate(date);
  const params = Object.fromEntries(u.searchParams);
  Object.assign(params, {
    "X-Amz-Algorithm": "AWS4-HMAC-SHA256",
    "X-Amz-Credential": `${accessKeyId}/${day}/${region}/${service}/aws4_request`,
    "X-Amz-Date": stamp,
    "X-Amz-Expires": String(expires),
    "X-Amz-SignedHeaders": "host",
  });
  const path = uriEncode(decodeURIComponent(u.pathname), true);
  const query = canonicalQuery(params);
  const canonical = [method, path, query, `host:${u.host}\n`, "host", "UNSIGNED-PAYLOAD"].join("\n");
  const sig = await signature({ secret, day, region, service, stamp, canonical });
  return `${u.origin}${path}?${query}&X-Amz-Signature=${sig}`;
}

/// Headers for a request the worker sends itself, signed with the payload hash.
export async function signedHeaders({ method, url, body = "", accessKeyId, secret, region = "auto", service = "s3", date = new Date(), headers = {} }) {
  const u = new URL(url);
  const { stamp, day } = amzDate(date);
  const payloadHash = await sha256Hex(typeof body === "string" ? body : new Uint8Array(body));
  const all = { ...Object.fromEntries(Object.entries(headers).map(([k, v]) => [k.toLowerCase(), String(v).trim()])),
    host: u.host, "x-amz-content-sha256": payloadHash, "x-amz-date": stamp };
  const names = Object.keys(all).sort();
  const canonicalHeaders = names.map((n) => `${n}:${all[n]}\n`).join("");
  const signed = names.join(";");
  const path = uriEncode(decodeURIComponent(u.pathname), true);
  const canonical = [method, path, canonicalQuery(Object.fromEntries(u.searchParams)), canonicalHeaders, signed, payloadHash].join("\n");
  const sig = await signature({ secret, day, region, service, stamp, canonical });
  const out = { ...all, authorization: `AWS4-HMAC-SHA256 Credential=${accessKeyId}/${day}/${region}/${service}/aws4_request, SignedHeaders=${signed}, Signature=${sig}` };
  delete out.host;
  return out;
}

/// R2's S3 endpoint for an account, bucket and key.
export function objectURL(accountId, bucket, key) {
  return `https://${accountId}.r2.cloudflarestorage.com/${bucket}/${uriEncode(key, true)}`;
}
