#!@nu@
# renders the grub theme: the host's card on the palette's surface, or on a blurred wallpaper when
# one is given. the build renders the fallback theme with it and the boot-theme service renders the
# live one onto the esp, so both share one layout.
#
# grub scales the background to whatever mode the firmware gives it, but fonts, rows and icons stay
# in pixels, so they're sized from the resolution's height. grub's theme parser takes only whole
# percents, and it reads only 8-bit pngs.

const roles = [
    surface_container_high
    surface_container_low
    on_surface_variant
    outline_variant
    on_primary
    on_surface
    primary
    surface
]

# the layout in whole percents. the background is drawn from the same numbers, so the card and the
# menu line up at any resolution.
const card = { left: 32, top: 38, width: 36, height: 24 }

def main [
    out: path
    --palette: path
    --host: string
    --width: int
    --height: int
    --wallpaper: path
] {
    let colors = (open --raw $palette | from json)
    for role in $roles {
        let value = ($colors | get --optional $role)
        if ($value == null) or not ($value =~ '^#[0-9a-fA-F]{6}$') {
            error make { msg: $"($palette): ($role) is not a #rrggbb color" }
        }
    }

    # pixel sizes are designed at 1440 rows.
    let px = {|value: int| ($value * $height + 720) // 1440 }
    let x = {|value: int| $value * $width // 100 }
    let y = {|value: int| $value * $height // 100 }

    let fonts = { small: (do $px 20), item: (do $px 22), title: (do $px 28) }
    # grub names a font by its family, style and size, not by its file.
    let font_name = {|size: int| $"Maple Mono NF Regular ($size)" }

    let inner = { left: ($card.left + 2), width: ($card.width - 4) }
    let rows = { header: ($card.top + 3), divider: ($card.top + 8), menu: ($card.top + 10) }
    let item = (do $px 52)
    let radius = (do $px 6)
    # grub draws one icon for an entry whether or not it's selected, so each glyph sits on a tile
    # that reads on both the card and the accent pill. an even inset keeps the glyph's size the same
    # parity as the tile's, so it can sit exactly centred.
    let tile = (do $px 34)
    let glyph = $tile - 2 * (do $px 7)

    mkdir ($out | path join icons)
    cd $out

    # the live background is a jpeg, since a photo as a png takes megabytes on the esp. grub.cfg
    # loads the jpeg reader before it switches to the live theme.
    let background = if $wallpaper == null { "background.png" } else { "background.jpg" }

    $"title-text: \"\"
desktop-image: \"($background)\"
desktop-color: \"($colors.surface)\"
terminal-font: \"(do $font_name $fonts.item)\"
terminal-box: \"terminal_*.png\"
terminal-left: \"0\"
terminal-top: \"0\"
terminal-width: \"100%\"
terminal-height: \"100%\"
terminal-border: \"0\"

+ label {
  left = ($inner.left)%
  top = ($rows.header)%
  width = ($inner.width)%
  text = \"($host)\"
  font = \"(do $font_name $fonts.title)\"
  color = \"($colors.on_surface)\"
}

+ label {
  left = ($inner.left)%
  top = ($rows.header)%
  width = ($inner.width)%
  align = \"right\"
  id = \"__timeout__\"
  text = \"booting in %ds\"
  font = \"(do $font_name $fonts.small)\"
  color = \"($colors.on_surface_variant)\"
}

+ boot_menu {
  left = ($inner.left)%
  top = ($rows.menu)%
  width = ($inner.width)%
  height = ($card.top + $card.height - 3 - $rows.menu)%
  item_font = \"(do $font_name $fonts.item)\"
  selected_item_font = \"(do $font_name $fonts.item)\"
  item_color = \"($colors.on_surface_variant)\"
  selected_item_color = \"($colors.on_primary)\"
  selected_item_pixmap_style = \"select_*.png\"
  icon_width = ($tile)
  icon_height = ($tile)
  item_icon_space = (do $px 16)
  item_height = ($item)
  item_padding = (($item - $tile) // 2)
  item_spacing = (do $px 6)
  scrollbar = false
}
" | save theme.txt

    # latin only: the nerd font's icon glyphs would make each .pf2 several megabytes on the esp.
    for size in ($fonts | values | uniq) {
        ^@mkfont@ --size $size --range 0x20-0x7e,0xa0-0x17f --output $"maple-($size).pf2" @font@
    }

    let size = $"($width)x($height)"
    let card_shape = (
        $"roundrectangle (do $x $card.left),(do $y $card.top),"
        + $"(do $x ($card.left + $card.width)),(do $y ($card.top + $card.height)),"
        + $"(do $px 10),(do $px 10)"
    )
    # blurring at an eighth of the size is quicker than a full-size blur and looks the same. the tint
    # toward the surface keeps the card's text readable on a bright wallpaper.
    let base = if $wallpaper == null {
        [-size $size $"xc:($colors.surface)"]
    } else {
        [
            $"($wallpaper)[0]" -auto-orient -resize $"($size)^" -gravity center -extent $size +gravity
            -resize 12.5% -blur $"0x(do $px 5)" -resize $"($size)!"
            -fill $colors.surface -colorize 45%
        ]
    }
    # over a wallpaper the card is a translucent panel on the blur, so it reads as frosted glass. the
    # shadow is cut out under the card, or it would show through and darken the glass.
    let card_fill = if $wallpaper == null { $colors.surface_container_low } else { $"($colors.surface_container_low)66" }
    let encoding = if $wallpaper == null {
        [-depth 8 -define png:color-type=2]
    } else {
        [-depth 8 -quality 92 -sampling-factor 4:2:0]
    }
    (^@magick@ ...$base
        "(" -size $size xc:none -fill "rgba(0,0,0,0.45)" -draw $card_shape -blur $"0x(do $px 28)"
            "(" -size $size xc:none -fill white -draw $card_shape ")" -compose DstOut -composite ")"
        -compose Over -composite
        -fill $card_fill -stroke $colors.outline_variant -strokewidth (do $px 2) -draw $card_shape
        -draw $"line (do $x $inner.left),(do $y $rows.divider),(do $x ($inner.left + $inner.width)),(do $y $rows.divider)"
        ...$encoding $background)

    # the selection is a pill cut into a stretchable middle and two rounded ends.
    let pill = (mktemp --tmpdir --suffix .png)
    ^@magick@ -size $"64x($item)" xc:none -fill $colors.primary -draw $"roundrectangle 0,0,63,($item - 1),($radius),($radius)" $pill
    let rgba = [+repage -depth 8 -define png:color-type=6]
    ^@magick@ $pill -crop $"($radius)x($item)+0+0" ...$rgba select_w.png
    ^@magick@ $pill -crop $"1x($item)+32+0" ...$rgba select_c.png
    ^@magick@ $pill -crop $"($radius)x($item)+(64 - $radius)+0" ...$rgba select_e.png
    rm $pill

    # grub picks an entry's icon by its --class: nixos for each generation, submenu for the rest.
    let icons = { nixos: "@nixos_icon@", submenu: "@submenu_icon@" }
    for class in ($icons | columns) {
        let shape = (mktemp --tmpdir --suffix .png)
        ^@rsvg@ --width $glyph --height $glyph --keep-aspect-ratio ($icons | get $class) --output $shape
        (^@magick@ -size $"($tile)x($tile)" xc:none
            -fill $colors.surface_container_high -stroke $colors.outline_variant -strokewidth (do $px 2)
            -draw $"roundrectangle 1,1,($tile - 2),($tile - 2),($radius),($radius)"
            "(" $shape -fill $colors.primary -colorize 100 -gravity center -background none -extent $"($glyph)x($glyph)" ")"
            -gravity center -composite ...$rgba $"icons/($class).png")
        rm $shape
    }

    ^@magick@ -size 8x8 $"xc:($colors.surface)" -depth 8 -define png:color-type=6 terminal_c.png
}
