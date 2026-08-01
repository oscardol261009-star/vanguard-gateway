--!strict
--[[
	Spring.luau
	Ressorts amortis à intégration semi-implicite.

	Pourquoi pas un simple lerp ? Un lerp dépend du framerate et n'a pas
	d'inertie. Ici on résout analytiquement l'équation du ressort amorti,
	ce qui est *inconditionnellement stable* : même à 5 FPS ou avec une
	raideur absurde, la simulation n'explose jamais.

		x'' = f² (target - x) - 2 z f x'

	frequency : pulsation propre (oscillations/s * 2π ~ réactivité)
	damping   : facteur d'amortissement
	            < 1 -> rebondit, = 1 -> critique (pas d'overshoot), > 1 -> mou
]]

local Spring = {}

--============================================================
-- Noyau commun (fonctionne pour un scalaire comme pour un Vector3,
-- seules les opérations +, -, * scalaire sont utilisées)
--============================================================

local function solveCoefficients(frequency: number, damping: number, dt: number): (number, number, number, number)
	local f = 1 + 2 * dt * damping * frequency
	local omegaSq = frequency * frequency
	local hOmegaSq = dt * omegaSq
	local hhOmegaSq = dt * hOmegaSq
	local detInv = 1 / (f + hhOmegaSq)
	return f, hOmegaSq, hhOmegaSq, detInv
end

--============================================================
-- RESSORT VECTORIEL
--============================================================

local VectorSpring = {}
VectorSpring.__index = VectorSpring

export type VectorSpring = typeof(setmetatable(
	{} :: {
		position: Vector3,
		velocity: Vector3,
		target: Vector3,
		frequency: number,
		damping: number,
	},
	VectorSpring
))

function Spring.vector(frequency: number, damping: number, initial: Vector3?): VectorSpring
	local value = initial or Vector3.zero
	return setmetatable({
		position = value,
		velocity = Vector3.zero,
		target = value,
		frequency = frequency,
		damping = damping,
	}, VectorSpring)
end

function VectorSpring.update(self: VectorSpring, dt: number): Vector3
	if dt <= 0 then
		return self.position
	end
	local f, hOmegaSq, hhOmegaSq, detInv = solveCoefficients(self.frequency, self.damping, dt)
	local detX = self.position * f + self.velocity * dt + self.target * hhOmegaSq
	local detV = self.velocity + (self.target - self.position) * hOmegaSq
	self.position = detX * detInv
	self.velocity = detV * detInv
	return self.position
end

function VectorSpring.impulse(self: VectorSpring, velocity: Vector3)
	self.velocity += velocity
end

function VectorSpring.reset(self: VectorSpring, value: Vector3)
	self.position = value
	self.target = value
	self.velocity = Vector3.zero
end

--============================================================
-- RESSORT SCALAIRE
--============================================================

local NumberSpring = {}
NumberSpring.__index = NumberSpring

export type NumberSpring = typeof(setmetatable(
	{} :: {
		position: number,
		velocity: number,
		target: number,
		frequency: number,
		damping: number,
	},
	NumberSpring
))

function Spring.number(frequency: number, damping: number, initial: number?): NumberSpring
	local value = initial or 0
	return setmetatable({
		position = value,
		velocity = 0,
		target = value,
		frequency = frequency,
		damping = damping,
	}, NumberSpring)
end

function NumberSpring.update(self: NumberSpring, dt: number): number
	if dt <= 0 then
		return self.position
	end
	local f, hOmegaSq, hhOmegaSq, detInv = solveCoefficients(self.frequency, self.damping, dt)
	local detX = self.position * f + self.velocity * dt + self.target * hhOmegaSq
	local detV = self.velocity + (self.target - self.position) * hOmegaSq
	self.position = detX * detInv
	self.velocity = detV * detInv
	return self.position
end

function NumberSpring.impulse(self: NumberSpring, velocity: number)
	self.velocity += velocity
end

function NumberSpring.reset(self: NumberSpring, value: number)
	self.position = value
	self.target = value
	self.velocity = 0
end

--============================================================
-- HELPERS SANS ÉTAT
--============================================================

--[[
	Force d'un ressort-amortisseur classique, à appliquer directement.
	`displacement` : écart par rapport au repos (positif = comprimé)
	`relativeVelocity` : vitesse relative le long de l'axe du ressort
]]
function Spring.force(displacement: number, relativeVelocity: number, stiffness: number, damper: number): number
	return displacement * stiffness - relativeVelocity * damper
end

--[[ Convertit "je veux atteindre X en T secondes sans dépasser" en fréquence. ]]
function Spring.frequencyForSettleTime(settleTime: number): number
	-- pour un amortissement critique, ~99 % atteint en 6.64 / f secondes
	return 6.64 / math.max(settleTime, 1e-3)
end

return Spring
