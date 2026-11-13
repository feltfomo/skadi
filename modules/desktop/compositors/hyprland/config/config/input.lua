hl.config({
	input = {
		touchpad = {
			-- the click's button comes from how many fingers press, not where. libinput's default
			-- splits the pad's bottom edge into button areas, and a finger resting there also stops
			-- two-finger scrolling.
			clickfinger_behavior = true,
			-- the pad otherwise ignores touches for a moment after each key, dropping scrolls
			-- that start right after typing.
			disable_while_typing = false,
		},
	},
})
