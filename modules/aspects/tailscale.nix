_: {
  # tailscale's here for Funnel: it puts notion-sync's localhost webhook
  # listener on a stable *.ts.net name so Notion stops pausing the subscription
  # every time an ephemeral tunnel url churns. funnel itself isn't a nix option,
  # so after the rebuild run `tailscale funnel --bg 8080` once -- it persists in
  # tailscaled state across reboots, BUT only because impermanence.nix persists
  # /var/lib/tailscale. Drop that persist line and khion re-registers as a new
  # node (khion-1, khion-2, ...) and loses the funnel on every reboot.
  den.aspects.tailscale.nixos =
    { lib, config, ... }:
    {
      services.tailscale.enable = true;

      # --- Keep the Funnel ingress warm (fixes the one-shot 502 on delivery) ---
      # Tailscale's ingress relay lets an idle relay<->node link go cold: the first
      # inbound request after idle 502s while it re-establishes, then works. Notion
      # delivers webhook events one-shot, so a cold relay silently drops the first
      # event (the poller re-pulls it a cycle later, defeating the webhook's point)
      # and, worse, fails subscription verification, itself a single one-shot POST.
      #
      # This was a hand-rolled oneshot + timer here; notion-sync (>= 0.6.0) now ships
      # the exact same behavior as a module option, so we just turn it on.
      # forcePublicPath makes the ping cross the public relay -- a request from khion
      # itself takes the direct tailnet path and never warms the ingress -- by
      # resolving the funnel name against a public resolver and hitting each relay IP
      # with `curl --resolve`. interval defaults to 45s (under Tailscale's idle
      # window); lower it if a gap ever slips through. khion-only: it owns the funnel.
      services.notion-sync.keepWarm = lib.mkIf (config.networking.hostName == "khion") {
        enable = true;
        url = "https://khion.tail4f0c8e.ts.net/notion-webhook";
        forcePublicPath = true;
      };
    };
}
