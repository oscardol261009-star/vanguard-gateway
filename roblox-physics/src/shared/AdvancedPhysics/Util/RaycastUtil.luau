--!nonstrict
--[[
	RaycastUtil.luau
	Helpers de lancer de rayons : paramètres réutilisables, casts ignorant
	dynamiquement certaines pièces, sondes de sol multi-rayons, ligne de vue.
]]

local Workspace = game:GetService("Workspace")

local VectorUtil = require(script.Parent.VectorUtil)

local RaycastUtil = {}

--[[ Crée un RaycastParams "exclusion" prêt à l'emploi. ]]
function RaycastUtil.params(ignoreList: { Instance }?, collisionGroup: string?, ignoreWater: boolean?): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignoreList or {}
	params.IgnoreWater = ignoreWater ~= false
	params.RespectCanCollide = true
	if collisionGroup then
		params.CollisionGroup = collisionGroup
	end
	return params
end

--[[
	Lance un rayon en ignorant à la volée les pièces refusées par `shouldIgnore`.
	Utile quand le filtre ne peut pas être connu à l'avance (ex. traverser
	les vitres mais pas les murs).
]]
function RaycastUtil.castIgnoring(
	origin: Vector3,
	direction: Vector3,
	params: RaycastParams,
	shouldIgnore: (result: RaycastResult) -> boolean,
	maxAttempts: number?
): RaycastResult?
	local attempts = maxAttempts or 8
	local ignored: { Instance } = table.clone(params.FilterDescendantsInstances)
	local workingParams = params
	local currentOrigin = origin
	local remaining = direction

	for _ = 1, attempts do
		local result = Workspace:Raycast(currentOrigin, remaining, workingParams)
		if not result then
			return nil
		end
		if not shouldIgnore(result) then
			return result
		end

		table.insert(ignored, result.Instance)
		workingParams = RaycastParams.new()
		workingParams.FilterType = Enum.RaycastFilterType.Exclude
		workingParams.FilterDescendantsInstances = ignored
		workingParams.IgnoreWater = params.IgnoreWater
		workingParams.CollisionGroup = params.CollisionGroup
		workingParams.RespectCanCollide = params.RespectCanCollide

		local travelled = (result.Position - currentOrigin).Magnitude
		local leftover = remaining.Magnitude - travelled
		if leftover <= 1e-3 then
			return nil
		end
		currentOrigin = result.Position
		remaining = VectorUtil.safeUnit(remaining) * leftover
	end
	return nil
end

--[[
	Spherecast avec repli automatique sur un raycast si la forme n'est pas
	supportée (anciens clients, cas dégénérés).
]]
function RaycastUtil.sphereCast(
	origin: Vector3,
	radius: number,
	direction: Vector3,
	params: RaycastParams
): RaycastResult?
	if radius > 0 then
		local ok, result = pcall(function()
			return Workspace:Spherecast(origin, radius, direction, params)
		end)
		if ok then
			return result
		end
	end
	return Workspace:Raycast(origin, direction, params)
end

--[[
	Sonde de sol robuste.

	Un rayon unique produit une normale qui saute d'une face à l'autre sur les
	arêtes, ce qui fait vibrer les contrôleurs. On tire donc un rayon central
	plus une couronne de rayons, et on moyenne les normales du contact le plus
	haut. `samples = 0` retombe sur un seul rayon (moins cher).
]]
function RaycastUtil.groundProbe(
	origin: Vector3,
	up: Vector3,
	distance: number,
	radius: number,
	params: RaycastParams,
	samples: number?
): (RaycastResult?, Vector3)
	local down = -VectorUtil.safeUnit(up) * distance
	local best = Workspace:Raycast(origin, down, params)
	local accumulatedNormal = best and best.Normal or Vector3.zero
	local count = best and 1 or 0

	local ringSamples = samples or 4
	if ringSamples > 0 and radius > 0 then
		local right, _, forward = VectorUtil.orthonormalBasis(up)
		for i = 1, ringSamples do
			local angle = (i - 1) / ringSamples * math.pi * 2
			local offset = right * (math.cos(angle) * radius) + forward * (math.sin(angle) * radius)
			local result = Workspace:Raycast(origin + offset, down, params)
			if result then
				accumulatedNormal += result.Normal
				count += 1
				if not best or result.Distance < best.Distance then
					best = result
				end
			end
		end
	end

	if count == 0 then
		return nil, up
	end
	return best, VectorUtil.safeUnit(accumulatedNormal / count)
end

--[[ Vrai s'il n'y a aucun obstacle entre deux points. ]]
function RaycastUtil.lineOfSight(from: Vector3, to: Vector3, params: RaycastParams): (boolean, RaycastResult?)
	local delta = to - from
	if delta.Magnitude < 1e-4 then
		return true, nil
	end
	local result = Workspace:Raycast(from, delta, params)
	return result == nil, result
end

--[[
	Mesure l'épaisseur d'un obstacle en le retraversant depuis l'autre côté.
	Renvoie (épaisseur, point de sortie) ou nil si le mur dépasse `maxThickness`.
]]
function RaycastUtil.measureThickness(
	entryPosition: Vector3,
	direction: Vector3,
	maxThickness: number,
	target: BasePart
): (number?, Vector3?)
	local unit = VectorUtil.safeUnit(direction)
	local span = maxThickness + 0.1
	local farSide = entryPosition + unit * span

	local exitParams = RaycastParams.new()
	exitParams.FilterType = Enum.RaycastFilterType.Include
	exitParams.FilterDescendantsInstances = { target }

	local exit = Workspace:Raycast(farSide, -unit * span, exitParams)
	if not exit then
		return nil, nil
	end
	local thickness = (exit.Position - entryPosition).Magnitude
	if thickness > maxThickness then
		return nil, nil
	end
	return thickness, exit.Position
end

--[[ OverlapParams d'exclusion, pendant de RaycastUtil.params. ]]
function RaycastUtil.overlapParams(ignoreList: { Instance }?, collisionGroup: string?, maxParts: number?): OverlapParams
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignoreList or {}
	params.MaxParts = maxParts or 0
	params.RespectCanCollide = false
	if collisionGroup then
		params.CollisionGroup = collisionGroup
	end
	return params
end

return RaycastUtil
