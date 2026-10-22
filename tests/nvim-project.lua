local repo = assert(arg[1], "pass the repository root")
local fixture = (arg[2] or repo .. "/.runtime/nvim-workbench/project-fixture") .. "/" .. vim.uv.hrtime()
package.path = repo .. "/configs/nvim/lua/?.lua;" .. package.path

local function write(path, content)
	vim.fn.mkdir(vim.fs.dirname(path), "p")
	vim.fn.writefile(content or {}, path)
end

vim.fn.mkdir(fixture, "p")
assert(vim.system({ "git", "init", "-q", fixture }):wait().code == 0)
write(fixture .. "/.gitignore", { "**/build/", "**/target/", ".gradle/" })
write(fixture .. "/settings.gradle.kts")
write(fixture .. "/build.gradle.kts")
write(fixture .. "/client/deep module/build.gradle.kts")
write(fixture .. "/client/deep module/src/main/kotlin/example/Example.kt")
write(fixture .. "/client/deep module/build/generated/build.gradle.kts")
write(fixture .. "/helios/Cargo.toml")
write(fixture .. "/helios/crates/agent/Cargo.toml")
write(fixture .. "/helios/crates/agent/src/lib.rs")
write(fixture .. "/helios/target/generated/Cargo.toml")
write(fixture .. "/.gradle/cache/build.gradle.kts")

local project = require("config.project")
local modules = project.modules(fixture)
assert(
	vim.deep_equal(modules, {
		fixture,
		fixture .. "/client/deep module",
		fixture .. "/helios",
		fixture .. "/helios/crates/agent",
	}),
	vim.inspect(modules)
)

local cwd = vim.fn.getcwd()
vim.cmd.edit(vim.fn.fnameescape(fixture .. "/client/deep module/src/main/kotlin/example/Example.kt"))
assert(project.root() == fixture)
assert(project.module_root() == fixture .. "/client/deep module")
vim.cmd.edit(vim.fn.fnameescape(fixture .. "/helios/crates/agent/src/lib.rs"))
assert(project.root() == fixture)
assert(project.module_root() == fixture .. "/helios/crates/agent")
assert(vim.fn.getcwd() == cwd, "navigation changed the working directory")

local standalone = fixture .. "/standalone"
write(standalone .. "/build.gradle")
assert(vim.deep_equal(project.modules(standalone), { standalone }))
print("project navigation passed: nested modules, untracked manifests, ignored output, spaces, and stable cwd")
