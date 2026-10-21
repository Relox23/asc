--[[
	Config
	Settings of the intro cutscene "Awaken" (docs/intro/DESIGN.md §7.5).
]]

return {
	-- where the space stage is built (far past the world border, nothing else there)
	SPACE_ORIGIN = CFrame.new(0, 3000, 40000),
	-- "auto" = the Sylverune spawn circle (moved toward the hub), or a Vector3 on the ground
	LANDING = "auto",
	LANDING_OFFSET_TO_HUB = 14,
	-- trees within this distance of the landing point bend in the shockwave wind
	WIND_RADIUS = 320,
	-- the server script gives the player the real sword when the cutscene ends
	GIVE_SWORD = true,
	-- Studio play tests only: this key replays the intro with TEST_COLOR
	TEST_IN_STUDIO_KEY = Enum.KeyCode.F7,
	TEST_COLOR = Color3.fromRGB(120, 200, 255),
	-- optional "rbxassetid://..." image for the view through the rift (used when the import lost its texture)
	RIFT_VIEW_IMAGE = "",
	-- sound ids ("rbxassetid://..." or just the number) for the sound:<name> markers; "" = silent
	SOUNDS = {
		ignite = "",
		whoosh = "",
		crack = "",
		rift = "",
		impact = "",
		resonance = "",
		shockwave = "",
		wind = "",
		land = "",
	},
	-- let the player skip (Space / Enter / gamepad A / tap); shows a small hint
	ALLOW_SKIP = false,

	-- additions to DESIGN §7.5 ------------------------------------------------------------------
	-- longest frame step the cutscene clock takes (a long hitch slows the cutscene instead of
	-- jumping over whole shots; markers in between still fire in order)
	MAX_FRAME_DT = 0.25,
	-- hide the game's other ScreenGuis and the backpack / player list / health / emotes core GUI
	HIDE_GUI = true,
	-- print every marker as it fires (debugging)
	DEBUG = false,
}
