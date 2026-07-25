-- 🏠 House RNG Simulator — logique serveur (autorité)
--
-- Gère : les terrains des joueurs, le tirage des maisons, la construction de la
-- meilleure maison sur le terrain, le revenu par seconde et l'amélioration Chance.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Houses = require(ReplicatedStorage.Shared.Houses)

-- ─── Remotes (créés par code, le client les attend avec WaitForChild) ───
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = ReplicatedStorage

local function makeEvent(name: string): RemoteEvent
	local e = Instance.new("RemoteEvent")
	e.Name = name
	e.Parent = remotes
	return e
end

local RollEvent = makeEvent("Roll") -- client -> serveur : demande un tirage
local ResultEvent = makeEvent("RollResult") -- serveur -> client : maison tirée
local DataEvent = makeEvent("UpdateData") -- serveur -> client : état du joueur
local LuckEvent = makeEvent("BuyLuck") -- client -> serveur : acheter de la chance

-- ─── Réglages ───
local ROLL_COOLDOWN = 0.35 -- secondes entre deux tirages
local PLOT_SIZE = 46
local PLOT_GAP = 14
local PLOTS_PER_ROW = 5
local LUCK_BASE_COST = 150
local LUCK_STEP = 0.6 -- +0.6 de chance par niveau

-- ─── État par joueur ───
local data = {} -- [player] = { cashFloat, cash, luckLevel, luck, bestTier, bestId, plot, lastRoll }

local function luckCost(level: number): number
	return math.floor(LUCK_BASE_COST * (1.7 ^ level))
end

-- ─── Terrains ───
local freePlots = {}
local nextPlotIndex = 0

local function buildPlot(index: number)
	local col = index % PLOTS_PER_ROW
	local row = math.floor(index / PLOTS_PER_ROW)
	local origin = Vector3.new(col * (PLOT_SIZE + PLOT_GAP), 0.5, row * (PLOT_SIZE + PLOT_GAP) - 120)

	local model = Instance.new("Model")
	model.Name = "Plot_" .. index

	local base = Instance.new("Part")
	base.Anchored = true
	base.Size = Vector3.new(PLOT_SIZE, 2, PLOT_SIZE)
	base.Position = origin
	base.Color = Color3.fromRGB(74, 108, 74)
	base.Material = Enum.Material.Grass
	base.TopSurface = Enum.SurfaceType.Smooth
	base.Parent = model

	model.Parent = workspace
	return { model = model, origin = origin + Vector3.new(0, 1, 0), houseModel = nil }
end

local function getPlot()
	if #freePlots > 0 then
		return table.remove(freePlots)
	end
	local p = buildPlot(nextPlotIndex)
	nextPlotIndex += 1
	return p
end

-- ─── Construction d'une maison sur un terrain (tout est généré par code) ───
local function buildHouse(plot, house, tier: number)
	if plot.houseModel then
		plot.houseModel:Destroy()
	end

	local model = Instance.new("Model")
	model.Name = "House"

	local cx, cz = plot.origin.X, plot.origin.Z
	local y = plot.origin.Y
	local floorH = 5
	local floors = tier -- 1 étage pour Cabane ... 7 pour Palais d'Or
	local baseW = 12

	for f = 1, floors do
		local shrink = (f - 1) * 0.9
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
	roof.Size = Vector3.new(baseW - (floors - 1) * 0.9 + 2, 1.4, baseW - (floors - 1) * 0.9 + 2)
	roof.Position = Vector3.new(cx, topY + 0.7, cz)
	roof.Color = Color3.fromRGB(60, 48, 42)
	roof.Material = Enum.Material.Slate
	roof.Parent = model

	local door = Instance.new("Part")
	door.Anchored = true
	door.Size = Vector3.new(3, 5, 0.5)
	door.Position = Vector3.new(cx, y + 2.5, cz - baseW / 2)
	door.Color = Color3.fromRGB(48, 30, 20)
	door.Material = Enum.Material.Wood
	door.Parent = model

	-- flèche dorée pour Légendaire+
	if tier >= 5 then
		local spire = Instance.new("Part")
		spire.Anchored = true
		spire.Size = Vector3.new(1.4, 9, 1.4)
		spire.Position = Vector3.new(cx, topY + 5, cz)
		spire.Color = Color3.fromRGB(235, 205, 120)
		spire.Material = Enum.Material.Metal
		spire.Parent = model
	end

	-- orbe lumineux pour Mythique+
	if tier >= 6 then
		local orb = Instance.new("Part")
		orb.Anchored = true
		orb.Shape = Enum.PartType.Ball
		orb.Size = Vector3.new(4, 4, 4)
		orb.Position = Vector3.new(cx, topY + 11, cz)
		orb.Color = house.color
		orb.Material = Enum.Material.Neon
		orb.Parent = model

		local light = Instance.new("PointLight")
		light.Color = house.color
		light.Range = 26
		light.Brightness = 3
		light.Parent = orb
	end

	-- étiquette flottante au-dessus
	local bb = Instance.new("BillboardGui")
	bb.Adornee = roof
	bb.Size = UDim2.fromOffset(230, 54)
	bb.StudsOffset = Vector3.new(0, 4, 0)
	bb.AlwaysOnTop = true

	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(1, 0.6)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.TextColor3 = Houses.RarityColor[house.rarity]
	title.TextStrokeTransparency = 0.4
	title.Text = house.name
	title.Parent = bb

	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.fromScale(1, 0.4)
	sub.Position = UDim2.fromScale(0, 0.6)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.GothamMedium
	sub.TextScaled = true
	sub.TextColor3 = Color3.fromRGB(230, 230, 230)
	sub.TextStrokeTransparency = 0.5
	sub.Text = "+" .. Houses.format(house.income) .. " /s"
	sub.Parent = bb

	bb.Parent = roof

	model.Parent = plot.model
	plot.houseModel = model
