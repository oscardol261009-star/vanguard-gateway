-- 🏠 House RNG Tycoon — logique serveur (autorité)
--
-- Boucle : ROLL -> maisons dans l'inventaire -> on les POSE sur une grille de
-- cases -> chaque maison posée rapporte de l'argent -> RENAISSANCE pour un
-- multiplicateur permanent. Améliorations : Chance (meilleurs tirages).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Houses = require(ReplicatedStorage.Shared.Houses)
local World = require(script.World)

World.build()

-- ─── Remotes ───
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = ReplicatedStorage

local function makeEvent(name: string): RemoteEvent
	local e = Instance.new("RemoteEvent")
	e.Name = name
	e.Parent = remotes
	return e
end

local RollEvent = makeEvent("Roll")
local ResultEvent = makeEvent("RollResult")
local DataEvent = makeEvent("UpdateData")
local LuckEvent = makeEvent("BuyLuck")
local SelectEvent = makeEvent("Select") -- client choisit une maison de l'inventaire
local RebirthEvent = makeEvent("Rebirth")

-- ─── Réglages ───
local ROLL_COOLDOWN = 0.3
local PLOT_SIZE = 58
local PLOT_GAP = 16
local PLOTS_PER_ROW = 5
local GRID = 4 -- grille 4x4 = 16 cases
local SLOTS = GRID * GRID
local SPACING = 12
local LUCK_BASE_COST = 150
local LUCK_STEP = 0.6
local REBIRTH_BASE = 10000
local REBIRTH_MULT_STEP = 0.5 -- +50% de revenu par renaissance
local REBIRTH_LUCK_STEP = 1 -- +1 de chance par renaissance

local data = {}

local function luckCost(level: number): number
	return math.floor(LUCK_BASE_COST * (1.7 ^ level))
end
local function rebirthReq(n: number): number
	return math.floor(REBIRTH_BASE * (6 ^ n))
end

-- ─── Construction d'un terrain + sa grille de cases cliquables ───
local freePlots = {}
local nextPlotIndex = 0

local function buildPlot(index: number)
	local col = index % PLOTS_PER_ROW
	local row = math.floor(index / PLOTS_PER_ROW)
	local origin = Vector3.new(col * (PLOT_SIZE + PLOT_GAP), 0.5, row * (PLOT_SIZE + PLOT_GAP) - 140)

	local model = Instance.new("Model")
	model.Name = "Plot_" .. index

	-- rebord en pierre (un peu plus grand, plus bas)
	local rim = Instance.new("Part")
	rim.Anchored = true
	rim.Size = Vector3.new(PLOT_SIZE + 4, 2, PLOT_SIZE + 4)
	rim.Position = origin - Vector3.new(0, 0.4, 0)
	rim.Color = Color3.fromRGB(90, 96, 105)
	rim.Material = Enum.Material.Slate
	rim.TopSurface = Enum.SurfaceType.Smooth
	rim.Parent = model

	local base = Instance.new("Part")
	base.Anchored = true
	base.Size = Vector3.new(PLOT_SIZE, 2, PLOT_SIZE)
	base.Position = origin
	base.Color = Color3.fromRGB(96, 150, 92)
	base.Material = Enum.Material.Grass
	base.TopSurface = Enum.SurfaceType.Smooth
	base.Parent = model

	model.Parent = workspace

	local top = origin + Vector3.new(0, 1, 0)
	local pads = {}
	for slot = 0, SLOTS - 1 do
		local c = slot % GRID
		local r = math.floor(slot / GRID)
		local pos = top + Vector3.new((c - (GRID - 1) / 2) * SPACING, 0.15, (r - (GRID - 1) / 2) * SPACING)

		-- halo néon sous la case
		local glow = Instance.new("Part")
		glow.Name = "Glow_" .. slot
		glow.Anchored = true
		glow.Size = Vector3.new(SPACING - 0.6, 0.2, SPACING - 0.6)
		glow.Position = pos - Vector3.new(0, 0.15, 0)
		glow.Color = Color3.fromRGB(120, 235, 170)
		glow.Material = Enum.Material.Neon
		glow.Transparency = 0.55
		glow.CanCollide = false
		glow.Parent = model

		local pad = Instance.new("Part")
		pad.Name = "Pad_" .. slot
		pad.Anchored = true
		pad.Size = Vector3.new(SPACING - 1.5, 0.4, SPACING - 1.5)
		pad.Position = pos
		pad.Color = Color3.fromRGB(70, 110, 80)
		pad.Material = Enum.Material.SmoothPlastic
		pad.Transparency = 0.35
		pad.Parent = model

		local cd = Instance.new("ClickDetector")
		cd.MaxActivationDistance = 90
		cd.Parent = pad

		pads[slot] = pad
	end

	return { model = model, origin = top, pads = pads }
end

local function getPlot()
	if #freePlots > 0 then
		return table.remove(freePlots)
	end
	local p = buildPlot(nextPlotIndex)
	nextPlotIndex += 1
	return p
