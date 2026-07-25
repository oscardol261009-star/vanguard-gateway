-- 🏠 House RNG Tycoon — logique serveur (autorité)
--
-- Boucle : au MARCHÉ (au sol, dans le monde), des présentoirs affichent une
-- maison qui change automatiquement ; on s'approche et on maintient E pour
-- l'ACHETER -> elle rejoint l'inventaire. On la POSE ensuite sur sa propre
-- grille (clic sur une case) où elle rapporte de l'argent/seconde. On
-- améliore la Remise (prix au marché moins cher) et on fait des Renaissances
-- pour un multiplicateur de revenu permanent.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Houses = require(ReplicatedStorage.Shared.Houses)
local HouseBuilder = require(script.HouseBuilder)
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

local AcquiredEvent = makeEvent("Acquired") -- serveur -> client : maison achetée (déclenche l'effet 3D)
local DataEvent = makeEvent("UpdateData")
local DiscountEvent = makeEvent("BuyDiscount")
local SelectEvent = makeEvent("Select")
local RebirthEvent = makeEvent("Rebirth")

-- ─── Réglages ───
local PLOT_SIZE = 58
local PLOT_GAP = 16
local PLOTS_PER_ROW = 5
local GRID = 4
local SLOTS = GRID * GRID
local SPACING = 12
local DISCOUNT_BASE_COST = 150
local DISCOUNT_STEP = 0.03 -- 3% de remise au marché par niveau
local DISCOUNT_MAX = 0.75
local REBIRTH_BASE = 5000
local REBIRTH_MULT_STEP = 0.5

local MARKET_CENTER = Vector3.new(120, 1, 40) -- même centre que la plaza (World.luau)
local MARKET_RADIUS = 26
local MARKET_STALLS = 8

local data = {}

local function discountCost(level: number): number
	return math.floor(DISCOUNT_BASE_COST * (1.7 ^ level))
end
local function rebirthReq(n: number): number
	return math.floor(REBIRTH_BASE * (5 ^ n))
end

-- ─── Terrains des joueurs ───
local freePlots = {}
local nextPlotIndex = 0

local function buildPlot(index: number)
	local col = index % PLOTS_PER_ROW
	local row = math.floor(index / PLOTS_PER_ROW)
	local origin = Vector3.new(col * (PLOT_SIZE + PLOT_GAP), 0.5, row * (PLOT_SIZE + PLOT_GAP) - 220)

	local model = Instance.new("Model")
	model.Name = "Plot_" .. index

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

		local glow = Instance.new("Part")
		glow.Name = "Glow_" .. slot
		glow.Anchored = true
		glow.CanCollide = false
		glow.Size = Vector3.new(SPACING - 0.6, 0.2, SPACING - 0.6)
		glow.Position = pos - Vector3.new(0, 0.15, 0)
		glow.Color = Color3.fromRGB(120, 235, 170)
		glow.Material = Enum.Material.Neon
		glow.Transparency = 0.55
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

local function setSlotVisual(d, slot: number, occupied: boolean)
	d.plot.pads[slot].Transparency = occupied and 0.9 or 0.35
	local glow = d.plot.model:FindFirstChild("Glow_" .. slot)
	if glow then
		glow.Transparency = occupied and 1 or 0.55
	end
end

local function buildHouseOnPad(d, slot: number, house, tier: number)
	if d.placedModels[slot] then
		d.placedModels[slot]:Destroy()
		d.placedModels[slot] = nil
	end
	local pad = d.plot.pads[slot]
	local model = HouseBuilder.build(d.plot.model, CFrame.new(pad.Position), house, tier, 1, {
		label = true,
		labelColor = Houses.RarityColor[house.rarity],
		subtitle = "+" .. Houses.format(house.income) .. " /s",
	})
	d.placedModels[slot] = model
end

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
		luckCost = discountCost(d.luckLevel),
		rebirths = d.rebirths,
		mult = d.mult,
		rebirthReq = rebirthReq(d.rebirths),
		income = d.income,
		inventory = d.inventory,
		selected = d.selected,
	})
end

-- ─── Marché : présentoirs qui changent d'article automatiquement ───
local pedestals = {}

local function refreshPedestal(i: number)
	local pd = pedestals[i]
	local house = Houses.roll(1)
	pd.house = house

	if pd.mini then
		pd.mini:Destroy()
	end
	pd.mini = HouseBuilder.build(pd.model, CFrame.new(pd.top), house, Houses.TierById[house.id], 0.42, {})

	local rc = Houses.RarityColor[house.rarity]
	pd.title.Text = house.name
	pd.title.TextColor3 = rc
	pd.sub.Text = house.rarity .. "  •  1 sur " .. Houses.format(Houses.oneIn(house))
	pd.price.Text = "💰 " .. Houses.format(house.cost)
	pd.prompt.ObjectText = house.name
	pd.prompt.ActionText = "Acheter (" .. Houses.format(house.cost) .. ")"
end

