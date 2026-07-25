-- 🏠 House RNG Tycoon — interface joueur (design + animations)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Houses = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Houses"))
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local RollEvent = remotes:WaitForChild("Roll")
local ResultEvent = remotes:WaitForChild("RollResult")
local DataEvent = remotes:WaitForChild("UpdateData")
local LuckEvent = remotes:WaitForChild("BuyLuck")
local SelectEvent = remotes:WaitForChild("Select")
local RebirthEvent = remotes:WaitForChild("Rebirth")

local player = Players.LocalPlayer
local ROLL_COOLDOWN = 0.25
local rng = Random.new()

-- ─── Thème ───
local PANEL_TOP = Color3.fromRGB(30, 36, 46)
local PANEL_BOT = Color3.fromRGB(17, 20, 27)
local GOLD = Color3.fromRGB(255, 206, 84)
local TXT = Color3.fromRGB(236, 241, 247)
local DIM = Color3.fromRGB(150, 165, 182)

-- ─── Helpers ───
local function new(class, props)
	local o = Instance.new(class)
	for k, v in props do
		(o :: any)[k] = v
	end
	return o
end
local function corner(inst, r)
	new("UICorner", { CornerRadius = UDim.new(0, r), Parent = inst })
end
local function stroke(inst, color, thick, trans)
	return new("UIStroke", { Color = color, Thickness = thick or 1.5, Transparency = trans or 0, Parent = inst })
end
local function gradient(inst, c1, c2, rot)
	return new("UIGradient", { Color = ColorSequence.new(c1, c2), Rotation = rot or 90, Parent = inst })
end
local function panel(props)
	local f = new("Frame", props)
	corner(f, 16)
	gradient(f, PANEL_TOP, PANEL_BOT, 90)
	stroke(f, Color3.fromRGB(70, 82, 100), 1.5, 0.3)
	return f
end

local gui = new("ScreenGui", {
	Name = "HouseRNG",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui"),
})

-- overlay de flash (révélations rares)
local flash = new("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(255, 255, 255),
	BackgroundTransparency = 1,
	ZIndex = 5,
	Parent = gui,
})

-- ─── Argent (haut) ───
local cashPill = panel({
	Size = UDim2.fromScale(0.34, 0.085),
	Position = UDim2.fromScale(0.33, 0.025),
	Parent = gui,
})
stroke(cashPill, GOLD, 2, 0.15)
local cashLabel = new("TextLabel", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Font = Enum.Font.FredokaOne,
	TextScaled = true,
	TextColor3 = GOLD,
	Text = "💰 0",
	Parent = cashPill,
})
new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), Parent = cashLabel })

-- ─── Panneau stats (gauche) ───
local statPanel = panel({
	Size = UDim2.fromScale(0.24, 0.2),
	Position = UDim2.fromScale(0.02, 0.13),
	Parent = gui,
})
local sp = new("UIPadding", { Parent = statPanel })
sp.PaddingLeft = UDim.new(0, 14)
sp.PaddingTop = UDim.new(0, 10)
sp.PaddingRight = UDim.new(0, 10)
new("UIListLayout", { Padding = UDim.new(0, 4), Parent = statPanel })

new("TextLabel", {
	Size = UDim2.fromScale(1, 0.2),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = DIM,
	Text = "STATISTIQUES",
	Parent = statPanel,
})
local function statLine()
	return new("TextLabel", {
		Size = UDim2.fromScale(1, 0.24),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = TXT,
		Text = "",
		Parent = statPanel,
	})
end
local incomeLine = statLine()
local luckLine = statLine()
local rebirthLine = statLine()

-- ─── Boutons gauche (Chance / Renaissance) ───
local function bigButton(pos, c1, c2)
	local b = new("TextButton", {
		Size = UDim2.fromScale(0.24, 0.075),
		Position = pos,
		BackgroundColor3 = c1,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		AutoButtonColor = true,
		Text = "",
		Parent = gui,
	})
	corner(b, 12)
	gradient(b, c1, c2, 90)
	stroke(b, Color3.fromRGB(255, 255, 255), 1.5, 0.6)
	new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4), Parent = b })
	return b
end
local luckBtn = bigButton(UDim2.fromScale(0.02, 0.35), Color3.fromRGB(72, 170, 92), Color3.fromRGB(44, 120, 66))
local rebirthBtn = bigButton(UDim2.fromScale(0.02, 0.44), Color3.fromRGB(150, 92, 210), Color3.fromRGB(96, 54, 150))

