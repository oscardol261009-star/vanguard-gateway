--!nonstrict
--[[
	PhysicsServer.server.luau
	À placer dans ServerScriptService.

	Montre comment câbler le framework côté serveur :
	  - déclaration des champs de gravité de la map
	  - tir de projectiles validé serveur (le client n'envoie qu'une intention)
	  - flottabilité automatique sur les pièces marquées
	  - explosions

	Rien ici n'est obligatoire : c'est un exemple d'intégration à adapter.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AdvancedPhysics = require(ReplicatedStorage:WaitForChild("AdvancedPhysics"))

local GravityField = AdvancedPhysics.GravityField
local ProjectileSystem = AdvancedPhysics.ProjectileSystem
local ForceEffects = AdvancedPhysics.ForceEffects
local Buoyancy = AdvancedPhysics.Buoyancy
local RaycastUtil = AdvancedPhysics.RaycastUtil

--============================================================
-- REMOTES
--============================================================

local remotes = ReplicatedStorage:FindFirstChild("PhysicsRemotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "PhysicsRemotes"
	remotes.Parent = ReplicatedStorage
end

local fireRemote = remotes:FindFirstChild("FireProjectile") :: RemoteEvent?
if not fireRemote then
	fireRemote = Instance.new("RemoteEvent")
	fireRemote.Name = "FireProjectile"
	fireRemote.Parent = remotes
end

local impactRemote = remotes:FindFirstChild("ProjectileImpact") :: RemoteEvent?
if not impactRemote then
	impactRemote = Instance.new("RemoteEvent")
	impactRemote.Name = "ProjectileImpact"
	impactRemote.Parent = remotes
end

--============================================================
-- CHAMPS DE GRAVITÉ DE LA MAP
--============================================================

--[[
	Toute pièce taguée "PlanetGravity" devient une planète : on marche sur
	toute sa surface, y compris à l'envers.
]]
local function registerPlanet(part: BasePart)
	GravityField.add({
		id = `planet_{part:GetDebugId()}`,
		kind = "Point",
		origin = part.Position,
		radius = part.Size.X * 2.5,
		strength = workspace.Gravity,
		falloff = "None",
		priority = 10,
	})
end

for _, part in CollectionService:GetTagged("PlanetGravity") do
	if part:IsA("BasePart") then
		registerPlanet(part)
	end
end
CollectionService:GetInstanceAddedSignal("PlanetGravity"):Connect(function(instance)
	if instance:IsA("BasePart") then
		registerPlanet(instance)
	end
end)

--[[ Zones à gravité personnalisée : une pièce invisible taguée "GravityZone". ]]
local function registerZone(part: BasePart)
	local strength = part:GetAttribute("GravityStrength") or workspace.Gravity * 0.35
	local directionAttribute = part:GetAttribute("GravityDirection")

	GravityField.add({
		id = `zone_{part:GetDebugId()}`,
		kind = "Box",
		part = part,
		direction = directionAttribute or -part.CFrame.UpVector,
		strength = strength,
		priority = 20,
		blend = part:GetAttribute("GravityBlend") or 1,
	})
end

for _, part in CollectionService:GetTagged("GravityZone") do
	if part:IsA("BasePart") then
		registerZone(part)
	end
end
CollectionService:GetInstanceAddedSignal("GravityZone"):Connect(function(instance)
	if instance:IsA("BasePart") then
		registerZone(instance)
	end
end)

--============================================================
-- FLOTTABILITÉ
--============================================================

local floaters: { [BasePart]: any } = {}

local function addFloater(part: BasePart)
	if floaters[part] then
		return
	end
	local floater = Buoyancy.createFloater(part, {
		surfaceY = part:GetAttribute("WaterLevel") or 0,
		waveAmplitude = part:GetAttribute("WaveAmplitude") or 1.2,
		waveLength = 60,
		waveSpeed = 4,
		linearDrag = 2.2,
		angularDrag = 3.5,
	})
	floaters[part] = floater
	AdvancedPhysics.register(floater)
end

local function removeFloater(part: BasePart)
	local floater = floaters[part]
	if floater then
		AdvancedPhysics.destroy(floater)
		floaters[part] = nil
	end
end

for _, part in CollectionService:GetTagged("Floats") do
	if part:IsA("BasePart") then
		addFloater(part)
	end
end
CollectionService:GetInstanceAddedSignal("Floats"):Connect(function(instance)
	if instance:IsA("BasePart") then
		addFloater(instance)
	end
end)
CollectionService:GetInstanceRemovedSignal("Floats"):Connect(function(instance)
	if instance:IsA("BasePart") then
		removeFloater(instance)
	end
end)

--============================================================
-- TIR SERVEUR-AUTORITAIRE
--============================================================

local WEAPONS = {
	Rifle = {
		muzzleVelocity = 900,
		damage = 34,
		penetrations = 2,
		penetrationPower = 5,
		ricochets = 0,
		spread = 0.6,
		cooldown = 0.1,
	},
	Sniper = {
		muzzleVelocity = 1500,
		damage = 90,
		penetrations = 3,
		penetrationPower = 9,
		ricochets = 0,
		spread = 0.05,
		cooldown = 1.2,
	},
	Ricochet = {
		muzzleVelocity = 500,
		damage = 25,
		penetrations = 0,
		penetrationPower = 0,
		ricochets = 3,
		spread = 1.2,
		cooldown = 0.25,
	},
}

local MAX_MUZZLE_DISTANCE = 12 -- studs entre le joueur et son point de départ
local lastShot: { [Player]: number } = {}

local function resolveHumanoid(part: BasePart): Humanoid?
	local model = part:FindFirstAncestorOfClass("Model")
	return model and model:FindFirstChildOfClass("Humanoid") or nil
end

fireRemote.OnServerEvent:Connect(function(player: Player, weaponName, origin, direction)
	local weapon = WEAPONS[weaponName]
	if not weapon then
		return
	end
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then
		return
	end
	if direction.Magnitude < 1e-3 then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	-- Validation : on refuse un point de départ trop loin du joueur, sinon
	-- un client modifié pourrait tirer depuis n'importe où sur la map.
	if (origin - root.Position).Magnitude > MAX_MUZZLE_DISTANCE then
		origin = root.Position
	end

	local now = os.clock()
	if now - (lastShot[player] or 0) < weapon.cooldown then
		return
	end
	lastShot[player] = now

	local aim = AdvancedPhysics.VectorUtil.randomInCone(direction.Unit, weapon.spread)

	ProjectileSystem.fire({
		position = origin,
		velocity = aim * weapon.muzzleVelocity,
		penetrations = weapon.penetrations,
		penetrationPower = weapon.penetrationPower,
		ricochets = weapon.ricochets,
		raycastParams = RaycastUtil.params({ character }),
		userData = { player = player, weapon = weaponName },

		onHit = function(hit)
			local humanoid = resolveHumanoid(hit.instance)
			if humanoid and humanoid.Parent ~= character then
				-- dégâts modulés par la vitesse résiduelle : une balle ayant
				-- traversé deux murs fait moins mal
				local speedRatio = math.clamp(hit.speed / weapon.muzzleVelocity, 0, 1)
				local multiplier = hit.instance.Name == "Head" and 2 or 1
				humanoid:TakeDamage(weapon.damage * speedRatio * multiplier)
				return "Stop"
			end

			impactRemote:FireAllClients(hit.position, hit.normal, hit.material)
			return nil -- laisse le système décider (ricochet / pénétration / arrêt)
		end,
	})
end)

Players.PlayerRemoving:Connect(function(player)
	lastShot[player] = nil
end)

--============================================================
-- EXEMPLE : BARIL EXPLOSIF
--============================================================

CollectionService:GetInstanceAddedSignal("ExplosiveBarrel"):Connect(function(instance)
	if not instance:IsA("BasePart") then
		return
	end

	local exploded = false
	instance:GetAttributeChangedSignal("Health"):Connect(function()
		if exploded or (instance:GetAttribute("Health") or 100) > 0 then
			return
		end
		exploded = true

		ForceEffects.explode(instance.Position, {
			radius = instance:GetAttribute("BlastRadius") or 45,
			impulse = 260,
			upBias = 0.4,
			angularImpulse = 40,
			lineOfSight = true,
			ignore = { instance },
			onAffected = function(part, strength)
				local humanoid = resolveHumanoid(part)
				if humanoid then
					humanoid:TakeDamage(80 * strength)
				end
			end,
		})

		instance:Destroy()
	end)
end)
