local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer

local IsTouch = UserInputService.TouchEnabled

--// Library root

local Library = {}
Library.__index = Library

Library.Toggles = {}   -- [Idx] = ToggleObject
Library.Options = {}   -- [Idx] = Slider/Keybind/ColorPicker object
Library.Unloaded = false

Library.Theme = {
	Background       = Color3.new(0.06, 0.06, 0.06),
	TabBackground    = Color3.new(0.05, 0.05, 0.05),
	Accent           = Color3.new(0.25, 0.24, 0.45),
	Outline          = Color3.new(0, 0, 0),
	Text             = Color3.new(1, 1, 1),
	MutedText        = Color3.new(0.66, 0.66, 0.66),
	GradientLight    = Color3.new(1, 1, 1),
	GradientMid      = Color3.new(0.62, 0.62, 0.62),
	GradientSoft     = Color3.new(0.69, 0.69, 0.69),
	FillGradientDark = Color3.new(0.38, 0.38, 0.38),
}

-- Every {Instance, Property, ThemeKey} triple registered here gets repainted
-- whenever Library:Repaint() runs (used by ThemeManager's live color pickers).
Library.ThemeRegistry = {}

local Font = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.SemiBold, Enum.FontStyle.Normal)

--// Utility -----------------------------------------------------------------

local function Create(class, props, children)
	local inst = Instance.new(class)
	for prop, value in pairs(props or {}) do
		inst[prop] = value
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	return inst
end

local function Round(value, decimals)
	local mult = 10 ^ (decimals or 0)
	return math.floor(value * mult + 0.5) / mult
end

local function Clamp(value, min, max)
	return math.max(min, math.min(max, value))
end

-- Registers an instance/property pair so it updates when the theme changes.
function Library:Themed(inst, prop, key)
	inst[prop] = self.Theme[key]
	table.insert(self.ThemeRegistry, { Instance = inst, Property = prop, Key = key })
	return inst
end

function Library:Repaint()
	for _, entry in ipairs(self.ThemeRegistry) do
		if entry.Instance and entry.Instance.Parent then
			entry.Instance[entry.Property] = self.Theme[entry.Key]
		end
	end
end

local function AddStroke(inst, parentLib, colorKey)
	local stroke = Create("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Miter,
	})
	stroke.Parent = inst
	if colorKey then
		parentLib:Themed(stroke, "Color", colorKey)
	end
	return stroke
end

local function AddGradient(inst, rotation, lightKey, darkKey, parentLib)
	local grad = Create("UIGradient", { Rotation = rotation })
	grad.Parent = inst
	parentLib:Themed(grad, "Color", nil) -- placeholder, set manually below
	-- UIGradient.Color can't be themed with a single key since it's a sequence,
	-- so we build + refresh it manually via a tiny closure stored on the instance.
	local function refresh()
		grad.Color = ColorSequence.new(
			ColorSequenceKeypoint.new(0, parentLib.Theme[lightKey]),
			ColorSequenceKeypoint.new(1, parentLib.Theme[darkKey])
		)
	end
	refresh()
	table.insert(parentLib.ThemeRegistry, { Refresh = refresh })
	return grad
end

-- Patch Repaint to also run gradient refresh closures.
local _origRepaint = Library.Repaint
function Library:Repaint()
	for _, entry in ipairs(self.ThemeRegistry) do
		if entry.Refresh then
			entry.Refresh()
		elseif entry.Instance and entry.Instance.Parent then
			entry.Instance[entry.Property] = self.Theme[entry.Key]
		end
	end
end

local function MakeDraggable(handle, target)
	local dragging, dragInput, startPos, startInputPos

	handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			startPos = target.Position
			startInputPos = input.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)

	handle.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			dragInput = input
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if input == dragInput and dragging then
			local delta = input.Position - startInputPos
			target.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y
			)
		end
	end)
end

--// Window -------------------------------------------------------------------

