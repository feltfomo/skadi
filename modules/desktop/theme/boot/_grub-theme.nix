# the boot menu: a palette card on the palette's surface, drawn at the screen's resolution. grub
# scales the background to whatever mode the firmware gives it, but fonts, rows and icons stay in
# pixels, so they're sized from the resolution's height.
{
  lib,
  runCommand,
  grub2_efi,
  imagemagick,
  librsvg,
  maple-mono,
  nixos-icons,
  palette,
  hostName,
  resolution,
}:
let
  inherit (resolution) width height;
  # pixel sizes are designed at 1440 rows.
  px = value: (value * height + 720) / 1440;

  font = "${maple-mono.NF}/share/fonts/truetype/MapleMono-NF-Regular.ttf";
  # grub names a font by its family, style and size, not by its file.
  fontName = size: "Maple Mono NF Regular ${toString size}";
  fonts = {
    small = px 20;
    item = px 22;
    title = px 28;
  };

  # the layout in whole percents, which is all grub's theme parser takes. the background is drawn
  # from the same numbers, so the card and the menu line up at any resolution.
  card = {
    left = 32;
    top = 38;
    width = 36;
    height = 24;
  };
  inner = {
    left = card.left + 2;
    width = card.width - 4;
  };
  rows = {
    header = card.top + 3;
    divider = card.top + 8;
    menu = card.top + 10;
  };
  x = value: toString (value * width / 100);
  y = value: toString (value * height / 100);

  item = px 52;
  radius = px 6;
  # grub draws one icon for an entry whether or not it's selected, so each glyph sits on a tile
  # that reads on both the card and the accent pill.
  tile = px 34;
  glyph = px 20;
  # grub picks an entry's icon by its --class: nixos for each generation, submenu for the rest.
  icons = {
    nixos = "${nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake-white.svg";
    submenu = ./grub/submenu.svg;
  };

  theme = ''
    title-text: ""
    desktop-image: "background.png"
    desktop-color: "${palette.surface}"
    terminal-font: "${fontName fonts.item}"
    terminal-box: "terminal_*.png"
    terminal-left: "0"
    terminal-top: "0"
    terminal-width: "100%"
    terminal-height: "100%"
    terminal-border: "0"

    + label {
      left = ${toString inner.left}%
      top = ${toString rows.header}%
      width = ${toString inner.width}%
      text = "${hostName}"
      font = "${fontName fonts.title}"
      color = "${palette.on_surface}"
    }

    + label {
      left = ${toString inner.left}%
      top = ${toString rows.header}%
      width = ${toString inner.width}%
      align = "right"
      id = "__timeout__"
      text = "booting in %ds"
      font = "${fontName fonts.small}"
      color = "${palette.on_surface_variant}"
    }

    + boot_menu {
      left = ${toString inner.left}%
      top = ${toString rows.menu}%
      width = ${toString inner.width}%
      height = ${toString (card.top + card.height - 3 - rows.menu)}%
      item_font = "${fontName fonts.item}"
      selected_item_font = "${fontName fonts.item}"
      item_color = "${palette.on_surface_variant}"
      selected_item_color = "${palette.on_primary}"
      selected_item_pixmap_style = "select_*.png"
      icon_width = ${toString tile}
      icon_height = ${toString tile}
      item_icon_space = ${toString (px 16)}
      item_height = ${toString item}
      item_padding = ${toString ((item - tile) / 2)}
      item_spacing = ${toString (px 6)}
      scrollbar = false
    }
  '';
in
runCommand "skadi-grub-theme"
  {
    nativeBuildInputs = [
      imagemagick
      grub2_efi
      librsvg
    ];
    inherit theme;
    passAsFile = [ "theme" ];
  }
  ''
    set -euo pipefail
    mkdir -p "$out/icons"
    cp "$themePath" "$out/theme.txt"

    # latin only: the nerd font's icon glyphs would make each .pf2 several megabytes on the esp.
    ${lib.concatMapStrings (size: ''
      grub-mkfont --size ${toString size} --range 0x20-0x7e,0xa0-0x17f \
        --output "$out/maple-${toString size}.pf2" ${font}
    '') (lib.unique (lib.attrValues fonts))}

    # grub reads only 8-bit truecolor pngs; blurring makes imagemagick write 16-bit otherwise.
    card="roundrectangle ${x card.left},${y card.top},${x (card.left + card.width)},${y (card.top + card.height)},${toString (px 10)},${toString (px 10)}"
    magick -size ${toString width}x${toString height} xc:'${palette.surface}' \
      \( -size ${toString width}x${toString height} xc:none -fill 'rgba(0,0,0,0.45)' -draw "$card" -blur 0x${toString (px 28)} \) -composite \
      -fill '${palette.surface_container_low}' -stroke '${palette.outline_variant}' -strokewidth ${toString (px 2)} \
      -draw "$card" \
      -draw "line ${x inner.left},${y rows.divider},${x (inner.left + inner.width)},${y rows.divider}" \
      -depth 8 -define png:color-type=2 "$out/background.png"

    # the selection is a pill cut into a stretchable middle and two rounded ends.
    magick -size 64x${toString item} xc:none -fill '${palette.primary}' \
      -draw "roundrectangle 0,0,63,${toString (item - 1)},${toString radius},${toString radius}" pill.png
    magick pill.png -crop ${toString radius}x${toString item}+0+0 +repage -depth 8 -define png:color-type=6 "$out/select_w.png"
    magick pill.png -crop 1x${toString item}+32+0 +repage -depth 8 -define png:color-type=6 "$out/select_c.png"
    magick pill.png -crop ${toString radius}x${toString item}+${toString (64 - radius)}+0 +repage -depth 8 -define png:color-type=6 "$out/select_e.png"

    ${lib.concatStrings (
      lib.mapAttrsToList (class: svg: ''
        rsvg-convert --width ${toString glyph} --height ${toString glyph} --keep-aspect-ratio ${svg} \
          | magick - -fill '${palette.primary}' -colorize 100 -gravity center -background none \
            -extent ${toString glyph}x${toString glyph} glyph.png
        magick -size ${toString tile}x${toString tile} xc:none \
          -fill '${palette.surface_container_high}' -stroke '${palette.outline_variant}' -strokewidth ${toString (px 2)} \
          -draw "roundrectangle 1,1,${toString (tile - 2)},${toString (tile - 2)},${toString radius},${toString radius}" \
          glyph.png -gravity center -composite -depth 8 -define png:color-type=6 "$out/icons/${class}.png"
      '') icons
    )}

    magick -size 8x8 xc:'${palette.surface}' -depth 8 -define png:color-type=6 "$out/terminal_c.png"
  ''
