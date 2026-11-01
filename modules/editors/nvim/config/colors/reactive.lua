vim.cmd("hi clear")
if vim.fn.exists("syntax_on") then
	vim.cmd("syntax reset")
end
vim.g.colors_name = "reactive"

local p = dofile(vim.fn.stdpath("config") .. "/lua/reactive/palette.lua")
-- fixed hues keep git and diagnostic colors meaning the same thing on every wallpaper
local s = require("mini.hues").make_palette({
	background = p.bg,
	foreground = p.fg,
	saturation = "mediumhigh",
	n_hues = 8,
})

local function oklab(hex)
	local value = tonumber(hex:sub(2), 16)
	local function linear(shift)
		local channel = bit.band(bit.rshift(value, shift), 255) / 255
		return channel <= 0.04045 and channel / 12.92 or ((channel + 0.055) / 1.055) ^ 2.4
	end
	local r, g, b = linear(16), linear(8), linear(0)
	local l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ^ (1 / 3)
	local m = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ^ (1 / 3)
	local c = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ^ (1 / 3)
	return 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * c,
		1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * c,
		0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * c
end

local function oklch_to_rgb(lightness, chroma, hue)
	local a, b = chroma * math.cos(hue), chroma * math.sin(hue)
	local l = (lightness + 0.3963377774 * a + 0.2158037573 * b) ^ 3
	local m = (lightness - 0.1055613458 * a - 0.0638541728 * b) ^ 3
	local c = (lightness - 0.0894841775 * a - 1.2914855480 * b) ^ 3
	return 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * c,
		-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * c,
		-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * c
end

local background_lightness = oklab(p.bg)
local _, primary_a, primary_b = oklab(p.primary)
local primary_hue = math.atan2(primary_b, primary_a)

-- syntax rotates around the wallpaper's hue, with lightness set per role so hues can't blend
-- together and every theme stays readable, however grey its material accents are
local function tone(degrees, dark, light, chroma)
	local lightness = background_lightness < 0.5 and dark or light
	local hue = primary_hue + math.rad(degrees)
	local r, g, b = oklch_to_rgb(lightness, chroma, hue)
	while math.min(r, g, b) < 0 or math.max(r, g, b) > 1 do
		chroma = chroma * 0.95
		r, g, b = oklch_to_rgb(lightness, chroma, hue)
	end
	local function encode(v)
		v = v <= 0.0031308 and v * 12.92 or 1.055 * v ^ (1 / 2.4) - 0.055
		return math.floor(v * 255 + 0.5)
	end
	return string.format("#%02x%02x%02x", encode(r), encode(g), encode(b))
end

local c = {
	func = tone(0, 0.84, 0.42, 0.11),
	type = tone(72, 0.88, 0.44, 0.1),
	string = tone(144, 0.82, 0.43, 0.11),
	constant = tone(216, 0.8, 0.45, 0.13),
	keyword = tone(288, 0.76, 0.45, 0.14),
	member = tone(0, 0.9, 0.34, 0.03),
	punctuation = tone(0, 0.7, 0.5, 0.02),
	comment = tone(0, 0.66, 0.52, 0.03),
}

local function hl(group, opts)
	vim.api.nvim_set_hl(0, group, opts)
end

local function mix(top, base, amount)
	local a, b = tonumber(top:sub(2), 16), tonumber(base:sub(2), 16)
	local mixed = 0
	for _, shift in ipairs({ 16, 8, 0 }) do
		local x, y = bit.band(bit.rshift(a, shift), 255), bit.band(bit.rshift(b, shift), 255)
		mixed = mixed + bit.lshift(math.floor(x * amount + y * (1 - amount) + 0.5), shift)
	end
	return string.format("#%06x", mixed)
end

-- panels share the editor's background so the terminal stays see-through and borders do the framing
local panel = p.bg
local hover = mix(p.primary, panel, 0.12)
local border = mix(p.primary, p.outline_variant, 0.35)
local strong_border = mix(p.primary, p.outline_variant, 0.65)

