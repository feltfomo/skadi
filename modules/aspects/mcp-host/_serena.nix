{
  lib,
  pkgs,
  projectRoot,
}:
let
  # solidlsp passes --stdio, but fwcd's kotlin server rejects that flag.
  serenaKotlinLanguageServer = pkgs.writeShellApplication {
    name = "serena-kotlin-language-server";
    text = ''
      if [ "''${1-}" = "--stdio" ]; then
        shift
      fi
      exec ${pkgs.kotlin-language-server}/bin/kotlin-language-server "$@"
    '';
  };
  serenaJdtlsRoot = "/var/lib/serena-mcp/jdtls";
  serenaNixdConfig = pkgs.writeText "serena-nixd.json" (
    builtins.toJSON {
      nixpkgs.expr = "import <nixpkgs> { }";
      formatting.command = [ "${pkgs.nixfmt}/bin/nixfmt" ];
    }
  );
  serenaConfig = pkgs.writeText "serena-config.yml" ''
    language_backend: LSP
    web_dashboard: false
    web_dashboard_open_on_launch: false
    gui_log_window: false
    log_level: 30
    tool_timeout: 300
    base_modes:
      - no-memories
    default_modes:
      - planning
    project_serena_folder_location: "/var/lib/serena-mcp/projects/$projectFolderName/.serena"
    trusted_project_path_patterns:
      - ${projectRoot}
    projects:
      - ${projectRoot}
    ls_specific_settings:
      kotlin:
        ls_path: "${serenaKotlinLanguageServer}/bin/serena-kotlin-language-server"
      java:
        jdtls_path: "${serenaJdtlsRoot}"
        lombok_path: "${lib.getOutput "out" pkgs.lombok}/share/java/lombok.jar"
        java_home: "${pkgs.jdk21}"
        gradle_java_home: "${pkgs.jdk25}"
        gradle_user_home: "/var/lib/serena-mcp/gradle"
        gradle_wrapper_enabled: true
        runtimes:
          - name: "JavaSE-25"
            path: "${pkgs.jdk25}"
            default: true
      rust:
        ls_path: "${pkgs.rust-analyzer}/bin/rust-analyzer"
      cpp:
        ls_path: "${pkgs.clang-tools}/bin/clangd"
      nix:
        ls_path: "${pkgs.nixd}/bin/nixd"
        config_path: "${serenaNixdConfig}"
  '';
  serenaProjectConfig = pkgs.writeText "fomo-client-serena-project.yml" ''
    project_name: fomo-client
    languages:
      - kotlin
      - java
      - rust
      - cpp
      - nix
    language_backend: LSP
    read_only: true
    ignored_paths:
      - .devenv
      - .git
      - .gradle
      - .idea
      - .kotlin
      - .runtime
      - build
      - helios/target
      - logs
      - visibility-accelerator/target
    excluded_tools:
      - create_text_file
      - delete_lines
      - execute_shell_command
      - insert_after_symbol
      - insert_at_line
      - insert_before_symbol
      - replace_content
      - replace_lines
      - replace_symbol_body
      - write_memory
  '';
in
{
  inherit
    serenaJdtlsRoot
    serenaConfig
    serenaProjectConfig
    ;
}
