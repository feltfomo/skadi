local M = {}

M.primary = "rgb({{ primary.hex }})"
M.on_primary = "rgb({{ onPrimary.hex }})"
M.primary_container = "rgb({{ primaryContainer.hex }})"
M.on_primary_container = "rgb({{ onPrimaryContainer.hex }})"

M.secondary = "rgb({{ secondary.hex }})"
M.on_secondary = "rgb({{ onSecondary.hex }})"
M.secondary_container = "rgb({{ secondaryContainer.hex }})"

M.tertiary = "rgb({{ tertiary.hex }})"
M.tertiary_container = "rgb({{ tertiaryContainer.hex }})"

M.error = "rgb({{ error.hex }})"
M.error_container = "rgb({{ errorContainer.hex }})"

M.surface = "rgb({{ surface.hex }})"
M.on_surface = "rgb({{ onSurface.hex }})"
M.surface_variant = "rgb({{ surfaceVariant.hex }})"
M.on_surface_variant = "rgb({{ onSurfaceVariant.hex }})"
M.surface_container = "rgb({{ surfaceContainer.hex }})"
M.surface_container_high = "rgb({{ surfaceContainerHigh.hex }})"
M.surface_container_highest = "rgb({{ surfaceContainerHighest.hex }})"
M.surface_container_low = "rgb({{ surfaceContainerLow.hex }})"
M.surface_container_lowest = "rgb({{ surfaceContainerLowest.hex }})"

M.outline = "rgb({{ outline.hex }})"
M.outline_variant = "rgb({{ outlineVariant.hex }})"

M.inverse_surface = "rgb({{ inverseSurface.hex }})"
M.inverse_primary = "rgb({{ inversePrimary.hex }})"

M.primary_alpha = "rgba({{ primary.hex }}ee)"
M.surface_alpha = "rgba({{ surface.hex }}cc)"
M.outline_alpha = "rgba({{ outline.hex }}88)"
M.shadow_alpha = "rgba({{ shadow.hex }}aa)"

return M
