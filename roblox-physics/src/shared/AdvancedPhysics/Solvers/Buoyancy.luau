--!nonstrict
--[[
	Buoyancy.luau
	Flottabilité, traînée fluide et couple de redressement.

	Principe d'Archimède : une pièce immergée subit vers le haut le poids
	du fluide déplacé. En calculant la fraction immergée à partir de la
	boîte englobante orientée, on obtient un bateau qui tangue correctement
	sans simuler le maillage.
]]

local Config = require(script.Parent.Parent.Config)
local VectorUtil = require(script.Parent.Parent.Util.VectorUtil)

local Buoyancy = {}

local STUDS_PER_METER = Config.Environment.StudsPerMeter
local STUDS3_PER_M3 = STUDS_PER_METER ^ 3

export type WaterVolume = {
	surfaceY: number, -- niveau de l'eau (monde)
	density: number?, -- kg/m³
	current: Vector3?, -- courant, studs/s
	linearDrag: number?, -- amortissement linéaire dans l'eau
	quadraticDrag: number?, -- amortissement quadratique
	angularDrag: number?, -- amortissement de la rotation
	uprightStrength: number?, -- couple de redressement (0 = aucun)
	waveAmplitude: number?, -- houle sinusoïdale optionnelle
	waveLength: number?,
	waveSpeed: number?,
}

--[[ Hauteur locale de la surface, houle comprise. ]]
function Buoyancy.surfaceAt(volume: WaterVolume, position: Vector3, clock: number?): number
	local amplitude = volume.waveAmplitude
	if not amplitude or amplitude <= 0 then
		return volume.surfaceY
	end
	local length = volume.waveLength or 40
	local speed = volume.waveSpeed or 6
	local t = clock or os.clock()
	local k = (math.pi * 2) / math.max(length, 1e-3)
	-- deux trains d'ondes croisés : évite l'aspect "tôle ondulée"
	local a = math.sin(position.X * k + t * speed)
	local b = math.sin(position.Z * k * 0.83 + t * speed * 1.17)
	return volume.surfaceY + (a + b) * 0.5 * amplitude
end

--[[
	Demi-hauteur verticale de la boîte englobante orientée d'une pièce.
	On projette les trois demi-axes locaux sur l'axe Y du monde.
]]
local function verticalHalfExtent(part: BasePart): number
	local cf = part.CFrame
	local size = part.Size
	return 0.5
		* (
			math.abs(cf.RightVector.Y) * size.X
			+ math.abs(cf.UpVector.Y) * size.Y
			+ math.abs(cf.LookVector.Y) * size.Z
		)
end

--[[
	Fraction immergée d'une pièce, de 0 (à sec) à 1 (totalement sous l'eau).
]]
function Buoyancy.submergedFraction(part: BasePart, volume: WaterVolume, clock: number?): number
	local halfExtent = verticalHalfExtent(part)
	if halfExtent <= 1e-4 then
		return part.Position.Y < Buoyancy.surfaceAt(volume, part.Position, clock) and 1 or 0
	end
	local surface = Buoyancy.surfaceAt(volume, part.Position, clock)
	local bottom = part.Position.Y - halfExtent
	local depth = surface - bottom
	return math.clamp(depth / (halfExtent * 2), 0, 1)
end

--[[
	Calcule (force, couple) à appliquer à une pièce immergée.
	La force est en newtons-Roblox (masse * studs/s²), donc directement
	utilisable avec ApplyImpulse(force * dt) ou VectorForce.Force.
]]
function Buoyancy.solve(
	part: BasePart,
	volume: WaterVolume,
	gravity: number?,
	clock: number?
): (Vector3, Vector3, number)
	local fraction = Buoyancy.submergedFraction(part, volume, clock)
	if fraction <= 0 then
		return Vector3.zero, Vector3.zero, 0
	end

	local g = gravity or workspace.Gravity
	local fluidDensity = volume.density or Config.Environment.WaterDensity

	-- Volume déplacé, converti studs³ -> m³
	local sizeStuds = part.Size
	local volumeStuds3 = sizeStuds.X * sizeStuds.Y * sizeStuds.Z
	local displacedM3 = (volumeStuds3 * fraction) / STUDS3_PER_M3

	-- Poussée d'Archimède : ρ V g, orientée vers le haut
	local buoyantForce = Vector3.yAxis * (fluidDensity * displacedM3 * g)

	-- Traînée fluide (linéaire + quadratique), relative au courant
	local current = volume.current or Vector3.zero
	local relative = part.AssemblyLinearVelocity - current
	local speed = relative.Magnitude
	local linear = volume.linearDrag or 2.5
	local quadratic = volume.quadraticDrag or 0.12
	local mass = part.AssemblyMass

	local dragForce = Vector3.zero
	if speed > 1e-4 then
		local magnitude = (linear * speed + quadratic * speed * speed) * mass * fraction
		dragForce = -VectorUtil.safeUnit(relative) * magnitude
	end

	-- Couple : amortissement angulaire + redressement vers la verticale
	local angularDrag = volume.angularDrag or 3.0
	local torque = -part.AssemblyAngularVelocity * (angularDrag * mass * fraction)

	local uprightStrength = volume.uprightStrength or 0
	if uprightStrength > 0 then
		local up = part.CFrame.UpVector
		local axis = up:Cross(Vector3.yAxis)
		torque += axis * (uprightStrength * mass * fraction)
	end

	return buoyantForce + dragForce, torque, fraction
