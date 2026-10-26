local M = {}

M.errorformat = table.concat({
	"%t: file://%f:%l:%c %m",
	[[%t: %f: (%l\, %c): %m]],
	"%f:%l:%c: %t%*[^:]: %m",
	"%f:%l: %t%*[^:]: %m",
	"%f:%l:%c: %m",
	"%Eerror[E%n]: %m",
	"%Eerror: %m",
	"%Wwarning: %m",
	"%C %#--> %f:%l:%c",
	"%-G%.%#",
}, ",")

return M
