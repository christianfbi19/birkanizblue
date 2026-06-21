--[[
	BananaLib — Roblox UI Prototype
	--------------------------------
	Minimal prototype library implementing only:
		Window, Tab, Groupbox, Toggle

	Not a full framework. Built to test a specific visual concept:
	dark theme, square corners, thin strokes, subtle gradients,
	accent color rgb(255,245,163).
]]

local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local BananaLib = {}
BananaLib.__index = BananaLib

-- ============================================================
-- Theme
-- ============================================================

local Colors = {
	Background = Color3.fromRGB(18, 18, 18),   -- main window / groupbox content
	Header     = Color3.fromRGB(25, 25, 25),   -- title bars / tab bar
	Accent     = Color3.fromRGB(255, 245, 163),
	ToggleOff  = Color3.fromRGB(30, 30, 30),
	Text       = Color3.fromRGB(255, 255, 255),
	Stroke     = Color3.fromRGB(0, 0, 0),
}

local FONT = Enum.Font.GothamSemibold

-- ============================================================
-- Helpers
-- ============================================================

local function new(class, props, parent)
	local inst = Instance.new(class)
	for prop, value in pairs(props) do
		inst[prop] = value
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function addGradient(parent, rotation)
	return new("UIGradient", {
		Color = ColorSequence.new(
			Color3.fromRGB(255, 255, 255),
			Color3.fromRGB(148, 148, 148)
		),
		Rotation = rotation or 90,
	}, parent)
end

local function addStroke(parent, color)
	return new("UIStroke", {
		Color = color or Colors.Stroke,
		Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Miter,
	}, parent)
end

local function makeDraggable(handle, target)
	local dragging, dragStart, startPos

	handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = target.Position

			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)

	handle.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			target.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y
			)
		end
	end)
end

-- ============================================================
-- Window
-- ============================================================

local Window = {}
Window.__index = Window

function BananaLib:CreateWindow(config)
	config = config or {}

	local self = setmetatable({}, Window)
	self.Tabs = {}
	self.TabButtons = {}
	self.SelectedTab = nil

	-- ScreenGui
	local screenGui = new("ScreenGui", {
		Name = "BananaLib",
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		ResetOnSpawn = false,
	})

	local ok = pcall(function()
		screenGui.Parent = game:GetService("CoreGui")
	end)
	if not ok then
		screenGui.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
	end
	self.ScreenGui = screenGui

	-- Main window frame
	local Main = new("Frame", {
		Name = "Main",
		Size = UDim2.new(0, 440, 0, 457),
		Position = UDim2.new(0.5, -220, 0.5, -228),
		BackgroundColor3 = Colors.Background,
		BorderSizePixel = 0,
	}, screenGui)
	addGradient(Main, 45)
	addStroke(Main)
	self.Main = Main

	-- Title bar
	local TitleBar = new("Frame", {
		Name = "TitleBar",
		Size = UDim2.new(0, 440, 0, 24),
		BackgroundColor3 = Colors.Header,
		BorderSizePixel = 0,
	}, Main)
	addGradient(TitleBar, -90)
	addStroke(TitleBar)

	new("TextLabel", {
		Name = "Text",
		Size = UDim2.new(1, -12, 1, 0),
		Position = UDim2.new(0, 12, 0, 0),
		BackgroundTransparency = 1,
		Font = FONT,
		TextSize = 14,
		TextColor3 = Colors.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = config.Name or "BananaLib",
	}, TitleBar)

	makeDraggable(TitleBar, Main)

	-- Pages holder (sits between title bar and bottom tab bar)
	local Pages = new("Frame", {
		Name = "Pages",
		Size = UDim2.new(1, 0, 1, -54), -- minus title (24) and tabs bar (30)
		Position = UDim2.new(0, 0, 0, 24),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, Main)
	self.Pages = Pages

	-- Bottom tab bar
	local TabsBar = new("Frame", {
		Name = "Tabs",
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.new(0, 0, 1, -30),
		BackgroundColor3 = Colors.Header,
		BorderSizePixel = 0,
	}, Main)
	addGradient(TabsBar, 90)
	addStroke(TabsBar)

	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalFlex = Enum.UIFlexAlignment.Fill,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, TabsBar)

	self.TabsBar = TabsBar

	return self
end

-- ============================================================
-- Tab
-- ============================================================

local Tab = {}
Tab.__index = Tab