end

--[[
	Applique directement la flottabilité à une pièce pour un pas `dt`.
	À appeler dans RunService.PreSimulation.
]]
function Buoyancy.apply(part: BasePart, volume: WaterVolume, dt: number, clock: number?): number
	local force, torque, fraction = Buoyancy.solve(part, volume, workspace.Gravity, clock)
	if fraction <= 0 then
		return 0
	end
	part:ApplyImpulse(force * dt)
	part:ApplyAngularImpulse(torque * dt)
	return fraction
end

--[[
	Crée un flotteur persistant : plusieurs points de poussée répartis sur
	la pièce, ce qui produit un vrai tangage/roulis (un bateau se redresse,
	une caisse bascule). `points` sont en espace local.
]]
export type Floater = {
	part: BasePart,
	volume: WaterVolume,
	points: { Vector3 },
	step: (self: any, dt: number) -> (),
	destroy: (self: any) -> (),
}

local FloaterImpl = {}
FloaterImpl.__index = FloaterImpl

function Buoyancy.createFloater(part: BasePart, volume: WaterVolume, points: { Vector3 }?): Floater
	local resolved = points
	if not resolved then
		-- 4 points aux coins de la face inférieure : suffisant pour flotter droit
		local half = part.Size * 0.5
		resolved = {
			Vector3.new(-half.X * 0.7, -half.Y * 0.5, -half.Z * 0.7),
			Vector3.new(half.X * 0.7, -half.Y * 0.5, -half.Z * 0.7),
			Vector3.new(-half.X * 0.7, -half.Y * 0.5, half.Z * 0.7),
			Vector3.new(half.X * 0.7, -half.Y * 0.5, half.Z * 0.7),
		}
	end

	return setmetatable({
		part = part,
		volume = volume,
		points = resolved,
		_alive = true,
	}, FloaterImpl) :: any
end

function FloaterImpl.step(self, dt: number)
	if not self._alive or not self.part.Parent then
		return
	end

	local part: BasePart = self.part
	local volume: WaterVolume = self.volume
	local clock = os.clock()
	local pointCount = #self.points
	if pointCount == 0 then
		return
	end

	local g = workspace.Gravity
	local fluidDensity = volume.density or Config.Environment.WaterDensity
	local size = part.Size
	local volumePerPoint = (size.X * size.Y * size.Z) / STUDS3_PER_M3 / pointCount
	local current = volume.current or Vector3.zero
	local linear = volume.linearDrag or 2.5
	local quadratic = volume.quadraticDrag or 0.12
	local massPerPoint = part.AssemblyMass / pointCount
	local depthScale = math.max(size.Y, 1e-3)

	for _, localPoint in self.points do
		local worldPoint = part.CFrame:PointToWorldSpace(localPoint)
		local surface = Buoyancy.surfaceAt(volume, worldPoint, clock)
		local depth = surface - worldPoint.Y
		if depth <= 0 then
			continue
		end

		local submersion = math.clamp(depth / depthScale, 0, 1)
		local buoyantForce = Vector3.yAxis * (fluidDensity * volumePerPoint * submersion * g)

		local pointVelocity = VectorUtil.velocityAtPoint(part, worldPoint) - current
		local speed = pointVelocity.Magnitude
		local dragForce = Vector3.zero
		if speed > 1e-4 then
			local magnitude = (linear * speed + quadratic * speed * speed) * massPerPoint * submersion
			dragForce = -VectorUtil.safeUnit(pointVelocity) * magnitude
		end

		part:ApplyImpulseAtPosition((buoyantForce + dragForce) * dt, worldPoint)
	end

	local angularDrag = volume.angularDrag or 3.0
	if angularDrag > 0 then
		part:ApplyAngularImpulse(-part.AssemblyAngularVelocity * (angularDrag * part.AssemblyMass * dt))
	end
end

function FloaterImpl.destroy(self)
	self._alive = false
end

return Buoyancy
