--[[
	UIController  (LocalScript)
	Location: StarterPlayer > StarterPlayerScripts > UIController

	Builds AND drives the entire UI in code (so it is copy-paste ready and every
	element has an exact, predictable name). Resulting hierarchy in PlayerGui:

	PlayerGui
	├── MainMenuGui (ScreenGui, DisplayOrder 20)
	│   └── Background
	│       ├── Title / Subtitle
	│       ├── Buttons (PlayButton, HowToPlayButton, StoreButton)
	│       └── HowToPlayPanel (Body, BackButton)
	├── HUDGui (ScreenGui, DisplayOrder 5)
	│   ├── TopBar (CoinsFrame > CoinsLabel, EggsFrame > EggsLabel)
	│   ├── ObjectiveFrame > ObjectiveLabel
	│   ├── CarryIndicator > CarryLabel
	│   ├── OxygenFrame (OxygenTitle, OxygenBarBack > OxygenFill, OxygenText)
	│   ├── DepthMeter (DepthLabel, ZoneLabel, DepthTrack > Zone1..5 segments, DepthMarker)
	│   ├── ChaseWarning (WarningLabel) + Vignette (Top/Bottom/Left/Right)
	│   ├── SideButtons (StoreButton)
	│   ├── CelebratePopup
	│   └── ToastContainer
	└── ShopGui (ScreenGui, DisplayOrder 10)
	    ├── TanksShop      (Header > Title/CoinsLabel/CloseButton, ItemList > ItemCard_<id>)
	    ├── FlippersShop   (same layout)
	    ├── MutationsShop  (same layout)
	    └── RobuxStore     (Header, ItemList > PassCard_<key> / ProductCard_<key>)

	Each ItemCard: Swatch > Icon, ItemName, ItemStats, PriceLabel, ActionButton
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("SwimForEggsShared"):WaitForChild("Config"))
local Remotes = ReplicatedStorage:WaitForChild("SwimForEggsRemotes")
local ShopAction = Remotes:WaitForChild("ShopAction")
local NotifyEvent = Remotes:WaitForChild("Notify")
local CelebrateEvent = Remotes:WaitForChild("Celebrate")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

----------------------------------------------------------------------
-- THEME
----------------------------------------------------------------------
local FONT = Enum.Font.FredokaOne
local BODY_FONT = Enum.Font.GothamBold
local C = {
	Panel = Color3.fromRGB(18, 60, 110),
	PanelDark = Color3.fromRGB(10, 35, 70),
	Stroke = Color3.fromRGB(0, 20, 45),
	White = Color3.fromRGB(255, 255, 255),
	Gold = Color3.fromRGB(255, 215, 50),
	Green = Color3.fromRGB(70, 220, 90),
	Red = Color3.fromRGB(255, 70, 70),
	Orange = Color3.fromRGB(255, 160, 40),
	Blue = Color3.fromRGB(40, 160, 255),
	Grey = Color3.fromRGB(120, 130, 145),
	Cyan = Color3.fromRGB(0, 230, 255),
}
local TOAST_COLORS = { Success = C.Green, Danger = C.Red, Warning = C.Orange, Info = C.Blue }

----------------------------------------------------------------------
-- UI HELPERS
----------------------------------------------------------------------
local function create(className: string, props: { [string]: any }?, children: { Instance }?)
	local inst = Instance.new(className)
	local parent = nil
	for key, value in pairs(props or {}) do
		if key == "Parent" then
			parent = value
		else
			inst[key] = value
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function corner(radius: number?)
	return create("UICorner", { CornerRadius = UDim.new(0, radius or 12) })
end

local function stroke(color: Color3?, thickness: number?)
	return create("UIStroke", {
		Color = color or C.Stroke,
		Thickness = thickness or 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

local function textStroke(thickness: number?)
	return create("UIStroke", { Color = C.Stroke, Thickness = thickness or 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual })
end

local function padding(px: number)
	return create("UIPadding", {
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
	})
end

local function gradient(top: Color3, bottom: Color3)
	return create("UIGradient", { Color = ColorSequence.new(top, bottom), Rotation = 90 })
end

local function label(props)
	local defaults = {
		BackgroundTransparency = 1,
		Font = FONT,
		TextColor3 = C.White,
		TextScaled = true,
	}
	for k, v in pairs(props) do
		defaults[k] = v
	end
	local lbl = create("TextLabel", defaults)
	textStroke().Parent = lbl
	return lbl
end

local function button(props, color: Color3)
	local defaults = {
		BackgroundColor3 = color,
		Font = FONT,
		TextColor3 = C.White,
		TextScaled = true,
		AutoButtonColor = true,
	}
	for k, v in pairs(props) do
		defaults[k] = v
	end
	local btn = create("TextButton", defaults, { corner(10), stroke(C.Stroke, 3), gradient(C.White, Color3.fromRGB(200, 200, 200)) })
	textStroke().Parent = btn
	create("UITextSizeConstraint", { MaxTextSize = 30 }, nil).Parent = btn

	-- Bouncy press feedback
	local scale = create("UIScale", { Parent = btn })
	btn.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1.05 }):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1 }):Play()
	end)
	btn.MouseButton1Down:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.06), { Scale = 0.94 }):Play()
	end)
	btn.MouseButton1Up:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end)
	return btn
