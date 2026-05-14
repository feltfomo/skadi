Mod         = "SUPER"
ModAlt      = "SUPER + ALT"
Menu        = "fuzzel"
Terminal    = "kitty"
FileManager = "dolphin"
ScreenShot  = "hyprshot -m region --raw | satty --filename -"
HostName    = io.popen("hostname"):read("*l")
Directions  = {
    right = { arrow = "right", vim = "l" },
    left  = { arrow = "left", vim = "h" },
    up    = { arrow = "up", vim = "k" },
    down  = { arrow = "down", vim = "j" },
}