hl("Normal", { fg = p.fg, bg = p.bg })
hl("NormalNC", { link = "Normal" })
hl("NormalFloat", { fg = p.fg, bg = panel })
hl("FloatBorder", { fg = border, bg = panel })
hl("FloatTitle", { fg = p.primary, bg = panel, bold = true })
hl("FloatFooter", { fg = p.fg_muted, bg = panel })
hl("Cursor", { fg = p.bg, bg = p.fg })
hl("CursorLine", { bg = p.container })
hl("CursorColumn", { link = "CursorLine" })
hl("ColorColumn", { bg = p.container })
hl("LineNr", { fg = p.outline_variant })
hl("CursorLineNr", { fg = p.primary, bold = true })
hl("CursorLineSign", { link = "SignColumn" })
hl("CursorLineFold", { link = "FoldColumn" })
hl("SignColumn", { bg = p.bg })
hl("FoldColumn", { fg = p.outline_variant })
hl("Folded", { fg = p.fg_muted, bg = p.surface })
hl("StatusLine", { fg = p.fg, bg = p.container })
hl("StatusLineNC", { fg = p.fg_muted, bg = p.bg_dim })
hl("WinSeparator", { fg = border })
hl("TabLine", { fg = p.fg_muted, bg = p.bg })
hl("TabLineSel", { fg = p.fg, bg = panel, bold = true })
hl("TabLineFill", { bg = p.bg })
hl("Pmenu", { fg = p.fg, bg = panel })
hl("PmenuSel", { fg = p.on_primary_container, bg = p.primary_container })
hl("PmenuSbar", { bg = panel })
hl("PmenuThumb", { bg = border })
hl("PmenuKind", { fg = p.secondary })
hl("PmenuKindSel", { fg = p.on_secondary_container, bg = p.secondary_container })
hl("PmenuExtra", { fg = p.fg_muted })
hl("PmenuExtraSel", { fg = p.on_secondary_container, bg = p.secondary_container })
hl("PmenuMatch", { fg = p.primary, bold = true })
hl("PmenuMatchSel", { fg = p.on_primary_container, bg = p.primary_container, bold = true })
hl("Search", { fg = p.on_tertiary_container, bg = p.tertiary_container })
hl("IncSearch", { fg = p.on_tertiary, bg = p.tertiary })
hl("CurSearch", { link = "IncSearch" })
hl("Substitute", { link = "IncSearch" })
hl("Visual", { bg = p.primary_container })
hl("VisualNOS", { link = "Visual" })
hl("MatchParen", { fg = p.on_secondary_container, bg = p.secondary_container, bold = true })
hl("NonText", { fg = p.outline_variant })
hl("Whitespace", { link = "NonText" })
hl("SpecialKey", { link = "NonText" })
hl("Conceal", { fg = p.fg_muted })
hl("EndOfBuffer", { fg = p.bg })
hl("Directory", { fg = p.primary })
hl("Title", { fg = p.primary, bold = true })
hl("ModeMsg", { fg = p.fg_muted })
hl("MoreMsg", { fg = p.primary })
hl("Question", { fg = p.primary })
hl("WarningMsg", { fg = p.error })
hl("ErrorMsg", { fg = p.error })
hl("MsgSeparator", { fg = p.outline_variant })
hl("WinBar", { fg = p.fg_muted })
hl("WinBarNC", { fg = p.outline_variant })
hl("QuickFixLine", { bg = p.container })
hl("SpellBad", { undercurl = true, sp = p.error })
hl("SpellCap", { undercurl = true, sp = p.tertiary })
hl("SpellLocal", { undercurl = true, sp = p.secondary })
hl("SpellRare", { undercurl = true, sp = p.outline_variant })
hl("WildMenu", { link = "PmenuSel" })
hl("Comment", { fg = c.comment, italic = true })
hl("Constant", { fg = c.constant })
hl("String", { fg = c.string })
hl("Character", { link = "String" })
hl("Number", { fg = c.constant })
hl("Boolean", { link = "Constant" })
hl("Float", { link = "Number" })
hl("Identifier", { fg = p.fg })
hl("Function", { fg = c.func })
hl("Statement", { fg = c.keyword })
hl("Conditional", { link = "Keyword" })
hl("Repeat", { link = "Keyword" })
hl("Label", { fg = c.constant })
hl("Operator", { fg = c.punctuation })
hl("Keyword", { fg = c.keyword })
hl("Exception", { fg = s.red })
hl("PreProc", { fg = c.keyword })
hl("Include", { fg = c.keyword })
hl("Define", { fg = c.constant })
hl("Macro", { fg = c.constant })
hl("PreCondit", { link = "PreProc" })
hl("Type", { fg = c.type })
hl("StorageClass", { fg = c.keyword })
hl("Structure", { fg = c.type })
hl("Typedef", { link = "Type" })
hl("Special", { fg = c.constant })
hl("SpecialChar", { fg = c.constant })
hl("Tag", { fg = c.func })
hl("Delimiter", { fg = c.punctuation })
hl("SpecialComment", { fg = c.comment })
hl("Debug", { fg = s.red })
hl("Underlined", { fg = c.func, underline = true })
hl("Ignore", { fg = p.outline_variant })
hl("Error", { fg = p.error })
hl("Todo", { fg = p.on_tertiary_container, bg = p.tertiary_container, bold = true })
hl("Added", { fg = s.green })
hl("Changed", { fg = s.yellow })
hl("Removed", { fg = p.error })
hl("@variable", { fg = p.fg })
hl("@variable.builtin", { fg = c.keyword })
hl("@variable.parameter", { fg = p.fg })
hl("@variable.member", { fg = c.member })
hl("@constant", { link = "Constant" })
hl("@constant.builtin", { link = "Constant" })
hl("@constant.macro", { link = "Macro" })
hl("@module", { fg = p.fg })
hl("@label", { link = "Label" })
hl("@string", { link = "String" })
hl("@string.documentation", { link = "String" })
hl("@string.escape", { fg = c.constant })
hl("@string.special", { link = "SpecialChar" })
hl("@character", { link = "Character" })
hl("@character.special", { link = "SpecialChar" })
hl("@boolean", { link = "Boolean" })
hl("@number", { link = "Number" })
hl("@number.float", { link = "Float" })
hl("@float", { link = "Float" })
hl("@function", { link = "Function" })
hl("@function.builtin", { link = "Function" })
hl("@function.call", { link = "Function" })
hl("@function.macro", { link = "Macro" })
hl("@function.method", { link = "Function" })
hl("@function.method.call", { link = "Function" })
hl("@constructor", { fg = c.type })
hl("@operator", { link = "Operator" })
hl("@keyword", { link = "Keyword" })
hl("@keyword.function", { fg = c.keyword })
hl("@keyword.operator", { fg = c.keyword })
hl("@keyword.import", { link = "Include" })
hl("@keyword.type", { fg = c.keyword })
hl("@keyword.modifier", { fg = c.keyword })
hl("@keyword.repeat", { fg = c.keyword })
hl("@keyword.return", { fg = c.keyword })
hl("@keyword.conditional", { fg = c.keyword })
hl("@keyword.exception", { fg = s.red })
hl("@keyword.coroutine", { fg = c.keyword })
hl("@keyword.debug", { link = "Debug" })
hl("@keyword.directive", { link = "PreProc" })
hl("@keyword.directive.define", { link = "Define" })
hl("@type", { link = "Type" })
hl("@type.builtin", { link = "Type" })
hl("@type.definition", { link = "Typedef" })
hl("@type.qualifier", { fg = c.keyword })
hl("@attribute", { fg = c.constant })
hl("@property", { fg = c.member })
hl("@punctuation.delimiter", { link = "Delimiter" })
hl("@punctuation.bracket", { fg = c.punctuation })
hl("@punctuation.special", { fg = c.punctuation })
hl("@comment", { link = "Comment" })
hl("@comment.documentation", { fg = c.comment, italic = true })
hl("@comment.error", { fg = p.error })
hl("@comment.warning", { fg = s.yellow })
hl("@comment.note", { fg = s.cyan })
hl("@comment.todo", { link = "Todo" })
hl("@markup.heading", { fg = c.func, bold = true })
hl("@markup.link", { fg = c.func })
hl("@markup.link.label", { fg = c.member })
hl("@markup.link.url", { fg = c.func, underline = true })
hl("@markup.raw", { fg = c.string })
hl("@markup.quote", { fg = c.comment, italic = true })
hl("@markup.list", { fg = c.member })
hl("@markup.strong", { bold = true })
hl("@markup.italic", { italic = true })
hl("@markup.strikethrough", { strikethrough = true })
hl("@markup.underline", { underline = true })
hl("@tag", { fg = c.func })
hl("@tag.builtin", { fg = c.func })
hl("@tag.attribute", { fg = c.member })
hl("@tag.delimiter", { fg = c.punctuation })
hl("@diff.plus", { fg = s.green })
hl("@diff.minus", { fg = p.error })
hl("@diff.delta", { fg = s.yellow })
hl("@none", {})
for group, target in pairs({
	class = "@type",
	interface = "@type",
	struct = "@type",
	enum = "@type",
	type = "@type",
	typeParameter = "@type",
	namespace = "@module",
	variable = "@variable",
	parameter = "@variable.parameter",
	property = "@property",
	enumMember = "@constant",
	["function"] = "@function",
	method = "@function.method",
	macro = "@function.macro",
	decorator = "@attribute",
	keyword = "@keyword",
	string = "@string",
	number = "@number",
	operator = "@operator",
}) do
	hl("@lsp.type." .. group, { link = target })
