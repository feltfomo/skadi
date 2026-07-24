_: {
  # minecraft client dev shell and an intellij wrapper for it
  perSystem =
    { pkgs, lib, ... }:
    let
      # jbr ships dcevm so classes hotswap, jdk 21 for 1.21.x, jdk 25 for 26.1+
      jbr = pkgs.jetbrains.jdk-no-jcef;
      inherit (pkgs) jdk21 jdk25;

      # native libs the client dlopens, kept on LD_LIBRARY_PATH
      mcLibs = with pkgs; [
        libGL
        glfw3-minecraft
        openal
        libpulseaudio
        flite
        stdenv.cc.cc.lib
        vulkan-loader
        vulkan-validation-layers
        vulkan-tools
      ];

      # build and language tooling for java, kotlin and scala
      jvmTooling = with pkgs; [
        gradle
        maven
        kotlin
        kotlin-language-server
        scala_3
        sbt
        coursier
        metals
        shaderc
        glslang
        spirv-tools
      ];

      # intellij carrying the same lib path so gradle run tasks work outside the shell
      idea-minecraft = pkgs.symlinkJoin {
        name = "idea-minecraft";
        paths = [
          (pkgs.jetbrains.idea-oss.override {
            vmopts = ''
              -Dnosplash=true
              -Dawt.toolkit.name=WLToolkit
            '';
          })
        ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/idea-oss \
            --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath mcLibs}
        '';
      };
    in
    {
      devShells.default = pkgs.mkShell {
        packages = with pkgs; [
          nixd
          nixfmt
          deadnix
          statix
          lua-language-server
          stylua
          go
          cargo
          rustc
          clippy
          rustfmt
          rust-analyzer
        ];
      };

      devShells.minecraft = pkgs.mkShell {
        packages = [
          jbr
          jdk21
          jdk25
          idea-minecraft
          pkgs.git
        ]
        ++ jvmTooling
        ++ mcLibs;

        env = {
          JAVA_HOME = "${jbr.home}";
          LD_LIBRARY_PATH = lib.makeLibraryPath mcLibs;
        };

        shellHook = ''
          echo "minecraft client dev shell"
          echo "jdk homes for intellij sdks:"
          echo "  jbr ${jbr.home}"
          echo "  21  ${jdk21.home}"
          echo "  25  ${jdk25.home}"
        '';
      };
    };
}
