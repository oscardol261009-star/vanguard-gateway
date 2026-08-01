--!nonstrict
--[[
	ForceEffects.luau
	Forces d'ambiance : explosions, attracteurs, souffles, zones de vent.

	Différence avec l'objet `Explosion` de Roblox : ici on contrôle
	l'atténuation, la ligne de vue (un mur protège vraiment), le biais
	vertical, et on peut inclure ou non les personnages.
]]

local Config = require(script.Parent.Parent.Config)
local RaycastUtil = require(script.Parent.Parent.Util.RaycastUtil)
local VectorUtil = require(script.Parent.Parent.Util.VectorUtil)

local ForceEffects = {}

--============================================================
-- ATTÉNUATION
--============================================================

local function falloff(kind: string, distance: number, radius: number): number
	local normalized = math.clamp(distance / math.max(radius, 1e-3), 0, 1)
	if kind == "None" then
		return 1
	elseif kind == "Linear" then
		return 1 - normalized
	elseif kind == "InverseSquare" then
		-- énergie répartie sur une sphère : ~1/d², borné près du centre
		local d = math.max(distance, radius * 0.08)
		local reference = radius * 0.08
		return math.clamp((reference * reference) / (d * d), 0, 1) * (1 - normalized)
	end
	return 1 - normalized
end

ForceEffects.falloff = falloff

--============================================================
-- EXPLOSION
--============================================================

export type ExplosionOptions = {
	radius: number?,
	impulse: number?, -- impulsion par unité de masse à distance nulle
	falloff: string?,
	upBias: number?, -- 0..1 : part de la poussée redirigée vers le haut
	lineOfSight: boolean?, -- un mur bloque le souffle
	ignore: { Instance }?,
	affectAnchored: boolean?, -- inutile physiquement, sert aux callbacks
	angularImpulse: number?, -- fait tournoyer les débris
	onAffected: ((part: BasePart, strength: number, direction: Vector3) -> ())?,
}

--[[
	Applique un souffle radial. Renvoie le nombre d'assemblages touchés.

		ForceEffects.explode(grenade.Position, {
			radius = 45, impulse = 220, upBias = 0.4,
			onAffected = function(part, strength) applyDamage(part, strength * 30) end,
		})
]]
function ForceEffects.explode(origin: Vector3, options: ExplosionOptions?): number
	local settings = options or {}
	local radius = settings.radius or Config.Force.ExplosionRadius
	local impulse = settings.impulse or Config.Force.ExplosionImpulse
	local falloffKind = settings.falloff or Config.Force.ExplosionFalloff
	local upBias = settings.upBias or Config.Force.ExplosionUpBias
	local checkSight = settings.lineOfSight
	if checkSight == nil then
		checkSight = Config.Force.ExplosionLineOfSight
	end

	local overlapParams = RaycastUtil.overlapParams(settings.ignore)
	local parts = workspace:GetPartBoundsInRadius(origin, radius, overlapParams)

	local sightParams = RaycastUtil.params(settings.ignore)
	-- un assemblage ne doit recevoir qu'une impulsion, pas une par pièce
	local processedAssemblies: { [BasePart]: boolean } = {}
	local affected = 0

	for _, part in parts do
		if part.Anchored and not settings.affectAnchored then
			continue
		end

		local rootPart = part.AssemblyRootPart
		if rootPart then
			if processedAssemblies[rootPart] then
				continue
			end
			processedAssemblies[rootPart] = true
		end

		local delta = part.Position - origin
		local distance = delta.Magnitude
		if distance > radius then
			continue
		end

		if checkSight and distance > 1e-3 then
			local blockParams = RaycastParams.new()
			blockParams.FilterType = Enum.RaycastFilterType.Exclude
			local excluded = table.clone(settings.ignore or {})
			table.insert(excluded, part)
			blockParams.FilterDescendantsInstances = excluded

			local blocked = workspace:Raycast(origin, delta, blockParams)
			if blocked then
				continue
			end
		end

		local strength = falloff(falloffKind, distance, radius)
		if strength <= 1e-4 then
			continue
		end

		local direction = distance > 1e-3 and (delta / distance) or Vector3.yAxis
		direction = VectorUtil.safeUnit(direction:Lerp(Vector3.yAxis, math.clamp(upBias, 0, 1)))

		if not part.Anchored then
			local magnitude = impulse * strength * part.AssemblyMass
			part:ApplyImpulseAtPosition(direction * magnitude, part.Position)

			local spin = settings.angularImpulse
			if spin and spin > 0 then
				local random = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
				part:ApplyAngularImpulse(random * (spin * strength * part.AssemblyMass))
			end
		end

		affected += 1
		if settings.onAffected then
			settings.onAffected(part, strength, direction)
		end
	end

	return affected
end

--============================================================
-- IMPULSION DIRIGÉE (souffle conique, coup de bélier)
--============================================================

