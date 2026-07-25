--!strict
-- Données du jeu : la liste des maisons (rareté, revenu, prix, matériaux).
-- Utilisé côté serveur (marché, construction, revenu) et côté client (affichage).

local Houses = {}

export type House = {
	id: string,
	name: string,
	rarity: string,
	weight: number, -- poids relatif d'apparition au marché : plus petit = plus rare
	income: number, -- argent par seconde une fois posée
	cost: number, -- prix d'achat au marché (avant remise)
	color: Color3,
	wallMaterial: Enum.Material,
	roofMaterial: Enum.Material,
	trimColor: Color3,
	windowColor: Color3,
}

-- Du plus commun au plus rare. L'ordre = le niveau (tier) de la maison.
Houses.List = {
	{
		id = "cabane", name = "Cabane", rarity = "Commun",
		weight = 1000, income = 1, cost = 50,
		color = Color3.fromRGB(150, 111, 80),
		wallMaterial = Enum.Material.WoodPlanks, roofMaterial = Enum.Material.Slate,
		trimColor = Color3.fromRGB(74, 52, 38), windowColor = Color3.fromRGB(200, 225, 235),
	},
	{
		id = "maison", name = "Maison", rarity = "Peu commun",
		weight = 400, income = 6, cost = 400,
		color = Color3.fromRGB(222, 222, 222),
		wallMaterial = Enum.Material.Brick, roofMaterial = Enum.Material.Slate,
		trimColor = Color3.fromRGB(70, 60, 55), windowColor = Color3.fromRGB(195, 222, 235),
	},
	{
		id = "villa", name = "Villa", rarity = "Rare",
		weight = 150, income = 30, cost = 2500,
		color = Color3.fromRGB(235, 238, 242),
		wallMaterial = Enum.Material.Concrete, roofMaterial = Enum.Material.Pebble,
		trimColor = Color3.fromRGB(90, 170, 255), windowColor = Color3.fromRGB(150, 210, 255),
	},
	{
		id = "manoir", name = "Manoir", rarity = "Épique",
		weight = 40, income = 150, cost = 15000,
		color = Color3.fromRGB(238, 232, 245),
		wallMaterial = Enum.Material.Marble, roofMaterial = Enum.Material.Slate,
		trimColor = Color3.fromRGB(180, 110, 255), windowColor = Color3.fromRGB(210, 180, 255),
	},
	{
		id = "chateau", name = "Château", rarity = "Légendaire",
		weight = 9, income = 800, cost = 90000,
		color = Color3.fromRGB(240, 236, 220),
		wallMaterial = Enum.Material.Marble, roofMaterial = Enum.Material.Metal,
		trimColor = Color3.fromRGB(255, 185, 55), windowColor = Color3.fromRGB(255, 224, 160),
	},
	{
		id = "palais", name = "Palais", rarity = "Mythique",
		weight = 1.5, income = 4000, cost = 600000,
		color = Color3.fromRGB(255, 235, 245),
		wallMaterial = Enum.Material.Marble, roofMaterial = Enum.Material.Metal,
		trimColor = Color3.fromRGB(255, 80, 130), windowColor = Color3.fromRGB(255, 180, 210),
	},
	{
		id = "palais_or", name = "Palais d'Or", rarity = "Secret",
		weight = 0.15, income = 25000, cost = 5000000,
		color = Color3.fromRGB(255, 221, 120),
		wallMaterial = Enum.Material.Metal, roofMaterial = Enum.Material.Metal,
		trimColor = Color3.fromRGB(255, 240, 120), windowColor = Color3.fromRGB(255, 250, 200),
	},
}

Houses.RarityColor = {
	["Commun"] = Color3.fromRGB(205, 205, 205),
	["Peu commun"] = Color3.fromRGB(120, 220, 120),
	["Rare"] = Color3.fromRGB(90, 170, 255),
	["Épique"] = Color3.fromRGB(190, 110, 255),
	["Légendaire"] = Color3.fromRGB(255, 190, 60),
	["Mythique"] = Color3.fromRGB(255, 80, 130),
	["Secret"] = Color3.fromRGB(255, 240, 120),
}

-- Tables d'accès rapide
Houses.TierById = {} -- id -> index (le tier, de 1 à 7)
Houses.ById = {} -- id -> House
Houses.TotalWeight = 0
for i, h in Houses.List do
	Houses.TierById[h.id] = i
	Houses.ById[h.id] = h
	Houses.TotalWeight += h.weight
end

local rng = Random.new()

-- Tire une maison au hasard : utilisé pour choisir l'article affiché sur
-- chaque présentoir du marché. `luck` >= 1 booste les maisons rares.
function Houses.roll(luck: number): House
	luck = math.max(1, luck)
	local weights = table.create(#Houses.List)
	local total = 0
	for i, h in Houses.List do
		local w = if h.weight < 300 then h.weight * luck else h.weight
		weights[i] = w
		total += w
	end

	local r = rng:NextNumber() * total
	local acc = 0
	for i, h in Houses.List do
		acc += weights[i]
		if r <= acc then
			return h
		end
	end
	return Houses.List[1]
end

-- "1 sur X" (rareté de base) pour l'affichage, pure info/flavor.
function Houses.oneIn(house: House): number
	return math.max(1, math.floor(Houses.TotalWeight / house.weight))
end

-- Formate un grand nombre : 1234 -> "1.23K", 4500000 -> "4.50M"...
function Houses.format(n: number): string
	local a = math.abs(n)
	if a >= 1e12 then
		return string.format("%.2fT", n / 1e12)
	elseif a >= 1e9 then
		return string.format("%.2fB", n / 1e9)
	elseif a >= 1e6 then
		return string.format("%.2fM", n / 1e6)
	elseif a >= 1e3 then
		return string.format("%.2fK", n / 1e3)
	end
	return tostring(math.floor(n))
end

return Houses