end
hl("@lsp.typemod.variable.readonly", { link = "Constant" })
hl("@lsp.typemod.property.readonly", { link = "Constant" })
hl("@lsp.mod.deprecated", { strikethrough = true })

for level, color in ipairs({ c.func, c.keyword, c.string, c.constant, c.member, c.type }) do
	hl("@markup.heading." .. level, { fg = color, bold = true })
	hl("RenderMarkdownH" .. level, { fg = color, bold = true })
	hl("RenderMarkdownH" .. level .. "Bg", { bg = p.container })
end
hl("RenderMarkdownCode", { bg = p.container })
hl("RenderMarkdownCodeInline", { fg = c.string, bg = p.container })
hl("RenderMarkdownTableHead", { fg = c.func, bold = true })
hl("RenderMarkdownTableRow", { fg = c.punctuation })
hl("RenderMarkdownBullet", { fg = c.member })
hl("RenderMarkdownChecked", { fg = s.green })
hl("RenderMarkdownUnchecked", { fg = c.punctuation })
hl("DiagnosticError", { fg = p.error })
hl("DiagnosticWarn", { fg = s.yellow })
hl("DiagnosticInfo", { fg = s.cyan })
hl("DiagnosticHint", { fg = p.fg_muted })
hl("DiagnosticOk", { fg = s.green })
hl("DiagnosticVirtualTextError", { fg = p.error, bg = p.error_container })
hl("DiagnosticVirtualTextWarn", { fg = s.yellow, bg = p.tertiary_container })
hl("DiagnosticVirtualTextInfo", { fg = s.cyan, bg = p.secondary_container })
hl("DiagnosticVirtualTextHint", { fg = p.fg_muted, bg = p.surface })
hl("DiagnosticVirtualTextOk", { fg = s.green, bg = p.surface })
hl("DiagnosticUnderlineError", { undercurl = true, sp = p.error })
hl("DiagnosticUnderlineWarn", { undercurl = true, sp = s.yellow })
hl("DiagnosticUnderlineInfo", { undercurl = true, sp = s.cyan })
hl("DiagnosticUnderlineHint", { undercurl = true, sp = p.outline_variant })
hl("DiagnosticUnderlineOk", { undercurl = true, sp = p.green })
hl("DiagnosticFloatingError", { link = "DiagnosticError" })
hl("DiagnosticFloatingWarn", { link = "DiagnosticWarn" })
hl("DiagnosticFloatingInfo", { link = "DiagnosticInfo" })
hl("DiagnosticFloatingHint", { link = "DiagnosticHint" })
hl("DiagnosticFloatingOk", { link = "DiagnosticOk" })
hl("DiagnosticSignError", { link = "DiagnosticError" })
hl("DiagnosticSignWarn", { link = "DiagnosticWarn" })
hl("DiagnosticSignInfo", { link = "DiagnosticInfo" })
hl("DiagnosticSignHint", { link = "DiagnosticHint" })
hl("DiagnosticSignOk", { link = "DiagnosticOk" })
hl("DiagnosticDeprecated", { strikethrough = true, sp = p.error })
hl("DiagnosticUnnecessary", { underline = true, sp = s.fg_mid2 })
hl("DiffAdd", { fg = s.green, bg = p.surface })
hl("DiffChange", { fg = s.yellow, bg = p.surface })
hl("DiffDelete", { fg = p.error, bg = p.surface })
hl("DiffText", { fg = p.on_tertiary_container, bg = p.tertiary_container })
hl("diffAdded", { link = "Added" })
hl("diffRemoved", { link = "Removed" })
hl("diffChanged", { link = "Changed" })
hl("diffOldFile", { fg = p.error })
hl("diffNewFile", { fg = s.green })
hl("diffFile", { fg = p.primary })
hl("diffLine", { fg = p.fg_muted })
hl("diffIndexLine", { fg = p.secondary })
hl("GitSignsAdd", { fg = s.green })
hl("GitSignsChange", { fg = s.yellow })
hl("GitSignsDelete", { fg = p.error })
hl("GitSignsChangedelete", { fg = s.yellow })
hl("GitSignsTopdelete", { fg = p.error })
hl("GitSignsUntracked", { fg = p.outline_variant })
hl("GitSignsCurrentLineBlame", { fg = p.outline_variant, italic = true })
hl("LspReferenceText", { bg = p.container })
hl("LspReferenceRead", { bg = p.container })
hl("LspReferenceWrite", { bg = p.container_high })
hl("LspInlayHint", { fg = p.outline })
hl("LspCodeLens", { fg = p.outline_variant })
hl("LspSignatureActiveParameter", { fg = p.on_tertiary_container, bg = p.tertiary_container })
hl("TelescopeNormal", { link = "NormalFloat" })
hl("TelescopePromptNormal", { fg = p.fg, bg = panel })
hl("TelescopeResultsNormal", { link = "TelescopeNormal" })
hl("TelescopePreviewNormal", { link = "TelescopeNormal" })
hl("TelescopeBorder", { link = "FloatBorder" })
hl("TelescopePromptBorder", { fg = border, bg = panel })
hl("TelescopeResultsBorder", { link = "TelescopeBorder" })
hl("TelescopePreviewBorder", { link = "TelescopeBorder" })
hl("TelescopeTitle", { link = "FloatTitle" })
hl("TelescopePromptTitle", { link = "FloatTitle" })
hl("TelescopeResultsTitle", { fg = p.fg_muted })
hl("TelescopePreviewTitle", { fg = p.fg_muted })
hl("TelescopePromptPrefix", { fg = p.primary, bg = panel })
hl("TelescopePromptCounter", { fg = p.fg_muted, bg = panel })
-- an accent fill would swallow match colors, which telescope paints over the selection
hl("TelescopeSelection", { fg = p.fg, bg = p.primary_container, bold = true })
hl("TelescopeSelectionCaret", { fg = p.primary, bg = p.primary_container })
hl("TelescopeMultiSelection", { fg = p.secondary, bold = true })
hl("TelescopeMultiIcon", { fg = p.secondary })
hl("TelescopeMatching", { fg = p.tertiary, bold = true })
hl("TelescopePreviewLine", { bg = hover })
hl("TelescopePreviewMatch", { fg = p.tertiary, bold = true })
hl("TelescopeResultsLineNr", { fg = p.outline })
hl("TelescopeResultsComment", { fg = p.fg_muted, italic = true })
hl("TelescopeResultsDiffAdd", { fg = s.green })
hl("TelescopeResultsDiffChange", { fg = s.yellow })
hl("TelescopeResultsDiffDelete", { fg = p.error })
hl("TelescopeResultsDiffUntracked", { fg = p.fg_muted })
hl("BlinkCmpMenu", { link = "Pmenu" })
hl("BlinkCmpMenuBorder", { link = "FloatBorder" })
hl("BlinkCmpMenuSelection", { link = "PmenuSel" })
hl("BlinkCmpScrollBarThumb", { link = "PmenuThumb" })
hl("BlinkCmpScrollBarGutter", { link = "PmenuSbar" })
hl("BlinkCmpLabel", { fg = p.fg })
hl("BlinkCmpLabelDeprecated", { fg = p.outline_variant, strikethrough = true })
hl("BlinkCmpLabelMatch", { fg = p.primary, bold = true })
hl("BlinkCmpLabelDetail", { fg = p.fg_muted })
hl("BlinkCmpLabelDescription", { fg = p.fg_muted })
hl("BlinkCmpKind", { fg = p.secondary })
hl("BlinkCmpSource", { fg = p.outline_variant })
hl("BlinkCmpGhostText", { fg = p.outline_variant })
hl("BlinkCmpDoc", { link = "NormalFloat" })
hl("BlinkCmpDocBorder", { link = "FloatBorder" })
hl("BlinkCmpDocSeparator", { fg = border, bg = panel })
hl("BlinkCmpSignatureHelp", { link = "NormalFloat" })
hl("BlinkCmpSignatureHelpBorder", { link = "FloatBorder" })
hl("LazyNormal", { link = "NormalFloat" })
hl("LazyButton", { fg = p.fg, bg = panel })
hl("LazyButtonActive", { fg = p.on_primary_container, bg = p.primary_container })
hl("LazyH1", { fg = p.on_primary, bg = p.primary })
hl("LazyH2", { fg = p.primary, bold = true })
hl("LazySpecial", { fg = p.secondary })
hl("LazyProgressDone", { fg = p.primary })
hl("LazyProgressTodo", { fg = p.outline_variant })
hl("LazyReasonPlugin", { fg = p.tertiary })
hl("NoiceCmdlinePopup", { link = "NormalFloat" })
hl("NoiceCmdlinePopupBorder", { fg = strong_border, bg = panel })
hl("NoiceCmdlinePopupTitle", { link = "FloatTitle" })
hl("NoicePopup", { link = "NormalFloat" })
hl("NoicePopupBorder", { link = "FloatBorder" })
hl("NoicePopupmenu", { link = "Pmenu" })
hl("NoicePopupmenuBorder", { link = "FloatBorder" })
hl("NoicePopupmenuSelected", { link = "PmenuSel" })
hl("NoicePopupmenuMatch", { fg = p.primary, bold = true })
hl("NoiceMini", { fg = p.fg_muted, bg = panel })
hl("ScrollView", { bg = border })
hl("ScrollViewHover", { bg = p.primary })
hl("ScrollViewRestricted", { link = "ScrollView" })
hl("SnacksIndent", { fg = p.outline_variant })
hl("SnacksIndentScope", { fg = p.primary })
hl("SnacksNotifierHistory", { link = "NormalFloat" })
hl("SnacksNotifierHistoryTitle", { link = "FloatTitle" })
hl("SnacksIndentChunk", { fg = p.primary })
for level, color in pairs({ Info = s.cyan, Warn = s.yellow, Error = p.error, Debug = p.fg_muted, Trace = p.outline }) do
	hl("SnacksNotifier" .. level, { fg = p.fg, bg = panel })
	hl("SnacksNotifierIcon" .. level, { fg = color, bg = panel })
	hl("SnacksNotifierTitle" .. level, { fg = color, bg = panel, bold = true })
	hl("SnacksNotifierBorder" .. level, { fg = border, bg = panel })
	hl("SnacksNotifierFooter" .. level, { fg = p.fg_muted, bg = panel })