local function buildMarket()
	for i = 0, MARKET_STALLS - 1 do
		local angle = (i / MARKET_STALLS) * math.pi * 2
		local pos = MARKET_CENTER + Vector3.new(math.cos(angle) * MARKET_RADIUS, 0, math.sin(angle) * MARKET_RADIUS)

		local model = Instance.new("Model")
		model.Name = "Stall_" .. i
		model.Parent = workspace

		local stand = Instance.new("Part")
		stand.Anchored = true
		stand.Size = Vector3.new(6, 3, 6)
		stand.Position = pos + Vector3.new(0, 1.5, 0)
		stand.Color = Color3.fromRGB(70, 78, 92)
		stand.Material = Enum.Material.Marble
		stand.Parent = model

		local ring = Instance.new("Part")
		ring.Anchored = true
		ring.CanCollide = false
		ring.Shape = Enum.PartType.Cylinder
		ring.Size = Vector3.new(0.4, 6.6, 6.6)
		ring.Orientation = Vector3.new(0, 0, 90)
		ring.Position = pos + Vector3.new(0, 3.05, 0)
		ring.Color = Color3.fromRGB(255, 214, 90)
		ring.Material = Enum.Material.Neon
		ring.Parent = model

		local top = pos + Vector3.new(0, 3, 0)

		local bbAnchor = Instance.new("Part")
		bbAnchor.Anchored = true
		bbAnchor.CanCollide = false
		bbAnchor.Transparency = 1
		bbAnchor.Size = Vector3.new(1, 1, 1)
		bbAnchor.Position = top + Vector3.new(0, 7, 0)
		bbAnchor.Parent = model

		local bb = Instance.new("BillboardGui")
		bb.Adornee = bbAnchor
		bb.Size = UDim2.fromOffset(220, 80)
		bb.AlwaysOnTop = true
		bb.Parent = model

		local title = Instance.new("TextLabel")
		title.Size = UDim2.fromScale(1, 0.42)
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.FredokaOne
		title.TextScaled = true
		title.TextStrokeTransparency = 0.3
		title.Text = ""
		title.Parent = bb

		local sub = Instance.new("TextLabel")
		sub.Size = UDim2.fromScale(1, 0.3)
		sub.Position = UDim2.fromScale(0, 0.42)
		sub.BackgroundTransparency = 1
		sub.Font = Enum.Font.GothamMedium
		sub.TextScaled = true
		sub.TextColor3 = Color3.fromRGB(220, 225, 230)
		sub.TextStrokeTransparency = 0.4
		sub.Text = ""
		sub.Parent = bb

		local price = Instance.new("TextLabel")
		price.Size = UDim2.fromScale(1, 0.28)
		price.Position = UDim2.fromScale(0, 0.72)
		price.BackgroundTransparency = 1
		price.Font = Enum.Font.GothamBlack
		price.TextScaled = true
		price.TextColor3 = Color3.fromRGB(255, 214, 90)
		price.TextStrokeTransparency = 0.4
		price.Text = ""
		price.Parent = bb

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Acheter"
		prompt.ObjectText = ""
		prompt.HoldDuration = 0.35
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Parent = stand

		pedestals[i] = {
			model = model,
			top = top,
			title = title,
			sub = sub,
			price = price,
			prompt = prompt,
			mini = nil,
			house = nil,
		}

		prompt.Triggered:Connect(function(buyer)
			local d = data[buyer]
			local pd = pedestals[i]
			if not d or not pd.house then
				return
			end
			local discount = math.min(DISCOUNT_MAX, d.luckLevel * DISCOUNT_STEP)
			local cost = math.max(1, math.floor(pd.house.cost * (1 - discount)))
			if d.cashFloat < cost then
				return
			end
			d.cashFloat -= cost
			d.cash = math.floor(d.cashFloat)
			d.inventory[pd.house.id] = (d.inventory[pd.house.id] or 0) + 1
			buyer.leaderstats.Argent.Value = d.cash

			AcquiredEvent:FireClient(buyer, {
				name = pd.house.name,
				rarity = pd.house.rarity,
				oneIn = Houses.oneIn(pd.house),
				tier = Houses.TierById[pd.house.id],
			})
			pushData(buyer)
		end)

		task.spawn(function()
			task.wait(math.random() * 3)
			while true do
				refreshPedestal(i)
				task.wait(math.random(5, 9))
			end
		end)
	end
end

buildMarket()

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
		cashFloat = 150, -- de quoi acheter une première Maison ou plusieurs Cabanes
		cash = 150,
		luckLevel = 0,
		rebirths = 0,
		mult = 1,
		income = 0,
		inventory = {} :: { [string]: number },
		grid = {} :: { [number]: string },
		placedModels = {} :: { [number]: Model },
		plot = plot,
		selected = nil :: string?,
		lastRoll = 0,
	}
	data[player] = d
	cash.Value = d.cash

	for slot = 0, SLOTS - 1 do
		local cd = plot.pads[slot]:FindFirstChildOfClass("ClickDetector")
		if cd then
			cd.MouseClick:Connect(function(clicker)
				if clicker ~= player then
					return
				end
				local placed = d.grid[slot]
				if placed then
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
			end)
		end
	end

	-- une Cabane offerte, déjà posée, pour amorcer le revenu
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
	end
	data[player] = nil
end)

-- ─── Sélection d'une maison de l'inventaire (pour la poser) ───
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

-- ─── Amélioration : Remise au marché ───
DiscountEvent.OnServerEvent:Connect(function(player)
	local d = data[player]
	if not d then
		return
	end
	local cost = discountCost(d.luckLevel)
	if d.cashFloat < cost then
		return
	end
	d.cashFloat -= cost
	d.cash = math.floor(d.cashFloat)
	d.luckLevel += 1
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

print("🏠 House RNG Tycoon — serveur démarré (marché : " .. MARKET_STALLS .. " présentoirs)")