end

local function commas(n: number): string
	local s = tostring(math.floor(n))
	local formatted, count = s, 0
	repeat
		formatted, count = formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
	until count == 0
	return formatted
end

-- Scales the whole UI down on small (mobile) screens.
local function autoScale(screenGui: ScreenGui)
	local uiScale = create("UIScale", { Parent = screenGui })
	local function update()
		local camera = Workspace.CurrentCamera
		if camera then
			uiScale.Scale = math.clamp(camera.ViewportSize.Y / 900, 0.55, 1.15)
		end
	end
	update()
	if Workspace.CurrentCamera then
		Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	end
end

local function screenGui(name: string, order: number)
	local old = playerGui:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local gui = create("ScreenGui", {
		Name = name,
		ResetOnSpawn = false, -- survives respawns (we drive state from attributes)
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = order,
		IgnoreGuiInset = false,
		Parent = playerGui,
	})
	return gui
end

----------------------------------------------------------------------
-- TOASTS (needed early)
----------------------------------------------------------------------
local hud = screenGui("HUDGui", 5)
autoScale(hud)
hud.Enabled = false

local toastContainer = create("Frame", {
	Name = "ToastContainer",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 150),
	Size = UDim2.fromOffset(520, 300),
	BackgroundTransparency = 1,
	Parent = hud,
}, {
	create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 6),
	}),
})

local toastCounter = 0
local function showToast(text: string, kind: string?)
	toastCounter += 1
	local color = TOAST_COLORS[kind or "Info"] or C.Blue
	local toast = create("Frame", {
		Name = "Toast",
		LayoutOrder = toastCounter,
		Size = UDim2.fromOffset(500, 44),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.1,
		Parent = toastContainer,
	}, { corner(10), stroke(C.Stroke, 2) })
	local lbl = label({
		Size = UDim2.fromScale(1, 1),
		Text = text,
		Font = BODY_FONT,
		Parent = toast,
	})
	padding(6).Parent = lbl

	-- Keep at most 4 toasts.
	local toasts = {}
	for _, child in ipairs(toastContainer:GetChildren()) do
		if child.Name == "Toast" then
			table.insert(toasts, child)
		end
	end
	table.sort(toasts, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	while #toasts > 4 do
		table.remove(toasts, 1):Destroy()
	end

	task.delay(3.5, function()
		if toast.Parent then
			TweenService:Create(toast, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(lbl, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
			task.wait(0.4)
			toast:Destroy()
		end
	end)
end

NotifyEvent.OnClientEvent:Connect(function(text, kind)
	if type(text) == "string" then
		showToast(text, kind)
	end
end)

----------------------------------------------------------------------
-- HUD
----------------------------------------------------------------------
-- Top bar: Coins + Eggs Stolen
local topBar = create("Frame", {
	Name = "TopBar",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 8),
	Size = UDim2.fromOffset(420, 50),
	BackgroundTransparency = 1,
	Parent = hud,
}, {
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 12),
	}),
})

local function statPill(name: string, icon: string, color: Color3, order: number)
	local frame = create("Frame", {
		Name = name,
		LayoutOrder = order,
		Size = UDim2.fromOffset(200, 50),
		BackgroundColor3 = C.Panel,
		Parent = topBar,
	}, { corner(25), stroke(C.Stroke, 3), gradient(Color3.fromRGB(40, 110, 190), C.Panel) })
	label({ Name = "Icon", Size = UDim2.fromOffset(44, 44), Position = UDim2.fromOffset(4, 3), Text = icon, Parent = frame })
	local value = label({
		Name = name == "CoinsFrame" and "CoinsLabel" or "EggsLabel",
		Size = UDim2.new(1, -56, 1, -10),
		Position = UDim2.fromOffset(50, 5),
		Text = "0",
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})
	return value
end
local coinsLabel = statPill("CoinsFrame", "💰", C.Gold, 1)
local eggsLabel = statPill("EggsFrame", "🥚", C.White, 2)

