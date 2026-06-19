--[[
	Korona Library — SaveManager addon

	Generic save/load config system. Serializes every Library.Toggles / Library.Options
	entry to JSON on disk (writefile/readfile — works in any executor that exposes the
	standard file-system globals) and builds the on-screen "Config" UI: a name field,
	Save button, a scrollable list of saved configs (click = load, right click = set as
	AutoLoad, shift+click = delete), and an "Auto Load:" readout.

	Usage:
		local SaveManager = loadstring(game:HttpGet(".../addons/SaveManager.lua"))()
		SaveManager:SetLibrary(Library)
		SaveManager:SetFolder("Korona") -- optional, defaults to the window title
		SaveManager:BuildConfigSection(Tabs.Settings)
		SaveManager:LoadAutoloadConfig() -- call once everything else has been built
]]

local HttpService = game:GetService("HttpService")

local SaveManager = {}
SaveManager.Library = nil
SaveManager.Folder = "KoronaConfigs"
SaveManager.Ignore = {} -- Idx keys to skip when saving (e.g. one-off buttons)

local Font = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.SemiBold, Enum.FontStyle.Normal)

--// Filesystem helpers (pcall-wrapped so testing outside an executor doesn't error)

local function fsSupported()
	return typeof(writefile) == "function" and typeof(readfile) == "function"
		and typeof(isfolder) == "function" and typeof(makefolder) == "function"
		and typeof(listfiles) == "function"
end

function SaveManager:SetLibrary(Library)
	self.Library = Library
end

function SaveManager:SetFolder(name)
	self.Folder = name
end

local function ensureFolder(self)
	if not fsSupported() then return end
	if not isfolder(self.Folder) then
		makefolder(self.Folder)
	end
end

--// Serialization -------------------------------------------------------------

function SaveManager:Gather()
	local Library = self.Library
	local data = {}

	for idx, toggle in pairs(Library.Toggles) do
		if not self.Ignore[idx] then
			data[idx] = { Type = "Toggle", Value = toggle.Value }
		end
	end

	for idx, option in pairs(Library.Options) do
		if not self.Ignore[idx] then
			if option.Type == "Slider" then
				data[idx] = { Type = "Slider", Value = option.Value }
			elseif option.Type == "Keybind" then
				data[idx] = { Type = "Keybind", Value = option.Key and option.Key.Name or nil, Mode = option.Mode }
			elseif option.Type == "ColorPicker" then
				data[idx] = { Type = "ColorPicker", Value = option.Value:ToHex() }
			end
		end
	end

	return data
end

function SaveManager:Apply(data)
	local Library = self.Library

	for idx, entry in pairs(data) do
		if entry.Type == "Toggle" and Library.Toggles[idx] then
			Library.Toggles[idx]:Set(entry.Value)
		elseif entry.Type == "Slider" and Library.Options[idx] then
			Library.Options[idx]:Set(entry.Value)
		elseif entry.Type == "Keybind" and Library.Options[idx] then
			local ok, key = pcall(function() return Enum.KeyCode[entry.Value] end)
			if ok and key then
				Library.Options[idx].Key = key
				Library.Options[idx].Mode = entry.Mode or Library.Options[idx].Mode
				if Library.Options[idx].Instance then
					local bind = Library.Options[idx].Instance:FindFirstChild("Bind")
					if bind then bind.Text = key.Name end
				end
			end
		elseif entry.Type == "ColorPicker" and Library.Options[idx] then
			local ok, color = pcall(function() return Color3.fromHex(entry.Value) end)
			if ok then
				Library.Options[idx]:Set(color)
			end
		end
	end
end

--// File operations ------------------------------------------------------------

function SaveManager:Save(name)
	if not fsSupported() then
		warn("[SaveManager] File system functions are unavailable in this environment.")
		return false
	end
	ensureFolder(self)
	local data = self:Gather()
	local ok, encoded = pcall(HttpService.JSONEncode, HttpService, data)
	if not ok then return false end
	writefile(self.Folder .. "/" .. name .. ".json", encoded)
	return true
end

function SaveManager:Load(name)
	if not fsSupported() then return false end
	local path = self.Folder .. "/" .. name .. ".json"
	local ok, raw = pcall(readfile, path)
	if not ok then return false end
	local ok2, data = pcall(HttpService.JSONDecode, HttpService, raw)
	if not ok2 then return false end
	self:Apply(data)
	return true
end

function SaveManager:Delete(name)
	if not fsSupported() then return false end
	local path = self.Folder .. "/" .. name .. ".json"
	if typeof(delfile) == "function" then
		pcall(delfile, path)
	end
	return true
end

function SaveManager:List()
	if not fsSupported() then return {} end
	ensureFolder(self)
	local files = listfiles(self.Folder)
	local names = {}
	for _, path in ipairs(files) do
		local name = path:match("([^/\\]+)%.json$")
		if name then table.insert(names, name) end
	end
	table.sort(names)
	return names
end

