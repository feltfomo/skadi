import os
from pathlib import Path
import re
import subprocess
import sys
import tomllib


root = Path(sys.argv[1])
manifest = tomllib.loads((root / "herdr-plugin.toml").read_text())
env = {key: value for key, value in os.environ.items() if not key.startswith(("HERDR_", "PICKR_", "LUA_"))}
env["PATH"] = ""
for action in manifest["actions"]:
    result = subprocess.run(action["command"], cwd=root, env=env, capture_output=True, text=True, timeout=10)
    assert result.returncode == 1 and "Pickr must be launched inside Herdr" in result.stderr, result

launcher = manifest["panes"][0]["command"][0]
result = subprocess.run([launcher, "src/main.lua", "preview", "-"], cwd=root, env=env, capture_output=True, text=True, timeout=10)
assert result.returncode == 0 and result.stdout == "No pane available for preview.\n", result

probe = """
package.path = './src/?.lua;' .. package.path
local uv, process = require('luv'), require('pickr.process')
local code, output, errors = process.run(assert(uv.exepath()), {'-e', "require('luv'); io.write('child loaded')"})
assert(code == 0 and output == 'child loaded', errors)
for _, command in ipairs({'fzf', 'herdr', 'cat'}) do
  code, output, errors = process.run(command, {'--version'})
  assert(code == 0 and #output > 0, errors)
end
"""
result = subprocess.run([launcher, "-e", probe], cwd=root, env=env, capture_output=True, text=True, timeout=20)
assert result.returncode == 0, result
shell = re.search(r'--with-shell=([^"\n]+) -c', (root / "src/pickr/core.lua").read_text()).group(1)
assert shell.startswith("/nix/store/")
shell_probe = f"""
package.path = './src/?.lua;' .. package.path
local code, output = require('pickr.process').run('{shell}', {{'-c', 'cat'}}, 'shell closure')
assert(code == 0 and output == 'shell closure')
"""
result = subprocess.run([launcher, "-e", shell_probe], cwd=root, env=env, capture_output=True, text=True, timeout=10)
assert result.returncode == 0, result
print("Packaged actions, preview, child Lua/luv and dependencies work with empty PATH")
