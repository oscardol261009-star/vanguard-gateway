--!strict
--[[
	Aerodynamics.luau
	Traînée, portance et effet Magnus.

	Conversion d'unités : les coefficients aéro sont en SI (kg/m³, m², m/s)
	alors que Roblox raisonne en studs. On convertit la vitesse en m/s,
	on calcule la force en newtons, puis on repasse l'accélération en studs/s².
]]

local Config = require(script.Parent.Parent.Config)
local VectorUtil = require(script.Parent.Parent.Util.VectorUtil)

local Aerodynamics = {}

local STUDS_PER_METER = Config.Environment.StudsPerMeter

export type DragProfile = {
	dragCoefficient: number, -- Cd
	crossSection: number, -- m²
	density: number?, -- kg/m³ (défaut : air)
	wind: Vector3?, -- studs/s
}

--[[
	Traînée quadratique : F = -½ ρ Cd A |v|² v̂
	Renvoie une force en newtons, orientée en coordonnées Roblox.
]]
function Aerodynamics.dragForce(velocity: Vector3, profile: DragProfile): Vector3
	local wind = profile.wind or Config.Environment.Wind
	local relative = velocity - wind
	local speedStuds = relative.Magnitude
	if speedStuds < 1e-4 then
		return Vector3.zero
	end

	local speedMeters = speedStuds / STUDS_PER_METER
	local density = profile.density or Config.Environment.AirDensity
	local magnitude = 0.5 * density * profile.dragCoefficient * profile.crossSection * speedMeters * speedMeters

	return -VectorUtil.safeUnit(relative) * magnitude
end

--[[
	Traînée linéaire (régime de Stokes / amortissement visqueux).
	Plus simple à régler quand on cherche un "feeling" plutôt que du réalisme.
]]
function Aerodynamics.linearDragForce(velocity: Vector3, coefficient: number, wind: Vector3?): Vector3
	local relative = velocity - (wind or Config.Environment.Wind)
	return -relative * coefficient
end

--[[
	Effet Magnus : F = S (ω × v)
	Une balle en rotation dévie perpendiculairement à son axe de rotation :
	c'est ce qui fait courber un tir brossé au football.
]]
function Aerodynamics.magnusForce(spin: Vector3, velocity: Vector3, coefficient: number, wind: Vector3?): Vector3
	local relative = velocity - (wind or Config.Environment.Wind)
	if relative.Magnitude < 1e-4 or spin.Magnitude < 1e-4 then
		return Vector3.zero
	end
	return spin:Cross(relative) * coefficient
end

--[[
	Portance d'une surface : F = ½ ρ Cl A |v|² n̂
	`normal` est la normale de la surface portante (aile, aileron).
]]
function Aerodynamics.liftForce(
	velocity: Vector3,
	normal: Vector3,
	liftCoefficient: number,
	area: number,
	density: number?
): Vector3
	local speedMeters = velocity.Magnitude / STUDS_PER_METER
	if speedMeters < 1e-4 then
		return Vector3.zero
	end
	local rho = density or Config.Environment.AirDensity
	local magnitude = 0.5 * rho * liftCoefficient * area * speedMeters * speedMeters
	return VectorUtil.safeUnit(normal) * magnitude
end

--[[
	Amortissement de la rotation par frottement de l'air.
	Renvoie une variation de vitesse angulaire (rad/s) à retrancher.
]]
function Aerodynamics.angularDrag(spin: Vector3, coefficient: number, dt: number): Vector3
	local factor = math.exp(-coefficient * dt)
	return spin * factor
end

--[[
	Vitesse terminale (studs/s) d'un objet en chute libre avec traînée.
	Utile pour vérifier qu'un réglage n'est pas absurde.
]]
function Aerodynamics.terminalVelocity(mass: number, gravity: number, profile: DragProfile): number
	local density = profile.density or Config.Environment.AirDensity
	local denominator = 0.5 * density * profile.dragCoefficient * profile.crossSection
	if denominator <= 0 then
		return math.huge
	end
	local gravityMeters = gravity / STUDS_PER_METER
	return math.sqrt(mass * gravityMeters / denominator) * STUDS_PER_METER
end

--[[
	Accélération totale d'un projectile : gravité + traînée + Magnus.
	Signature compatible avec Integrator.rk4 via une fermeture.
]]
export type ProjectileForces = {
	mass: number,
	gravity: Vector3, -- studs/s²
	drag: DragProfile,
	spin: Vector3?,
	magnusCoefficient: number?,
}

function Aerodynamics.projectileAcceleration(velocity: Vector3, forces: ProjectileForces): Vector3
	local mass = math.max(forces.mass, 1e-6)
	local force = Aerodynamics.dragForce(velocity, forces.drag)

	if forces.spin and forces.magnusCoefficient then
		force += Aerodynamics.magnusForce(forces.spin, velocity, forces.magnusCoefficient, forces.drag.wind)
	end

	-- N -> m/s² -> studs/s²
	local accelerationStuds = (force / mass) * STUDS_PER_METER
	return forces.gravity + accelerationStuds
end

return Aerodynamics