--[[
	Souffle limité à un cône : idéal pour un fusil à pompe, un lance-flammes
	ou une poussée télékinétique.
]]
function ForceEffects.cone(
	origin: Vector3,
	direction: Vector3,
	options: {
		range: number?,
		halfAngle: number?,
		impulse: number?,
		ignore: { Instance }?,
		onAffected: ((part: BasePart, strength: number) -> ())?,
	}?
): number
	local settings = options or {}
	local range = settings.range or 40
	local halfAngle = settings.halfAngle or 30
	local impulse = settings.impulse or 120
	local forward = VectorUtil.safeUnit(direction)

	local parts = workspace:GetPartBoundsInRadius(origin, range, RaycastUtil.overlapParams(settings.ignore))
	local processed: { [BasePart]: boolean } = {}
	local affected = 0

	for _, part in parts do
		if part.Anchored then
			continue
		end
		local rootPart = part.AssemblyRootPart
		if rootPart then
			if processed[rootPart] then
				continue
			end
			processed[rootPart] = true
		end

		local delta = part.Position - origin
		local distance = delta.Magnitude
		if distance < 1e-3 then
			continue
		end

		local angle = VectorUtil.angleBetween(delta, forward)
		if angle > halfAngle then
			continue
		end

		-- atténuation combinée : distance et écart à l'axe
		local distanceFactor = 1 - distance / range
		local angleFactor = 1 - (angle / halfAngle) * 0.6
		local strength = math.clamp(distanceFactor * angleFactor, 0, 1)

		part:ApplyImpulseAtPosition(forward * (impulse * strength * part.AssemblyMass), part.Position)
		affected += 1
		if settings.onAffected then
			settings.onAffected(part, strength)
		end
	end

	return affected
end

--============================================================
-- ATTRACTEUR CONTINU
--============================================================

local Attractor = {}
Attractor.__index = Attractor

--[[
	Champ continu d'attraction ou de répulsion (trou noir, aimant, tornade).
	`strength` négatif = répulsion.

		local vortex = ForceEffects.createAttractor(orb.Position, {
			radius = 60, strength = 250, swirl = 120,
		})
		AdvancedPhysics.register(vortex)
]]
function ForceEffects.createAttractor(origin: Vector3, options)
	options = options or {}
	return setmetatable({
		origin = origin,
		radius = options.radius or 50,
		strength = options.strength or 200,
		swirl = options.swirl or 0, -- composante tangentielle : effet tourbillon
		falloff = options.falloff or Config.Force.AttractorFalloff,
		ignore = options.ignore or {},
		follow = options.follow, -- BasePart optionnelle à suivre
		maxSpeed = options.maxSpeed or 400,
		_alive = true,
	}, Attractor)
end

function Attractor:step(dt: number)
	if not self._alive then
		return
	end
	if self.follow and self.follow.Parent then
		self.origin = self.follow.Position
	end

	local parts = workspace:GetPartBoundsInRadius(self.origin, self.radius, RaycastUtil.overlapParams(self.ignore))
	local processed: { [BasePart]: boolean } = {}

	for _, part in parts do
		if part.Anchored then
			continue
		end
		local rootPart = part.AssemblyRootPart
		if rootPart then
			if processed[rootPart] then
				continue
			end
			processed[rootPart] = true
		end

		local delta = self.origin - part.Position
		local distance = delta.Magnitude
		if distance < 1e-3 then
			continue
		end
		if part.AssemblyLinearVelocity.Magnitude > self.maxSpeed then
			continue
		end

		local direction = delta / distance
		local strength = falloff(self.falloff, distance, self.radius)
		local force = direction * (self.strength * strength)

		if self.swirl ~= 0 then
			-- vitesse tangentielle autour de l'axe vertical : spirale au lieu
			-- d'une chute droite vers le centre
			local tangent = direction:Cross(Vector3.yAxis)
			if tangent.Magnitude > 1e-3 then
				force += tangent.Unit * (self.swirl * strength)
			end
		end

		part:ApplyImpulse(force * part.AssemblyMass * dt)
	end
end

function Attractor:destroy()
	self._alive = false
end

--============================================================
-- HELPERS
--============================================================

--[[ Impulsion pour amener un assemblage à une vitesse cible (dash, knockback). ]]
function ForceEffects.setVelocity(part: BasePart, targetVelocity: Vector3)
	local delta = targetVelocity - part.AssemblyLinearVelocity
	part:ApplyImpulse(delta * part.AssemblyMass)
end

--[[ Ajoute une vitesse sans écraser l'existante. ]]
function ForceEffects.addVelocity(part: BasePart, deltaVelocity: Vector3)
	part:ApplyImpulse(deltaVelocity * part.AssemblyMass)
end

--[[
	Recul d'arme : impulsion opposée au tir, appliquée à l'épaule pour
	produire aussi une rotation.
]]
function ForceEffects.recoil(part: BasePart, shotDirection: Vector3, force: number, offset: Vector3?)
	local position = offset and part.CFrame:PointToWorldSpace(offset) or part.Position
	part:ApplyImpulseAtPosition(-VectorUtil.safeUnit(shotDirection) * force * part.AssemblyMass, position)
end

return ForceEffects
