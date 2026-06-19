local ThemeManager = {}
ThemeManager.Library = nil

ThemeManager.Defaults = {
	Background = Color3.new(0.06, 0.06, 0.06),
	TabBackground = Color3.new(0.05, 0.05, 0.05),
	Accent = Color3.new(0.25, 0.24, 0.45),
	Outline = Color3.new(0, 0, 0),
	Text = Color3.new(1, 1, 1),
	MutedText = Color3.new(0.66, 0.66, 0.66),
}

function ThemeManager:SetLibrary(Library)
	self.Library = Library
end

-- Builds a groupbox of color pickers, one per theme key, on the given Tab.
-- Side can be "Left" or "Right" (defaults to Left).
function ThemeManager:BuildColorTab(Tab, Side)
	local Library = self.Library
	assert(Library, "ThemeManager:SetLibrary(Library) must be called first")

	local Groupbox
	if Side == "Right" then
		Groupbox = Tab:AddRightGroupbox("Colors")
	else
		Groupbox = Tab:AddLeftGroupbox("Colors")
	end

	local order = { "Accent", "Background", "TabBackground", "Outline", "Text", "MutedText" }
	for _, key in ipairs(order) do
		Groupbox:AddColorPicker("ThemeColor_" .. key, {
			Text = key,
			Default = Library.Theme[key],
			Callback = function(color)
				Library.Theme[key] = color
				Library:Repaint()
			end,
		})
	end

	Groupbox:AddButton({
		Text = "Reset to Korona theme",
		Callback = function()
			for key, color in pairs(self.Defaults) do
				Library.Theme[key] = color
				local picker = Library.Options["ThemeColor_" .. key]
				if picker then
					picker:Set(color)
				end
			end
			Library:Repaint()
		end,
	})

	return Groupbox
end

return ThemeManager
