--!strict
-- Données du jeu : la liste des maisons, leurs raretés, leurs chances et leurs
-- revenus. Utilisé côté serveur (tirage + revenu) et côté client (affichage).

local Houses = {}

export type House = {
	id: string,
	name: string,
	rarity: string,
	weight: number, -- poids relatif : plus c'est petit, plus c'est rare
	income: number, -- argent par seconde quand la maison est posée
	color: Color3,
}

-- Du plus commun au plus rare. L'ordre = le niveau (tier) de la maison,
-- qui sert aussi à la faire grandir visuellement (nombre d'étages).
Houses.List = {
	{ id = "cabane", name = "Cabane", rarity = "Commun", weight = 1000, income = 1, color = Color3.fromRGB(150, 111, 80) },
	{ id = "maison", name = "Maison", rarity = "Peu commun", weight = 400, income = 6, color = Color3.fromRGB(205, 205, 205) },
	{ id = "villa", name = "Villa", rarity = "Rare", weight = 150, income = 30, color = Color3.fromRGB(90, 170, 255) },
	{ id = "manoir", name = "Manoir", rarity = "Épique", weight = 40, income = 150, color = Color3.fromRGB(180, 110, 255) },
	{ id = "chateau", name = "Château", rarity = "Légendaire", weight = 9, income = 800, color = Color3.fromRGB(255, 185, 55) },
	{ id = "palais", name = "Palais", rarity = "Mythique", weight = 1.5, income = 4000, color = Color3.fromRGB(255, 80, 130) },
	{ id = "palais_or", name = "Palais d'Or", rarity = "Secret", weight = 0.15, income = 25000, color = Color3.fromRGB(255, 235, 100) },
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

-- Table id -> index (le tier, de 1 à 7)
Houses.TierById = {}
Houses.TotalWeight = 0
for i, h in Houses.List do
	Houses.TierById[h.id] = i
	Houses.TotalWeight += h.weight
end

local rng = Random.new()

-- Tire une maison au hasard. `luck` >= 1 booste les maisons rares.
function Houses.roll(luck: number): House
	luck = math.max(1, luck)
	local weights = table.create(#Houses.List)
	local total = 0
	for i, h in Houses.List do
		-- seules les maisons déjà peu communes profitent de la chance
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

-- "1 sur X" (chances de base, sans la chance bonus) pour l'affichage.
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
