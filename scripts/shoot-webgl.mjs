// Loads the WebGL build in a real browser and reports what happened.
//
// This exists because the WebGL player cannot be verified any other way from the
// command line. A build can have correct headers, a valid WebAssembly module and
// zero errors and still show a black screen, and the difference is only visible
// in something that actually rasterises it.
//
// It drives Chromium through Playwright, records every console message and page
// error, waits for Unity to finish creating its canvas, screenshots the frame,
// and then measures that screenshot. Measurement rather than inspection, because
// the alternative is a human looking at a PNG and saying whether it looks like a
// farm.
//
// The canvas is not read with readPixels: Unity leaves preserveDrawingBuffer off,
// so reading the GL backbuffer outside the draw frame yields an empty buffer even
// when the frame is fine. The screenshot comes through the compositor and does not
// have that problem.
//
//   node scripts\shoot-webgl.mjs http://localhost:8123\ out.png [settleMs] [--headed]
import { chromium } from "playwright";
import { decodePng, frameStats, regionMean, regionDelta } from "./png-probe.mjs";

const args = process.argv.slice(2);
const headed = args.includes("--headed");
const positional = args.filter((a) => !a.startsWith("--"));
const base = positional[0] || "http://localhost:8000/";
const shot = positional[1] || "webgl.png";
const settleMs = Number(positional[2] || 45000);

const browser = await chromium.launch({
  headless: !headed,
  args: headed
    ? []
    : [
        // Headless Chromium has no GPU, so WebGL has to come from SwiftShader.
        // Forced only when headless: passing these while headed would pin the
        // browser to software rendering and hide whatever the real GPU does,
        // which is the whole point of running headed.
        "--use-gl=angle",
        "--use-angle=swiftshader",
        "--enable-unsafe-swiftshader",
        "--ignore-gpu-blocklist",
      ],
});

const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });

const console_ = [];
const errors = [];

page.on("console", (m) => console_.push({ type: m.type(), text: m.text() }));
page.on("pageerror", (e) => errors.push(String(e && e.message ? e.message : e)));
page.on("requestfailed", (r) =>
  errors.push(`request failed: ${r.url()} ${r.failure()?.errorText ?? ""}`)
);

const summary = {
  url: base,
  screenshot: shot,
  mode: headed ? "headed (real GPU)" : "headless (SwiftShader)",
  webgl: null,
  rendered: false,
  elapsedMs: 0,
};
const started = Date.now();

try {
  const response = await page.goto(base, { waitUntil: "domcontentloaded", timeout: 60000 });
  summary.status = response ? response.status() : null;

  // What the browser actually got, as opposed to what the build was configured
  // to produce.
  summary.webgl = await page.evaluate(() => {
    const canvas = document.querySelector("canvas");
    if (!canvas) return { canvas: false };
    const gl =
      canvas.getContext("webgl2") ||
      canvas.getContext("webgl") ||
      canvas.getContext("experimental-webgl");
    if (!gl) return { canvas: true, context: false };
    const info = gl.getExtension("WEBGL_debug_renderer_info");
    return {
      canvas: true,
      context: true,
      width: canvas.width,
      height: canvas.height,
      renderer: info ? gl.getParameter(info.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER),
    };
  });

  // Unity reports progress by adding and removing a class on the body, so the
  // canvas existing is not the same as the game being up.
  await page
    .waitForFunction(() => !!document.querySelector("canvas"), null, { timeout: 60000 })
    .catch(() => {});

  // Give the scene time to stream in, light and render. A farm scene is not
  // instant even locally.
  await page.waitForTimeout(settleMs);
  summary.elapsedMs = Date.now() - started;

  const png = await page.screenshot({ path: shot });
  const img = decodePng(png);
  const stats = frameStats(img);

  summary.frame = { width: img.width, height: img.height, ...stats };

  // A frame that is one flat colour, or almost entirely black, is a blank frame
  // whatever the console says.
  summary.rendered = stats.distinctColours > 24 && stats.litFraction > 0.25;

  // The HUD is drawn at known places, so those regions can be checked directly.
  // The top-left stats panel sits at roughly (14,14) in the reference layout and
  // the hotbar is centred along the bottom.
  const stats_panel = regionMean(img, 20, 18, 200, 70);
  const hotbar = regionMean(img, img.width / 2 - 240, img.height - 90, 480, 70);
  const open_sky = regionMean(img, img.width / 2 - 40, 8, 80, 40);

  summary.hud = {
    statsPanel: stats_panel,
    hotbar,
    openSky: open_sky,
    statsPanelVisible: regionDelta(stats_panel, open_sky) > 24,
    hotbarVisible: regionDelta(hotbar, open_sky) > 24,
  };
} catch (error) {
  summary.error = String(error && error.message ? error.message : error);
  await page.screenshot({ path: shot }).catch(() => {});
} finally {
  await browser.close();
}

const noisy = console_.filter((m) => m.type === "error" || m.type === "warning");
const glLines = noisy.map((m) => m.text).filter((t) => /GL_INVALID|WebGL: too many errors/.test(t));
const uniqueGl = [...new Set(glLines)];

console.log(
  JSON.stringify(
    {
      ...summary,
      consoleErrors: noisy.filter((m) => m.type === "error"),
      glWarningCount: glLines.length,
      uniqueGlWarnings: uniqueGl,
      // Unity reports through console.log, so an empty or a broken scene shows
      // up here rather than in the error list.
      unityMessages: console_
        .filter((m) => !/GL_INVALID|too many errors/.test(m.text))
        .map((m) => `[${m.type}] ${m.text}`)
        .slice(0, 60),
      pageErrors: errors,
    },
    null,
    2
  )
);

process.exit(summary.rendered && errors.length === 0 ? 0 : 1);
