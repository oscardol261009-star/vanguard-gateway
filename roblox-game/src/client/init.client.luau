-- 🏠 House RNG Tycoon — HUD joueur
--
-- Plus de bouton "roll" : les maisons s'achètent directement au marché
-- (présentoirs qui tournent dans le monde, E pour acheter), puis se posent
-- sur la grille perso. La révélation de l'achat se joue en 3D (voir Reveal).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Houses = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Houses"))
local Reveal = require(script.Reveal)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local AcquiredEvent = remotes:WaitForChild("Acquired")
local DataEvent = remotes:WaitForChild("UpdateData")
local DiscountEvent = remotes:WaitForChild("BuyDiscount")
local SelectEvent = remotes:WaitForChild("Select")
local RebirthEvent = remotes:WaitForChild("Rebirth")

local player = Players.LocalPlayer

local PANEL_TOP = Color3.fromRGB(30, 36, 46)
local PANEL_BOT = Color3.fromRGB(17, 20, 27)
local GOLD = Color3.fromRGB(255, 206, 84)
local TXT = Color3.fromRGB(236, 241, 247)
local DIM = Color3.fromRGB(150, 165, 182)

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

-- Argent (haut)
local cashPill = panel({
	Size = UDim2.fromScale(0.32, 0.08),
	Position = UDim2.fromScale(0.34, 0.025),
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

-- Stats (gauche)
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
local discountLine = statLine()
local rebirthLine = statLine()

local function bigButton(pos, c1, c2)
	local b = new("TextButton", {
		Size = UDim2.fromScale(0.24, 0.075),
		Position = pos,
		BackgroundColor3 = c1,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		Text = "",
		Parent = gui,
	})
	corner(b, 12)
	gradient(b, c1, c2, 90)
	stroke(b, Color3.fromRGB(255, 255, 255), 1.5, 0.6)
	new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4), Parent = b })
	return b
end
local discountBtn = bigButton(UDim2.fromScale(0.02, 0.35), Color3.fromRGB(72, 170, 92), Color3.fromRGB(44, 120, 66))
local rebirthBtn = bigButton(UDim2.fromScale(0.02, 0.44), Color3.fromRGB(150, 92, 210), Color3.fromRGB(96, 54, 150))

-- Inventaire (droite)
local invPanel = panel({
	Size = UDim2.fromScale(0.23, 0.62),
	Position = UDim2.fromScale(0.75, 0.13),
	Parent = gui,
})
new("TextLabel", {
	Size = UDim2.fromScale(1, 0.07),
	BackgroundTransparency = 1,
	Font = Enum.Font.FredokaOne,
	TextScaled = true,
	TextColor3 = TXT,
	Text = "🎒 Inventaire",
	Parent = invPanel,
})
new("TextLabel", {
	Size = UDim2.fromScale(0.9, 0.11),
	Position = UDim2.fromScale(0.05, 0.07),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	TextScaled = true,
	TextWrapped = true,
	TextColor3 = DIM,
	Text = "Achète au marché (E), puis clique une case verte pour poser.",
	Parent = invPanel,
})
local invScroll = new("ScrollingFrame", {
	Size = UDim2.fromScale(0.92, 0.76),
	Position = UDim2.fromScale(0.04, 0.21),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 5,
	ScrollBarImageColor3 = DIM,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	Parent = invPanel,
})
new("UIListLayout", { Padding = UDim.new(0, 6), Parent = invScroll })

-- ─── Inventaire : cartes ───
local function rebuildInventory(inventory, selected)
	for _, c in invScroll:GetChildren() do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	local any = false
	for _, house in Houses.List do
		local count = inventory[house.id]
		if count and count > 0 then
			any = true
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
	if not any then
		new("TextLabel", {
			Size = UDim2.new(1, 0, 0, 60),
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			TextScaled = true,
			TextWrapped = true,
			TextColor3 = DIM,
			Text = "Vide. Va acheter une maison au marché !",
			Parent = invScroll,
		})
	end
end

-- ─── La révélation d'un achat se joue dans le monde 3D ───
AcquiredEvent.OnClientEvent:Connect(function(info)
	Reveal.play(info)
end)

-- ─── État ───
local currentReq = math.huge
DataEvent.OnClientEvent:Connect(function(d)
	incomeLine.Text = string.format("📈 Revenu : +%s /s", Houses.format(d.income))
	discountLine.Text = string.format("🏷️ Remise : Niv.%d (-%d%%)", d.luckLevel, math.min(75, d.luckLevel * 3))
	rebirthLine.Text = string.format("🔄 Renaissance : %d (x%.1f)", d.rebirths, d.mult)
	discountBtn.Text = "🏷️ Remise +\n" .. Houses.format(d.luckCost)
	rebirthBtn.Text = "🔄 Renaissance\n" .. Houses.format(d.rebirthReq)
	currentReq = d.rebirthReq
	rebuildInventory(d.inventory, d.selected)
end)

local stats = player:WaitForChild("leaderstats")
local argent = stats:WaitForChild("Argent")
local function refreshCash()
	cashLabel.Text = "💰 " .. Houses.format(argent.Value)
	rebirthBtn.BackgroundTransparency = (argent.Value >= currentReq) and 0 or 0.35
end
argent.Changed:Connect(refreshCash)
refreshCash()

-- ─── Actions ───
discountBtn.MouseButton1Click:Connect(function()
	DiscountEvent:FireServer()
end)
rebirthBtn.MouseButton1Click:Connect(function()
	RebirthEvent:FireServer()
end)

print("🏠 House RNG Tycoon — HUD prêt")
