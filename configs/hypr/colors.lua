local M = {}

M.primary = "rgb({{colors.primary.default.hex_stripped}})"
M.on_primary = "rgb({{colors.on_primary.default.hex_stripped}})"
M.primary_container = "rgb({{colors.primary_container.default.hex_stripped}})"
M.on_primary_container = "rgb({{colors.on_primary_container.default.hex_stripped}})"

M.secondary = "rgb({{colors.secondary.default.hex_stripped}})"
M.on_secondary = "rgb({{colors.on_secondary.default.hex_stripped}})"
M.secondary_container = "rgb({{colors.secondary_container.default.hex_stripped}})"

M.tertiary = "rgb({{colors.tertiary.default.hex_stripped}})"
M.tertiary_container = "rgb({{colors.tertiary_container.default.hex_stripped}})"

M.error = "rgb({{colors.error.default.hex_stripped}})"
M.error_container = "rgb({{colors.error_container.default.hex_stripped}})"

M.surface = "rgb({{colors.surface.default.hex_stripped}})"
M.on_surface = "rgb({{colors.on_surface.default.hex_stripped}})"
M.surface_variant = "rgb({{colors.surface_variant.default.hex_stripped}})"
M.on_surface_variant = "rgb({{colors.on_surface_variant.default.hex_stripped}})"
M.surface_container = "rgb({{colors.surface_container.default.hex_stripped}})"
M.surface_container_high = "rgb({{colors.surface_container_high.default.hex_stripped}})"
M.surface_container_highest = "rgb({{colors.surface_container_highest.default.hex_stripped}})"
M.surface_container_low = "rgb({{colors.surface_container_low.default.hex_stripped}})"
M.surface_container_lowest = "rgb({{colors.surface_container_lowest.default.hex_stripped}})"

M.outline = "rgb({{colors.outline.default.hex_stripped}})"
M.outline_variant = "rgb({{colors.outline_variant.default.hex_stripped}})"

M.inverse_surface = "rgb({{colors.inverse_surface.default.hex_stripped}})"
M.inverse_primary = "rgb({{colors.inverse_primary.default.hex_stripped}})"

-- rgba variants for borders, shadows, transparency
M.primary_alpha = "rgba({{colors.primary.default.hex_stripped}}ee)"
M.surface_alpha = "rgba({{colors.surface.default.hex_stripped}}cc)"
M.outline_alpha = "rgba({{colors.outline.default.hex_stripped}}88)"
M.shadow_alpha = "rgba({{colors.shadow.default.hex_stripped}}aa)"

return M
