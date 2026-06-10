{ ... }:
{
  # tailscale's here for Funnel: it puts notion-sync's localhost webhook
  # listener on a stable *.ts.net name so Notion stops pausing the subscription
  # every time an ephemeral tunnel url churns. funnel itself isn't a nix option,
  # so after the rebuild run `tailscale funnel --bg 8080` once -- it persists in
  # tailscaled state across reboots.
  den.aspects.tailscale.nixos.services.tailscale.enable = true;
}