-- ─── Inventaire (droite) ───
local invPanel = panel({
	Size = UDim2.fromScale(0.23, 0.6),
	Position = UDim2.fromScale(0.75, 0.13),
	Parent = gui,
})
new("TextLabel", {
	Size = UDim2.fromScale(1, 0.08),
	BackgroundTransparency = 1,
	Font = Enum.Font.FredokaOne,
	TextScaled = true,
	TextColor3 = TXT,
	Text = "🎒 Inventaire",
	Parent = invPanel,
})
new("TextLabel", {
	Size = UDim2.fromScale(0.9, 0.09),
	Position = UDim2.fromScale(0.05, 0.08),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	TextScaled = true,
	TextWrapped = true,
	TextColor3 = DIM,
	Text = "Choisis une maison, puis clique une case pour la poser.",
	Parent = invPanel,
})
local invScroll = new("ScrollingFrame", {
	Size = UDim2.fromScale(0.92, 0.78),
	Position = UDim2.fromScale(0.04, 0.2),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 5,
	ScrollBarImageColor3 = DIM,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	Parent = invPanel,
})
new("UIListLayout", { Padding = UDim.new(0, 6), Parent = invScroll })

-- ─── ROLL + AUTO (bas) ───
local rollBtn = new("TextButton", {
	Size = UDim2.fromScale(0.42, 0.135),
	Position = UDim2.fromScale(0.17, 0.83),
	BackgroundColor3 = Color3.fromRGB(86, 214, 122),
	Font = Enum.Font.FredokaOne,
	TextScaled = true,
	TextColor3 = Color3.fromRGB(9, 40, 20),
	AutoButtonColor = false,
	Text = "🎲 ROLL",
	Parent = gui,
})
corner(rollBtn, 20)
gradient(rollBtn, Color3.fromRGB(120, 240, 150), Color3.fromRGB(56, 180, 96), 90)
stroke(rollBtn, Color3.fromRGB(255, 255, 255), 2.5, 0.25)
new("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), Parent = rollBtn })

local autoBtn = new("TextButton", {
	Size = UDim2.fromScale(0.13, 0.135),
	Position = UDim2.fromScale(0.6, 0.83),
	BackgroundColor3 = Color3.fromRGB(52, 60, 72),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	TextColor3 = Color3.fromRGB(210, 216, 224),
	Text = "AUTO\nOFF",
	Parent = gui,
})
corner(autoBtn, 20)
stroke(autoBtn, Color3.fromRGB(90, 100, 115), 1.5, 0.3)

-- ─── Carte centrale (spin + résultat) ───
local card = panel({
	Size = UDim2.fromScale(0.4, 0.14),
	Position = UDim2.fromScale(0.3, 0.31),
	Visible = false,
	Parent = gui,
})
card.ZIndex = 6
local cardStroke = stroke(card, Color3.fromRGB(255, 255, 255), 3, 0)
local cardText = new("TextLabel", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Font = Enum.Font.FredokaOne,
	TextScaled = true,
	TextColor3 = TXT,
	Text = "",
	ZIndex = 7,
	Parent = card,
})
new("UIPadding", {
	PaddingTop = UDim.new(0, 10),
	PaddingBottom = UDim.new(0, 10),
	PaddingLeft = UDim.new(0, 12),
	PaddingRight = UDim.new(0, 12),
	Parent = cardText,
})

-- ─── Inventaire : construction des cartes ───
local function rebuildInventory(inventory, selected)
	for _, c in invScroll:GetChildren() do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	for _, house in Houses.List do
		local count = inventory[house.id]
		if count and count > 0 then
			local rc = Houses.RarityColor[house.rarity]
			local item = new("Frame", {
				Size = UDim2.new(1, 0, 0, 40),
				BackgroundColor3 = Color3.fromRGB(34, 40, 50),
				Parent = invScroll,
			})
			corner(item, 10)
			if house.id == selected then
				stroke(item, Color3.fromRGB(255, 255, 255), 2.5, 0)
			else
				stroke(item, rc, 1.5, 0.4)
			end
			-- barre de rareté à gauche
			local bar = new("Frame", {
				Size = UDim2.new(0, 6, 1, -10),
				Position = UDim2.fromOffset(6, 5),
				BackgroundColor3 = rc,
				Parent = item,
			})
			corner(bar, 3)
			new("TextLabel", {
				Size = UDim2.new(0.62, 0, 1, 0),
				Position = UDim2.fromOffset(20, 0),
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = rc,
				Text = house.name,
				Parent = item,
			})
			-- pastille de quantité
			local pill = new("TextLabel", {
				Size = UDim2.new(0.22, 0, 0.6, 0),
				Position = UDim2.new(0.76, 0, 0.2, 0),
				BackgroundColor3 = Color3.fromRGB(20, 24, 30),
				Font = Enum.Font.GothamBold,
				TextScaled = true,
				TextColor3 = TXT,
				Text = "x" .. count,
				Parent = item,
			})
			corner(pill, 8)
			local btn = new("TextButton", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = "",
				Parent = item,
			})
			btn.MouseButton1Click:Connect(function()
				SelectEvent:FireServer(house.id)
			end)
		end
	end
end

-- ─── Animation de tirage (machine à sous) ───
local spinning = false
local pending = nil

