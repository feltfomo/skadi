// recolors steam's own stylesheets in place. steam's colors are compiled to literals and its class
// names are hashed, so instead of selectors this maps every literal to the palette material at the
// same place in steam's hierarchy, by property and lightness. status hues stay native.

const PALETTE_URL = new URL("palette.css", import.meta.url);
const THEME_BASE = new URL(".", import.meta.url).href;
const POLL_MS = 2000;
const MAX_PALETTE_BYTES = 4096;
// only named hex colors reach the page, so the file can't inject other CSS.
const PALETTE_SHAPE = /^\s*:root\s*\{((?:\s*--skadi-[a-z-]+:\s*#[0-9a-fA-F]{6}\s*;)+)\s*\}\s*$/;

const COLOR =
  /rgba?\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*(?:,\s*([\d.]+)\s*)?\)|#([0-9a-fA-F]{8}|[0-9a-fA-F]{6}|[0-9a-fA-F]{3,4})\b|\b(white|black)\b/g;

// [highest lightness, material]; the first band at or above a color's lightness wins.
const BANDS = {
  fill: [
    [3, "well"],
    [12, "shell"],
    [20, "panel"],
    [26, "raised"],
    [40, "field"],
    [55, "border"],
    [78, "border-strong"],
    [100, "on-surface"],
  ],
  border: [
    [12, "border-faint"],
    [40, "border"],
    [100, "border-strong"],
  ],
  text: [
    [25, "surface"],
    [45, "disabled"],
    [80, "on-surface-variant"],
    [100, "on-surface"],
  ],
};

// every custom property this file can emit, checked against theme.css and the palette by the build.
export const VARIABLES = new Set([
  ...Object.values(BANDS).flatMap(bands => bands.map(([, name]) => name)),
  "primary",
  "on-primary",
  "accent-dim",
  "font",
]);

// steam's own value is the fallback, so a window without the palette keeps steam's look.
const ref = (name, fallback) => `var(--skadi-${name}, ${fallback})`;

export function kindOf(property) {
  if (/shadow|filter/i.test(property)) return null;
  if (property.startsWith("--")) {
    if (/text|fg|label/i.test(property)) return "text";
    if (/border|outline|divider|separator/i.test(property)) return "border";
    return "fill";
  }
  if (/^(color|fill|stroke|caret-color|-webkit-text-fill-color|text-decoration-color)$/.test(property)) return "text";
  if (/^(border|outline|column-rule)/.test(property)) return "border";
  if (/^background/.test(property)) return "fill";
  return null;
}

function parse(match) {
  const [, r, g, b, a, hex, name] = match;
  if (name) return name === "white" ? [255, 255, 255, 1] : [0, 0, 0, 1];
  if (hex) {
    const full = hex.length <= 4 ? [...hex].map(c => c + c).join("") : hex;
    const channel = i => parseInt(full.slice(i, i + 2), 16);
    return [channel(0), channel(2), channel(4), full.length === 8 ? channel(6) / 255 : 1];
  }
  return [Number(r), Number(g), Number(b), a === undefined ? 1 : Number(a)];
}

// the material a color becomes, or null to keep it. on an accent fill, text takes on-primary.
function targetOf([r, g, b, alpha], kind, onAccent) {
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const lightness = ((max + min) / 2 / 255) * 100;
  if (max - min >= 31) {
    const hue = hueOf(r, g, b, max, min);
    // steam's accent runs from its cyan to its blue; every other hue is a status or user color.
    if (hue < 185 || hue >= 260) return null;
    if (kind === "text" && onAccent) return "on-primary";
    return kind === "fill" && lightness < 35 ? "accent-dim" : "primary";
  }
  // translucent black is a scrim or shade, which reads right over any palette.
  if (alpha < 1 && lightness <= 3) return null;
  if (kind === "text" && onAccent) return "on-primary";
  return BANDS[kind].find(([limit]) => lightness <= limit)[1];
}

// returns the replacement for one color, or null to keep it.
export function mapColor(rgba, kind, onAccent = false) {
  const target = targetOf(rgba, kind, onAccent);
  if (!target) return null;
  const [r, g, b, alpha] = rgba;
  const own = ref(target, `rgb(${r}, ${g}, ${b})`);
  if (alpha >= 1) return own;
  return `color-mix(in srgb, ${own} ${Math.round(alpha * 1000) / 10}%, transparent)`;
}

function hueOf(r, g, b, max, min) {
  const d = max - min;
  const h = max === r ? ((g - b) / d) % 6 : max === g ? (b - r) / d + 2 : (r - g) / d + 4;
  return (h * 60 + 360) % 360;
}

export function recolorValue(property, value, onAccent = false) {
  if (property === "font-family") {
    return value.includes("Motiva Sans") ? ref("font", value) : value;
  }
  // the palette's own properties must stay literal, or materials built on them would cycle.
  if (property.startsWith("--skadi-")) return value;
  const kind = kindOf(property);
  if (!kind || value.includes("var(--skadi-")) return value;
  return value.replace(COLOR, (...match) => mapColor(parse(match), kind, onAccent) ?? match[0]);
}

// a rule whose background becomes the opaque accent.
function fillsAccent(declarations) {
  return declarations.some(
    ([property, value]) =>
      /^background/.test(property) &&
      [...value.matchAll(COLOR)].some(match => {
        const rgba = parse(match);
        return rgba[3] >= 1 && targetOf(rgba, "fill", false) === "primary";
      }),
  );
}

// recolors one rule's declarations together, so text on an accent fill gets on-primary even when
// the rule only sets the fill and its text color comes from elsewhere.
export function recolorDeclarations(declarations) {
  const onAccent = fillsAccent(declarations);
  const next = declarations.map(([property, value]) => [property, recolorValue(property, value, onAccent)]);
  if (onAccent && !declarations.some(([property]) => property === "color")) {
    next.push(["color", ref("on-primary", "rgb(255, 255, 255)")]);
  }
  return next;
}

function recolorStyle(style) {
  const declarations = Array.from(style, property => [property, style.getPropertyValue(property)]);
  for (const [property, value] of recolorDeclarations(declarations)) {
    if (value !== style.getPropertyValue(property)) {
      style.setProperty(property, value, style.getPropertyPriority(property));
    }
  }
}

function walk(rules) {
  for (const rule of rules) {
    if (rule.style) recolorStyle(rule.style);
    if (rule.cssRules) walk(rule.cssRules);
  }
}

const seen = new WeakSet();

function recolorSheets() {
  for (const sheet of document.styleSheets) {
    if (seen.has(sheet) || sheet.href?.startsWith(THEME_BASE) || sheet.ownerNode?.id === "skadi-palette") continue;
    let rules;
    try {
      rules = sheet.cssRules;
    } catch {
      // still loading, or cross-origin; a later load event retries it.
      continue;
    }
    seen.add(sheet);
    walk(rules);
    recolored += 1;
  }
}

let paletteText = null;
let recolored = 0;

async function reloadPalette() {
  let text;
  try {
    const response = await fetch(PALETTE_URL, { cache: "no-store" });
    text = await response.text();
  } catch (error) {
    console.warn(`skadi: palette fetch failed: ${error}`);
    return;
  }
  if (text === paletteText || text.length > MAX_PALETTE_BYTES) return;
  const declarations = text.match(PALETTE_SHAPE)?.[1];
  if (!declarations) return;
  paletteText = text;
  let style = document.getElementById("skadi-palette");
  if (!style) {
    style = Object.assign(document.createElement("style"), { id: "skadi-palette" });
    document.head.append(style);
  }
  style.textContent = `:root {${declarations} }`;
}

function start() {
  reloadPalette();
  recolorSheets();
  // late stylesheets: a <style> appears in <head>, a <link> once its load event fires.
  new MutationObserver(recolorSheets).observe(document.head, { childList: true });
  document.addEventListener("load", recolorSheets, true);
  // polling stops with the window; hidden windows catch up when they're shown or focused.
  setInterval(() => document.visibilityState === "visible" && reloadPalette(), POLL_MS);
  document.addEventListener("visibilitychange", reloadPalette);
  window.addEventListener("focus", reloadPalette);
  // one line per window in steam's webhelper log, so a broken theme shows which piece is missing.
  setTimeout(() => {
    const root = getComputedStyle(document.documentElement);
    const sheets = Array.from(document.styleSheets, sheet => sheet.href ?? "inline");
    console.info(
      `skadi: ${document.title}: ${recolored} sheets recolored, palette ${paletteText ? "fetched" : "missing"},` +
        ` --skadi-primary=${root.getPropertyValue("--skadi-primary").trim() || "unset"},` +
        ` --skadi-shell=${root.getPropertyValue("--skadi-shell").trim() ? "set" : "unset"},` +
        ` theme sheets: ${sheets.filter(href => href.startsWith(THEME_BASE)).join(" ") || "none"}`,
    );
  }, 3000);
}

if (typeof document !== "undefined") start();
