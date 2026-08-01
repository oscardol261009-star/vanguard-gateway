--!strict
--[[
	VectorUtil.luau
	Boîte à outils vectorielle. Toutes les fonctions sont pures et sûres
	face aux vecteurs nuls (pas de division par zéro, pas de NaN).
]]

local VectorUtil = {}

local EPSILON = 1e-6

--[[ Direction unitaire, ou Vector3.zero si le vecteur est trop court. ]]
function VectorUtil.safeUnit(v: Vector3): Vector3
	local magnitude = v.Magnitude
	if magnitude < EPSILON then
		return Vector3.zero
	end
	return v / magnitude
end

--[[ Limite la norme sans changer la direction. ]]
function VectorUtil.clampMagnitude(v: Vector3, maxMagnitude: number): Vector3
	local magnitude = v.Magnitude
	if magnitude > maxMagnitude and magnitude > EPSILON then
		return v * (maxMagnitude / magnitude)
	end
	return v
end

--[[ Composante de `v` parallèle à `axis`. ]]
function VectorUtil.projectOnVector(v: Vector3, axis: Vector3): Vector3
	local unit = VectorUtil.safeUnit(axis)
	return unit * v:Dot(unit)
end

--[[ Composante de `v` perpendiculaire à `normal` (projection sur le plan). ]]
function VectorUtil.projectOnPlane(v: Vector3, normal: Vector3): Vector3
	local unit = VectorUtil.safeUnit(normal)
	return v - unit * v:Dot(unit)
end

--[[
	Réflexion d'un vecteur sur une surface.
	restitution = 1 : rebond parfait ; 0 : le vecteur reste dans le plan.
]]
function VectorUtil.reflect(v: Vector3, normal: Vector3, restitution: number?): Vector3
	local unit = VectorUtil.safeUnit(normal)
	local e = restitution or 1
	return v - unit * (v:Dot(unit) * (1 + e))
end

--[[
	Rebond réaliste : la composante normale rebondit avec `restitution`,
	la composante tangentielle est freinée par `friction`.
]]
function VectorUtil.bounce(v: Vector3, normal: Vector3, restitution: number, friction: number): Vector3
	local unit = VectorUtil.safeUnit(normal)
	local normalPart = unit * v:Dot(unit)
	local tangentPart = v - normalPart
	return tangentPart * (1 - math.clamp(friction, 0, 1)) - normalPart * restitution
end

