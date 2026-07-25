-- 🏠 House RNG Tycoon — interface joueur
--
-- ROLL (+ AUTO, touche R), inventaire des maisons (sélection), pose sur la
-- grille en cliquant les cases, panneau de stats, Chance +, Renaissance.

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
local ROLL_COOLDOWN = 0.3

local function new(class: string, props: { [string]: any }): any
	local o = Instance.new(class)
	for k, v in props do
		(o :: any)[k] = v
	end
	return o
end
local function corner(parent: Instance, r: number)
	new("UICorner", { CornerRadius = UDim.new(0, r), Parent = parent })
end

-- ─── GUI racine ───
local gui = new("ScreenGui", {
	Name = "HouseRNG",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui"),
})

-- Argent (haut)
local cashLabel = new("TextLabel", {
	Size = UDim2.fromScale(0.5, 0.09),
	Position = UDim2.fromScale(0.25, 0.02),
	BackgroundColor3 = Color3.fromRGB(18, 24, 18),
	BackgroundTransparency = 0.15,
	Font = Enum.Font.GothamBlack,
	TextScaled = true,
	TextColor3 = Color3.fromRGB(255, 214, 90),
	Text = "💰 0",
	Parent = gui,
})
corner(cashLabel, 14)

-- Panneau de stats (gauche)
local panel = new("Frame", {
	Size = UDim2.fromScale(0.26, 0.22),
	Position = UDim2.fromScale(0.02, 0.13),
	BackgroundColor3 = Color3.fromRGB(18, 24, 18),
	BackgroundTransparency = 0.2,
	Parent = gui,
})
corner(panel, 14)
local pad = new("UIPadding", { Parent = panel })
pad.PaddingLeft = UDim.new(0, 12)
pad.PaddingTop = UDim.new(0, 8)
new("UIListLayout", { Padding = UDim.new(0, 5), Parent = panel })

local function statLine()
	return new("TextLabel", {
		Size = UDim2.fromScale(0.95, 0.24),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(230, 240, 230),
		Text = "",
		Parent = panel,
	})
end
local incomeLine = statLine()
local luckLine = statLine()
local rebirthLine = statLine()

-- Bouton Chance
local luckBtn = new("TextButton", {
	Size = UDim2.fromScale(0.26, 0.07),
	Position = UDim2.fromScale(0.02, 0.37),
	BackgroundColor3 = Color3.fromRGB(60, 130, 70),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	TextColor3 = Color3.fromRGB(255, 255, 255),
	Text = "🍀 Chance +",
	Parent = gui,
})
corner(luckBtn, 12)

-- Bouton Renaissance
local rebirthBtn = new("TextButton", {
	Size = UDim2.fromScale(0.26, 0.07),
	Position = UDim2.fromScale(0.02, 0.46),
	BackgroundColor3 = Color3.fromRGB(120, 70, 160),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	TextColor3 = Color3.fromRGB(255, 255, 255),
	Text = "🔄 Renaissance",
	Parent = gui,
})
corner(rebirthBtn, 12)

-- ─── Inventaire (droite) ───
local invFrame = new("Frame", {
	Size = UDim2.fromScale(0.22, 0.62),
	Position = UDim2.fromScale(0.76, 0.13),
	BackgroundColor3 = Color3.fromRGB(18, 24, 18),
	BackgroundTransparency = 0.2,
	Parent = gui,
})
corner(invFrame, 14)

local invTitle = new("TextLabel", {
	Size = UDim2.fromScale(1, 0.08),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	TextColor3 = Color3.fromRGB(255, 255, 255),
	Text = "🎒 Inventaire",
	Parent = invFrame,
})

local invHint = new("TextLabel", {
	Size = UDim2.fromScale(0.94, 0.1),
	Position = UDim2.fromScale(0.03, 0.08),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	TextScaled = true,
	TextWrapped = true,
	TextColor3 = Color3.fromRGB(160, 190, 165),
	Text = "Choisis une maison puis clique une case verte pour la poser.",
	Parent = invFrame,
})

local invScroll = new("ScrollingFrame", {
	Size = UDim2.fromScale(0.94, 0.78),
	Position = UDim2.fromScale(0.03, 0.2),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 5,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	Parent = invFrame,
})
new("UIListLayout", { Padding = UDim.new(0, 5), Parent = invScroll })

-- ─── Boutons bas : ROLL + AUTO ───
local rollBtn = new("TextButton", {
	Size = UDim2.fromScale(0.42, 0.13),
	Position = UDim2.fromScale(0.17, 0.84),
	BackgroundColor3 = Color3.fromRGB(70, 200, 110),
	Font = Enum.Font.GothamBlack,
	TextScaled = true,
	TextColor3 = Color3.fromRGB(10, 40, 20),
	Text = "🎲 ROLL",
	Parent = gui,
})
corner(rollBtn, 18)

local autoBtn = new("TextButton", {
	Size = UDim2.fromScale(0.13, 0.13),
	Position = UDim2.fromScale(0.6, 0.84),
	BackgroundColor3 = Color3.fromRGB(50, 60, 55),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	TextColor3 = Color3.fromRGB(220, 220, 220),
	Text = "AUTO\nOFF",
	Parent = gui,
})
corner(autoBtn, 18)

