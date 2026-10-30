// Test stand-ins for the worker's bindings: D1 on node:sqlite, R2 in memory, and a fake R2
// S3 endpoint for the multipart calls and presigned uploads.
import { DatabaseSync } from "node:sqlite";
import fs from "node:fs";

export function makeDB() {
  const db = new DatabaseSync(":memory:");
  db.exec(fs.readFileSync(new URL("../schema.sql", import.meta.url), "utf8"));
  const statement = (sql, args = []) => ({
    bind: (...a) => statement(sql, a),
    first: async () => db.prepare(sql).get(...args) ?? null,
    all: async () => ({ results: db.prepare(sql).all(...args) }),
    run: async () => ({ meta: { changes: Number(db.prepare(sql).run(...args).changes) } }),
  });
  return { prepare: (sql) => statement(sql), raw: db };
}

/// R2 binding plus the S3 endpoint behind presigned URLs, sharing one object map.
export function makeStorage() {
  const objects = new Map();   // key -> Uint8Array
  const uploads = new Map();   // uploadId -> {key, parts: Map(number -> bytes)}
  let next = 1;
  const keyOf = (u) => decodeURIComponent(new URL(u).pathname.split("/").slice(2).join("/"));
  const bucket = {
    objects,
    async head(key) { const o = objects.get(key); return o ? { size: o.length } : null; },
    async delete(keys) { for (const k of [].concat(keys)) objects.delete(k); },
  };
  async function fetchFn(target, init = {}) {
    const u = new URL(target);
    const method = init.method || "GET";
    const key = keyOf(target);
    if (method === "POST" && u.searchParams.has("uploads")) {
      const id = `up${next++}`;
      uploads.set(id, { key, parts: new Map() });
      return new Response(`<InitiateMultipartUploadResult><UploadId>${id}</UploadId></InitiateMultipartUploadResult>`);
    }
    if (method === "PUT" && u.searchParams.has("partNumber")) {
      const up = uploads.get(u.searchParams.get("uploadId"));
      if (!up) return new Response("<Error>NoSuchUpload</Error>", { status: 404 });
      const bytes = new Uint8Array(await new Response(init.body).arrayBuffer());
      up.parts.set(Number(u.searchParams.get("partNumber")), bytes);
      return new Response(null, { headers: { ETag: `"etag${u.searchParams.get("partNumber")}"` } });
    }
    if (method === "POST" && u.searchParams.has("uploadId")) {
      const up = uploads.get(u.searchParams.get("uploadId"));
      if (!up) return new Response("<Error>NoSuchUpload</Error>", { status: 404 });
      const numbers = [...String(init.body).matchAll(/<PartNumber>(\d+)<\/PartNumber>/g)].map((m) => Number(m[1]));
      const chunks = numbers.map((n) => up.parts.get(n));
      if (chunks.some((c) => !c)) return new Response("<Error>InvalidPart</Error>", { status: 400 });
      const all = new Uint8Array(chunks.reduce((s, c) => s + c.length, 0));
      let o = 0; for (const c of chunks) { all.set(c, o); o += c.length; }
      objects.set(up.key, all);
      uploads.delete(u.searchParams.get("uploadId"));
      return new Response("<CompleteMultipartUploadResult/>");
    }
    if (method === "DELETE" && u.searchParams.has("uploadId")) {
      uploads.delete(u.searchParams.get("uploadId"));
      return new Response(null, { status: 204 });
    }
    if (method === "PUT") {
      objects.set(key, new Uint8Array(await new Response(init.body).arrayBuffer()));
      return new Response(null, { headers: { ETag: '"x"' } });
    }
    if (method === "GET") {
      const o = objects.get(key);
      return o ? new Response(o) : new Response("<Error>NoSuchKey</Error>", { status: 404 });
    }
    return new Response("unexpected", { status: 500 });
  }
  return { bucket, uploads, fetch: fetchFn };
}