end
hl("SnacksInputNormal", { fg = p.fg, bg = panel })
hl("SnacksInputBorder", { fg = strong_border, bg = panel })
hl("SnacksInputTitle", { link = "FloatTitle" })
hl("SnacksInputIcon", { fg = p.primary, bg = panel })
hl("SnacksDashboardHeader", { fg = p.primary })
hl("SnacksDashboardTitle", { fg = p.primary, bold = true })
hl("SnacksDashboardDesc", { fg = p.fg })
hl("SnacksDashboardKey", { fg = p.tertiary, bold = true })
hl("SnacksDashboardIcon", { fg = p.primary })
hl("SnacksDashboardDir", { fg = p.fg_muted })
hl("SnacksDashboardFile", { fg = p.fg })
hl("SnacksDashboardFooter", { fg = p.fg_muted })
hl("SnacksDashboardSpecial", { fg = p.tertiary })

-- side panels sit on the editor's own background and rely on the separator, not a second fill
hl("NeoTreeNormal", { fg = p.fg, bg = p.bg })
hl("NeoTreeNormalNC", { link = "NeoTreeNormal" })
hl("NeoTreeEndOfBuffer", { fg = p.bg, bg = p.bg })
hl("NeoTreeSignColumn", { link = "NeoTreeNormal" })
hl("NeoTreeWinSeparator", { fg = border, bg = p.bg })
hl("NeoTreeVertSplit", { link = "NeoTreeWinSeparator" })
hl("NeoTreeCursorLine", { bg = p.primary_container, bold = true })
hl("NeoTreeRootName", { fg = p.primary, bold = true })
hl("NeoTreeDirectoryIcon", { fg = p.primary })
hl("NeoTreeDirectoryName", { fg = p.fg })
hl("NeoTreeFileName", { fg = p.fg })
hl("NeoTreeFileNameOpened", { fg = p.primary })
hl("NeoTreeIndentMarker", { fg = border })
hl("NeoTreeExpander", { fg = p.outline })
hl("NeoTreeDimText", { fg = p.outline })
hl("NeoTreeDotfile", { fg = p.fg_muted })
hl("NeoTreeGitAdded", { fg = s.green })
hl("NeoTreeGitModified", { fg = s.yellow })
hl("NeoTreeGitDeleted", { fg = p.error })
hl("NeoTreeGitConflict", { fg = p.error, bold = true })
hl("NeoTreeGitUntracked", { fg = p.fg_muted })
hl("NeoTreeGitIgnored", { fg = p.outline })
hl("NeoTreeGitStaged", { fg = s.green })
hl("NeoTreeGitUnstaged", { fg = s.yellow })
hl("NeoTreeTabActive", { fg = p.fg, bg = panel, bold = true })
hl("NeoTreeTabInactive", { fg = p.fg_muted, bg = p.bg })
hl("NeoTreeTabSeparatorActive", { fg = p.primary, bg = panel })
hl("NeoTreeTabSeparatorInactive", { fg = p.bg, bg = p.bg })
hl("NeoTreeFloatBorder", { link = "FloatBorder" })
hl("NeoTreeFloatNormal", { link = "NormalFloat" })
hl("NeoTreeFloatTitle", { link = "FloatTitle" })
hl("NeoTreeTitleBar", { fg = p.on_primary, bg = p.primary, bold = true })
hl("TroubleNormal", { fg = p.fg, bg = p.bg })
hl("TroubleNormalNC", { link = "TroubleNormal" })
hl("TroubleCount", { fg = p.primary, bold = true })
hl("TroubleText", { fg = p.fg })
hl("TroublePos", { fg = p.outline })

