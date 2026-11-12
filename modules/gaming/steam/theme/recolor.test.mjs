// usage: THEME_CSS=<compiled theme.css> PALETTE=<palette template> node --test recolor.test.mjs
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { VARIABLES, recolorDeclarations, recolorValue } from "./recolor.js";

test("steam's hierarchy maps onto the materials", () => {
  assert.equal(recolorValue("background-color", "rgb(14, 20, 27)"), "var(--skadi-shell, rgb(14, 20, 27))");
  assert.equal(recolorValue("background-color", "rgb(35, 38, 46)"), "var(--skadi-panel, rgb(35, 38, 46))");
  assert.equal(recolorValue("background-color", "rgb(61, 68, 80)"), "var(--skadi-field, rgb(61, 68, 80))");
  assert.equal(recolorValue("border-top-color", "rgb(14, 20, 27)"), "var(--skadi-border-faint, rgb(14, 20, 27))");
  assert.equal(recolorValue("color", "rgb(255, 255, 255)"), "var(--skadi-on-surface, rgb(255, 255, 255))");
  assert.equal(recolorValue("color", "rgb(139, 146, 154)"), "var(--skadi-on-surface-variant, rgb(139, 146, 154))");
});

test("steam's blue becomes the accent", () => {
  assert.equal(recolorValue("color", "rgb(26, 159, 255)"), "var(--skadi-primary, rgb(26, 159, 255))");
  assert.equal(recolorValue("--gpColor-Blue", "#1a9fff"), "var(--skadi-primary, rgb(26, 159, 255))");
});

test("steam's cyan counts as accent", () => {
  assert.equal(
    recolorValue("color", "rgba(0, 217, 255, 0.5)"),
    "color-mix(in srgb, var(--skadi-primary, rgb(0, 217, 255)) 50%, transparent)",
  );
});

test("text on an accent fill takes on-primary", () => {
  assert.deepEqual(
    recolorDeclarations([
      ["background-color", "rgb(26, 159, 255)"],
      ["color", "rgb(255, 255, 255)"],
    ]),
    [
      ["background-color", "var(--skadi-primary, rgb(26, 159, 255))"],
      ["color", "var(--skadi-on-primary, rgb(255, 255, 255))"],
    ],
  );
  // a fill-only rule gains the text color it would otherwise inherit.
  assert.deepEqual(recolorDeclarations([["background-color", "rgb(26, 159, 255)"]]), [
    ["background-color", "var(--skadi-primary, rgb(26, 159, 255))"],
    ["color", "var(--skadi-on-primary, rgb(255, 255, 255))"],
  ]);
  // dark blue fills are tinted panels, so their text stays light.
  assert.deepEqual(
    recolorDeclarations([
      ["background-color", "rgb(20, 51, 110)"],
      ["color", "rgb(255, 255, 255)"],
    ]),
    [
      ["background-color", "var(--skadi-accent-dim, rgb(20, 51, 110))"],
      ["color", "var(--skadi-on-surface, rgb(255, 255, 255))"],
    ],
  );
});

test("the palette's own properties stay literal", () => {
  assert.equal(recolorValue("--skadi-surface", "#131318"), "#131318");
  assert.equal(recolorValue("--skadi-primary", "#bdc2ff"), "#bdc2ff");
});

test("status hues, shadows and scrims stay native", () => {
  assert.equal(recolorValue("color", "rgb(89, 191, 64)"), "rgb(89, 191, 64)");
  assert.equal(recolorValue("box-shadow", "rgb(0, 0, 0) 0px 0px 4px"), "rgb(0, 0, 0) 0px 0px 4px");
  assert.equal(recolorValue("background-color", "rgba(0, 0, 0, 0.5)"), "rgba(0, 0, 0, 0.5)");
});

test("translucency and gradients keep their shape", () => {
  assert.equal(
    recolorValue("background-color", "rgba(255, 255, 255, 0.1)"),
    "color-mix(in srgb, var(--skadi-on-surface, rgb(255, 255, 255)) 10%, transparent)",
  );
  assert.equal(
    recolorValue("background-image", "linear-gradient(rgb(45, 51, 60) 0%, rgb(36, 40, 47) 20%)"),
    "linear-gradient(var(--skadi-raised, rgb(45, 51, 60)) 0%, var(--skadi-panel, rgb(36, 40, 47)) 20%)",
  );
});

test("motiva sans becomes the chrome font, other fonts stay", () => {
  assert.equal(
    recolorValue("font-family", '"Motiva Sans", Arial, sans-serif'),
    'var(--skadi-font, "Motiva Sans", Arial, sans-serif)',
  );
  assert.equal(recolorValue("font-family", "clientui"), "clientui");
});

test("every variable recolor.js emits is defined", () => {
  const defined = new Set(
    [readFileSync(process.env.THEME_CSS, "utf8"), readFileSync(process.env.PALETTE, "utf8")]
      .join("\n")
      .matchAll(/--skadi-([a-z-]+)\s*:/g)
      .map(([, name]) => name),
  );
  for (const name of VARIABLES) assert.ok(defined.has(name), `--skadi-${name} isn't defined`);
});
