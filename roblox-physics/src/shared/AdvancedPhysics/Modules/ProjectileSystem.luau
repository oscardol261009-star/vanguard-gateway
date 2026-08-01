--!nonstrict
--[[
	ProjectileSystem.luau
	Balistique sans pièces physiques.

	Un projectile rapide simulé avec une vraie Part traverse les murs : à
	3000 studs/s et 60 FPS, il parcourt 50 studs entre deux images. On simule
	donc le projectile *mathématiquement* et on relie chaque paire de positions
	successives par un raycast — aucune collision ne peut être manquée.

	Modélisation :
	  - traînée quadratique (la balle ralentit, la portée n'est pas infinie)
	  - effet Magnus (trajectoire courbe pour les projectiles en rotation)
	  - gravité issue des GravityField (fonctionne sur une planète)
	  - intégration RK4 : indispensable, l'accélération dépend de la vitesse
	  - pénétration des matériaux avec budget d'épaisseur
	  - ricochets en incidence rasante

	Le rendu est laissé à l'appelant via `onUpdate` : la simulation reste
	utilisable côté serveur sans le moindre visuel.
]]

local Aerodynamics = require(script.Parent.Parent.Solvers.Aerodynamics)
local Config = require(script.Parent.Parent.Config)
local GravityField = require(script.Parent.GravityField)
local Integrator = require(script.Parent.Parent.Solvers.Integrator)
local RaycastUtil = require(script.Parent.Parent.Util.RaycastUtil)
local VectorUtil = require(script.Parent.Parent.Util.VectorUtil)

local ProjectileSystem = {}

-- Distance maximale parcourue en un sous-pas. Plus c'est petit, plus la
-- courbure de la trajectoire est fidèle (et plus ça coûte cher).
local MAX_SEGMENT_STUDS = 24

local active: { any } = {}

--============================================================
-- CRÉATION
--============================================================

local Projectile = {}
Projectile.__index = Projectile

--[[
	Lance un projectile. Voir Types.ProjectileDef pour tous les champs.

		ProjectileSystem.fire({
			position = muzzle.WorldPosition,
			velocity = direction * 900,
			penetrations = 2,
			penetrationPower = 4,
			ricochets = 1,
			onHit = function(hit) ... end,
			onUpdate = function(pos, vel, dt) tracer:move(pos) end,
		})
]]
function ProjectileSystem.fire(definition)
	local defaults = Config.Projectile

	local params = definition.raycastParams or RaycastUtil.params()

	local projectile = setmetatable({
		position = definition.position,
		velocity = definition.velocity,
		origin = definition.position,

		mass = definition.mass or defaults.Mass,
		dragCoefficient = definition.dragCoefficient or defaults.DragCoefficient,
		crossSection = definition.crossSection or defaults.CrossSection,
		gravityScale = definition.gravityScale or defaults.GravityScale,
		spin = definition.spin,
		magnusCoefficient = definition.magnusCoefficient or defaults.MagnusCoefficient,
		wind = definition.wind,

		lifetime = definition.lifetime or defaults.Lifetime,
		maxDistance = definition.maxDistance or defaults.MaxDistance,
		minSpeed = definition.minSpeed or defaults.MinSpeed,

		penetrationsLeft = definition.penetrations or defaults.Penetrations,
		penetrationBudget = definition.penetrationPower or defaults.PenetrationPower,
		ricochetsLeft = definition.ricochets or defaults.Ricochets,
		ricochetMaxAngle = definition.ricochetMaxAngle or defaults.RicochetMaxAngle,
		restitution = definition.restitution or defaults.Restitution,
		tangentFriction = definition.tangentFriction or defaults.TangentFriction,

		radius = definition.radius or 0,
		useGravityFields = definition.useGravityFields ~= false,
		raycastParams = params,

		onUpdate = definition.onUpdate,
		onHit = definition.onHit,
		onTerminate = definition.onTerminate,
		userData = definition.userData,

		elapsed = 0,
		distanceTravelled = 0,
		alive = true,
		_ignored = {},
	}, Projectile)

	table.insert(active, projectile)
	return projectile
end

function Projectile:terminate(reason: string)
	if not self.alive then
		return
	end
	self.alive = false
	if self.onTerminate then
		task.spawn(self.onTerminate, self.position, reason)
	end
end

--[[ Ajoute une instance à ignorer pour ce projectile uniquement. ]]
function Projectile:ignore(instance: Instance)
	table.insert(self._ignored, instance)
	local newParams = RaycastParams.new()
	newParams.FilterType = Enum.RaycastFilterType.Exclude
	local combined = table.clone(self.raycastParams.FilterDescendantsInstances)
	for _, item in self._ignored do
		table.insert(combined, item)
	end
	newParams.FilterDescendantsInstances = combined
	newParams.IgnoreWater = self.raycastParams.IgnoreWater
	newParams.CollisionGroup = self.raycastParams.CollisionGroup
	newParams.RespectCanCollide = self.raycastParams.RespectCanCollide
	self.raycastParams = newParams
end

--============================================================
-- PHYSIQUE
--============================================================

function Projectile:_acceleration(velocity: Vector3): Vector3
	local gravity
	if self.useGravityFields then
		gravity = GravityField.sample(self.position) * self.gravityScale
	else
		gravity = Vector3.new(0, -workspace.Gravity * self.gravityScale, 0)
	end

	return Aerodynamics.projectileAcceleration(velocity, {
		mass = self.mass,
		gravity = gravity,
		drag = {
			dragCoefficient = self.dragCoefficient,
			crossSection = self.crossSection,
			density = Config.Environment.AirDensity,
			wind = self.wind,
		},
		spin = self.spin,
		magnusCoefficient = self.magnusCoefficient,
	})
end

--============================================================
-- IMPACTS
--============================================================

--[[
	Décide automatiquement quoi faire quand l'appelant ne le dit pas.
	`incidenceAngle` est mesuré depuis la surface : 0° = rasant, 90° = frontal.
	Un ricochet n'est plausible qu'en incidence rasante.
]]
function Projectile:_autoResolve(incidenceAngle: number): string
	if self.ricochetsLeft > 0 and incidenceAngle <= self.ricochetMaxAngle then
		return "Ricochet"
	end
	if self.penetrationsLeft > 0 and self.penetrationBudget > 0 then
		return "Penetrate"
	end
	return "Stop"
end

function Projectile:_handleHit(result: RaycastResult, segmentDirection: Vector3): boolean
	local speed = self.velocity.Magnitude

	-- angle entre la trajectoire et la surface (0° = rasant, 90° = frontal)
	local incidenceAngle = 90 - VectorUtil.angleBetween(-segmentDirection, result.Normal)
	incidenceAngle = math.abs(incidenceAngle)

	local hit = {
		instance = result.Instance,
		position = result.Position,
		normal = result.Normal,
		material = result.Material,
		distance = self.distanceTravelled,
		velocity = self.velocity,
		speed = speed,
		penetrationsLeft = self.penetrationsLeft,
		ricochetsLeft = self.ricochetsLeft,
		incidenceAngle = incidenceAngle,
		userData = self.userData,
	}

	local action: string? = nil
	if self.onHit then
		local ok, returned = pcall(self.onHit, hit)
		if ok then
			action = returned
		else
			warn(`[ProjectileSystem] onHit a échoué : {returned}`)
		end
	end

	action = action or self:_autoResolve(incidenceAngle)

	if action == "Ignore" then
		self:ignore(result.Instance)
		self.position = result.Position + segmentDirection * 0.05
		return true
	end

	if action == "Ricochet" and self.ricochetsLeft > 0 then
		self.ricochetsLeft -= 1
		self.velocity = VectorUtil.bounce(self.velocity, result.Normal, self.restitution, self.tangentFriction)
		self.position = result.Position + result.Normal * 0.1
		if self.velocity.Magnitude < self.minSpeed then
			self:terminate("SlowAfterRicochet")
			return false
		end
		return true
	end

	if action == "Penetrate" and self.penetrationsLeft > 0 then
		local thickness, exitPosition =
			RaycastUtil.measureThickness(result.Position, segmentDirection, self.penetrationBudget, result.Instance)

		if thickness and exitPosition then
			self.penetrationsLeft -= 1
			self.penetrationBudget -= thickness

			-- l'énergie perdue croît avec l'épaisseur traversée
			local lossRatio = math.clamp(thickness / math.max(self.penetrationBudget + thickness, 1e-3), 0, 0.9)
			self.velocity *= (1 - lossRatio * 0.65)

			-- légère déviation, comme une vraie balle qui traverse
			self.velocity = VectorUtil.randomInCone(self.velocity, 1.5) * self.velocity.Magnitude
			self.position = exitPosition + segmentDirection * 0.05
			self:ignore(result.Instance)

			if self.velocity.Magnitude < self.minSpeed then
				self:terminate("SlowAfterPenetration")
				return false
			end
			return true
		end
	end

	self.position = result.Position
	self:terminate("Hit")
	return false
end

--============================================================
-- PAS DE SIMULATION
--============================================================

function Projectile:step(dt: number): boolean
	if not self.alive then
		return false
	end

	self.elapsed += dt
	if self.elapsed >= self.lifetime then
		self:terminate("Lifetime")
		return false
	end

	local speed = self.velocity.Magnitude
	local steps = math.clamp(math.ceil((speed * dt) / MAX_SEGMENT_STUDS), 1, Config.General.MaxSubSteps)
	local stepDt = dt / steps

	for _ = 1, steps do
		local previousPosition = self.position

		local newPosition, newVelocity = Integrator.rk4(self.position, self.velocity, stepDt, function(_, velocity)
			return self:_acceleration(velocity)
		end)

		local segment = newPosition - previousPosition
		local segmentLength = segment.Magnitude

		if segmentLength > 1e-5 then
			local direction = segment / segmentLength
			local result
			if self.radius > 0 then
				result = RaycastUtil.sphereCast(previousPosition, self.radius, segment, self.raycastParams)
			else
				result = workspace:Raycast(previousPosition, segment, self.raycastParams)
			end

			if result then
				self.velocity = newVelocity
				self.distanceTravelled += (result.Position - previousPosition).Magnitude
				if not self:_handleHit(result, direction) then
					return false
				end
				continue
			end
		end

		self.position = newPosition
		self.velocity = newVelocity
		self.distanceTravelled += segmentLength
	end

	if self.distanceTravelled >= self.maxDistance then
		self:terminate("MaxDistance")
		return false
	end
	if self.velocity.Magnitude < self.minSpeed then
		self:terminate("TooSlow")
		return false
	end

	if self.onUpdate then
		self.onUpdate(self.position, self.velocity, dt)
	end

	return true
end

--============================================================
-- GESTIONNAIRE
--============================================================

--[[ Fait avancer tous les projectiles actifs. Appelé par l'ordonnanceur. ]]
function ProjectileSystem.step(dt: number)
	local clamped = math.min(dt, Config.General.MaxDeltaTime)
	for index = #active, 1, -1 do
		local projectile = active[index]
		local ok, alive = pcall(projectile.step, projectile, clamped)
		if not ok then
			warn(`[ProjectileSystem] erreur de simulation : {alive}`)
			projectile.alive = false
			table.remove(active, index)
		elseif not alive then
			table.remove(active, index)
		end
	end
end

function ProjectileSystem.count(): number
	return #active
end

function ProjectileSystem.clear()
	for _, projectile in active do
		projectile:terminate("Cleared")
	end
	table.clear(active)
end

--============================================================
-- PRÉVISUALISATION
--============================================================

--[[
	Calcule la trajectoire *sans* la simuler : sert à dessiner l'arc d'une
	grenade ou d'un grappin. S'arrête au premier obstacle.
	Renvoie la liste des points et le RaycastResult final (ou nil).
]]
function ProjectileSystem.predictPath(definition, maxPoints: number?, timeStep: number?): ({ Vector3 }, RaycastResult?)
	local points: { Vector3 } = {}
	local steps = maxPoints or 60
	local dt = timeStep or (1 / 30)

	local probe = setmetatable({
		position = definition.position,
		velocity = definition.velocity,
		mass = definition.mass or Config.Projectile.Mass,
		dragCoefficient = definition.dragCoefficient or Config.Projectile.DragCoefficient,
		crossSection = definition.crossSection or Config.Projectile.CrossSection,
		gravityScale = definition.gravityScale or 1,
		spin = definition.spin,
		magnusCoefficient = definition.magnusCoefficient or Config.Projectile.MagnusCoefficient,
		wind = definition.wind,
		useGravityFields = definition.useGravityFields ~= false,
	}, Projectile)

	local params = definition.raycastParams or RaycastUtil.params()
	table.insert(points, probe.position)

	for _ = 1, steps do
		local previous = probe.position
		local newPosition, newVelocity = Integrator.rk4(probe.position, probe.velocity, dt, function(_, velocity)
			return probe:_acceleration(velocity)
		end)

		local segment = newPosition - previous
		local result = workspace:Raycast(previous, segment, params)
		if result then
			table.insert(points, result.Position)
			return points, result
		end

		probe.position = newPosition
		probe.velocity = newVelocity
		table.insert(points, newPosition)
	end

	return points, nil
end

return ProjectileSystem