-- Objective
local objectiveFrame = create("Frame", {
	Name = "ObjectiveFrame",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 64),
	Size = UDim2.fromOffset(620, 40),
	BackgroundColor3 = C.PanelDark,
	BackgroundTransparency = 0.25,
	Parent = hud,
}, { corner(12), stroke(C.Stroke, 2) })
local objectiveLabel = label({
	Name = "ObjectiveLabel",
	Size = UDim2.new(1, -16, 1, -8),
	Position = UDim2.fromOffset(8, 4),
	Font = BODY_FONT,
	Text = "🎯 Swim down the slope and steal an egg! 🥚",
	Parent = objectiveFrame,
})

-- Carry indicator
local carryIndicator = create("Frame", {
	Name = "CarryIndicator",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 110),
	Size = UDim2.fromOffset(460, 34),
	BackgroundColor3 = C.Gold,
	Visible = false,
	Parent = hud,
}, { corner(17), stroke(C.Stroke, 2) })
local carryLabel = label({
	Name = "CarryLabel",
	Size = UDim2.new(1, -16, 1, -6),
	Position = UDim2.fromOffset(8, 3),
	Text = "",
	Parent = carryIndicator,
})

-- Oxygen bar
local oxygenFrame = create("Frame", {
	Name = "OxygenFrame",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -24),
	Size = UDim2.fromOffset(460, 64),
	BackgroundColor3 = C.Panel,
	Parent = hud,
}, { corner(14), stroke(C.Stroke, 3) })
label({
	Name = "OxygenTitle",
	Size = UDim2.fromOffset(120, 22),
	Position = UDim2.fromOffset(12, 4),
	Text = "🫧 OXYGEN",
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = oxygenFrame,
})
local oxygenText = label({
	Name = "OxygenText",
	AnchorPoint = Vector2.new(1, 0),
	Size = UDim2.fromOffset(160, 22),
	Position = UDim2.new(1, -12, 0, 4),
	Text = "20s",
	TextXAlignment = Enum.TextXAlignment.Right,
	Parent = oxygenFrame,
})
local oxygenBack = create("Frame", {
	Name = "OxygenBarBack",
	Position = UDim2.fromOffset(12, 30),
	Size = UDim2.new(1, -24, 0, 24),
	BackgroundColor3 = Color3.fromRGB(5, 20, 40),
	ClipsDescendants = true,
	Parent = oxygenFrame,
}, { corner(12) })
local oxygenFill = create("Frame", {
	Name = "OxygenFill",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = C.Cyan,
	Parent = oxygenBack,
}, { corner(12), create("UIGradient", {
	Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(170, 170, 170)),
	Rotation = 90,
}) })

-- Depth meter (right side)
local depthMeter = create("Frame", {
	Name = "DepthMeter",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -12, 0.5, 0),
	Size = UDim2.fromOffset(120, 380),
	BackgroundColor3 = C.Panel,
	BackgroundTransparency = 0.15,
	Parent = hud,
}, { corner(14), stroke(C.Stroke, 3) })
local depthLabel = label({
	Name = "DepthLabel",
	Size = UDim2.new(1, -12, 0, 34),
	Position = UDim2.fromOffset(6, 6),
	Text = "0m",
	TextColor3 = C.Cyan,
	Parent = depthMeter,
})
local zoneLabel = label({
	Name = "ZoneLabel",
	Size = UDim2.new(1, -12, 0, 22),
	Position = UDim2.fromOffset(6, 40),
	Text = "Surface",
	Font = BODY_FONT,
	Parent = depthMeter,
})
local depthTrack = create("Frame", {
	Name = "DepthTrack",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 70),
	Size = UDim2.new(0, 26, 1, -80),
	BackgroundColor3 = C.PanelDark,
	Parent = depthMeter,
}, { corner(8), stroke(C.Stroke, 2) })
for i, zone in ipairs(Config.Zones) do
	local seg = create("Frame", {
		Name = "Zone" .. i,
		Position = UDim2.fromScale(0, (i - 1) / #Config.Zones),
		Size = UDim2.fromScale(1, 1 / #Config.Zones),
		BackgroundColor3 = zone.AccentColor,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Parent = depthTrack,
	})
	label({
		Name = "Mark",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(0, -4, 0, -6),
		Size = UDim2.fromOffset(40, 14),
		Text = tostring((i - 1) * Config.World.ZoneHeight) .. "m",
		Font = BODY_FONT,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = seg,
	})
end
local depthMarker = create("Frame", {
	Name = "DepthMarker",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0),
	Size = UDim2.new(1, 14, 0, 8),
	BackgroundColor3 = C.White,
	ZIndex = 3,
	Parent = depthTrack,
}, { corner(4), stroke(C.Stroke, 2) })

-- Chase warning + red vignette
local chaseWarning = create("Frame", {
	Name = "ChaseWarning",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 150),
	Size = UDim2.fromOffset(560, 50),
	BackgroundColor3 = C.Red,
	Visible = false,
	Parent = hud,
}, { corner(12), stroke(C.Stroke, 3) })
local warningLabel = label({
	Name = "WarningLabel",
	Size = UDim2.new(1, -16, 1, -8),
	Position = UDim2.fromOffset(8, 4),
	Text = "",
	Parent = chaseWarning,
})

