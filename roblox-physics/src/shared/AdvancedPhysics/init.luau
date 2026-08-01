--!nonstrict
--[[
	AdvancedPhysics
	Framework de physique avancée pour Roblox (Luau).

	Point d'entrée unique :
		local AdvancedPhysics = require(ReplicatedStorage.AdvancedPhysics)

	Sous-modules exposés :
		.CharacterController  contrôleur capsule flottante (marche, saut, wall run, glissade)
		.AnimationController  animations pilotées par l'état du contrôleur
		.CameraEffects        FOV dynamique, inclinaison, encaissement (game feel)
		.ProjectileSystem     balistique raycast (traînée, Magnus, pénétration, ricochet)
		.VehicleController    véhicule à suspension raycast
		.GravityField         gravité arbitraire (planètes, zones, plafonds)
		.VerletRope           cordes / grappins Verlet
		.ForceEffects         explosions, cônes de souffle, attracteurs
		.Buoyancy             flottabilité (Archimède)
		.Aerodynamics         traînée, portance, Magnus
		.Integrator           RK4, Verlet, balistique analytique
		.Spring / .VectorUtil / .RaycastUtil / .Config / .Types

	ORDONNANCEUR
	Tout objet exposant `:step(dt)` peut être enregistré :

		local handle = AdvancedPhysics.register(controller)
		handle:disconnect()   -- ou AdvancedPhysics.unregister(controller)

	Pourquoi PreSimulation et pas Heartbeat ?
	PreSimulation s'exécute *avant* le pas physique du moteur. Les forces
	posées ici sont donc prises en compte par la simulation du même frame.
	Avec Heartbeat, on écrirait des forces qui ne s'appliqueraient qu'à
	l'image suivante : un frame de latence sur tout le contrôleur.

	Pourquoi pas de pas de temps fixe global ?
	Les modules qui en ont besoin (projectiles, cordes) font leur propre
	sous-échantillonnage en interne. Imposer un accumulateur global ferait
	varier le nombre d'appels par image (0, 1 ou 2), ce qui saccade les
	forces continues comme la suspension.
]]

local RunService = game:GetService("RunService")

local Config = require(script.Config)

local AdvancedPhysics = {}

AdvancedPhysics.Version = "1.0.0"

-- Utilitaires
AdvancedPhysics.Config = Config
AdvancedPhysics.Types = require(script.Types)
AdvancedPhysics.VectorUtil = require(script.Util.VectorUtil)
AdvancedPhysics.RaycastUtil = require(script.Util.RaycastUtil)
AdvancedPhysics.Spring = require(script.Util.Spring)

-- Solveurs
AdvancedPhysics.Integrator = require(script.Solvers.Integrator)
AdvancedPhysics.Aerodynamics = require(script.Solvers.Aerodynamics)
AdvancedPhysics.Buoyancy = require(script.Solvers.Buoyancy)

-- Modules
AdvancedPhysics.GravityField = require(script.Modules.GravityField)
AdvancedPhysics.CharacterController = require(script.Modules.CharacterController)
AdvancedPhysics.AnimationController = require(script.Modules.AnimationController)
AdvancedPhysics.CameraEffects = require(script.Modules.CameraEffects)
AdvancedPhysics.ProjectileSystem = require(script.Modules.ProjectileSystem)
AdvancedPhysics.VehicleController = require(script.Modules.VehicleController)
AdvancedPhysics.VerletRope = require(script.Modules.VerletRope)
AdvancedPhysics.ForceEffects = require(script.Modules.ForceEffects)

--============================================================
-- ORDONNANCEUR
--============================================================

local registered: { any } = {}
local connection: RBXScriptConnection? = nil
local stepping = false
local pendingRemovals: { any } = {}

local function stepAll(dt: number)
	local clamped = math.min(dt, Config.General.MaxDeltaTime)

	stepping = true
	for index = 1, #registered do
		local object = registered[index]
		if object then
			local ok, err = pcall(object.step, object, clamped)
			if not ok then
				warn(`[AdvancedPhysics] step() a échoué : {err}`)
			end
		end
	end
	stepping = false

	-- désenregistrements demandés pendant la boucle
	if #pendingRemovals > 0 then
		for _, object in pendingRemovals do
			AdvancedPhysics.unregister(object)
		end
		table.clear(pendingRemovals)
	end

	AdvancedPhysics.ProjectileSystem.step(clamped)
end

local function ensureConnection()
	if connection then
		return
	end
	connection = RunService.PreSimulation:Connect(stepAll)
end

--[[
	Enregistre un objet possédant `:step(dt)`.
	Renvoie un handle avec `:disconnect()`.
]]
function AdvancedPhysics.register(object)
	assert(type(object) == "table" and type(object.step) == "function", "[AdvancedPhysics] l'objet doit exposer :step(dt)")

	if table.find(registered, object) then
		return { disconnect = function() end }
	end

	table.insert(registered, object)
	ensureConnection()

	return {
		object = object,
		disconnect = function()
			AdvancedPhysics.unregister(object)
		end,
	}
end

function AdvancedPhysics.unregister(object)
	if stepping then
		table.insert(pendingRemovals, object)
		return
	end
	local index = table.find(registered, object)
	if index then
		table.remove(registered, index)
	end
end

--[[ Désenregistre puis détruit l'objet s'il expose `:destroy()`. ]]
function AdvancedPhysics.destroy(object)
	AdvancedPhysics.unregister(object)
	if type(object.destroy) == "function" then
		object:destroy()
	end
end

function AdvancedPhysics.registeredCount(): number
	return #registered
end

--[[ Arrête complètement l'ordonnanceur (changement de manche, tests). ]]
function AdvancedPhysics.shutdown()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	for _, object in registered do
		if type(object.destroy) == "function" then
			pcall(object.destroy, object)
		end
	end
	table.clear(registered)
	table.clear(pendingRemovals)
	AdvancedPhysics.ProjectileSystem.clear()
end

return AdvancedPhysics