function Library:CreateWindow(Config)
	Config = Config or {}
	local Title = Config.Title or "Korona"
	local Subtitle = Config.Subtitle or "v1"
	local Size = Config.Size or UDim2.fromOffset(448, 416)
	local ToggleKeybind = Config.ToggleKeybind or Enum.KeyCode.RightShift

	local ScreenGui = Create("ScreenGui", {
		Name = Title,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = true,
	})

	local ok = pcall(function()
		ScreenGui.Parent = game:GetService("CoreGui")
	end)
	if not ok then
		ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
	end

	self.ScreenGui = ScreenGui

	local Main = Create("Frame", {
		Name = "Main",
		Size = Size,
		Position = UDim2.new(0.5, -Size.X.Offset / 2, 0.5, -Size.Y.Offset / 2),
		BorderSizePixel = 0,
	})
	Main.Parent = ScreenGui
	self:Themed(Main, "BackgroundColor3", "Background")
	AddStroke(Main, self, "Outline")
	AddGradient(Main, 45, "GradientLight", "GradientMid", self)

	-- Auto-shrink the whole window to fit small/portrait screens (phones,
	-- tablets) instead of running off the edge. Desktop viewports are
	-- comfortably larger than the window so Scale stays at 1.
	local WindowScale = Create("UIScale", { Scale = 1 })
	WindowScale.Parent = Main

	local function FitToScreen()
		local camera = workspace.CurrentCamera
		if not camera then return end
		local viewport = camera.ViewportSize
		if viewport.X <= 0 or viewport.Y <= 0 then return end
		local margin = IsTouch and 24 or 40
		local scaleX = (viewport.X - margin) / Size.X.Offset
		local scaleY = (viewport.Y - margin) / Size.Y.Offset
		local scale = math.min(1, scaleX, scaleY)
		WindowScale.Scale = scale
	end

	FitToScreen()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(FitToScreen)
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(FitToScreen)
	end

	-- Title bar
	local TitleBar = Create("Frame", {
		Name = "Title",
		Size = UDim2.new(1, 0, 0, 33),
		BorderSizePixel = 0,
	})
	TitleBar.Parent = Main
	self:Themed(TitleBar, "BackgroundColor3", "Accent")
	AddGradient(TitleBar, 90, "GradientLight", "GradientSoft", self)
	AddStroke(TitleBar, self, "Outline")
	MakeDraggable(TitleBar, Main)

	local TitleText = Create("TextLabel", {
		Text = Title,
		Font = Enum.Font.Unknown,
		FontFace = Font,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextStrokeTransparency = 0,
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 220, 1, 0),
		RichText = true,
	})
	TitleText.Parent = TitleBar
	self:Themed(TitleText, "TextColor3", "Text")
	Create("UIPadding", { PaddingLeft = UDim.new(0, 12) }).Parent = TitleText

	local SubtitleText = Create("TextLabel", {
		Text = Subtitle,
		FontFace = Font,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextStrokeTransparency = 0,
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 200, 1, 0),
		Position = UDim2.new(1, -212, 0, 0),
		RichText = true,
	})
	SubtitleText.Parent = TitleBar
	self:Themed(SubtitleText, "TextColor3", "Text")
	Create("UIPadding", { PaddingRight = UDim.new(0, 12) }).Parent = SubtitleText

	-- Tab bar
	local TabBar = Create("Frame", {
		Name = "Tabs",
		Size = UDim2.new(1, 0, 0, 26),
		Position = UDim2.new(0, 0, 0, 33),
		BorderSizePixel = 0,
	})
	TabBar.Parent = Main
	self:Themed(TabBar, "BackgroundColor3", "TabBackground")
	AddGradient(TabBar, -90, "GradientLight", "GradientMid", self)
	AddStroke(TabBar, self, "Outline")
	Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalFlex = Enum.UIFlexAlignment.Fill,
		VerticalFlex = Enum.UIFlexAlignment.Fill,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}).Parent = TabBar

	-- Page container
	local Container = Create("Frame", {
		Name = "Container",
		Size = UDim2.new(1, -16, 1, -75),
		Position = UDim2.new(0, 8, 0, 67),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	})
	Container.Parent = Main

	local Window = setmetatable({
		Library = self,
		ScreenGui = ScreenGui,
		Main = Main,
		TabBar = TabBar,
		Container = Container,
		Tabs = {},
		ActiveTab = nil,
	}, { __index = self })

	self.Window = Window

	-- Whole-window show/hide keybind
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == ToggleKeybind then
			Main.Visible = not Main.Visible
		end
	end)

	-- Touch devices have no keyboard, so RightShift (or whatever
	-- ToggleKeybind is) is unreachable there. Give them a small draggable
	-- floating button that does the same thing.
	if IsTouch then
		local MobileToggle = Create("TextButton", {
			Name = "MobileToggle",
			Text = "K",
			FontFace = Font,
			TextSize = 18,
			AutoButtonColor = false,
			Size = UDim2.fromOffset(44, 44),
			Position = UDim2.new(1, -60, 1, -120),
			BorderSizePixel = 0,
			ZIndex = 100,
		})
		MobileToggle.Parent = ScreenGui
		self:Themed(MobileToggle, "BackgroundColor3", "Accent")
		self:Themed(MobileToggle, "TextColor3", "Text")
		AddGradient(MobileToggle, 90, "GradientLight", "GradientSoft", self)
		AddStroke(MobileToggle, self, "Outline")
		Create("UICorner", { CornerRadius = UDim.new(1, 0) }).Parent = MobileToggle

		-- MakeDraggable already distinguishes a tap from a drag well enough
		-- for the title bar, but a tap-to-toggle button needs an explicit
		-- "didn't move much" check so dragging it doesn't also fire a toggle.
		local pressPos, moved = nil, false
		MobileToggle.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				pressPos = input.Position
				moved = false
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if pressPos and (input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement) then
				if (input.Position - pressPos).Magnitude > 6 then
					moved = true
				end
			end
		end)
		MakeDraggable(MobileToggle, MobileToggle)
		MobileToggle.MouseButton1Click:Connect(function()
			if not moved then
				Main.Visible = not Main.Visible
			end
		end)
	end

	function Window:AddTab(Name)
		local lib = self.Library

		local TabButton = Create("TextButton", {
			Text = Name,
			FontFace = Font,
			TextSize = 14,
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			BorderSizePixel = 0,
			RichText = true,
		})
		TabButton.Parent = self.TabBar
		lib:Themed(TabButton, "TextColor3", "MutedText")

		local Page = Create("Frame", {
			Visible = false,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, 0),
			BorderSizePixel = 0,
		})
		Page.Parent = self.Container
		Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalFlex = Enum.UIFlexAlignment.Fill,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}).Parent = Page

		local Left = Create("Frame", { BackgroundTransparency = 1, BorderSizePixel = 0 })
		Left.Parent = Page
		Create("UIListLayout", {
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}).Parent = Left

		local Right = Create("Frame", { BackgroundTransparency = 1, BorderSizePixel = 0 })
		Right.Parent = Page
		Create("UIListLayout", {
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}).Parent = Right

		local Tab = setmetatable({
			Window = self,
			Library = lib,
			Name = Name,
			Page = Page,
			Left = Left,
			Right = Right,
		}, { __index = self })

		local function Select()
			for _, t in pairs(self.Tabs) do
				t.Page.Visible = (t == Tab)
				lib.Theme.MutedText = lib.Theme.MutedText -- no-op, keeps linter calm
				t.Button.TextColor3 = (t == Tab) and lib.Theme.Text or lib.Theme.MutedText
			end
			self.ActiveTab = Tab
		end

		Tab.Button = TabButton
		Tab.Select = Select

		TabButton.MouseButton1Click:Connect(Select)

		table.insert(self.Tabs, Tab)
		if #self.Tabs == 1 then
			Select()
		end

		--// Groupbox factory ------------------------------------------------

		local function AddGroupbox(Holder, GroupName)
			local Box = Create("Frame", {
				Name = "Groupbox",
				AutomaticSize = Enum.AutomaticSize.Y,
				Size = UDim2.new(1, 0, 0, 0),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
			})
			Box.Parent = Holder
			Create("UIListLayout", {
				SortOrder = Enum.SortOrder.LayoutOrder,
			}).Parent = Box

			local Header = Create("Frame", {
				Name = "Header",
				Size = UDim2.new(1, 0, 0, 30),
				BorderSizePixel = 0,
				LayoutOrder = 1,
			})
			Header.Parent = Box
			lib:Themed(Header, "BackgroundColor3", "Accent")
			AddGradient(Header, 90, "GradientLight", "GradientSoft", lib)
			AddStroke(Header, lib, "Outline")

			local HeaderText = Create("TextLabel", {
				Text = GroupName,
				FontFace = Font,
				TextSize = 14,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextStrokeTransparency = 0,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, -34, 1, 0),
				RichText = true,
			})
			HeaderText.Parent = Header
			lib:Themed(HeaderText, "TextColor3", "Text")
			Create("UIPadding", { PaddingLeft = UDim.new(0, 12) }).Parent = HeaderText

			local MinimizeBtn = Create("TextButton", {
				Text = "-",
				FontFace = Font,
				TextSize = 14,
				BackgroundTransparency = 1,
				AutoButtonColor = false,
				Size = UDim2.new(0, 30, 1, 0),
				Position = UDim2.new(1, -30, 0, 0),
			})
			MinimizeBtn.Parent = Header
			lib:Themed(MinimizeBtn, "TextColor3", "Text")

			local Contents = Create("Frame", {
				Name = "Contents",
				AutomaticSize = Enum.AutomaticSize.Y,
				Size = UDim2.new(1, 0, 0, 0),
				BorderSizePixel = 0,
				LayoutOrder = 2,
			})
			Contents.Parent = Box
			lib:Themed(Contents, "BackgroundColor3", "Background")
			AddGradient(Contents, 90, "GradientLight", "GradientSoft", lib)
			AddStroke(Contents, lib, "Outline")
			Create("UIListLayout", {
				Padding = UDim.new(0, 5),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}).Parent = Contents
			Create("UIPadding", {
				PaddingTop = UDim.new(0, 6),
				PaddingBottom = UDim.new(0, 6),
				PaddingLeft = UDim.new(0, 8),
				PaddingRight = UDim.new(0, 8),
			}).Parent = Contents

			local minimized = false
			MinimizeBtn.MouseButton1Click:Connect(function()
				minimized = not minimized
				Contents.Visible = not minimized
				MinimizeBtn.Text = minimized and "+" or "-"
			end)

			local Groupbox = setmetatable({
				Library = lib,
				Instance = Box,
				Contents = Contents,
			}, { __index = lib })

			--// Elements ------------------------------------------------------

			local function RowBase(height)
				if IsTouch and height < 24 then
					height = 24
				end
				return Create("Frame", {
					Size = UDim2.new(1, 0, 0, height),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
				})
			end

			-- Toggle ------------------------------------------------------------
			function Groupbox:AddToggle(Idx, Cfg)
				Cfg = Cfg or {}
				local Row = RowBase(16)
				Row.Parent = Contents

				local Swatch = Create("Frame", {
					Name = "Style",
					Size = UDim2.fromOffset(15, 15),
					BorderSizePixel = 0,
				})
				Swatch.Parent = Row
				AddStroke(Swatch, lib, "Outline")
				local accentStroke = AddStroke(Swatch, lib, "Accent")
				AddGradient(Swatch, 90, "GradientLight", "GradientSoft", lib)

				local Label = Create("TextLabel", {
					Text = Cfg.Text or Idx or "Toggle",
					FontFace = Font,
					TextSize = 14,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextStrokeTransparency = 0,
					BackgroundTransparency = 1,
					Size = UDim2.new(1, -23, 1, 0),
					Position = UDim2.fromOffset(23, 0),
					RichText = true,
				})
				Label.Parent = Row
				lib:Themed(Label, "TextColor3", "Text")

				local Hit = Create("TextButton", {
					Text = "",
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 1, 0),
					AutoButtonColor = false,
				})
				Hit.Parent = Row

				local Toggle = setmetatable({
					Value = Cfg.Default or false,
					Type = "Toggle",
					Instance = Row,
				}, { __index = lib })

				local function Repaint()
					if Toggle.Value then
						lib:Themed(Swatch, "BackgroundColor3", "Accent")
						accentStroke.Color = lib.Theme.Outline
					else
						Swatch.BackgroundColor3 = lib.Theme.Background
						accentStroke.Color = lib.Theme.Outline
					end
				end

				function Toggle:Set(value)
					self.Value = value
					Repaint()
					if Cfg.Callback then
						Cfg.Callback(self.Value)
					end
				end

				Hit.MouseButton1Click:Connect(function()
					Toggle:Set(not Toggle.Value)
				end)

				Repaint()
				if Cfg.Default and Cfg.Callback then
					Cfg.Callback(Toggle.Value)
				end

				if Idx then
					lib.Toggles[Idx] = Toggle
				end

				-- Chainable inline color swatch (matches the original design's
				-- per-feature color box docked to the right side of a toggle row)
				function Toggle:AddColorPicker(PIdx, PCfg)
					PCfg = PCfg or {}
					Label.Size = UDim2.new(1, -23 - 33, 1, 0)

					local PickerSwatch = Create("Frame", {
						Name = "Color",
						Size = UDim2.fromOffset(25, 15),
						Position = UDim2.new(1, -25, 0, 0),
						BorderSizePixel = 0,
						BackgroundColor3 = PCfg.Default or Color3.fromRGB(255, 255, 255),
					})
					PickerSwatch.Parent = Row
					AddStroke(PickerSwatch, lib, "Outline")

					local Picker = lib:_BuildColorPickerPopup(PickerSwatch, PCfg, lib)
					if PIdx then
						lib.Options[PIdx] = Picker
					end
					return self
				end

				return Toggle
			end

			-- Slider --------------------------------------------------------
			function Groupbox:AddSlider(Idx, Cfg)
				Cfg = Cfg or {}
				local Min = Cfg.Min or 0
				local Max = Cfg.Max or 100
				local Default = Clamp(Cfg.Default or Min, Min, Max)
				local Rounding = Cfg.Rounding or 0
				local Suffix = Cfg.Suffix or ""

				local Row = RowBase(30)
				Row.Parent = Contents

				local Label = Create("TextLabel", {
					Text = Cfg.Text or Idx or "Slider",
					FontFace = Font,
					TextSize = 14,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextStrokeTransparency = 0,
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 15),
				})
				Label.Parent = Row
				lib:Themed(Label, "TextColor3", "Text")

				local Background = Create("Frame", {
					Name = "Background",
					Size = UDim2.new(1, 0, 0, 15),
					Position = UDim2.new(0, 0, 0, 15),
					BorderSizePixel = 0,
				})
				Background.Parent = Row
				lib:Themed(Background, "BackgroundColor3", "Background")
				AddGradient(Background, 90, "GradientLight", "GradientSoft", lib)
				AddStroke(Background, lib, "Outline")

				local FillIn = Create("Frame", {
					Name = "FillIn",
					Size = UDim2.new(0, 0, 1, 0),
					BorderSizePixel = 0,
				})
				FillIn.Parent = Background
				lib:Themed(FillIn, "BackgroundColor3", "Accent")
				AddGradient(FillIn, 90, "GradientLight", "FillGradientDark", lib)

				local ValueText = Create("TextLabel", {
					Text = "",
					FontFace = Font,
					TextSize = 12,
					BackgroundTransparency = 1,
					Size = UDim2.new(0, Background.Size.X.Offset > 0 and Background.Size.X.Offset or 1000, 1, 0),
					TextStrokeTransparency = 0,
				})
				ValueText.Size = UDim2.new(10, 0, 1, 0) -- generously wide, parent clips via Background bounds visually
				ValueText.Parent = Background
				lib:Themed(ValueText, "TextColor3", "Text")
				Background.ClipsDescendants = true

				local Slider = setmetatable({
					Value = Default,
					Type = "Slider",
					Instance = Row,
				}, { __index = lib })

				local function Repaint()
					local frac = (Slider.Value - Min) / (Max - Min)
					FillIn.Size = UDim2.new(frac, 0, 1, 0)
					ValueText.Text = tostring(Slider.Value) .. Suffix
				end

				function Slider:Set(value)
					value = Clamp(Round(value, Rounding), Min, Max)
					self.Value = value
					Repaint()
					if Cfg.Callback then
						Cfg.Callback(self.Value)
					end
				end

				local dragging = false
				local Hit = Create("TextButton", {
					Text = "",
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 1, 0),
					AutoButtonColor = false,
				})
				Hit.Parent = Background

				local function UpdateFromMouse(x)
					local abs = Background.AbsolutePosition.X
					local size = Background.AbsoluteSize.X
					local frac = Clamp((x - abs) / size, 0, 1)
					Slider:Set(Min + frac * (Max - Min))
				end

				Hit.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
						dragging = true
						UpdateFromMouse(input.Position.X)
					end
				end)
				UserInputService.InputChanged:Connect(function(input)
					if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
						UpdateFromMouse(input.Position.X)
					end
				end)
				UserInputService.InputEnded:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
						dragging = false
					end
				end)

				Repaint()
				if Idx then
					lib.Options[Idx] = Slider
				end
				return Slider
			end

			-- Keybind ---------------------------------------------------------
			function Groupbox:AddKeybind(Idx, Cfg)
				Cfg = Cfg or {}
				local Mode = Cfg.Mode or "Hold" -- "Hold" | "Toggle" | "Always"
				local Modes = { "Hold", "Toggle", "Always" }

				local Row = RowBase(16)
				Row.Parent = Contents

				local Label = Create("TextLabel", {
					Text = Cfg.Text or Idx or "Keybind",
					FontFace = Font,
					TextSize = 14,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextStrokeTransparency = 0,
					BackgroundTransparency = 1,
					Size = UDim2.new(1, -60, 1, 0),
					RichText = true,
				})
				Label.Parent = Row
				lib:Themed(Label, "TextColor3", "Text")

				local Bind = Create("TextButton", {
					Name = "Bind",
					Text = Cfg.Default and Cfg.Default.Name or "None",
					FontFace = Font,
					TextSize = 14,
					TextXAlignment = Enum.TextXAlignment.Right,
					TextStrokeTransparency = 0,
					BackgroundTransparency = 1,
					AutoButtonColor = false,
					Size = UDim2.new(0, 60, 1, 0),
					Position = UDim2.new(1, -60, 0, 0),
				})
				Bind.Parent = Row
				lib:Themed(Bind, "TextColor3", "MutedText")

				local Keybind = setmetatable({
					Key = Cfg.Default,
					Mode = Mode,
					Active = false,
					Type = "Keybind",
					Instance = Row,
					ListEntry = nil,
				}, { __index = lib })

				local listening = false

				local function SetActive(state)
					Keybind.Active = state
					if Keybind.ListEntry then
						Keybind.ListEntry.Text.TextColor3 = state and lib.Theme.Accent or lib.Theme.Text
					end
					if Cfg.Callback then
						Cfg.Callback(state)
					end
				end

				Bind.MouseButton1Click:Connect(function()
					if listening then
						-- tap again to cancel (useful on touch, where there's
						-- no keyboard key to press to finish the assignment)
						listening = false
						Bind.Text = Keybind.Key and Keybind.Key.Name or "None"
						return
					end
					listening = true
					Bind.Text = "..."
				end)

				local function SetMode(newMode)
					Keybind.Mode = newMode
					if newMode == "Always" then
						SetActive(true)
					elseif Keybind.Active and newMode ~= "Hold" then
						-- leaving Always/Toggle while active: drop back to inactive
						SetActive(false)
					end
				end

				Bind.MouseButton2Click:Connect(function()
					local i = table.find(Modes, Keybind.Mode) or 1
					SetMode(Modes[(i % #Modes) + 1])
					if Keybind.ListEntry then
						Keybind.ListEntry.Text.Text = ("[%s] %s [%s]"):format(
							Keybind.Mode, Cfg.Text or Idx, Keybind.Key and Keybind.Key.Name or "None")
					end
				end)

				-- Right-click (mode cycling) doesn't exist on touch, so a
				-- long-press on the bind label does the same thing there.
				if IsTouch and Bind.TouchLongPress then
					Bind.TouchLongPress:Connect(function()
						local i = table.find(Modes, Keybind.Mode) or 1
						SetMode(Modes[(i % #Modes) + 1])
						if Keybind.ListEntry then
							Keybind.ListEntry.Text.Text = ("[%s] %s [%s]"):format(
								Keybind.Mode, Cfg.Text or Idx, Keybind.Key and Keybind.Key.Name or "None")
						end
					end)
				end

				if Mode == "Always" then
					task.defer(SetActive, true)
				end

				UserInputService.InputBegan:Connect(function(input, processed)
					if listening then
						if input.UserInputType == Enum.UserInputType.Keyboard then
							Keybind.Key = input.KeyCode
							Bind.Text = input.KeyCode.Name
							listening = false
							if Keybind.ListEntry then
								Keybind.ListEntry.Text.Text = ("[%s] %s [%s]"):format(
									Keybind.Mode, Cfg.Text or Idx, Keybind.Key.Name)
							end
						end
						return
					end
					if processed or not Keybind.Key then return end
					if input.KeyCode == Keybind.Key then
						if Keybind.Mode == "Hold" then
							SetActive(true)
						elseif Keybind.Mode == "Toggle" then
							SetActive(not Keybind.Active)
						end
					end
				end)

				UserInputService.InputEnded:Connect(function(input)
					if not Keybind.Key then return end
					if input.KeyCode == Keybind.Key and Keybind.Mode == "Hold" then
						SetActive(false)
					end
				end)

				if Cfg.List ~= false then
					Keybind.ListEntry = lib:_RegisterKeybindEntry(Cfg.Text or Idx, Keybind)
				end

				if Idx then
					lib.Options[Idx] = Keybind
				end
				return Keybind
			end

			-- Button ------------------------------------------------------------
			function Groupbox:AddButton(Cfg)
				Cfg = Cfg or {}
				local Btn = Create("TextButton", {
					Text = Cfg.Text or "Button",
					FontFace = Font,
					TextSize = 14,
					TextStrokeTransparency = 0,
					Size = UDim2.new(1, 0, 0, 26),
					AutoButtonColor = false,
					BorderSizePixel = 0,
				})
				Btn.Parent = Contents
				lib:Themed(Btn, "BackgroundColor3", "Accent")
				lib:Themed(Btn, "TextColor3", "Text")
				AddGradient(Btn, 90, "GradientLight", "GradientSoft", lib)
				AddStroke(Btn, lib, "Outline")

				Btn.MouseButton1Click:Connect(function()
					if Cfg.Callback then
						Cfg.Callback()
					end
				end)

				return { Instance = Btn }
			end

			-- Standalone ColorPicker (e.g. for a theme "Colors" tab) -----------
			function Groupbox:AddColorPicker(Idx, Cfg)
				Cfg = Cfg or {}
				local Row = RowBase(16)
				Row.Parent = Contents

				local Label = Create("TextLabel", {
					Text = Cfg.Text or Idx or "Color",
					FontFace = Font,
					TextSize = 14,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextStrokeTransparency = 0,
					BackgroundTransparency = 1,
					Size = UDim2.new(1, -33, 1, 0),
					RichText = true,
				})
				Label.Parent = Row
				lib:Themed(Label, "TextColor3", "Text")

				local Swatch = Create("Frame", {
					Name = "Color",
					Size = UDim2.fromOffset(25, 15),
					Position = UDim2.new(1, -25, 0, 0),
					BorderSizePixel = 0,
					BackgroundColor3 = Cfg.Default or Color3.fromRGB(255, 255, 255),
				})
				Swatch.Parent = Row
				AddStroke(Swatch, lib, "Outline")

				local Picker = lib:_BuildColorPickerPopup(Swatch, Cfg, lib)
				if Idx then
					lib.Options[Idx] = Picker
				end
				return Picker
			end

			return Groupbox
		end

		function Tab:AddLeftGroupbox(Name)
			return AddGroupbox(self.Left, Name)
		end

		function Tab:AddRightGroupbox(Name)
			return AddGroupbox(self.Right, Name)
		end

		return Tab
	end

	return Window
end

--// Floating keybind list (top-right corner) --------------------------------

function Library:_RegisterKeybindEntry(name, keybind)
	if not self._KeybindFrame then
		local Frame = Create("Frame", {
			Name = "Keybinds",
			Size = UDim2.fromOffset(170, 24),
			AutomaticSize = Enum.AutomaticSize.Y,
			Position = UDim2.new(1, -180, 0, 10),
			BorderSizePixel = 0,
		})
		Frame.Parent = self.ScreenGui
		self:Themed(Frame, "BackgroundColor3", "Accent")
		AddGradient(Frame, 90, "GradientLight", "GradientSoft", self)
		AddStroke(Frame, self, "Outline")

		local Title = Create("TextLabel", {
			Text = "Keybinds",
			FontFace = Font,
			TextSize = 14,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 24),
			TextStrokeTransparency = 0,
		})
		Title.Parent = Frame
		self:Themed(Title, "TextColor3", "Text")

		local List = Create("Frame", {
			Name = "Container",
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 0),
			Position = UDim2.new(0, 0, 0, 24),
			BackgroundTransparency = 1,
		})
		List.Parent = Frame
		Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }).Parent = List

		MakeDraggable(Frame, Frame)

		self._KeybindFrame = Frame
		self._KeybindList = List
	end

	local Row = Create("Frame", {
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
	})
	Row.Parent = self._KeybindList

	local Text = Create("TextLabel", {
		Text = ("[%s] %s [%s]"):format(keybind.Mode, name, keybind.Key and keybind.Key.Name or "None"),
		FontFace = Font,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		TextStrokeTransparency = 0,
	})
	Text.Parent = Row
	self:Themed(Text, "TextColor3", "Text")

	return { Row = Row, Text = Text }
end

--// Color picker (built from scratch — not present in the original dump) ----

function Library:_BuildColorPickerPopup(Swatch, Cfg, lib)
	local h, s, v = (Cfg.Default or Color3.fromRGB(255, 255, 255)):ToHSV()

	local Popup = Create("Frame", {
		Visible = false,
		Size = UDim2.fromOffset(160, 170),
		Position = UDim2.new(0, 0, 1, 6),
		ZIndex = 50,
		BorderSizePixel = 0,
	})
	Popup.Parent = Swatch
	lib:Themed(Popup, "BackgroundColor3", "Background")
	AddStroke(Popup, lib, "Outline")
	AddGradient(Popup, 90, "GradientLight", "GradientSoft", lib)

	-- Saturation/Value square
	local SVBox = Create("Frame", {
		Size = UDim2.fromOffset(144, 100),
		Position = UDim2.fromOffset(8, 8),
		BackgroundColor3 = Color3.fromHSV(h, 1, 1),
		BorderSizePixel = 0,
	})
	SVBox.Parent = Popup
	AddStroke(SVBox, lib, "Outline")

	local WhiteOverlay = Create("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		Size = UDim2.new(1, 0, 1, 0),
		BorderSizePixel = 0,
	})
	WhiteOverlay.Parent = SVBox
	Create("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}).Parent = WhiteOverlay

	local BlackOverlay = Create("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0),
		Size = UDim2.new(1, 0, 1, 0),
		BorderSizePixel = 0,
	})
	BlackOverlay.Parent = SVBox
	Create("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1, 0),
		}),
	}).Parent = BlackOverlay

	local SVCursor = Create("Frame", {
		Size = UDim2.fromOffset(6, 6),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 51,
	})
	SVCursor.Parent = SVBox
	AddStroke(SVCursor, lib, "Outline")

	-- Hue strip
	local HueBar = Create("Frame", {
		Size = UDim2.fromOffset(144, 14),
		Position = UDim2.fromOffset(8, 114),
		BorderSizePixel = 0,
	})
	HueBar.Parent = Popup
	AddStroke(HueBar, lib, "Outline")
	Create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0.00, Color3.fromHSV(0/6, 1, 1)),
			ColorSequenceKeypoint.new(1/6,  Color3.fromHSV(1/6, 1, 1)),
			ColorSequenceKeypoint.new(2/6,  Color3.fromHSV(2/6, 1, 1)),
			ColorSequenceKeypoint.new(3/6,  Color3.fromHSV(3/6, 1, 1)),
			ColorSequenceKeypoint.new(4/6,  Color3.fromHSV(4/6, 1, 1)),
			ColorSequenceKeypoint.new(5/6,  Color3.fromHSV(5/6, 1, 1)),
			ColorSequenceKeypoint.new(1.00, Color3.fromHSV(1, 1, 1)),
		}),
	}).Parent = HueBar

	local HueCursor = Create("Frame", {
		Size = UDim2.fromOffset(4, 14),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 51,
	})
	HueCursor.Parent = HueBar
	AddStroke(HueCursor, lib, "Outline")

	-- Hex input
	local HexBox = Create("TextBox", {
		Size = UDim2.fromOffset(144, 20),
		Position = UDim2.fromOffset(8, 134),
		FontFace = Font,
		TextSize = 14,
		ClearTextOnFocus = false,
		BorderSizePixel = 0,
	})
	HexBox.Parent = Popup
	lib:Themed(HexBox, "BackgroundColor3", "Background")
	lib:Themed(HexBox, "TextColor3", "Text")
	AddStroke(HexBox, lib, "Outline")

	local Picker = setmetatable({
		Value = Color3.fromHSV(h, s, v),
		Type = "ColorPicker",
		Instance = Swatch,
	}, { __index = lib })

	local function Repaint()
		Picker.Value = Color3.fromHSV(h, s, v)
		Swatch.BackgroundColor3 = Picker.Value
		SVBox.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
		SVCursor.Position = UDim2.new(s, 0, 1 - v, 0)
		HueCursor.Position = UDim2.new(h, -2, 0, 0)
		HexBox.Text = Picker.Value:ToHex():upper()
		if Cfg.Callback then
			Cfg.Callback(Picker.Value)
		end
	end

	function Picker:Set(color)
		h, s, v = color:ToHSV()
		Repaint()
	end

	local openButton = Create("TextButton", {
		Text = "",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
	})
	openButton.Parent = Swatch
	openButton.MouseButton1Click:Connect(function()
		Popup.Visible = not Popup.Visible
	end)

	local draggingSV, draggingHue = false, false

	-- Touch needs a noticeably bigger hit target than a mouse cursor, so on
	-- touch devices we pad the SV box / hue strip hit areas outward instead
	-- of relying on the visible frame bounds alone.
	local touchPad = UserInputService.TouchEnabled and 14 or 0

	local SVHit = Create("TextButton", {
		Text = "", BackgroundTransparency = 1,
		Size = UDim2.new(1, touchPad * 2, 1, touchPad * 2),
		Position = UDim2.new(0, -touchPad, 0, -touchPad),
	})
	SVHit.Parent = SVBox
	SVHit.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			draggingSV = true
		end
	end)

	local HueHit = Create("TextButton", {
		Text = "", BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, touchPad * 2),
		Position = UDim2.new(0, 0, 0, -touchPad),
	})
	HueHit.Parent = HueBar
	HueHit.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			draggingHue = true
		end
	end)

	local function UpdateDrag(input)
		if draggingSV then
			local pos = SVBox.AbsolutePosition
			local size = SVBox.AbsoluteSize
			s = Clamp((input.Position.X - pos.X) / size.X, 0, 1)
			v = 1 - Clamp((input.Position.Y - pos.Y) / size.Y, 0, 1)
			Repaint()
		elseif draggingHue then
			local pos = HueBar.AbsolutePosition
			local size = HueBar.AbsoluteSize
			h = Clamp((input.Position.X - pos.X) / size.X, 0, 1)
			Repaint()
		end
	end

	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			UpdateDrag(input)
		end
	end)

	-- Touch fires InputBegan/InputChanged/InputEnded once per finger contact
	-- rather than a continuous move stream like a mouse, so also sample on
	-- InputBegan to position the cursor correctly on the very first tap.
	SVHit.InputBegan:Connect(UpdateDrag)
	HueHit.InputBegan:Connect(UpdateDrag)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			draggingSV, draggingHue = false, false
		end
	end)

	HexBox.FocusLost:Connect(function()
		local hex = HexBox.Text:gsub("#", "")
		local success, color = pcall(function()
			return Color3.fromHex(hex)
		end)
		if success then
			h, s, v = color:ToHSV()
			Repaint()
		end
	end)

	Repaint()
	return Picker
