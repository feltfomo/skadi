// usage: node --test literals.test.mjs
import assert from "node:assert/strict";
import test from "node:test";
import { colorLiterals } from "./literals.mjs";

test("hex, rgb and hsl literals are caught", () => {
  assert.deepEqual(
    colorLiterals(`
      a { color: #fff; }
      b { background: linear-gradient(rgb(1, 2, 3), transparent); }
      c { border-color: rgba(0 0 0 / 0.5); outline-color: hsl(200 50% 50%); }
      d { box-shadow: 0 0 4px hsla(0, 0%, 0%, 0.3) !important }
    `),
    [
      "color: #fff",
      "background: linear-gradient(rgb(1, 2, 3), transparent)",
      "border-color: rgba(0 0 0 / 0.5)",
      "outline-color: hsl(200 50% 50%)",
      "box-shadow: 0 0 4px hsla(0, 0%, 0%, 0.3) !important",
    ],
  );
});

test("keywords, roles and relative colors pass", () => {
  assert.deepEqual(
    colorLiterals(`
      #MainNavMenu-Rest .add { color: currentColor; background: transparent; border: none; fill: inherit; }
      a { box-shadow: 0 8px 28px color-mix(in srgb, hsl(from var(--skadi-surface) h calc(s * 0.2) calc(l * 0.2)) 28%, transparent); }
      /* a comment may mention #fff */
    `),
    [],
  );
});