hl("WhichKey", { fg = p.primary, bold = true })
hl("WhichKeyGroup", { fg = p.tertiary })
hl("WhichKeyDesc", { fg = p.fg })
hl("WhichKeySeparator", { fg = p.outline })
hl("WhichKeyValue", { fg = p.fg_muted })
hl("WhichKeyIcon", { fg = p.primary })
hl("DropBarMenuHoverEntry", { fg = p.on_primary, bg = p.primary })
hl("DropBarMenuCurrentContext", { fg = p.fg, bg = hover })
hl("DropBarCurrentContext", { fg = p.fg, bg = hover })
hl("DropBarHover", { fg = p.fg, bg = hover })
hl("TreesitterContext", { bg = panel })
hl("TreesitterContextLineNumber", { fg = p.outline, bg = panel })
hl("TreesitterContextBottom", { underline = true, sp = border })
hl("TreesitterContextLineNumberBottom", { fg = p.outline, bg = panel, underline = true, sp = border })
hl("FlashBackdrop", { fg = p.outline })
hl("FlashMatch", { fg = p.on_tertiary_container, bg = p.tertiary_container })
hl("FlashCurrent", { fg = p.on_tertiary, bg = p.tertiary })
hl("FlashLabel", { fg = p.on_primary, bg = p.primary, bold = true })
hl("OilDir", { link = "Directory" })
hl("DiffviewNormal", { link = "Normal" })
hl("DiffviewFilePanelTitle", { fg = p.primary, bold = true })
hl("DiffviewFilePanelCounter", { fg = p.fg_muted })
hl("DiffviewWinSeparator", { link = "WinSeparator" })
hl("DapBreakpoint", { fg = p.error })
hl("DapStopped", { fg = s.yellow })
hl("DapStoppedLine", { bg = hover })
for name, color in pairs({
	Red = s.red,
	Yellow = s.yellow,
	Blue = s.azure,
	Orange = s.orange,
	Green = s.green,
	Violet = s.purple,
	Cyan = s.cyan,
}) do
	hl("RainbowDelimiter" .. name, { fg = color })
end
for name, color in pairs({
	Azure = s.azure,
	Blue = s.blue,
	Cyan = s.cyan,
	Green = s.green,
	Grey = p.fg_muted,
	Orange = s.orange,
	Purple = s.purple,
	Red = s.red,
	Yellow = s.yellow,
}) do
	hl("MiniIcons" .. name, { fg = color })
end

vim.g.terminal_color_background = p.bg
vim.g.terminal_color_foreground = p.fg
for i, c in ipairs(p.term) do
	vim.g["terminal_color_" .. (i - 1)] = c
end
