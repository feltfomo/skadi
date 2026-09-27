{
  den.aspects.tailscale = {
    # the node key, the tailnet name, and any serve/funnel config all live in
    # this directory. khion rolls its root back to @blank every boot, so
    # without persistence the machine rejoins as a brand new node and every
    # published url changes.
    persistence.directories = [ "/var/lib/tailscale" ];

    nixos = {
      # tailscaled terminates tls for funnel itself, so nothing here needs a
      # cert or an inbound port opened by hand.
      services.tailscale.enable = true;
    };
  };
}