--[[ Fait glisser un mouvement le long d'une surface (déplacement bloqué). ]]
function VectorUtil.slide(v: Vector3, normal: Vector3): Vector3
	local unit = VectorUtil.safeUnit(normal)
	local into = v:Dot(unit)
	if into >= 0 then
		return v
	end
	return v - unit * into
end

--[[ Déplace `current` vers `target` d'au plus `maxDelta`. ]]
function VectorUtil.moveTowards(current: Vector3, target: Vector3, maxDelta: number): Vector3
	local delta = target - current
	local distance = delta.Magnitude
	if distance <= maxDelta or distance < EPSILON then
		return target
	end
	return current + delta * (maxDelta / distance)
end

--[[
	Interpolation exponentielle indépendante du framerate.
	`smoothing` = fraction restante après 1 seconde (ex. 0.01 = très réactif).
]]
function VectorUtil.damp(current: Vector3, target: Vector3, smoothing: number, dt: number): Vector3
	local alpha = 1 - math.pow(math.clamp(smoothing, 1e-9, 1), dt)
	return current:Lerp(target, alpha)
end

function VectorUtil.dampNumber(current: number, target: number, smoothing: number, dt: number): number
	local alpha = 1 - math.pow(math.clamp(smoothing, 1e-9, 1), dt)
	return current + (target - current) * alpha
end

--[[ Angle (degrés) entre deux vecteurs. ]]
function VectorUtil.angleBetween(a: Vector3, b: Vector3): number
	local ua, ub = VectorUtil.safeUnit(a), VectorUtil.safeUnit(b)
	if ua.Magnitude < EPSILON or ub.Magnitude < EPSILON then
		return 0
	end
	return math.deg(math.acos(math.clamp(ua:Dot(ub), -1, 1)))
end

--[[ Angle signé (degrés) de `a` vers `b` autour de `axis`. ]]
function VectorUtil.signedAngle(a: Vector3, b: Vector3, axis: Vector3): number
	local unsigned = VectorUtil.angleBetween(a, b)
	local sign = math.sign(a:Cross(b):Dot(axis))
	return unsigned * (sign == 0 and 1 or sign)
end

--[[ Interpolation sphérique entre deux directions. ]]
function VectorUtil.slerp(from: Vector3, to: Vector3, alpha: number): Vector3
	local a, b = VectorUtil.safeUnit(from), VectorUtil.safeUnit(to)
	local dot = math.clamp(a:Dot(b), -1, 1)
	if dot > 0.9995 then
		return VectorUtil.safeUnit(a:Lerp(b, alpha))
	end
	local theta = math.acos(dot) * alpha
	local relative = VectorUtil.safeUnit(b - a * dot)
	return a * math.cos(theta) + relative * math.sin(theta)
end

--[[ Retourne un repère orthonormé quelconque dont l'axe Y vaut `up`. ]]
function VectorUtil.orthonormalBasis(up: Vector3): (Vector3, Vector3, Vector3)
	local y = VectorUtil.safeUnit(up)
	if y.Magnitude < EPSILON then
		return Vector3.xAxis, Vector3.yAxis, Vector3.zAxis
	end
	local reference = math.abs(y.Y) > 0.99 and Vector3.xAxis or Vector3.yAxis
	local x = VectorUtil.safeUnit(reference:Cross(y))
	local z = y:Cross(x)
	return x, y, z
end

--[[ Composante horizontale par rapport à un "haut" arbitraire. ]]
function VectorUtil.flatten(v: Vector3, up: Vector3?): Vector3
	return VectorUtil.projectOnPlane(v, up or Vector3.yAxis)
end

--[[
	Direction aléatoire dans un cône.
	`spreadDegrees` est le demi-angle du cône.
]]
function VectorUtil.randomInCone(direction: Vector3, spreadDegrees: number, rng: Random?): Vector3
	local random = rng or Random.new()
	local forward = VectorUtil.safeUnit(direction)
	if forward.Magnitude < EPSILON then
		return Vector3.zAxis
	end
	local right, _, _ = VectorUtil.orthonormalBasis(forward)
	local upAxis = forward:Cross(right)

	-- cos uniforme => répartition uniforme sur la calotte sphérique
	local cosMax = math.cos(math.rad(spreadDegrees))
	local cosTheta = 1 - random:NextNumber() * (1 - cosMax)
	local sinTheta = math.sqrt(math.max(0, 1 - cosTheta * cosTheta))
	local phi = random:NextNumber() * math.pi * 2

	return forward * cosTheta + right * (sinTheta * math.cos(phi)) + upAxis * (sinTheta * math.sin(phi))
end

--[[ Vélocité d'un point d'un assemblage rigide (rotation comprise). ]]
function VectorUtil.velocityAtPoint(part: BasePart, worldPosition: Vector3): Vector3
	local center = part.AssemblyCenterOfMass
	local angular = part.AssemblyAngularVelocity
	return part.AssemblyLinearVelocity + angular:Cross(worldPosition - center)
end

--[[ Vrai si le vecteur contient un NaN ou un infini. ]]
function VectorUtil.isFinite(v: Vector3): boolean
	return v.X == v.X
		and v.Y == v.Y
		and v.Z == v.Z
		and math.abs(v.X) ~= math.huge
		and math.abs(v.Y) ~= math.huge
		and math.abs(v.Z) ~= math.huge
end

--[[ Remplace un vecteur invalide par une valeur de repli. ]]
function VectorUtil.sanitize(v: Vector3, fallback: Vector3?): Vector3
	if VectorUtil.isFinite(v) then
		return v
	end
	return fallback or Vector3.zero
end

return VectorUtil
