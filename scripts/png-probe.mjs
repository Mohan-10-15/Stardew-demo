// A minimal PNG reader, enough to measure a screenshot.
//
// Playwright's screenshot goes through the compositor, so it is unaffected by
// WebGL's preserveDrawingBuffer: false, which makes reading the canvas itself
// return an empty buffer. Analysing the PNG is therefore the only reliable way
// to tell a rendered frame from a blank one, and it is also the only way to make
// a claim about pixels that does not depend on looking at them.
//
// Handles what Chromium's screenshots actually are: 8-bit, non-interlaced,
// truecolour with or without alpha.
import { inflateSync } from "node:zlib";

function paeth(a, b, c) {
  const p = a + b - c;
  const pa = Math.abs(p - a);
  const pb = Math.abs(p - b);
  const pc = Math.abs(p - c);
  if (pa <= pb && pa <= pc) return a;
  return pb <= pc ? b : c;
}

export function decodePng(buffer) {
  if (buffer.readUInt32BE(0) !== 0x89504e47) throw new Error("not a PNG");

  let offset = 8;
  let width = 0;
  let height = 0;
  let depth = 0;
  let colourType = 0;
  let interlace = 0;
  const idat = [];

  while (offset < buffer.length) {
    const length = buffer.readUInt32BE(offset);
    const type = buffer.toString("ascii", offset + 4, offset + 8);
    const data = buffer.subarray(offset + 8, offset + 8 + length);

    if (type === "IHDR") {
      width = data.readUInt32BE(0);
      height = data.readUInt32BE(4);
      depth = data[8];
      colourType = data[9];
      interlace = data[12];
    } else if (type === "IDAT") {
      idat.push(data);
    } else if (type === "IEND") {
      break;
    }

    offset += 12 + length;
  }

  if (depth !== 8) throw new Error(`unsupported bit depth ${depth}`);
  if (interlace !== 0) throw new Error("interlaced PNG not supported");
  if (colourType !== 2 && colourType !== 6) {
    throw new Error(`unsupported colour type ${colourType}`);
  }

  const channels = colourType === 6 ? 4 : 3;
  const raw = inflateSync(Buffer.concat(idat));
  const stride = width * channels;
  const out = Buffer.alloc(height * stride);

  // Undo the per-scanline filters.
  for (let y = 0; y < height; y++) {
    const filter = raw[y * (stride + 1)];
    const line = raw.subarray(y * (stride + 1) + 1, y * (stride + 1) + 1 + stride);
    const target = out.subarray(y * stride, (y + 1) * stride);
    const prior = y > 0 ? out.subarray((y - 1) * stride, y * stride) : null;

    for (let i = 0; i < stride; i++) {
      const a = i >= channels ? target[i - channels] : 0;
      const b = prior ? prior[i] : 0;
      const c = prior && i >= channels ? prior[i - channels] : 0;
      const x = line[i];

      switch (filter) {
        case 0: target[i] = x; break;
        case 1: target[i] = (x + a) & 0xff; break;
        case 2: target[i] = (x + b) & 0xff; break;
        case 3: target[i] = (x + ((a + b) >> 1)) & 0xff; break;
        case 4: target[i] = (x + paeth(a, b, c)) & 0xff; break;
        default: throw new Error(`bad filter ${filter} on row ${y}`);
      }
    }
  }

  return { width, height, channels, data: out };
}

const at = (img, x, y) => {
  const i = (y * img.width + x) * img.channels;
  return [img.data[i], img.data[i + 1], img.data[i + 2]];
};

/** Mean luminance and the fraction of pixels that are not near-black. */
export function frameStats(img) {
  let sum = 0;
  let lit = 0;
  let count = 0;
  const buckets = new Set();

  for (let y = 0; y < img.height; y += 2) {
    for (let x = 0; x < img.width; x += 2) {
      const [r, g, b] = at(img, x, y);
      const luma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
      sum += luma;
      if (luma > 12) lit++;
      buckets.add((r >> 4) << 8 | (g >> 4) << 4 | (b >> 4));
      count++;
    }
  }

  return {
    meanLuma: sum / count,
    litFraction: lit / count,
    distinctColours: buckets.size,
  };
}

/**
 * Averages a rectangle. The HUD is drawn at known positions, so a region that
 * comes back the same colour as the rest of the frame means that panel is
 * missing, whatever the frame as a whole looks like.
 */
export function regionMean(img, x0, y0, w, h) {
  let r = 0;
  let g = 0;
  let b = 0;
  let n = 0;

  for (let y = y0; y < Math.min(y0 + h, img.height); y++) {
    for (let x = x0; x < Math.min(x0 + w, img.width); x++) {
      const px = at(img, x, y);
      r += px[0];
      g += px[1];
      b += px[2];
      n++;
    }
  }

  return n === 0 ? null : { r: r / n, g: g / n, b: b / n };
}

/** How different two regions are, 0 meaning identical. */
export function regionDelta(a, b) {
  if (!a || !b) return null;
  return Math.abs(a.r - b.r) + Math.abs(a.g - b.g) + Math.abs(a.b - b.b);
}
