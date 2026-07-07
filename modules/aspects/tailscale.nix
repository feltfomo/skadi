_: {
  # tailscale's here for funnel: it puts notion-sync's localhost webhook listener
  # on a stable *.ts.net name so notion stops pausing the subscription every time
  # an ephemeral tunnel url churns. funnel itself isn't a nix option, so after the
  # rebuild run `tailscale funnel --bg 8080` once -- it persists in tailscaled
  # state across reboots, but only because impermanence.nix persists
  # /var/lib/tailscale. drop that persist line and khion re-registers as a new node
  # (khion-1, khion-2, ...) and loses the funnel on every reboot.
  den.aspects.tailscale.nixos = {
    services.tailscale.enable = true;
  };
}
