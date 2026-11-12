# Steam theme

Steam runs under Millennium, which injects the Skadi theme into two kinds of target: the client's own windows (library, settings, menus, friends) and the store and community web pages shown in the client's browser view. Each kind has its own layer. Both draw every color from the palette template, [config/palette.css](config/palette.css), through the shared design layer's `css.*` helpers, so the theme follows the wallpaper and the build's literal check rejects any hand-written color.

| File | What it owns |
| --- | --- |
| [theme.nix](theme.nix) | The client window patterns, the web page list, the generated `skin.json` and the deployed file list |
| [\_theme-package.nix](_theme-package.nix) | Compiling every sheet and the checks: the literal-color check, recolor's tests |
| [theme/theme.scss](theme/theme.scss) and `theme/components/` | The client layer's materials and components |
| [theme/recolor.js](theme/recolor.js) | Runtime recoloring of the client's compiled colors, and palette refresh |
| `theme/web/` | The web layer: one sheet per page on a shared base |

## Client layer

Client windows are matched by window title or root class, listed in `windows` in theme.nix. Each match gets `palette.css`, `theme.css` and `recolor.js`. Steam's client classes are build hashes, so `recolor.js` maps the compiled colors onto the palette materials at runtime, and the component sheets restyle the controls that need a shape as well as a color.

## Web layer

Millennium registers each patch's `MatchRegexString` as a URL hook too, and injects the patch's sheet into any Steam page whose whole URL matches. Steam's content security policy blocks theme scripts on its web pages, so the web layer is CSS only and `recolor.js` doesn't run there. A web page picks up a new palette the next time it loads.

Each entry in `pages` in theme.nix names a page and gives its URL regex. The build compiles `theme/web/<name>.scss` to `web/<name>.css`, and the skin gives the page `palette.css` and that sheet. A page that isn't listed, such as checkout, the cart or help, stays native.

The page sheets build on shared partials:

- `_base.scss` is the layer every page uses. It remaps `shared_global.css`'s `--gp*` palette and the React components' 12-step `--color-accent-*` and `--color-dull-*` scales, sets the page material, scrollbars, selection and focus ring, and themes Steam's button classes (`btn_green_steamui`, `btnv6_blue_hoverfade` and the rest).
- `_store.scss` adds what store pages share: the store menu bar with its search and dropdowns, the capsule hover card, prices and the footer.
- `components/` holds the mixins page sheets reuse. `surfaces` has `page`, `card`, `well`, `frame`, `floating`, `heading-rule` and `clear`. `buttons.button` styles any element as the shared button, with an optional selected class. `fields.box` styles a wrapper that holds an input. `tags.label` and `tags.link` style genre and feature chips. `rank.$outrank` lifts a selector above Steam's long `:not()` chains.

The materials follow the client: the page is the panel material, the same as the library page; cards are raised with a hairline; bars that continue the client's title bar use the frame material. Buy and play actions, and the chosen one of a set of toggles, take the accent fill. Steam's semantic colors stay native: review summaries (positive blue, mixed, negative), the sale green of discount badges, and promo labels such as deal types.

### Selectors

Steam's classic pages use readable class names. Its React components use CSS-module hashes such as `XLbP8xOkCYw-` that change whenever Valve rebuilds the bundle, so a page sheet never names one. Reach React parts through what stays stable:

- `data-featuretarget` attributes, which name each React section (`store-menu-v7`, `appreviews`, `deck-verified-results`).
- Roles and element structure, such as `[role="navigation"] button[role="button"]` or `div:has(> div > [role="img"])`.
- The readable classes React parts still carry: `.Panel`, `.Focusable`, `.DialogButton`, `.FollowButton`, `.WidgetHeaderCtn`, `.carousel__inner-slide`.

Steam's classic sheets load before the theme's but its React chunks load after, and many of its rules are `!important`. So theme declarations that compete with Steam's are `!important`, and a rule that fights a long Steam selector appends `rank.$outrank`. Prefer remapping a Steam CSS variable over restyling its consumers: `home.css` declares its own palette at `:root`, and `game.css` one text color.

## Add a web page

1. Find the page's URL shape and write a regex that matches the whole URL, including an optional query string. Add `{ name; url; }` to `pages` in theme.nix.
1. Create `theme/web/<name>.scss`. Start it with `@use "store";` for a store page or `@use "base";` for any other, then the components it needs.
1. Remap the page's own CSS variables first. List them by reading the page's stylesheets in DevTools.
1. Style the remaining components with the shared mixins. Only add a mixin to `components/` when a second page needs it.
1. Run `git add` on the new sheet, since the flake only sees tracked files.

## Dev loop

Work against a copy of the theme so the deployed one stays intact. Build the check with `nix build --print-out-paths .#checks.x86_64-linux.steam-theme`, copy every file in its output into `~/.local/share/Steam/millennium/themes/Skadi-dev`, add the deployed `palette.css` beside them, and set `activeTheme` to `Skadi-dev` in `~/.config/millennium/config.json` while Steam is shut down. The scratch helpers in `.runtime/steam-theme/` do this: `dev.sh` builds and copies, `shot.sh` captures the Steam window, and `cdp.mjs` drives Steam's DevTools.

DevTools only listens when Steam runs as `steam -dev`. Shut Steam down and start it from the home directory, then wait until `http://127.0.0.1:8080/json` lists a page titled `Steam`:

```sh
cd /home/feltfomo && steam -shutdown
cd /home/feltfomo && setsid steam -dev
```

After a sheet change, rebuild, copy and reload only the web page's DevTools target. Never call `Page.reload` on the main client window, titled `Steam`; it blanks the client until Steam restarts. A change to `skin.json`, such as a new page, needs a Steam restart.

The user works on another monitor, so a capture switches to Steam's workspace and must put the user's workspaces, focused window and cursor back from an exit trap, the way `shot.sh` does.

## Verify

- Wait for the page to be ready before every capture: the document complete, the element present, two animation frames and a short settle.
- Judge details on crops enlarged 2x, not full-window captures. Check every edge, corner and state of a component: idle, hover, pressed, focus, selected and disabled where they exist. DevTools' `CSS.forcePseudoState` holds a hover or focus state while you capture.
- Compare against the native page by disabling the injected sheets: set `disabled` on the page's `link[href*=millennium]` elements.
- Check that the client windows still look right: the library, settings and a menu.
- Before handing over, run `nix build --no-link .#checks.x86_64-linux.steam-theme`, and set `activeTheme` back to `Skadi` and restart Steam without `-dev`.
