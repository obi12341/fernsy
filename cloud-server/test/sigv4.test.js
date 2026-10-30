import test from "node:test";
import assert from "node:assert/strict";
import { presign, signedHeaders } from "../sigv4.js";

// AWS's published SigV4 examples (S3 API reference, "Authenticating Requests").
const cred = { accessKeyId: "AKIAIOSFODNN7EXAMPLE", secret: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY", region: "us-east-1" };
const date = new Date("2013-05-24T00:00:00Z");

test("presigned GET matches AWS's example", async () => {
  const url = await presign({ method: "GET", url: "https://examplebucket.s3.amazonaws.com/test.txt", expires: 86400, date, ...cred });
  assert.match(url, /X-Amz-Signature=aeeed9bbccd4d02ee5c0109b86d86835f995330da4c265957d157751f604d404$/);
  assert.match(url, /X-Amz-Credential=AKIAIOSFODNN7EXAMPLE%2F20130524%2Fus-east-1%2Fs3%2Faws4_request/);
});

test("signed GET with Range matches AWS's example", async () => {
  const h = await signedHeaders({ method: "GET", url: "https://examplebucket.s3.amazonaws.com/test.txt", headers: { Range: "bytes=0-9" }, date, ...cred });
  assert.match(h.authorization, /Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41$/);
  assert.match(h.authorization, /SignedHeaders=host;range;x-amz-content-sha256;x-amz-date/);
});

test("signed PUT with body matches AWS's example", async () => {
  const h = await signedHeaders({ method: "PUT", url: "https://examplebucket.s3.amazonaws.com/test$file.text", body: "Welcome to Amazon S3.",
    headers: { "x-amz-storage-class": "REDUCED_REDUNDANCY", date: "Fri, 24 May 2013 00:00:00 GMT" }, date, ...cred });
  assert.match(h.authorization, /Signature=98ad721746da40c64f1a55b78f14c238d841ea1380cd77a1b5971af0ece108bd$/);
});