local vignette = create("Frame", {
	Name = "Vignette",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Visible = false,
	ZIndex = 0,
	Parent = hud,
})
local vignetteEdges = {}
for _, edge in ipairs({
	{ "Top", UDim2.fromScale(0, 0), UDim2.new(1, 0, 0.18, 0), 90 },
	{ "Bottom", UDim2.fromScale(0, 0.82), UDim2.new(1, 0, 0.18, 0), -90 },
	{ "Left", UDim2.fromScale(0, 0), UDim2.new(0.12, 0, 1, 0), 0 },
	{ "Right", UDim2.fromScale(0.88, 0), UDim2.new(0.12, 0, 1, 0), 180 },
}) do
	local frame = create("Frame", {
		Name = edge[1],
		Position = edge[2],
		Size = edge[3],
		BackgroundColor3 = Color3.fromRGB(255, 0, 0),
		BorderSizePixel = 0,
		Parent = vignette,
	}, {
		create("UIGradient", {
			Rotation = edge[4],
			Transparency = NumberSequence.new(0.35, 1),
		}),
	})
	table.insert(vignetteEdges, frame)
end

-- Side buttons
local sideButtons = create("Frame", {
	Name = "SideButtons",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 12, 0.5, 0),
	Size = UDim2.fromOffset(130, 60),
	BackgroundTransparency = 1,
	Parent = hud,
})
local hudStoreButton = button({
	Name = "StoreButton",
	Size = UDim2.fromOffset(130, 54),
	Text = "💎 Store",
	Parent = sideButtons,
}, C.Green)

-- Celebration popup
local celebratePopup = label({
	Name = "CelebratePopup",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.4),
	Size = UDim2.fromOffset(600, 90),
	Text = "",
	TextColor3 = C.Gold,
	Visible = false,
	Parent = hud,
})
local celebrateScale = create("UIScale", { Parent = celebratePopup })

----------------------------------------------------------------------
-- SHOP WINDOWS
----------------------------------------------------------------------
local shopGui = screenGui("ShopGui", 10)
autoScale(shopGui)

local windows = {} -- [name] = { Frame, Refresh }
local openWindowName = nil
local openShopPromptPart = nil

local function closeAllWindows()
	for _, w in pairs(windows) do
		w.Frame.Visible = false
	end
	openWindowName = nil
	openShopPromptPart = nil
end

local function openWindow(name: string, promptPart: BasePart?)
	closeAllWindows()
	local w = windows[name]
	if not w then
		return
	end
	openWindowName = name
	openShopPromptPart = promptPart
	w.Refresh()
	w.Frame.Visible = true
	local scale = w.Frame:FindFirstChildOfClass("UIScale")
	if scale then
		scale.Scale = 0.6
		TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end
end