function SaveManager:SetAutoload(name)
	if not fsSupported() then return end
	writefile(self.Folder .. "/autoload.txt", name or "")
end

function SaveManager:GetAutoload()
	if not fsSupported() then return nil end
	local ok, name = pcall(readfile, self.Folder .. "/autoload.txt")
	if ok and name ~= "" then return name end
	return nil
end

function SaveManager:LoadAutoloadConfig()
	local name = self:GetAutoload()
	if name then
		self:Load(name)
	end
end

--// UI --------------------------------------------------------------------------

function SaveManager:BuildConfigSection(Tab, Side)
	local Library = self.Library
	assert(Library, "SaveManager:SetLibrary(Library) must be called first")
	ensureFolder(self)

	local Groupbox
	if Side == "Right" then
		Groupbox = Tab:AddRightGroupbox("Config")
	else
		Groupbox = Tab:AddLeftGroupbox("Config")
	end

	local Contents = Groupbox.Contents

	local NameBox = Instance.new("TextBox")
	NameBox.PlaceholderText = "Config name..."
	NameBox.Text = ""
	NameBox.FontFace = Font
	NameBox.TextSize = 14
	NameBox.ClearTextOnFocus = false
	NameBox.Size = UDim2.new(1, 0, 0, 22)
	NameBox.BorderSizePixel = 0
	NameBox.Parent = Contents
	Library:Themed(NameBox, "BackgroundColor3", "Background")
	Library:Themed(NameBox, "TextColor3", "Text")

	local ListHolder = Instance.new("Frame")
	ListHolder.BackgroundTransparency = 1
	ListHolder.AutomaticSize = Enum.AutomaticSize.Y
	ListHolder.Size = UDim2.new(1, 0, 0, 0)
	ListHolder.Parent = Contents
	local ListLayout = Instance.new("UIListLayout")
	ListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	ListLayout.Padding = UDim.new(0, 3)
	ListLayout.Parent = ListHolder

	local AutoLoadRow = Instance.new("Frame")
	AutoLoadRow.BackgroundTransparency = 1
	AutoLoadRow.Size = UDim2.new(1, 0, 0, 16)
	AutoLoadRow.Parent = Contents

	local AutoLoadLabel = Instance.new("TextLabel")
	AutoLoadLabel.Text = "Auto Load:"
	AutoLoadLabel.FontFace = Font
	AutoLoadLabel.TextSize = 12
	AutoLoadLabel.TextXAlignment = Enum.TextXAlignment.Left
	AutoLoadLabel.BackgroundTransparency = 1
	AutoLoadLabel.Size = UDim2.new(0.5, 0, 1, 0)
	AutoLoadLabel.Parent = AutoLoadRow
	Library:Themed(AutoLoadLabel, "TextColor3", "Text")

	local AutoLoadValue = Instance.new("TextLabel")
	AutoLoadValue.Text = self:GetAutoload() or "None"
	AutoLoadValue.FontFace = Font
	AutoLoadValue.TextSize = 12
	AutoLoadValue.TextXAlignment = Enum.TextXAlignment.Right
	AutoLoadValue.BackgroundTransparency = 1
	AutoLoadValue.Size = UDim2.new(0.5, 0, 1, 0)
	AutoLoadValue.Position = UDim2.new(0.5, 0, 0, 0)
	AutoLoadValue.Parent = AutoLoadRow
	Library:Themed(AutoLoadValue, "TextColor3", "MutedText")

	local function Refresh()
		for _, child in ipairs(ListHolder:GetChildren()) do
			if child:IsA("GuiObject") then child:Destroy() end
		end

		for _, name in ipairs(self:List()) do
			local Row = Instance.new("TextButton")
			Row.Text = "  " .. name
			Row.FontFace = Font
			Row.TextSize = 13
			Row.TextXAlignment = Enum.TextXAlignment.Left
			Row.AutoButtonColor = false
			Row.Size = UDim2.new(1, 0, 0, 20)
			Row.BorderSizePixel = 0
			Row.Parent = ListHolder
			Library:Themed(Row, "BackgroundColor3", "Background")
			Library:Themed(Row, "TextColor3", "Text")

			Row.MouseButton1Click:Connect(function()
				self:Load(name)
			end)
			Row.MouseButton2Click:Connect(function()
				self:SetAutoload(name)
				AutoLoadValue.Text = name
			end)
		end
	end

	Groupbox:AddButton({
		Text = "Save",
		Callback = function()
			local name = NameBox.Text
			if name == "" then return end
			self:Save(name)
			Refresh()
		end,
	})

	Groupbox:AddButton({
		Text = "Delete selected (type name above, then press)",
		Callback = function()
			local name = NameBox.Text
			if name == "" then return end
			self:Delete(name)
			if self:GetAutoload() == name then
				self:SetAutoload(nil)
				AutoLoadValue.Text = "None"
			end
			Refresh()
		end,
	})

	Refresh()

	return Groupbox
end

return SaveManager
