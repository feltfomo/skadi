def main [
    source: path
    gtk_theme: path
    qt_theme: path
    gtk_reload: path
    qt5_plugins: path
    qt5_platform_plugins: path
    qt6_plugins: path
    qt6_platform_plugins: path
    output: path
] {
    let probe = ($source | path join tests theme-hot-reload.py)
    for version in ["3.0" "4.0"] {
        ^python $probe gtk $version $source $gtk_theme $qt_theme $output --gtk-reload $gtk_reload
        if $env.LAST_EXIT_CODE != 0 { exit $env.LAST_EXIT_CODE }
    }
    for version in ["5" "6"] {
        let plugins = if $version == "5" { $qt5_plugins } else { $qt6_plugins }
        let platform_plugins = if $version == "5" { $qt5_platform_plugins } else { $qt6_platform_plugins }
        ^python $probe qt $version $source $gtk_theme $qt_theme $output --qt-plugins $plugins --qt-platform-plugins $platform_plugins
        if $env.LAST_EXIT_CODE != 0 { exit $env.LAST_EXIT_CODE }
        ^python $probe qt $version $source $gtk_theme $qt_theme $output --qt-plugins $plugins --qt-platform-plugins $platform_plugins --replace-style
        if $env.LAST_EXIT_CODE != 0 { exit $env.LAST_EXIT_CODE }
    }
}