local function makeWindow(name: string, title: string, theme: Color3)
	local frame = create("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(760, 500),
		BackgroundColor3 = C.Panel,
		Visible = false,
		Parent = shopGui,
	}, { corner(18), stroke(C.Stroke, 4), create("UIScale", {}) })

	local header = create("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 64),
		BackgroundColor3 = theme,
		Parent = frame,
	}, { corner(18), gradient(C.White, Color3.fromRGB(190, 190, 190)) })
	label({
		Name = "Title",
		Size = UDim2.new(0.6, 0, 1, -14),
		Position = UDim2.fromOffset(18, 7),
		Text = title,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = header,
	})
	local coins = label({
		Name = "CoinsLabel",
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.new(0.25, 0, 1, -24),
		Position = UDim2.new(1, -80, 0, 12),
		Text = "💰 0",
		TextColor3 = C.Gold,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = header,
	})
	local close = button({
		Name = "CloseButton",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(48, 48),
		Text = "X",
	}, C.Red)
	close.Parent = header
	close.Activated:Connect(closeAllWindows)

	local list = create("ScrollingFrame", {
		Name = "ItemList",
		Position = UDim2.fromOffset(14, 76),
		Size = UDim2.new(1, -28, 1, -90),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = frame,
	}, {
		create("UIGridLayout", {
			CellSize = UDim2.fromOffset(170, 250),
			CellPadding = UDim2.fromOffset(12, 12),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}),
		create("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4) }),
	})

	return frame, list, coins
end

local function makeCard(list: Instance, name: string, order: number, color: Color3, icon: string, title: string)
	local card = create("Frame", {
		Name = name,
		LayoutOrder = order,
		BackgroundColor3 = C.PanelDark,
		Parent = list,
	}, { corner(14), stroke(C.Stroke, 3) })
	local swatch = create("Frame", {
		Name = "Swatch",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(80, 80),
		BackgroundColor3 = color,
		Parent = card,
	}, { corner(40), stroke(C.Stroke, 3), gradient(C.White, Color3.fromRGB(150, 150, 150)) })
	label({ Name = "Icon", Size = UDim2.fromScale(0.7, 0.7), Position = UDim2.fromScale(0.15, 0.15), Text = icon, Parent = swatch })
	label({
		Name = "ItemName",
		Position = UDim2.fromOffset(6, 96),
		Size = UDim2.new(1, -12, 0, 30),
		Text = title,
		Parent = card,
	})
	local stats = label({
		Name = "ItemStats",
		Position = UDim2.fromOffset(6, 128),
		Size = UDim2.new(1, -12, 0, 40),
		Font = BODY_FONT,
		Text = "",
		TextColor3 = Color3.fromRGB(200, 230, 255),
		Parent = card,
	})
	local price = label({
		Name = "PriceLabel",
		Position = UDim2.fromOffset(6, 168),
		Size = UDim2.new(1, -12, 0, 22),
		Text = "",
		TextColor3 = C.Gold,
		Parent = card,
	})
	local action = button({
		Name = "ActionButton",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(1, -20, 0, 42),
		Text = "...",
	}, C.Green)
	action.Parent = card
	return card, stats, price, action
end

-- Data readers (replicated from the server; never trusted for purchases)
local function getCoins(): number
	local ls = player:FindFirstChild("leaderstats")
	local coins = ls and ls:FindFirstChild("Coins")
	return coins and coins.Value or 0
end

local function ownsItem(shopId: string, itemId: string): boolean
	local inv = player:FindFirstChild("Inventory")
	local folder = inv and inv:FindFirstChild(shopId)
	return folder ~= nil and folder:FindFirstChild(itemId) ~= nil
end

local function equippedId(shopId: string): string?
	local gear = player:FindFirstChild("Gear")
	local value = gear and gear:FindFirstChild(Config.Shops[shopId].GearValue)
	return value and value.Value or nil
end

local function statText(shopId: string, item): string
	if shopId == "Tanks" then
		return string.format("⏱ %ds of air", item.Oxygen)
	elseif shopId == "Flippers" then
		return string.format("💨 Swim speed %d", item.SwimSpeed)
	else
		return string.format("💰 x%s coins\n✨ Neon egg", tostring(item.Multiplier))
	end
end

local busy = false
local function buildGearShop(shopId: string)
	local shop = Config.Shops[shopId]
	local frame, list, coinsInHeader = makeWindow(shopId .. "Shop", shop.Icon .. " " .. shop.DisplayName, shop.ThemeColor)
	local cards = {}

	for order, item in ipairs(Config.Items[shopId]) do
		local _, stats, price, action = makeCard(list, "ItemCard_" .. item.Id, order, item.Color, shop.Icon, item.Name)
		stats.Text = statText(shopId, item)
		cards[item.Id] = { Item = item, Price = price, Action = action }

		action.Activated:Connect(function()
			if busy then
				return
			end
			busy = true
			local ok, success, message = pcall(ShopAction.InvokeServer, ShopAction, shopId, item.Id)
			busy = false
			if not ok then
				showToast("Shop is busy, try again!", "Warning")
			else
				showToast(message or "", if success then "Success" else "Danger")
			end
			if windows[shopId .. "Shop"] then
				windows[shopId .. "Shop"].Refresh()
			end
		end)
	end

	local function refresh()
		local coins = getCoins()
		coinsInHeader.Text = "💰 " .. commas(coins)
		local equipped = equippedId(shopId)
		for itemId, card in pairs(cards) do
			local owned = ownsItem(shopId, itemId)
			if owned and equipped == itemId then
				card.Action.Text = "EQUIPPED"
				card.Action.BackgroundColor3 = C.Grey
				card.Price.Text = "✔ Owned"
			elseif owned then
				card.Action.Text = "EQUIP"
				card.Action.BackgroundColor3 = C.Blue
				card.Price.Text = "✔ Owned"
			else
				card.Action.Text = "BUY"
				card.Action.BackgroundColor3 = if coins >= card.Item.Price then C.Green else C.Red
				card.Price.Text = "💰 " .. commas(card.Item.Price)
			end
		end
	end

	windows[shopId .. "Shop"] = { Frame = frame, Refresh = refresh }
end

for _, shopId in ipairs(Config.ShopOrder) do
	buildGearShop(shopId)
end

-- Robux store (gamepasses + developer products)
do
	local frame, list, coinsInHeader = makeWindow("RobuxStore", "💎 Robux Store", Color3.fromRGB(70, 220, 90))
	local passCards = {}
	local order = 0

	for key, pass in pairs(Config.GamePasses) do
		order += 1
		local _, stats, price, action = makeCard(list, "PassCard_" .. key, order, C.Gold, pass.Icon, pass.Name)
		stats.Text = pass.Description
		price.Text = "Gamepass"
		passCards[key] = { Pass = pass, Action = action }
		action.Activated:Connect(function()
			if player:GetAttribute(pass.Attribute) then
				showToast("You already own " .. pass.Name .. "!", "Info")
				return
			end
			if pass.Id == 0 then
				showToast(pass.Name .. " isn't set up yet (Id = 0 in Config).", "Warning")
				return
			end
			local ok, err = pcall(MarketplaceService.PromptGamePassPurchase, MarketplaceService, player, pass.Id)
			if not ok then
				warn("[UI] PromptGamePassPurchase failed:", err)
			end
		end)
	end

	for key, product in pairs(Config.DevProducts) do
		order += 1
		local _, stats, price, action = makeCard(list, "ProductCard_" .. key, order, C.Cyan, product.Icon, product.Name)
		stats.Text = product.Description
		price.Text = "Developer Product"
		action.Text = "BUY"
		action.Activated:Connect(function()
			if product.Id == 0 then
				showToast(product.Name .. " isn't set up yet (Id = 0 in Config).", "Warning")
				return
			end
			local ok, err = pcall(MarketplaceService.PromptProductPurchase, MarketplaceService, player, product.Id)
			if not ok then
				warn("[UI] PromptProductPurchase failed:", err)
			end
		end)
	end

	windows.RobuxStore = {
		Frame = frame,
		Refresh = function()
			coinsInHeader.Text = "💰 " .. commas(getCoins())
			for _, card in pairs(passCards) do
				local owned = player:GetAttribute(card.Pass.Attribute) == true
				card.Action.Text = if owned then "OWNED" else "BUY"
				card.Action.BackgroundColor3 = if owned then C.Grey else C.Green
			end
		end,
	}
end

hudStoreButton.Activated:Connect(function()
	if openWindowName == "RobuxStore" then
		closeAllWindows()
	else
		openWindow("RobuxStore")
	end
end)

-- Open a shop when its ProximityPrompt is triggered (fires on this client).
ProximityPromptService.PromptTriggered:Connect(function(prompt, triggeringPlayer)
	if triggeringPlayer ~= player then
		return
	end
	local shopId = prompt:GetAttribute("ShopId")
	if type(shopId) == "string" and windows[shopId .. "Shop"] then
		local parentPart = prompt.Parent
		openWindow(shopId .. "Shop", if parentPart and parentPart:IsA("BasePart") then parentPart else nil)
	end
end)

----------------------------------------------------------------------
-- MAIN MENU
----------------------------------------------------------------------
local menu = screenGui("MainMenuGui", 20)
menu.IgnoreGuiInset = true
autoScale(menu)

local background = create("Frame", {
	Name = "Background",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(0, 90, 170),
	BackgroundTransparency = 0.35,
	Parent = menu,
}, {
	create("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(0, 200, 255), Color3.fromRGB(10, 20, 80)),
		Rotation = 90,
	}),
})

