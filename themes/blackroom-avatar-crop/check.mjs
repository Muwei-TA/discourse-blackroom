import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const source = await readFile(
  new URL("./javascripts/discourse/lib/avatar-crop.js", import.meta.url),
  "utf8"
);
const { cropBounds } = await import(
  `data:text/javascript,${encodeURIComponent(source.replace(/^import .*;\n/gm, ""))}`
);

assert.deepEqual(cropBounds(1200, 800, 1, 600, 400), {
  x: 200,
  y: 0,
  size: 800,
});
assert.deepEqual(cropBounds(800, 1200, 2, 400, 600), {
  x: 200,
  y: 400,
  size: 400,
});
for (const [width, height] of [
  [1200, 800],
  [800, 1200],
  [512, 512],
  [1, 1000],
]) {
  for (const zoom of [1, 1.01, 2, 4]) {
    for (const [x, y] of [
      [-10000, -10000],
      [0, 0],
      [width / 2, height / 2],
      [10000, 10000],
    ]) {
      const bounds = cropBounds(width, height, zoom, x, y);
      assert(bounds.x >= 0 && bounds.y >= 0);
      assert(
        bounds.x + bounds.size <= width && bounds.y + bounds.size <= height
      );
      assert(bounds.size > 0 && bounds.size <= Math.min(width, height));
    }
  }
}
console.log(
  "Avatar crop geometry passed: landscape, portrait, square, edge clamps and zoom."
);
