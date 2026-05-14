hl.config({
    general = {
        gaps_in = 5,
        gaps_out = 15,
        border_size = 0,
        layout = "dwindle"
    },

    decoration = {
        rounding = 10,
        rounding_power = 4,
        active_opacity = 0.9,
        inactive_opacity = 0.9,
        blur = {
            enabled = true,
            size = 10,
            passes = 3,
            new_optimizations = true,
        },
        shadow = {
            enabled = true,
            range = 16,
            render_power = 4,
        }
    },

    animations = {
        enabled = true,
    }
})
