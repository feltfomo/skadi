{ ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    {
      # default dev shell for skadi config editing
      devShells.default = pkgs.mkShell {
        packages = with pkgs; [
          nixd
          alejandra
          nix-tree
          nvd
          statix
          deadnix
          lua
          lua-language-server
          stylua
          vscode-langservers-extracted
          prettierd
        ];
      };

      # minecraft mod dev shell
      devShells.minecraft =
        let
          jdks = with pkgs; [
            zulu
            temurin-bin-21
            jetbrains.jdk-no-jcef
            graalvmPackages.graalvm-ce
          ];

          mcLibs = with pkgs; [
            # graphics
            libGL
            mesa-demos
            vulkan-loader
            glfw3-minecraft
            # audio
            openal
            alsa-lib
            libjack2
            pipewire
            libpulseaudio
            # input / window
            libx11
            libxext
            libxrandr
            libxcursor
            libxxf86vm
            udev
            # misc
            flite
            (lib.getLib stdenv.cc.cc)
          ];
        in
        pkgs.mkShell {
          nativeBuildInputs =
            jdks
            ++ (with pkgs; [
              gradle
              kotlin
              git
            ]);
          buildInputs = mcLibs;
          env = {
            JAVA_HOME = "${pkgs.jetbrains.jdk-no-jcef.home}";
            LD_LIBRARY_PATH = lib.makeLibraryPath mcLibs;
            GRADLE_OPTS = "-Dorg.gradle.java.home=${pkgs.jetbrains.jdk-no-jcef.home}";
          };
        };
    };
}
