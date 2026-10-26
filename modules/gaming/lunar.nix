{ lexicon, ... }:
{
  den.aspects.lunar = lexicon {
    # the fhs sandbox hides /etc/egl, so nvidia's egl can't find its wayland
    # platform and falls back to software rendering. /run stays visible.
    package =
      pkgs:
      pkgs.symlinkJoin {
        name = "lunar-client-${pkgs.lunar-client.version}";
        inherit (pkgs.lunar-client) pname version meta;
        paths = [ pkgs.lunar-client ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram "$out/bin/lunarclient" \
            --set __EGL_EXTERNAL_PLATFORM_CONFIG_DIRS /run/opengl-driver/share/egl/egl_external_platform.d
        '';
      };
  };
}
