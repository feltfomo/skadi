hl.config({
	input = {
		touchpad = {
			-- the click's button comes from how many fingers press, not where. libinput's default
			-- splits the pad's bottom edge into button areas, and a finger resting there also stops
			-- two-finger scrolling.
			clickfinger_behavior = true,
		},
	},
})