local title = label({
	Name = "Title",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.12, 0),
	Size = UDim2.fromOffset(820, 130),
	Text = "SWIM FOR EGGS",
	TextColor3 = C.Gold,
	Parent = background,
})
title:FindFirstChildOfClass("UIStroke").Thickness = 6
label({
	Name = "Subtitle",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.12, 135),
	Size = UDim2.fromOffset(700, 40),
	Text = "🌊 Dive deep • Steal eggs • Outswim the monsters 🦈",
	Font = BODY_FONT,
	Parent = background,
})

local buttons = create("Frame", {
	Name = "Buttons",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	Size = UDim2.fromOffset(320, 230),
	BackgroundTransparency = 1,
	Parent = background,
}, {
	create("UIListLayout", {
		Padding = UDim.new(0, 14),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})
local playButton = button({ Name = "PlayButton", LayoutOrder = 1, Size = UDim2.fromOffset(320, 80), Text = "▶ PLAY" }, C.Green)
playButton.Parent = buttons
local howButton = button({ Name = "HowToPlayButton", LayoutOrder = 2, Size = UDim2.fromOffset(280, 56), Text = "❓ How to Play" }, C.Blue)
howButton.Parent = buttons
local menuStoreButton = button({ Name = "StoreButton", LayoutOrder = 3, Size = UDim2.fromOffset(280, 56), Text = "💎 Store" }, C.Orange)
menuStoreButton.Parent = buttons

local howPanel = create("Frame", {
	Name = "HowToPlayPanel",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.55),
	Size = UDim2.fromOffset(640, 420),
	BackgroundColor3 = C.Panel,
	Visible = false,
	Parent = background,
}, { corner(18), stroke(C.Stroke, 4) })
local howBody = label({
	Name = "Body",
	Position = UDim2.fromOffset(20, 16),
	Size = UDim2.new(1, -40, 1, -96),
	Font = BODY_FONT,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	Text = table.concat({
		"🥚 Swim down the slope and touch an egg to steal it.",
		"🦈 Each biome's Sea Monster will instantly hunt you!",
		"🏝️ Bring the egg back to the green DROP-OFF zone for coins.",
		"🫧 Watch your Oxygen. Deeper water drains it faster!",
		"🛒 Buy Tanks (more air), Flippers (more speed) and",
		"    Mutations (neon eggs worth more coins) in the Safe Zone.",
		"🌋 Every 100m is a new biome. The deeper, the richer!",
	}, "\n"),
	Parent = howPanel,
})
howBody.TextScaled = true
local backButton = button({
	Name = "BackButton",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -16),
	Size = UDim2.fromOffset(200, 54),
	Text = "Got it!",
}, C.Green)
backButton.Parent = howPanel