end

--// Watermark ----------------------------------------------------------------

function Library:CreateWatermark(Cfg)
	Cfg = Cfg or {}
	local Frame = Create("Frame", {
		Name = "Watermark",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 26),
		Position = Cfg.Position or UDim2.new(0, 10, 0, 10),
		BorderSizePixel = 0,
	})
	Frame.Parent = self.ScreenGui
	self:Themed(Frame, "BackgroundColor3", "Background")
	AddGradient(Frame, 45, "GradientLight", "GradientMid", self)
	AddStroke(Frame, self, "Outline")

	local Text = Create("TextLabel", {
		FontFace = Font,
		TextSize = 14,
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 26),
		TextStrokeTransparency = 0,
	})
	Text.Parent = Frame
	self:Themed(Text, "TextColor3", "Text")
	Create("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }).Parent = Text

	local template = Cfg.Text or "{title}"
	local lastUpdate = 0

	local function Refresh()
		local fps = math.floor(1 / RunService.RenderStepped:Wait())
		local ping = LocalPlayer and LocalPlayer:GetNetworkPing() and math.floor(LocalPlayer:GetNetworkPing() * 1000) or 0
		Text.Text = (template:gsub("{fps}", tostring(fps)):gsub("{ping}", tostring(ping)))
	end

	if Cfg.AutoUpdate ~= false then
		RunService.Heartbeat:Connect(function(dt)
			lastUpdate += dt
			if lastUpdate >= 1 then
				lastUpdate = 0
				local fps = math.floor(1 / dt)
				local ping = 0
				pcall(function() ping = math.floor(LocalPlayer:GetNetworkPing() * 1000) end)
				Text.Text = (template:gsub("{fps}", tostring(fps)):gsub("{ping}", tostring(ping)))
			end
		end)
	else
		Text.Text = template
	end

	return { Instance = Frame, Text = Text, SetText = function(_, t) template = t end }
end

--// Teardown -----------------------------------------------------------------

function Library:Unload()
	self.Unloaded = true
	if self.ScreenGui then
		self.ScreenGui:Destroy()
	end
end

return Library
