--!strict
--[[
	Integrator.luau
	Intégrateurs numériques pour les corps simulés à la main (projectiles,
	particules de corde, orbites...).

	- semiImplicitEuler : rapide, stable pour les forces classiques
	- rk4               : 4e ordre, indispensable dès que l'accélération
	                      dépend fortement de la vitesse (traînée quadratique,
	                      Magnus, gravité orbitale)
	- substep           : découpe un dt en pas bornés
]]

local Integrator = {}

export type AccelerationFn = (position: Vector3, velocity: Vector3, t: number) -> Vector3

--[[
	Euler semi-implicite : v += a*dt ; x += v*dt
	Conserve bien mieux l'énergie qu'un Euler explicite, pour le même coût.
]]
function Integrator.semiImplicitEuler(
	position: Vector3,
	velocity: Vector3,
	dt: number,
	accelerationFn: AccelerationFn,
	t: number?
): (Vector3, Vector3)
	local acceleration = accelerationFn(position, velocity, t or 0)
	local newVelocity = velocity + acceleration * dt
	local newPosition = position + newVelocity * dt
	return newPosition, newVelocity
end

--[[
	Runge-Kutta 4 pour l'EDO du second ordre x'' = a(x, x', t).
	Coût : 4 évaluations de l'accélération, précision d'ordre 4.
]]
function Integrator.rk4(
	position: Vector3,
	velocity: Vector3,
	dt: number,
	accelerationFn: AccelerationFn,
	t: number?
): (Vector3, Vector3)
	local time = t or 0
	local half = dt * 0.5

	local k1v = accelerationFn(position, velocity, time)
	local k1x = velocity

	local k2v = accelerationFn(position + k1x * half, velocity + k1v * half, time + half)
	local k2x = velocity + k1v * half

	local k3v = accelerationFn(position + k2x * half, velocity + k2v * half, time + half)
	local k3x = velocity + k2v * half

	local k4v = accelerationFn(position + k3x * dt, velocity + k3v * dt, time + dt)
	local k4x = velocity + k3v * dt

	local newPosition = position + (k1x + (k2x + k3x) * 2 + k4x) * (dt / 6)
	local newVelocity = velocity + (k1v + (k2v + k3v) * 2 + k4v) * (dt / 6)
	return newPosition, newVelocity
end

--[[
	Verlet à vitesse : très stable, réversible, idéal pour les particules
	dont l'accélération ne dépend pas de la vitesse.
]]
function Integrator.velocityVerlet(
	position: Vector3,
	velocity: Vector3,
	acceleration: Vector3,
	dt: number,
	accelerationFn: AccelerationFn,
	t: number?
): (Vector3, Vector3, Vector3)
	local newPosition = position + velocity * dt + acceleration * (0.5 * dt * dt)
	local newAcceleration = accelerationFn(newPosition, velocity + acceleration * dt, (t or 0) + dt)
	local newVelocity = velocity + (acceleration + newAcceleration) * (0.5 * dt)
	return newPosition, newVelocity, newAcceleration
end

--[[
	Découpe `dt` en pas d'au plus `maxStep` et appelle `fn` pour chacun.
	Le dernier pas absorbe le reste, donc la somme vaut exactement `dt`.
	`maxSteps` borne le coût si dt est énorme.
]]
function Integrator.substep(dt: number, maxStep: number, maxSteps: number, fn: (stepDt: number) -> boolean?)
	if dt <= 0 then
		return
	end
	local steps = math.min(math.max(1, math.ceil(dt / maxStep)), maxSteps)
	local stepDt = dt / steps
	for _ = 1, steps do
		if fn(stepDt) == false then
			return
		end
	end
end

--[[
	Prédit la position d'un projectile balistique simple (sans traînée).
	Pratique pour tracer une trajectoire de grenade côté client.
]]
function Integrator.ballisticPosition(origin: Vector3, velocity: Vector3, gravity: Vector3, t: number): Vector3
	return origin + velocity * t + gravity * (0.5 * t * t)
end

--[[
	Vitesse initiale pour atteindre `target` depuis `origin` en `time` secondes.
	Renvoie nil si `time` est nul.
]]
function Integrator.solveLaunchVelocity(origin: Vector3, target: Vector3, gravity: Vector3, time: number): Vector3?
	if time <= 1e-4 then
		return nil
	end
	return (target - origin - gravity * (0.5 * time * time)) / time
end

--[[
	Résout l'angle de tir balistique vers une cible (solution basse par défaut).
	`speed` est la vitesse initiale imposée. Renvoie nil si hors de portée.
]]
function Integrator.solveBallisticArc(
	origin: Vector3,
	target: Vector3,
	speed: number,
	gravityMagnitude: number,
	useHighArc: boolean?
): Vector3?
	local delta = target - origin
	local horizontal = Vector3.new(delta.X, 0, delta.Z)
	local horizontalDistance = horizontal.Magnitude
	local verticalDistance = delta.Y

	if horizontalDistance < 1e-4 then
		return Vector3.new(0, speed * math.sign(verticalDistance == 0 and 1 or verticalDistance), 0)
	end

	local speedSq = speed * speed
	local discriminant = speedSq * speedSq
		- gravityMagnitude
			* (gravityMagnitude * horizontalDistance * horizontalDistance + 2 * verticalDistance * speedSq)

	if discriminant < 0 then
		return nil -- cible hors de portée à cette vitesse
	end

	local root = math.sqrt(discriminant)
	local angle = math.atan((speedSq + (useHighArc and root or -root)) / (gravityMagnitude * horizontalDistance))

	local horizontalUnit = horizontal / horizontalDistance
	return horizontalUnit * (math.cos(angle) * speed) + Vector3.yAxis * (math.sin(angle) * speed)
end

return Integrator
