#!@nu@
# renders the boot theme into two directories: grub/, the menu's theme, and plymouth/, the splash's
# images. the build renders the fallback theme with it and the boot-theme service renders the live
# one onto the esp, so both share one layout. with a wallpaper, both stages sit on a blur of it;
# without one, on the palette's surface.
#
# grub scales the background to whatever mode the firmware gives it, but fonts, rows and icons stay
# in pixels, so they're sized from the resolution's height. grub's theme parser takes only whole
# percents, and it reads only 8-bit pngs. plymouth reads only pngs, and its script can't read
# colors at boot, so every piece of its scene in a palette color is an image rendered here.

const roles = [
    surface_container_high
    surface_container_low
    on_surface_variant
    outline_variant
    on_primary
    on_surface
    primary
    surface
    warning
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

    mkdir ($out | path join grub icons) ($out | path join plymouth)
    let out = ($out | path expand)
    let backdrop = (render-backdrop $"($out)/plymouth" $colors $width $height $wallpaper)
    render-grub $"($out)/grub" $colors $host $width $height $backdrop ($wallpaper != null)
    render-plymouth $"($out)/plymouth" $colors $host ($wallpaper != null)
}

# the blurred, tinted wallpaper at an eighth of the screen, or the bare surface without one. plymouth
# stretches it to the screen itself; blurred, it looks the same as a full-size render, and loads in
# a fraction of the time. the tint toward the surface keeps text readable on a bright wallpaper.
def render-backdrop [out: path, colors: record, width: int, height: int, wallpaper: any] {
    let small = $"($width // 8)x($height // 8)"
    let source = if $wallpaper == null {
        [-size $small $"xc:($colors.surface)"]
    } else {
        [
            $"($wallpaper)[0]" -auto-orient -resize $"($width)x($height)^" -gravity center
            -extent $"($width)x($height)" +gravity -resize $"($small)!"
            -blur $"0x((5 * $height + 720) // 1440)" -fill $colors.surface -colorize 45%
        ]
    }
    let path = $"($out)/backdrop.png"
    ^@magick@ ...$source -depth 8 -define png:color-type=2 $path
    $path
}

def render-grub [
    out: path
    colors: record
    host: string
    width: int
    height: int
    backdrop: path
    photo: bool
] {
    cd $out

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

    # a blurred photo is a jpeg, since as a png it takes megabytes on the esp. grub.cfg loads the jpeg
    # reader before it switches to the live theme.
    let extension = if $photo { "jpg" } else { "png" }
    let encoding = if $photo {
        [-depth 8 -quality 92 -sampling-factor 4:2:0]
    } else {
        [-depth 8 -define png:color-type=2]
    }
    let background = $"background.($extension)"

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

    # grub keeps showing its background image after an entry is picked, while it loads the kernel.
    # the backdrop is the same picture without the card, so the card leaves with the menu.
    let size = $"($width)x($height)"
    let full = $"backdrop.($extension)"
    ^@magick@ $backdrop -resize $"($size)!" ...$encoding $full

    let card_shape = (
        $"roundrectangle (do $x $card.left),(do $y $card.top),"
        + $"(do $x ($card.left + $card.width)),(do $y ($card.top + $card.height)),"
        + $"(do $px 10),(do $px 10)"
    )
    # over a photo the card is a translucent panel on the blur, so it reads as frosted glass. the
    # shadow is cut out under the card, or it would show through and darken the glass.
    let card_fill = if $photo { $"($colors.surface_container_low)66" } else { $colors.surface_container_low }
    (^@magick@ $full
        "(" -size $size xc:none -fill "rgba(0,0,0,0.45)" -draw $card_shape -blur $"0x(do $px 28)"
            "(" -size $size xc:none -fill white -draw $card_shape ")" -compose DstOut -composite ")"
        -compose Over -composite
        # a faint accent on the rim, like light catching the glass, without competing with the pill.
        -fill $card_fill -stroke $"($colors.primary)66" -strokewidth (do $px 2) -draw $card_shape
        -stroke $colors.outline_variant -draw $"line (do $x $inner.left),(do $y $rows.divider),(do $x ($inner.left + $inner.width)),(do $y $rows.divider)"
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

# the splash's pieces. sizes are in points at plymouth's 96 dpi, so they match what plymouth's own
# text rendering would draw.
def render-plymouth [out: path, colors: record, host: string, photo: bool] {
    cd $out
    let rgba = [-depth 8 -define png:color-type=6]
    let text = {|file: string, label: string, color: string, points: int|
        (^@magick@ -background none -fill $color -font @font@ -density 96 -pointsize $points
            $"label:($label)" ...$rgba $file)
    }
    do $text name.png $host $colors.on_surface_variant 16
    do $text hint.png password $colors.on_surface_variant 14
    do $text caps.png "caps lock is on" $colors.warning 12
    do $text pulse.png "•" $colors.on_surface_variant 16
    do $text bullet.png "•" $colors.on_surface 18
    # the password field matches grub's card: frosted over a photo, with the same faint accent rim.
    # it's less see-through than the card, so the typed dots stay crisp.
    let fill = if $photo { $"($colors.surface_container_low)99" } else { $colors.surface_container_high }
    (^@magick@ -size 560x56 xc:none
        -fill $fill -stroke $"($colors.primary)66" -strokewidth 2
        -draw "roundrectangle 1,1,558,54,6,6" ...$rgba field.png)
}