end

-- ─── Construction visuelle d'une maison sur une case ───
local function buildHouseOnPad(d, slot: number, house, tier: number)
	if d.placedModels[slot] then
		d.placedModels[slot]:Destroy()
		d.placedModels[slot] = nil
	end

	local pad = d.plot.pads[slot]
	local cx, cz = pad.Position.X, pad.Position.Z
	local y = pad.Position.Y

	local model = Instance.new("Model")
	model.Name = "House_" .. slot

	local floors = math.min(tier, 6)
	local floorH = 3
	local baseW = 7

	for f = 1, floors do
		local shrink = (f - 1) * 0.7
		local part = Instance.new("Part")
		part.Anchored = true
		part.Size = Vector3.new(baseW - shrink, floorH, baseW - shrink)
		part.Position = Vector3.new(cx, y + floorH / 2 + (f - 1) * floorH, cz)
		part.Color = house.color
		part.Material = Enum.Material.SmoothPlastic
		part.Parent = model
	end

	local topY = y + floors * floorH

	local roof = Instance.new("Part")
	roof.Anchored = true
	roof.Size = Vector3.new(baseW - (floors - 1) * 0.7 + 1.5, 1, baseW - (floors - 1) * 0.7 + 1.5)
	roof.Position = Vector3.new(cx, topY + 0.5, cz)
	roof.Color = Color3.fromRGB(60, 48, 42)
	roof.Material = Enum.Material.Slate
	roof.Parent = model

	local door = Instance.new("Part")
	door.Anchored = true
	door.Size = Vector3.new(2, 3, 0.4)
	door.Position = Vector3.new(cx, y + 1.5, cz - baseW / 2)
	door.Color = Color3.fromRGB(48, 30, 20)
	door.Parent = model

	if tier >= 5 then
		local spire = Instance.new("Part")
		spire.Anchored = true
		spire.Size = Vector3.new(1, 6, 1)
		spire.Position = Vector3.new(cx, topY + 3.5, cz)
		spire.Color = Color3.fromRGB(235, 205, 120)
		spire.Material = Enum.Material.Metal
		spire.Parent = model
	end
	if tier >= 6 then
		local orb = Instance.new("Part")
		orb.Anchored = true
		orb.Shape = Enum.PartType.Ball
		orb.Size = Vector3.new(3, 3, 3)
		orb.Position = Vector3.new(cx, topY + 8, cz)
		orb.Color = house.color
		orb.Material = Enum.Material.Neon
		orb.Parent = model
		local light = Instance.new("PointLight")
		light.Color = house.color
		light.Range = 22
		light.Brightness = 3
		light.Parent = orb
	end

	local bb = Instance.new("BillboardGui")
	bb.Adornee = roof
	bb.Size = UDim2.fromOffset(150, 30)
	bb.StudsOffset = Vector3.new(0, 2.5, 0)
	bb.AlwaysOnTop = true
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamBold
	lbl.TextScaled = true
	lbl.TextColor3 = Houses.RarityColor[house.rarity]
	lbl.TextStrokeTransparency = 0.4
	lbl.Text = house.name
	lbl.Parent = bb
	bb.Parent = roof

	model.Parent = d.plot.model
	d.placedModels[slot] = model
end

-- ─── Revenu total = somme des maisons posées × multiplicateur ───
local function recomputeIncome(d)
	local total = 0
	for _, id in d.grid do
		total += Houses.ById[id].income
	end
	d.income = total * d.mult
end

local function pushData(player)
	local d = data[player]
	if not d then
		return
	end
	DataEvent:FireClient(player, {
		cash = d.cash,
		luckLevel = d.luckLevel,
		luck = d.luck,
		luckCost = luckCost(d.luckLevel),
		rebirths = d.rebirths,
		mult = d.mult,
		rebirthReq = rebirthReq(d.rebirths),
		income = d.income,
		inventory = d.inventory,
		selected = d.selected,
	})
end

-- ─── Poser / reprendre une maison quand on clique une case ───
local function setSlotVisual(d, slot: number, occupied: boolean)
	d.plot.pads[slot].Transparency = occupied and 0.9 or 0.35
	local glow = d.plot.model:FindFirstChild("Glow_" .. slot)
	if glow then
		glow.Transparency = occupied and 1 or 0.55
	end
end

local function onPadClicked(player, slot: number)
	local d = data[player]
	if not d then
		return
	end

	local placed = d.grid[slot]
	if placed then
		-- reprendre : la maison retourne dans l'inventaire
		d.inventory[placed] = (d.inventory[placed] or 0) + 1
		d.grid[slot] = nil
		if d.placedModels[slot] then
			d.placedModels[slot]:Destroy()
			d.placedModels[slot] = nil
		end
		setSlotVisual(d, slot, false)
		recomputeIncome(d)
		pushData(player)
		return
	end

	-- poser la maison sélectionnée
	local id = d.selected
	if not id or (d.inventory[id] or 0) <= 0 then
		return
	end
	d.inventory[id] -= 1
	if d.inventory[id] <= 0 then
		d.inventory[id] = nil
		d.selected = nil
	end
	d.grid[slot] = id
	setSlotVisual(d, slot, true)
	buildHouseOnPad(d, slot, Houses.ById[id], Houses.TierById[id])
	recomputeIncome(d)
	pushData(player)
