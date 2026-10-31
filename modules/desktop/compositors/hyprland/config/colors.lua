local M = {}

M.primary = "rgb({{ primary.bare }})"
M.on_primary = "rgb({{ onPrimary.bare }})"
M.primary_container = "rgb({{ primaryContainer.bare }})"
M.on_primary_container = "rgb({{ onPrimaryContainer.bare }})"

M.secondary = "rgb({{ secondary.bare }})"
M.on_secondary = "rgb({{ onSecondary.bare }})"
M.secondary_container = "rgb({{ secondaryContainer.bare }})"

M.tertiary = "rgb({{ tertiary.bare }})"
M.tertiary_container = "rgb({{ tertiaryContainer.bare }})"

M.error = "rgb({{ error.bare }})"
M.error_container = "rgb({{ errorContainer.bare }})"

M.surface = "rgb({{ surface.bare }})"
M.on_surface = "rgb({{ onSurface.bare }})"
M.surface_variant = "rgb({{ surfaceVariant.bare }})"
M.on_surface_variant = "rgb({{ onSurfaceVariant.bare }})"
M.surface_container = "rgb({{ surfaceContainer.bare }})"
M.surface_container_high = "rgb({{ surfaceContainerHigh.bare }})"
M.surface_container_highest = "rgb({{ surfaceContainerHighest.bare }})"
M.surface_container_low = "rgb({{ surfaceContainerLow.bare }})"
M.surface_container_lowest = "rgb({{ surfaceContainerLowest.bare }})"

M.outline = "rgb({{ outline.bare }})"
M.outline_variant = "rgb({{ outlineVariant.bare }})"

M.inverse_surface = "rgb({{ inverseSurface.bare }})"
M.inverse_primary = "rgb({{ inversePrimary.bare }})"

-- rgba variants for borders, shadows, transparency
M.primary_alpha = "rgba({{ primary.bare }}ee)"
M.surface_alpha = "rgba({{ surface.bare }}cc)"
M.outline_alpha = "rgba({{ outline.bare }}88)"
M.shadow_alpha = "rgba({{ shadow.bare }}aa)"

return M
