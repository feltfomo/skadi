local repo = assert(arg[1], "pass the repository root")
local fixture = assert(arg[2], "pass a scratch directory")
package.path = repo .. "/configs/nvim/lua/?.lua;" .. package.path
vim.fn.mkdir(fixture, "p")

local efm = require("config.task_output").errorformat
local items = vim.fn.getqflist({
	lines = {
		"> Task :client:compileKotlin FAILED",
		"e: file:///tmp/Example.kt:12:8 Unresolved reference 'example'.",
		"w: /tmp/Legacy.kt: (5, 9): Unused parameter",
		"/tmp/native.c:4:2: error: unknown type name 'example'",
		"/tmp/Style.kt:9:3: Function is too long [LongMethod]",
		"error[E0308]: mismatched types",
		"  --> /tmp/lib.rs:7:11",
		"   |",
		" 7 | example()",
		"   | ^^^^^^^ expected u32",
		"BUILD FAILED in 1s",
	},
	efm = efm,
}).items
items = vim.tbl_filter(function(item)
	return item.valid == 1
end, items)
assert(#items == 5, vim.inspect(items))
for index, expected in ipairs({
	{ "/tmp/Example.kt", 12, 8 },
	{ "/tmp/Legacy.kt", 5, 9 },
	{ "/tmp/native.c", 4, 2 },
	{ "/tmp/Style.kt", 9, 3 },
	{ "/tmp/lib.rs", 7, 11 },
}) do
	local item = items[index]
	assert(vim.api.nvim_buf_get_name(item.bufnr) == expected[1], vim.inspect(item))
	assert(item.lnum == expected[2] and item.col == expected[3], vim.inspect(item))
end
assert(items[5].text:find("mismatched types", 1, true))
assert(items[5].nr == 308)
local unrelated =
	vim.fn.getqflist({ lines = { "hello world", "BUILD SUCCESSFUL", "test result: ok" }, efm = efm }).items
assert(not vim.iter(unrelated):any(function(item)
	return item.valid == 1
end))

local nix = require("config.nix")
assert(vim.tbl_isempty(nix.settings(fixture)))
vim.fn.writefile({ "{}" }, fixture .. "/flake.nix")
local settings = nix.settings(fixture)
assert(settings.nixpkgs.expr:find(fixture, 1, true))
assert(settings.options.nixos.expr:find(vim.uv.os_gethostname(), 1, true))
vim.fn.writefile({ vim.json.encode(settings) }, fixture .. "/nix-settings.json")
print("IDE checks passed: Kotlin, C, Detekt and Rust locations; noise filtering; per-project Nix settings")