end

-- ─── Connexion ───
Players.PlayerAdded:Connect(function(player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	stats.Parent = player

	local cash = Instance.new("IntValue")
	cash.Name = "Argent"
	cash.Parent = stats

	local reb = Instance.new("IntValue")
	reb.Name = "Renaissance"
	reb.Parent = stats

	local plot = getPlot()

	local d = {
		cashFloat = 0,
		cash = 0,
		luckLevel = 0,
		luck = 1,
		rebirths = 0,
		mult = 1,
		income = 0,
		inventory = { cabane = 3 }, -- 3 cabanes pour démarrer
		grid = {},
		placedModels = {},
		plot = plot,
		selected = "cabane",
		lastRoll = 0,
	}
	data[player] = d

	-- brancher le clic de chaque case
	for slot = 0, SLOTS - 1 do
		local cd = plot.pads[slot]:FindFirstChildOfClass("ClickDetector")
		if cd then
			cd.MouseClick:Connect(function(clicker)
				if clicker == player then
					onPadClicked(player, slot)
				end
			end)
		end
	end

	-- poser une cabane de départ pour amorcer le revenu
	d.inventory.cabane = 2
	d.grid[0] = "cabane"
	setSlotVisual(d, 0, true)
	buildHouseOnPad(d, 0, Houses.ById.cabane, 1)
	recomputeIncome(d)

	player.CharacterAdded:Connect(function(char)
		local hrp = char:WaitForChild("HumanoidRootPart")
		task.wait(0.15)
		hrp.CFrame = CFrame.new(plot.origin + Vector3.new(0, 6, PLOT_SIZE / 2 - 5))
	end)

	pushData(player)
end)

Players.PlayerRemoving:Connect(function(player)
	local d = data[player]
	if d then
		d.plot.model:Destroy()
		-- terrain recréé à la volée pour le prochain (évite les modèles orphelins)
	end
	data[player] = nil
end)

-- ─── Tirage : va dans l'inventaire ───
RollEvent.OnServerEvent:Connect(function(player)
	local d = data[player]
	if not d then
		return
	end
	local now = os.clock()
	if now - d.lastRoll < ROLL_COOLDOWN then
		return
	end
	d.lastRoll = now

	local house = Houses.roll(d.luck)
	d.inventory[house.id] = (d.inventory[house.id] or 0) + 1
	if not d.selected then
		d.selected = house.id
	end

	ResultEvent:FireClient(player, {
		name = house.name,
		rarity = house.rarity,
		income = house.income,
		oneIn = Houses.oneIn(house),
		tier = Houses.TierById[house.id],
	})
	pushData(player)
end)

-- ─── Sélection d'une maison de l'inventaire ───
SelectEvent.OnServerEvent:Connect(function(player, houseId)
	local d = data[player]
	if not d or typeof(houseId) ~= "string" then
		return
	end
	if (d.inventory[houseId] or 0) > 0 then
		d.selected = houseId
		pushData(player)
	end
end)

-- ─── Achat de Chance ───
LuckEvent.OnServerEvent:Connect(function(player)
	local d = data[player]
	if not d then
		return
	end
	local cost = luckCost(d.luckLevel)
	if d.cashFloat < cost then
		return
	end
	d.cashFloat -= cost
	d.cash = math.floor(d.cashFloat)
	d.luckLevel += 1
	d.luck = 1 + d.luckLevel * LUCK_STEP
	player.leaderstats.Argent.Value = d.cash
	pushData(player)
end)

-- ─── Renaissance ───
RebirthEvent.OnServerEvent:Connect(function(player)
	local d = data[player]
	if not d then
		return
	end
	if d.cashFloat < rebirthReq(d.rebirths) then
		return
	end
	d.rebirths += 1
	d.mult = 1 + d.rebirths * REBIRTH_MULT_STEP
	d.luck += REBIRTH_LUCK_STEP
	d.cashFloat = 0
	d.cash = 0
	player.leaderstats.Argent.Value = 0
	player.leaderstats.Renaissance.Value = d.rebirths
	recomputeIncome(d)
	pushData(player)
end)

-- ─── Boucle de revenu ───
RunService.Heartbeat:Connect(function(dt)
	for player, d in data do
		if d.income > 0 then
			d.cashFloat += d.income * dt
			local rounded = math.floor(d.cashFloat)
			if rounded ~= d.cash then
				d.cash = rounded
				local stats = player:FindFirstChild("leaderstats")
				if stats then
					stats.Argent.Value = rounded
				end
			end
		end
	end
end)

print("🏠 House RNG Tycoon — serveur démarré")
