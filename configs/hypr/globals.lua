Mod = "SUPER"
ModAlt = "SUPER + ALT"
Menu = "fuzzel"
Terminal = "kitty"
FileManager = "dolphin"
ScreenShot = "hyprshot -m region --raw | satty --filename -"
HostName = io.popen("hostname"):read("*l")
NotcaliaShellClipper = "noctalia msg panel-toggle clipboard"
NoctaliaShellLauncher = "noctalia msg panel-toggle launcher"
Directions = {
	right = { arrow = "right", vim = "l" },
	left = { arrow = "left", vim = "h" },
	up = { arrow = "up", vim = "k" },
	down = { arrow = "down", vim = "j" },
}
