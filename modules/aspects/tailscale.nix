{
  # tailscale's here for funnel: it puts notion-sync's localhost webhook listener
  # on a stable *.ts.net name so notion stops pausing the subscription every time
  # an ephemeral tunnel url churns. funnel itself isn't a nix option, so after the
  # rebuild run `tailscale funnel --bg 8080` once.
  den.aspects.tailscale = {
    # node identity plus funnel/serve state; without it khion re-registers as a
    # new node and loses the funnel after every root rollback.
    persistence.directories = [ "/var/lib/tailscale" ];

    nixos.services.tailscale.enable = true;
  };
}