-- Carte de résultat (centre)
local resultCard = new("TextLabel", {
	Size = UDim2.fromScale(0.44, 0.13),
	Position = UDim2.fromScale(0.28, 0.3),
	BackgroundColor3 = Color3.fromRGB(15, 20, 15),
	BackgroundTransparency = 0.1,
	Font = Enum.Font.GothamBlack,
	TextScaled = true,
	TextColor3 = Color3.fromRGB(255, 255, 255),
	Text = "",
	Visible = false,
	Parent = gui,
})
corner(resultCard, 16)
local resultStroke = new("UIStroke", { Color = Color3.fromRGB(255, 255, 255), Thickness = 3, Parent = resultCard })

-- ─── Inventaire : (re)construction ───
local selectedId = nil
local function rebuildInventory(inventory, selected)
	selectedId = selected
	for _, child in invScroll:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	for _, house in Houses.List do -- ordre par rareté
		local count = inventory[house.id]
		if count and count > 0 then
			local btn = new("TextButton", {
				Size = UDim2.new(1, 0, 0, 34),
				BackgroundColor3 = Color3.fromRGB(30, 40, 32),
				Font = Enum.Font.GothamBold,
				TextScaled = true,
				TextColor3 = Houses.RarityColor[house.rarity],
				Text = "  " .. house.name .. "  x" .. count,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = invScroll,
			})
			corner(btn, 8)
			if house.id == selected then
				new("UIStroke", { Color = Color3.fromRGB(255, 255, 255), Thickness = 2.5, Parent = btn })
			end
			btn.MouseButton1Click:Connect(function()
				SelectEvent:FireServer(house.id)
			end)
		end
	end
end

-- ─── Résultat d'un tirage ───
local hideToken = 0
local function showResult(info)
	local color = Houses.RarityColor[info.rarity] or Color3.fromRGB(255, 255, 255)
	local rare = info.tier and info.tier >= 4
	resultCard.TextColor3 = color
	resultStroke.Color = color
	resultCard.Text = string.format(
		"%s\n%s  •  1 sur %s%s",
		info.name,
		info.rarity,
		Houses.format(info.oneIn),
		rare and "  ⭐" or ""
	)
	resultCard.Visible = true
	resultCard.Size = UDim2.fromScale(0.4, 0.12)
	TweenService:Create(resultCard, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(0.44, 0.13),
	}):Play()

	hideToken += 1
	local myToken = hideToken
	task.delay(rare and 2 or 1, function()
		if myToken == hideToken then
			resultCard.Visible = false
		end
	end)
end
ResultEvent.OnClientEvent:Connect(showResult)

-- ─── Mise à jour des stats ───
local currentReq = math.huge
DataEvent.OnClientEvent:Connect(function(d)
	incomeLine.Text = string.format("📈 Revenu : +%s /s", Houses.format(d.income))
	luckLine.Text = string.format("🍀 Chance : Niv. %d (x%.1f)", d.luckLevel, d.luck)
	rebirthLine.Text = string.format("🔄 Renaissance : %d (x%.1f)", d.rebirths, d.mult)
	luckBtn.Text = "🍀 Chance +  (" .. Houses.format(d.luckCost) .. ")"
	rebirthBtn.Text = "🔄 Renaissance\n(" .. Houses.format(d.rebirthReq) .. ")"
	currentReq = d.rebirthReq
	rebuildInventory(d.inventory, d.selected)
end)

-- Argent temps réel + état du bouton Renaissance
local stats = player:WaitForChild("leaderstats")
local argent = stats:WaitForChild("Argent")
local function refreshCash()
	cashLabel.Text = "💰 " .. Houses.format(argent.Value)
	local ok = argent.Value >= currentReq
	rebirthBtn.BackgroundColor3 = ok and Color3.fromRGB(160, 90, 210) or Color3.fromRGB(70, 55, 90)
end
argent.Changed:Connect(refreshCash)
refreshCash()

-- ─── Actions ───
local lastRoll = 0
local function tryRoll()
	local now = os.clock()
	if now - lastRoll < ROLL_COOLDOWN then
		return
	end
	lastRoll = now
	RollEvent:FireServer()
end

rollBtn.MouseButton1Click:Connect(tryRoll)
luckBtn.MouseButton1Click:Connect(function()
	LuckEvent:FireServer()
end)
rebirthBtn.MouseButton1Click:Connect(function()
	RebirthEvent:FireServer()
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.R then
		tryRoll()
	end
end)

local auto = false
autoBtn.MouseButton1Click:Connect(function()
	auto = not auto
	autoBtn.Text = auto and "AUTO\nON" or "AUTO\nOFF"
	autoBtn.BackgroundColor3 = auto and Color3.fromRGB(70, 160, 90) or Color3.fromRGB(50, 60, 55)
end)
task.spawn(function()
	while true do
		if auto then
			tryRoll()
		end
		task.wait(ROLL_COOLDOWN)
	end
end)

print("🏠 House RNG Tycoon — interface prête")
