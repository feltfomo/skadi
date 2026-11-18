{ lexicon, ... }:
{
  den.aspects.chiaki-ng = lexicon {
    # the ui is qml, which takes QT_STYLE_OVERRIDE as a quick controls style. kvantum is only a
    # widget style, so the window fails with "module kvantum is not installed" and the app quits.
    package =
      pkgs:
      pkgs.symlinkJoin {
        name = "chiaki-ng-${pkgs.chiaki-ng.version}";
        inherit (pkgs.chiaki-ng) pname version meta;
        paths = [ pkgs.chiaki-ng ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram "$out/bin/chiaki" --unset QT_STYLE_OVERRIDE
        '';
      };
    nixos = {
      # discovery broadcasts from a local port in this range and the console
      # answers by unicast, which conntrack doesn't count as a reply.
      networking.firewall.allowedUDPPortRanges = [
        {
          from = 9303;
          to = 9319;
        }
      ];
    };
  };
}
