{ den, lexicon, ... }:
{
  den.aspects.prismlauncher = {
    includes = [ den.aspects.graalvm-oracle-21 ];
  }
  // lexicon {
    package =
      pkgs:
      with pkgs;
      prismlauncher.override {
        # lwjgl 3.4.1's bundled glfw dlopens libxkbcommon under wayland and the
        # nixpkgs wrapper doesn't ship it, so 26.2 died at "Failed to load libxkbcommon"
        # the rest is chromium's runtime, for mods that ship their own libcef
        # (liquidbounce/mcef), which failed on libnspr4.so
        additionalLibs = [
          libXcomposite
          libxkbcommon
          at-spi2-core
          libxshmfence
          at-spi2-atk
          libXdamage
          libXfixes
          libdrm
          libgbm
          libxcb
          cairo
          expat
          pango
          nspr
          cups
          dbus
          glib
          gtk3
          nss
          atk
        ];
        jdks = [
          jdk8
          jdk21
          jdk17
          jdk25
          graalvm-oracle-21
          graalvmPackages.graalvm-ce
        ];
      };
  };
}
