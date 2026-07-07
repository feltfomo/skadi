{ inputs, ... }:
{
  # noctalia-greeter: the greetd login screen that matches the noctalia shell.
  # upstream ships a flake + nixos module (programs.noctalia-greeter) that
  # enables greetd and points greetd's default_session.command at
  # noctalia-greeter-session for us, so this aspect just imports + enables it.
  # nixos-only, so it belongs on the host includes (khion), not the user.
  den.aspects.noctalia-greeter.nixos = {
    imports = [ inputs.noctalia-greeter.nixosModules.default ];

    programs.noctalia-greeter.enable = true;

    # polkit backs the privilege escalation that Settings -> Security ->
    # Noctalia Greeter -> Sync Now uses to copy your wallpaper/palette to the
    # login screen. if pkexec is disabled, run0 (systemd >= 256) is the
    # documented fallback.
    security.polkit.enable = true;

    # to open straight into a session, set greeter-args to a name from
    # `noctalia-greeter sessions` (Hyprland is the only graphical session here):
    # programs.noctalia-greeter.greeter-args = "-- --session Hyprland";
  };
}
