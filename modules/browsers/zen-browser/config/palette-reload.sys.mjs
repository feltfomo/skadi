import { clearTimeout, setTimeout } from "resource://gre/modules/Timer.sys.mjs";

const lazy = {};
ChromeUtils.defineESModuleGetters(lazy, {
  Subprocess: "resource://gre/modules/Subprocess.sys.mjs",
});

const PALETTE_WATCH = "@paletteWatch@";
// matches app-theme-setup's reading of XDG_CONFIG_HOME, so both agree on the deployed theme.
const THEME_DIRECTORY = PathUtils.join(
  Services.env.get("XDG_CONFIG_HOME") ||
    PathUtils.join(Services.dirsvc.get("Home", Ci.nsIFile).path, ".config"),
  "zen",
  "theme"
);
const PALETTE_PATH = PathUtils.join(THEME_DIRECTORY, "palette.css");
// real palettes are under 400 bytes, and PALETTE_SHAPE judges whatever fits under this bound.
const MAX_PALETTE_BYTES = 4096;
const DEBOUNCE_MS = 75;
// only named hex colors reach the generated sheet, so the file can't inject other CSS. a palette
// caught mid-write fails this too, and the previous colors stay.
const PALETTE_SHAPE =
  /^\s*:root\s*\{((?:\s*--skadi-[a-z-]+:\s*#[0-9a-fA-F]{6}\s*;)+)\s*\}\s*$/;

let currentText = null;
let currentSheet = null;
let pendingReload = null;
let reloads = Promise.resolve();

async function readPalette() {
  try {
    const bytes = await IOUtils.read(PALETTE_PATH, {
      maxBytes: MAX_PALETTE_BYTES,
    });
    return new TextDecoder().decode(bytes);
  } catch {
    return null;
  }
}

// user-origin !important beats the palette.css that userChrome.css and userContent.css imported,
// without touching those sheets. the service shares it with every document in every process,
// including windows that don't exist yet, which no per-window update can do. about: pages take it
// too; web pages don't, since they read nothing from the palette.
function applyPalette(text) {
  const declarations = text
    .match(PALETTE_SHAPE)?.[1]
    .replaceAll(/\s*;/g, " !important;");
  if (!declarations) {
    return false;
  }
  const css = `@-moz-document url-prefix("chrome:"), url-prefix("about:") { :root {${declarations} } }`;
  const sheet = Services.io.newURI(
    `data:text/css;charset=utf-8,${encodeURIComponent(css)}`
  );
  const service = Cc["@mozilla.org/content/style-sheet-service;1"].getService(
    Ci.nsIStyleSheetService
  );
  // the swap shares one task with no style flush inside it, so no frame sees neither sheet.
  service.loadAndRegisterSheet(sheet, service.USER_SHEET);
  if (currentSheet) {
    service.unregisterSheet(currentSheet, service.USER_SHEET);
  }
  currentSheet = sheet;
  return true;
}

async function reload() {
  const text = await readPalette();
  if (text !== null && text !== currentText && applyPalette(text)) {
    currentText = text;
  }
}

function queueReload() {
  clearTimeout(pendingReload);
  pendingReload = setTimeout(() => {
    reloads = reloads.then(reload).catch(console.error);
  }, DEBOUNCE_MS);
}

// chrome JS has no file watcher, and polling would wake the browser for the whole session.
async function watch(startupText) {
  currentText = await startupText;
  const watcher = await lazy.Subprocess.call({
    command: PALETTE_WATCH,
    arguments: [THEME_DIRECTORY],
    // inotifywait's "Watches established." is the first reload, which catches a palette written
    // between startup and the watch going live.
    stderr: "stdout",
    environment: {},
  });
  Services.obs.addObserver(() => {
    clearTimeout(pendingReload);
    watcher.stdin.close();
  }, "quit-application");
  while (await watcher.stdout.readString()) {
    queueReload();
  }
}

// read before the first window loads userChrome.css, so a palette that hasn't changed since then
// needs no sheet and no restyle.
const startupText = readPalette();

Services.obs.addObserver(function started() {
  Services.obs.removeObserver(started, "browser-delayed-startup-finished");
  watch(startupText).catch(console.error);
}, "browser-delayed-startup-finished");
