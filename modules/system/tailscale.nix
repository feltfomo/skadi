{
  den.aspects.tailscale = {
    # preserve the node identity and serve/funnel settings across root rollback
    # so rebooting khion doesn't change its published urls.
    persistence.directories = [ "/var/lib/tailscale" ];

    nixos = {
      # tailscaled terminates tls for funnel itself, so nothing here needs a
      # cert or an inbound port opened by hand.
      services.tailscale.enable = true;
    };
  };
}
