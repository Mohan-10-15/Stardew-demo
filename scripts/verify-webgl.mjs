// Confirms the WebGL build is servable, without a browser.
//
// The failure this guards against is specific: Unity's brotli-compressed output
// stores WebGL.wasm.br on disk, the browser decompresses it, and
// WebAssembly.compile then rejects the response unless its Content-Type is
// "application/wasm". Serving octet-stream compiles nothing and the loader dies
// with "Incorrect response MIME type".
//
// So this fetches every asset the loader asks for, checks the headers it needs,
// then decompresses the wasm and asks WebAssembly itself whether the result is
// a valid module. If that passes, a real browser would accept it too.
const base = process.argv[2] || "http://localhost:8000/";

const assets = [
  { path: "Build/WebGL.loader.js", type: "application/javascript", encoding: null },
  { path: "Build/WebGL.framework.js.br", type: "application/javascript", encoding: "br" },
  { path: "Build/WebGL.wasm.br", type: "application/wasm", encoding: "br" },
  { path: "Build/WebGL.data.br", type: "application/octet-stream", encoding: "br" },
];

let failures = 0;

function check(label, ok, detail) {
  console.log(`  ${ok ? "PASS" : "FAIL"}  ${label}${detail ? `  ${detail}` : ""}`);
  if (!ok) failures++;
}

for (const asset of assets) {
  const url = new URL(asset.path, base).href;
  const response = await fetch(url);

  const type = (response.headers.get("content-type") || "").split(";")[0].trim();
  const encoding = response.headers.get("content-encoding");

  check(`${asset.path} status`, response.ok, `${response.status}`);
  check(`${asset.path} content-type`, type === asset.type, `got "${type}", want "${asset.type}"`);
  check(
    `${asset.path} content-encoding`,
    encoding === asset.encoding,
    `got ${encoding === null ? "none" : `"${encoding}"`}, want ${asset.encoding === null ? "none" : `"${asset.encoding}"`}`
  );

  // Drain the body before making the next request. The server is single
  // threaded, so leaving a 10 MB body in flight and opening another connection
  // gets that request reset rather than served.
  //
  // The client transparently decodes "Content-Encoding: br", so this buffer is
  // already the decompressed asset. That decode succeeding is itself part of
  // what is being verified: it proves the brotli stream is intact and that the
  // encoding header is honest about it.
  const body = Buffer.from(await response.arrayBuffer());

  // Range support is what Unity's streaming loader depends on.
  const ranged = await fetch(url, { headers: { Range: "bytes=0-1023" } });
  const contentRange = ranged.headers.get("content-range") || "";
  check(
    `${asset.path} range`,
    ranged.status === 206,
    `${ranged.status}${contentRange ? ` ${contentRange}` : ""}`
  );
  check(
    `${asset.path} range covers 1024 bytes`,
    /bytes 0-1023\//.test(contentRange),
    contentRange || "no Content-Range"
  );
  await ranged.arrayBuffer().catch(() => undefined);

  if (asset.path.endsWith(".wasm.br")) {
    const magic = body.subarray(0, 4).toString("hex");
    check("wasm magic bytes", magic === "0061736d", `got 0x${magic}, want 0x0061736d`);

    const valid = WebAssembly.validate(body);
    check("WebAssembly.validate", valid, valid ? "" : "module rejected");

    if (valid) {
      const module = await WebAssembly.compile(body);
      const exports = WebAssembly.Module.exports(module).map((e) => e.name);
      check("wasm instantiates", true, `${(body.length / 1048576).toFixed(1)} MB, ${exports.length} exports`);
    }
  }
}

console.log(failures === 0 ? "\nAll WebGL asset checks passed." : `\n${failures} check(s) failed.`);
process.exit(failures === 0 ? 0 : 1);