howButton.Activated:Connect(function()
	howPanel.Visible = true
	buttons.Visible = false
end)
backButton.Activated:Connect(function()
	howPanel.Visible = false
	buttons.Visible = true
end)
menuStoreButton.Activated:Connect(function()
	openWindow("RobuxStore")
end)

-- Cinematic menu camera + blur
local blur = Lighting:FindFirstChild("MenuBlur") or create("BlurEffect", { Name = "MenuBlur", Size = 14, Parent = Lighting })
local MENU_CAMERA_BIND = "SwimForEggsMenuCamera"
local menuStart = os.clock()
RunService:BindToRenderStep(MENU_CAMERA_BIND, Enum.RenderPriority.Camera.Value + 1, function()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	local t = os.clock() - menuStart
	local eye = Vector3.new(math.sin(t * 0.08) * 60, 45, Config.World.SafeZoneMaxZ - 60)
	local focus = Vector3.new(0, -60, Config.World.OceanStartZ + 250)
	camera.CFrame = CFrame.lookAt(eye, focus)
end)

local function startGame()
	RunService:UnbindFromRenderStep(MENU_CAMERA_BIND)
	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
	TweenService:Create(blur, TweenInfo.new(0.5), { Size = 0 }):Play()
	TweenService:Create(background, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
	closeAllWindows()
	task.delay(0.4, function()
		menu.Enabled = false
	end)
	hud.Enabled = true
end
playButton.Activated:Connect(startGame)

----------------------------------------------------------------------
-- LIVE BINDINGS
----------------------------------------------------------------------
local function refreshOpenWindow()
	if openWindowName and windows[openWindowName] then
		windows[openWindowName].Refresh()
	end
end

-- leaderstats
task.spawn(function()
	local leaderstats = player:WaitForChild("leaderstats", 60)
	if not leaderstats then
		warn("[UI] leaderstats never arrived")
		return
	end
	local coins = leaderstats:WaitForChild("Coins")
	local eggs = leaderstats:WaitForChild("Eggs Stolen")
	local function update()
		coinsLabel.Text = commas(coins.Value)
		eggsLabel.Text = commas(eggs.Value)
		refreshOpenWindow()
	end
	coins.Changed:Connect(update)
	eggs.Changed:Connect(update)
	update()
end)

-- Inventory / Gear changes refresh shops
task.spawn(function()
	for _, name in ipairs({ "Inventory", "Gear" }) do
		local folder = player:WaitForChild(name, 60)
		if folder then
			folder.DescendantAdded:Connect(refreshOpenWindow)
			for _, v in ipairs(folder:GetDescendants()) do
				if v:IsA("ValueBase") then
					v.Changed:Connect(refreshOpenWindow)
				end
			end
		end
	end
end)

-- Objective / carrying / chase
local function updateObjective()
	local text = player:GetAttribute("Objective")
	objectiveLabel.Text = "🎯 " .. (if type(text) == "string" then text else "Steal an egg!")
end

local function updateCarry()
	local zoneName = player:GetAttribute("CarryingEgg")
	if type(zoneName) == "string" then
		local mult = player:GetAttribute("CarryingMultiplier") or 1
		carryIndicator.Visible = true
		carryLabel.Text = string.format("🥚 Carrying %s Egg  (x%s)", zoneName, tostring(mult))
	else
		carryIndicator.Visible = false
	end
end

local chasedBy = nil
local function updateChase()
	local name = player:GetAttribute("ChasedBy")
	chasedBy = if type(name) == "string" and name ~= "" then name else nil
	chaseWarning.Visible = chasedBy ~= nil
	vignette.Visible = chasedBy ~= nil
	if chasedBy then
		warningLabel.Text = "⚠️ " .. string.upper(chasedBy) .. " IS CHASING YOU! ⚠️"
	end
end

player:GetAttributeChangedSignal("Objective"):Connect(updateObjective)
player:GetAttributeChangedSignal("CarryingEgg"):Connect(updateCarry)
player:GetAttributeChangedSignal("CarryingMultiplier"):Connect(updateCarry)
player:GetAttributeChangedSignal("ChasedBy"):Connect(updateChase)
player.AttributeChanged:Connect(function(name)
	if name:match("^Pass_") then
		refreshOpenWindow()
	end
end)
updateObjective()
updateCarry()
updateChase()

-- Score celebration
CelebrateEvent.OnClientEvent:Connect(function(info)
	if type(info) ~= "table" then
		return
	end
	celebratePopup.Text = string.format("+%s COINS! 💰", commas(info.Coins or 0))
	celebratePopup.Visible = true
	celebrateScale.Scale = 0.3
	TweenService:Create(celebrateScale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	local detail = string.format("Scored a %s Egg", tostring(info.ZoneName))
	if info.Mutation and info.Mutation ~= "Plain Egg" then
		detail ..= " with " .. tostring(info.Mutation)
	end
	detail ..= string.format(" (x%s)", tostring(info.Multiplier))
	if info.DoubleCoins then
		detail ..= " • 2x Coins!"
	end
	showToast(detail, "Success")
	task.delay(1.8, function()
		celebratePopup.Visible = false
	end)
end)

-- Per-frame HUD: oxygen bar + depth meter + vignette pulse + shop auto-close
local displayedRatio = 1
RunService.RenderStepped:Connect(function(dt)
	-- Oxygen
	local oxygen = player:GetAttribute("Oxygen") or 0
	local maxOxygen = player:GetAttribute("MaxOxygen") or 1
	local infinite = player:GetAttribute(Config.GamePasses.InfiniteOxygen.Attribute) == true
	local ratio = if infinite then 1 else math.clamp(oxygen / math.max(maxOxygen, 1), 0, 1)
	displayedRatio += (ratio - displayedRatio) * math.clamp(dt * 8, 0, 1)
	oxygenFill.Size = UDim2.fromScale(displayedRatio, 1)

	if infinite then
		oxygenText.Text = "∞ Infinite"
		oxygenFill.BackgroundColor3 = C.Gold
	else
		oxygenText.Text = string.format("%ds", math.ceil(oxygen))
		if ratio > 0.5 then
			oxygenFill.BackgroundColor3 = C.Cyan
		elseif ratio > 0.25 then
			oxygenFill.BackgroundColor3 = Color3.fromRGB(255, 220, 40)
		else
			-- Flash red when nearly empty
			local flash = (math.sin(os.clock() * 12) + 1) / 2
			oxygenFill.BackgroundColor3 = C.Red:Lerp(Color3.fromRGB(255, 200, 200), flash * 0.6)
		end
	end

	-- Depth
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		local depth = Config.GetDepth(root.Position.Y)
		local maxDepth = #Config.Zones * Config.World.ZoneHeight
		if Config.IsInOceanXZ(root.Position) and depth > 0.5 then
			local index = Config.GetZoneIndexForDepth(depth)
			local zone = Config.Zones[index]
			depthLabel.Text = string.format("%dm", math.floor(depth))
			zoneLabel.Text = zone.Name
			zoneLabel.TextColor3 = zone.AccentColor
		else
			depthLabel.Text = "0m"
			zoneLabel.Text = if root.Position.Z < Config.World.OceanStartZ then "Safe Zone" else "Surface"
			zoneLabel.TextColor3 = C.Green
			depth = 0
		end
		depthMarker.Position = UDim2.fromScale(0.5, math.clamp(depth / maxDepth, 0, 1))

		-- Auto-close a shop if the player walks away from its counter
		if openShopPromptPart and (openShopPromptPart.Position - root.Position).Magnitude > 25 then
			closeAllWindows()
		end
	end

	-- Chase vignette pulse
	if chasedBy then
		local pulse = 0.35 + (math.sin(os.clock() * 8) + 1) * 0.2
		for _, edge in ipairs(vignetteEdges) do
			edge.BackgroundTransparency = pulse - 0.35
		end
	end
end)
