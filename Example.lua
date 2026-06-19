--[[
	Example: rebuilding the original Korona layout (Bot / Visuals / Misc tabs,
	"Day" / "World" / "Other" groupboxes, a Settings tab with live theme colors
	and the config save/load system) using the new Library.

	This file is just a USAGE EXAMPLE for your own script — it only wires up the
	UI (tabs, groupboxes, elements, callbacks). It intentionally contains no
	actual game-feature logic; fill in each Callback with whatever your script
	is supposed to do.

	Replace YOUR_USER / YOUR_REPO / BRANCH below once this is pushed to GitHub.
]]

local BASE = "https://raw.githubusercontent.com/christianfbi19/birkanizblue/main/"

local Library = loadstring(game:HttpGet(BASE .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(BASE .. "addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(BASE .. "addons/SaveManager.lua"))()

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:SetFolder("Korona")

local Window = Library:CreateWindow({
	Title = "Korona",
	Subtitle = "v1",
	Size = UDim2.fromOffset(448, 416),
	ToggleKeybind = Enum.KeyCode.RightShift, -- press to show/hide the whole menu
})

local Tabs = {
	Bot = Window:AddTab("Bot"),
	Visuals = Window:AddTab("Visuals"),
	Misc = Window:AddTab("Misc"),
	Settings = Window:AddTab("Settings"),
}

--// Bot tab — "Day" groupbox (left column) ----------------------------------

local Day = Tabs.Bot:AddLeftGroupbox("Day")

Day:AddToggle("DayEnabled", {
	Text = "Enabled",
	Default = false,
	Callback = function(value)
		-- your feature toggle logic goes here
		print("Day.Enabled =", value)
	end,
}):AddColorPicker("DayColor", {
	Default = Color3.fromRGB(74, 255, 117),
	Callback = function(color)
		print("Day.Color =", color)
	end,
})

Day:AddToggle("DayNegative", {
	Text = "Negative",
	Default = false,
	Callback = function(value)
		print("Day.Negative =", value)
	end,
})

Day:AddKeybind("DayKeybind", {
	Text = "Key (Hold)",
	Default = Enum.KeyCode.O,
	Mode = "Hold",
	Callback = function(active)
		print("Day key active:", active)
	end,
})

Day:AddSlider("DayTransparency", {
	Text = "Transparency",
	Min = 0,
	Max = 100,
	Default = 48,
	Suffix = "%",
	Callback = function(value)
		print("Day.Transparency =", value)
	end,
})

--// Bot tab — "World" groupbox (right column) -------------------------------

local World = Tabs.Bot:AddRightGroupbox("World")

World:AddToggle("WorldEnabled", {
	Text = "Enabled",
	Default = false,
	Callback = function(value)
		print("World.Enabled =", value)
	end,
})

World:AddKeybind("MenuToggleKeybind", {
	Text = "Toggle Menu",
	Default = Enum.KeyCode.End,
	Mode = "Toggle",
	Callback = function(active)
		Window.Main.Visible = not Window.Main.Visible
	end,
})

--// Misc tab — simple button example ----------------------------------------

local OtherBox = Tabs.Misc:AddLeftGroupbox("Other")
OtherBox:AddButton({
	Text = "Print hello",
	Callback = function()
		print("Hello from Korona!")
	end,
})

--// Settings tab — live theme colors + config save/load ---------------------

ThemeManager:BuildColorTab(Tabs.Settings, "Left")
SaveManager:BuildConfigSection(Tabs.Settings, "Right")

-- Apply a saved config automatically on startup, if one was marked as AutoLoad.
SaveManager:LoadAutoloadConfig()

--// Optional watermark, matching the original's style ------------------------

Library:CreateWatermark({
	Text = "Korona | {fps}fps | {ping}ms",
})