end

-- ─── Envoi de l'état au client ───
local function pushData(player)
	local d = data[player]
	if not d then
		return
	end
	local best = Houses.List[d.bestTier]
	DataEvent:FireClient(player, {
		cash = d.cash,
		luckLevel = d.luckLevel,
		luck = d.luck,
		luckCost = luckCost(d.luckLevel),
		bestName = best.name,
		bestRarity = best.rarity,
		income = best.income,
	})
end

-- ─── Connexion / déconnexion ───
Players.PlayerAdded:Connect(function(player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	stats.Parent = player

	local cash = Instance.new("IntValue")
	cash.Name = "Argent"
	cash.Parent = stats

	local maison = Instance.new("StringValue")
	maison.Name = "Maison"
	maison.Value = "Cabane"
	maison.Parent = stats

	local plot = getPlot()

	data[player] = {
		cashFloat = 0,
		cash = 0,
		luckLevel = 0,
		luck = 1,
		bestTier = 1,
		plot = plot,
		lastRoll = 0,
	}

	buildHouse(plot, Houses.List[1], 1) -- on démarre avec une Cabane

	player.CharacterAdded:Connect(function(char)
		local hrp = char:WaitForChild("HumanoidRootPart")
		task.wait(0.15)
		hrp.CFrame = CFrame.new(plot.origin + Vector3.new(0, 6, PLOT_SIZE / 2 - 6))
	end)

	pushData(player)
end)

Players.PlayerRemoving:Connect(function(player)
	local d = data[player]
	if d then
		if d.plot.houseModel then
			d.plot.houseModel:Destroy()
			d.plot.houseModel = nil
		end
		table.insert(freePlots, d.plot)
	end
	data[player] = nil
end)

-- ─── Tirage ───
RollEvent.OnServerEvent:Connect(function(player)
	local d = data[player]
	if not d then
		return
	end
	local now = os.clock()
	if now - d.lastRoll < ROLL_COOLDOWN then
		return -- anti-spam : le serveur décide
	end
	d.lastRoll = now

	local house = Houses.roll(d.luck)
	local tier = Houses.TierById[house.id]
	local isNewBest = tier > d.bestTier

	if isNewBest then
		d.bestTier = tier
		buildHouse(d.plot, house, tier)
		player.leaderstats.Maison.Value = house.name
		pushData(player)
	end

	ResultEvent:FireClient(player, {
		name = house.name,
		rarity = house.rarity,
		income = house.income,
		oneIn = Houses.oneIn(house),
		isNewBest = isNewBest,
	})
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

-- ─── Boucle de revenu ───
RunService.Heartbeat:Connect(function(dt)
	for player, d in data do
		local income = Houses.List[d.bestTier].income
		d.cashFloat += income * dt
		local rounded = math.floor(d.cashFloat)
		if rounded ~= d.cash then
			d.cash = rounded
			local stats = player:FindFirstChild("leaderstats")
			if stats then
				stats.Argent.Value = rounded
			end
		end
	end
end)

print("🏠 House RNG Simulator — serveur démarré")
