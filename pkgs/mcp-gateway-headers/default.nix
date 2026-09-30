{ pkgs }:
let
  config = builtins.fromJSON (builtins.readFile ../../configs/pi/mcp-adapter.json);
in
pkgs.writeScriptBin config.mcpServers.desktop-commander.requestHeadersCommand.command ''
  #!${pkgs.python3}/bin/python3
  import json
  import os
  import pathlib
  import shlex
  import sys

  if len(sys.argv) != 1:
      sys.exit("No arguments expected")
  token = os.environ.get("DESKTOP_COMMANDER_MCP_TOKEN")
  if not token:
      secret = pathlib.Path(os.environ.get("MCP_GATEWAY_TOKEN_FILE", "/run/secrets/desktop-commander-mcp-token"))
      for line in secret.read_text().splitlines():
          key, separator, value = line.partition("=")
          if separator and key.strip() == "DESKTOP_COMMANDER_MCP_TOKEN":
              values = shlex.split(value, comments=True)
              if len(values) == 1:
                  token = values[0]
  if not token or any(character.isspace() for character in token):
      sys.exit("Gateway token is missing or invalid")
  print(json.dumps({"Authorization": "Bearer " + token}))
''
