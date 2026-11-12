// finds color literals in a compiled stylesheet. every color in the theme comes from the palette's
// roles, so a hex, rgb() or hsl() value means a sheet bypassed the renderer and won't follow the
// wallpaper. a relative color built from a role (`hsl(from var(...) ...)`) is the renderer's own.
// usage: node literals.mjs <css file>...
import { readFileSync } from "node:fs";
import { argv, exit } from "node:process";

const LITERAL = /#[0-9a-fA-F]{3,8}\b|\b(?:rgba?|hsla?)\((?!\s*from\s)/;

// declarations only, so an id selector such as `#add` isn't mistaken for a hex color.
export function colorLiterals(css) {
  const found = [];
  const text = css.replace(/\/\*[\s\S]*?\*\//g, "");
  for (const [, body] of text.matchAll(/\{([^{}]*)\}/g)) {
    for (const declaration of body.split(";")) {
      const colon = declaration.indexOf(":");
      if (colon < 0) continue;
      if (LITERAL.test(declaration.slice(colon + 1))) found.push(declaration.trim());
    }
  }
  return found;
}

if (import.meta.url === `file://${argv[1]}`) {
  let failed = false;
  for (const path of argv.slice(2)) {
    for (const declaration of colorLiterals(readFileSync(path, "utf8"))) {
      console.error(`${path}: color literal in \`${declaration}\``);
      failed = true;
    }
  }
  exit(failed ? 1 : 0);
}
