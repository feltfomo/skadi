return {
	"mfussenegger/nvim-dap",
	dependencies = {
		"rcarriga/nvim-dap-ui",
		"nvim-neotest/nvim-nio",
		{ "theHamsta/nvim-dap-virtual-text", opts = {} },
	},
	keys = {
		{
			"<leader>db",
			function()
				require("dap").toggle_breakpoint()
			end,
			desc = "Toggle Breakpoint",
		},
		{
			"<leader>dB",
			function()
				require("dap").set_breakpoint(vim.fn.input("Condition: "))
			end,
			desc = "Conditional Breakpoint",
		},
		{
			"<leader>dc",
			function()
				require("dap").continue()
			end,
			desc = "Continue / Start Debugging",
		},
		{
			"<leader>di",
			function()
				require("dap").step_into()
			end,
			desc = "Step Into",
		},
		{
			"<leader>do",
			function()
				require("dap").step_over()
			end,
			desc = "Step Over",
		},
		{
			"<leader>dO",
			function()
				require("dap").step_out()
			end,
			desc = "Step Out",
		},
		{
			"<leader>dq",
			function()
				require("dap").terminate()
			end,
			desc = "Stop Debugging",
		},
		{
			"<leader>du",
			function()
				require("dapui").toggle()
			end,
			desc = "Toggle Debug Windows",
		},
		{
			"<leader>de",
			function()
				require("dapui").eval()
			end,
			desc = "Evaluate Expression",
			mode = { "n", "x" },
		},
	},
	config = function()
		local dap = require("dap")
		local ui = require("dapui")
		ui.setup({
			layouts = {
				{ elements = { "scopes", "watches", "stacks", "breakpoints" }, size = 40, position = "right" },
				{ elements = { "repl", "console" }, size = 0.25, position = "bottom" },
			},
		})
		dap.listeners.after.event_initialized["editor_ui"] = function()
			ui.open()
		end
		dap.listeners.before.event_terminated["editor_ui"] = function()
			ui.close()
		end
		dap.listeners.before.event_exited["editor_ui"] = function()
			ui.close()
		end
		dap.configurations.java = {
			{
				type = "java",
				request = "attach",
				name = "Attach to local JVM",
				hostName = "127.0.0.1",
				port = function()
					local port = tonumber(vim.fn.input("JVM debug port: ", "5005"))
					return port and port >= 1 and port <= 65535 and port or dap.ABORT
				end,
			},
		}
	end,
}