local function spinPick()
	local r = rng:NextNumber() * Houses.TotalWeight
	local acc = 0
	for _, h in Houses.List do
		acc += h.weight
		if r <= acc then
			return h
		end
	end
	return Houses.List[1]
end

local function setCardPreview(h)
	cardText.Text = h.name .. "\n" .. h.rarity
	cardText.TextColor3 = Houses.RarityColor[h.rarity]
	cardStroke.Color = Houses.RarityColor[h.rarity]
end

local function landing(info)
	local color = Houses.RarityColor[info.rarity] or TXT
	local tier = info.tier or 1
	local rare = tier >= 4
	cardText.TextColor3 = color
	cardStroke.Color = color
	cardText.Text = string.format(
		"%s\n%s • 1 sur %s%s",
		info.name,
		info.rarity,
		Houses.format(info.oneIn),
		rare and "  ⭐" or ""
	)

	-- pop
	card.Size = UDim2.fromScale(0.34, 0.12)
	TweenService:Create(card, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(0.42, 0.15),
	}):Play()
	cardStroke.Thickness = 8
	TweenService:Create(cardStroke, TweenInfo.new(0.4), { Thickness = 3 }):Play()

	if rare then
		-- flash d'écran + secousse de la carte
		flash.BackgroundColor3 = color
		flash.BackgroundTransparency = 0.35
		TweenService:Create(flash, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
		local base = UDim2.fromScale(0.29, 0.305)
		for _ = 1, 6 do
			card.Position = base + UDim2.fromOffset(math.random(-8, 8), math.random(-8, 8))
			task.wait(0.03)
		end
		card.Position = UDim2.fromScale(0.29, 0.305)
	end

	task.delay(rare and 2 or 1.1, function()
		if not spinning then
			card.Visible = false
		end
	end)
end

local function playSpin()
	card.Visible = true
	card.Position = UDim2.fromScale(0.29, 0.305)
	card.Size = UDim2.fromScale(0.42, 0.15)
	local interval = 0.045
	local elapsed = 0
	while elapsed < 0.85 do
		setCardPreview(spinPick())
		task.wait(interval)
		elapsed += interval
		interval *= 1.09 -- décélération
	end
	local t = 0
	while not pending and t < 1 do
		task.wait(0.05)
		t += 0.05
	end
	if pending then
		landing(pending)
	end
	spinning = false
end

ResultEvent.OnClientEvent:Connect(function(info)
	pending = info
end)

-- ─── Mises à jour d'état ───
local currentReq = math.huge
DataEvent.OnClientEvent:Connect(function(d)
	incomeLine.Text = string.format("📈 Revenu : +%s /s", Houses.format(d.income))
	luckLine.Text = string.format("🍀 Chance : Niv.%d (x%.1f)", d.luckLevel, d.luck)
	rebirthLine.Text = string.format("🔄 Renaissance : %d (x%.1f)", d.rebirths, d.mult)
	luckBtn.Text = "🍀 Chance +\n" .. Houses.format(d.luckCost)
	rebirthBtn.Text = "🔄 Renaissance\n" .. Houses.format(d.rebirthReq)
	currentReq = d.rebirthReq
	rebuildInventory(d.inventory, d.selected)
end)

local stats = player:WaitForChild("leaderstats")
local argent = stats:WaitForChild("Argent")
local function refreshCash()
	cashLabel.Text = "💰 " .. Houses.format(argent.Value)
	local ok = argent.Value >= currentReq
	rebirthBtn.BackgroundTransparency = ok and 0 or 0.35
end
argent.Changed:Connect(refreshCash)
refreshCash()

-- ─── Actions ───
local lastRoll = 0
local function doRoll()
	if spinning then
		return
	end
	local now = os.clock()
	if now - lastRoll < ROLL_COOLDOWN then
		return
	end
	lastRoll = now
	spinning = true
	pending = nil
	RollEvent:FireServer()
	task.spawn(playSpin)
end

rollBtn.MouseButton1Click:Connect(doRoll)
rollBtn.MouseButton1Down:Connect(function()
	rollBtn.Size = UDim2.fromScale(0.4, 0.125)
end)
rollBtn.MouseButton1Up:Connect(function()
	rollBtn.Size = UDim2.fromScale(0.42, 0.135)
end)
luckBtn.MouseButton1Click:Connect(function()
	LuckEvent:FireServer()
end)
rebirthBtn.MouseButton1Click:Connect(function()
	RebirthEvent:FireServer()
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.R then
		doRoll()
	end
end)

local auto = false
autoBtn.MouseButton1Click:Connect(function()
	auto = not auto
	autoBtn.Text = auto and "AUTO\nON" or "AUTO\nOFF"
	autoBtn.BackgroundColor3 = auto and Color3.fromRGB(72, 170, 92) or Color3.fromRGB(52, 60, 72)
end)
task.spawn(function()
	while true do
		if auto and not spinning then
			doRoll()
		end
		task.wait(0.05)
	end
end)

print("🏠 House RNG Tycoon — interface prête")
