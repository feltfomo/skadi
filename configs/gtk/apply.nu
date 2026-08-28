# keep the generated palette separate from user and toolkit css
const palette_import = '@import url("reactive.css");'

# existing gtk.css files may be owned by a theme tool so update them in place
# instead of asking home manager to replace them during activation
def ensure-import [version: string] {
  let config_home = ($env.XDG_CONFIG_HOME? | default ($env.HOME | path join ".config"))
  let directory = ([$config_home $version] | path join)
  let css = ([$directory "gtk.css"] | path join)

  mkdir $directory
  let content = if ($css | path exists) { open --raw $css } else { "" }
  if not ($content | str contains $palette_import) {
    let updated = if ($content | is-empty) {
      $"($palette_import)\n"
    } else {
      $"($content)\n\n($palette_import)\n"
    }
    $updated | save --force $css
  }
}

ensure-import "gtk-3.0"
ensure-import "gtk-4.0"

# refresh the desktop preference after both gtk palettes have been published
if (which gsettings | is-not-empty) {
  do --ignore-errors {
    ^gsettings set org.gnome.desktop.interface color-scheme prefer-dark
    ^gsettings set org.gnome.desktop.interface gtk-theme adw-gtk3-dark
  }
}