function Window:Tab(name)
	local tab = setmetatable({}, Tab)
	tab.Name = name
	tab._window = self

	-- Tab button (in bottom bar)
	local Button = new("TextButton", {
		Name = name,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Font = FONT,
		TextSize = 14,
		Text = name,
		TextColor3 = Colors.Text,
	}, self.TabsBar)

	local Accent = new("Frame", {
		Name = "Accent",
		Size = UDim2.new(0, 28, 0, 2),
		Position = UDim2.new(0.5, -14, 1, -6),
		BackgroundColor3 = Colors.Accent,
		BorderSizePixel = 0,
		Visible = false,
	}, Button)

	-- Page (content area for this tab)
	local Page = new("Frame", {
		Name = name .. "Page",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
	}, self.Pages)

	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalFlex = Enum.UIFlexAlignment.Fill,
		Padding = UDim.new(0, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, Page)

	new("UIPadding", {
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		PaddingTop = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 8),
	}, Page)

	local Left = new("Frame", {
		Name = "Left",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, Page)
	new("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, Left)

	local Right = new("Frame", {
		Name = "Right",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, Page)
	new("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, Right)

	tab.Button = Button
	tab.Accent = Accent
	tab.Page = Page
	tab.Left = Left
	tab.Right = Right

	table.insert(self.Tabs, tab)

	-- Selection logic
	Button.MouseButton1Click:Connect(function()
		self:SelectTab(tab)
	end)

	-- First tab added is selected by default
	if not self.SelectedTab then
		self:SelectTab(tab)
	end

	return tab
end

function Window:SelectTab(tab)
	for _, t in ipairs(self.Tabs) do
		local isSelected = (t == tab)
		t.Page.Visible = isSelected
		t.Accent.Visible = isSelected
		t.Button.TextColor3 = isSelected and Colors.Accent or Colors.Text
	end
	self.SelectedTab = tab
end

-- ============================================================
-- Groupbox
-- ============================================================

local Groupbox = {}
Groupbox.__index = Groupbox

function Tab:Groupbox(config)
	config = config or {}
	local side = config.Side == "Right" and self.Right or self.Left

	local box = setmetatable({}, Groupbox)

	-- Outer frame: auto-height, stacks title + content
	local Container = new("Frame", {
		Name = (config.Name or "Groupbox") .. "Groupbox",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, side)

	new("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, Container)

	-- Title bar
	local Title = new("Frame", {
		Name = "Title",
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundColor3 = Colors.Header,
		BorderSizePixel = 0,
		LayoutOrder = 1,
	}, Container)
	addGradient(Title, -90)
	addStroke(Title)

	new("TextLabel", {
		Name = "Text",
		Size = UDim2.new(1, -12, 1, 0),
		Position = UDim2.new(0, 12, 0, 0),
		BackgroundTransparency = 1,
		Font = FONT,
		TextSize = 14,
		TextColor3 = Colors.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = config.Name or "Groupbox",
	}, Title)

	-- Content container
	local Contents = new("Frame", {
		Name = "Contents",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Colors.Background,
		BorderSizePixel = 0,
		LayoutOrder = 2,
	}, Container)
	addGradient(Contents, 90)
	addStroke(Contents)

	new("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, Contents)

	new("UIPadding", {
		PaddingLeft = UDim.new(0, 6),
		PaddingRight = UDim.new(0, 6),
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 6),
	}, Contents)

	box.Container = Container
	box.Contents = Contents

	return box
end

-- ============================================================
-- Toggle
-- ============================================================

local Toggle = {}
Toggle.__index = Toggle

function Groupbox:Toggle(config)
	config = config or {}
	local toggle = setmetatable({}, Toggle)

	toggle.Value = config.Default or false
	toggle.Callback = config.Callback or function() end

	local Holder = new("Frame", {
		Name = (config.Name or "Toggle") .. "Toggle",
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, self.Contents)

	local Box = new("Frame", {
		Name = "Box",
		Size = UDim2.new(0, 12, 0, 12),
		Position = UDim2.new(0, 0, 0.5, -6),
		BorderSizePixel = 0,
		BackgroundColor3 = toggle.Value and Colors.Accent or Colors.ToggleOff,
	}, Holder)
	addGradient(Box, 90)
	addStroke(Box)

	new("TextLabel", {
		Name = "Text",
		Size = UDim2.new(1, -20, 1, 0),
		Position = UDim2.new(0, 20, 0, 0),
		BackgroundTransparency = 1,
		Font = FONT,
		TextSize = 14,
		TextColor3 = Colors.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = config.Name or "Toggle",
	}, Holder)

	local ClickArea = new("TextButton", {
		Name = "ClickArea",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
	}, Holder)

	toggle.Box = Box

	function toggle:Set(value)
		toggle.Value = value
		Box.BackgroundColor3 = value and Colors.Accent or Colors.ToggleOff
		toggle.Callback(value)
	end

	ClickArea.MouseButton1Click:Connect(function()
		toggle:Set(not toggle.Value)
	end)

	-- Fire callback once with the default value, like most UI libs do
	toggle.Callback(toggle.Value)

	return toggle
end

-- ============================================================

return BananaLib
