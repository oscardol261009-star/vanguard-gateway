-- 🏠 House RNG Simulator — interface joueur
--
-- Bouton ROLL (+ auto-roll), carte de résultat animée, panneau de stats,
-- bouton d'amélioration Chance. Tout est construit par code, aucun GUI à poser.

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

local player = Players.LocalPlayer
local ROLL_COOLDOWN = 0.35

-- ─── Petits utilitaires de création ───
local function corner(parent: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
	return c
end

local function new(class: string, props: { [string]: any }): any
	local o = Instance.new(class)
	for k, v in props do
		(o :: any)[k] = v
	end
	return o
end

-- ─── GUI ───
local gui = new("ScreenGui", {
	Name = "HouseRNG",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui"),
})

-- Argent (en haut, doré)
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
new("UIStroke", { Color = Color3.fromRGB(255, 214, 90), Thickness = 1.5, Transparency = 0.5, Parent = cashLabel })

-- Panneau de stats (à gauche)
local panel = new("Frame", {
	Size = UDim2.fromScale(0.26, 0.24),
	Position = UDim2.fromScale(0.02, 0.14),
	BackgroundColor3 = Color3.fromRGB(18, 24, 18),
	BackgroundTransparency = 0.2,
	Parent = gui,
})
corner(panel, 14)
local pad = new("UIPadding", { Parent = panel })
pad.PaddingLeft = UDim.new(0, 12)
pad.PaddingTop = UDim.new(0, 10)
local layout = new("UIListLayout", {
	Padding = UDim.new(0, 6),
	Parent = panel,
})

local function statLine(txt: string)
	return new("TextLabel", {
		Size = UDim2.fromScale(0.95, 0.2),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(230, 240, 230),
		Text = txt,
		Parent = panel,
	})
end

local bestLine = statLine("🏆 Meilleure : Cabane")
local incomeLine = statLine("📈 Revenu : +1 /s")
local luckLine = statLine("🍀 Chance : Niv. 0 (x1.0)")

-- Bouton Chance (amélioration)
local luckBtn = new("TextButton", {
	Size = UDim2.fromScale(0.26, 0.08),
	Position = UDim2.fromScale(0.02, 0.4),
	BackgroundColor3 = Color3.fromRGB(60, 130, 70),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	TextColor3 = Color3.fromRGB(255, 255, 255),
	Text = "🍀 Chance +  (150)",
	AutoButtonColor = true,
	Parent = gui,
})
corner(luckBtn, 12)

-- Bouton ROLL (gros, en bas)
local rollBtn = new("TextButton", {
	Size = UDim2.fromScale(0.42, 0.14),
	Position = UDim2.fromScale(0.29, 0.82),
	BackgroundColor3 = Color3.fromRGB(70, 200, 110),
	Font = Enum.Font.GothamBlack,
	TextScaled = true,
	TextColor3 = Color3.fromRGB(10, 40, 20),
	Text = "🎲 ROLL",
	AutoButtonColor = true,
	Parent = gui,
})
corner(rollBtn, 18)
new("UIStroke", { Color = Color3.fromRGB(255, 255, 255), Thickness = 2, Transparency = 0.3, Parent = rollBtn })

-- Bouton AUTO
local autoBtn = new("TextButton", {
	Size = UDim2.fromScale(0.14, 0.14),
	Position = UDim2.fromScale(0.72, 0.82),
	BackgroundColor3 = Color3.fromRGB(50, 60, 55),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	TextColor3 = Color3.fromRGB(220, 220, 220),
	Text = "AUTO\nOFF",
	AutoButtonColor = true,
	Parent = gui,
})
corner(autoBtn, 18)

-- Carte de résultat (au centre, cachée par défaut)
local resultCard = new("TextLabel", {
	Size = UDim2.fromScale(0.5, 0.16),
	Position = UDim2.fromScale(0.25, 0.32),
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

-- ─── Résultat d'un tirage ───
local hideToken = 0
local function showResult(info)
	local color = Houses.RarityColor[info.rarity] or Color3.fromRGB(255, 255, 255)
	resultCard.TextColor3 = color
	resultStroke.Color = color
	resultCard.Text = string.format(
		"%s\n%s  •  1 sur %s%s",
		info.name,
		info.rarity,
		Houses.format(info.oneIn),
		info.isNewBest and "  ⭐ NOUVEAU !" or ""
	)
	resultCard.Visible = true

	-- petit pop
	resultCard.Size = UDim2.fromScale(0.44, 0.14)
	TweenService:Create(resultCard, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(0.5, 0.16),
	}):Play()

	hideToken += 1
	local myToken = hideToken
	task.delay(info.isNewBest and 2.2 or 1.1, function()
		if myToken == hideToken then
			resultCard.Visible = false
		end
	end)
end

ResultEvent.OnClientEvent:Connect(showResult)

-- ─── Mise à jour des stats ───
DataEvent.OnClientEvent:Connect(function(d)
	bestLine.Text = "🏆 Meilleure : " .. d.bestName
	incomeLine.Text = "📈 Revenu : +" .. Houses.format(d.income) .. " /s"
	luckLine.Text = string.format("🍀 Chance : Niv. %d (x%.1f)", d.luckLevel, d.luck)
	luckBtn.Text = "🍀 Chance +  (" .. Houses.format(d.luckCost) .. ")"
end)

-- Argent en temps réel depuis leaderstats
local stats = player:WaitForChild("leaderstats")
local argent = stats:WaitForChild("Argent")
local function refreshCash()
	cashLabel.Text = "💰 " .. Houses.format(argent.Value)
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

-- clavier : R pour roll
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.R then
		tryRoll()
	end
end)

-- auto-roll
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

print("🏠 House RNG Simulator — interface prête")
