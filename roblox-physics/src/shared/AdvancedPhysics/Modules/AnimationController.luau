--!nonstrict
--[[
	AnimationController.luau
	Pilote les animations depuis l'état du CharacterController.

	POURQUOI CE MODULE EST NÉCESSAIRE
	Le script `Animate` que Roblox insère dans chaque personnage lit
	`Humanoid.MoveDirection` et les états du Humanoid. Comme le contrôleur met
	le Humanoid en état `Physics` et sa WalkSpeed à 0, `Animate` croit que le
	personnage est immobile : plus aucune animation ne se joue. On le désactive
	donc et on rejoue nous-mêmes les pistes.

	D'OÙ VIENNENT LES ANIMATIONS
	Plutôt que de coder en dur des IDs, on les **récupère dans le script
	`Animate` du personnage**. Avantage : ça marche pour R6 comme pour R15, et
	ça respecte le pack d'animations que le joueur a équipé sur son avatar.
	Les IDs par défaut ne servent que de filet de sécurité.

	Les animations de parkour (glissade, wall run, réception) n'existent pas
	dans Roblox : passe tes propres IDs pour les activer.

		local animator = AnimationController.new(character, controller, {
			slide = "rbxassetid://TON_ID",
			wallRun = "rbxassetid://TON_ID",
			land = "rbxassetid://TON_ID",
		})
		AdvancedPhysics.register(animator)
]]

local Config = require(script.Parent.Parent.Config)

local AnimationController = {}
AnimationController.__index = AnimationController

-- Filet de sécurité : animations R15 par défaut de Roblox. Utilisées
-- uniquement si le script `Animate` est absent ou incomplet.
local FALLBACK_IDS = {
	idle = "rbxassetid://507766666",
	walk = "rbxassetid://507777826",
	run = "rbxassetid://507767714",
	jump = "rbxassetid://507765000",
	fall = "rbxassetid://507767968",
	climb = "rbxassetid://507765644",
}

-- Correspondance entre les dossiers du script `Animate` et nos noms de pistes.
local ANIMATE_SOURCES = {
	idle = "idle",
	walk = "walk",
	run = "run",
	jump = "jump",
	fall = "fall",
	climb = "climb",
}

--============================================================
-- RÉCUPÉRATION DES ANIMATIONS
--============================================================

local function harvestFromAnimateScript(character: Model): { [string]: string }
	local ids = {}
	local animate = character:FindFirstChild("Animate")
	if not animate then
		return ids
	end

	for trackName, folderName in ANIMATE_SOURCES do
		local folder = animate:FindFirstChild(folderName)
		if folder then
			local animation = folder:FindFirstChildWhichIsA("Animation")
			if animation and animation.AnimationId ~= "" then
				ids[trackName] = animation.AnimationId
			end
		end
	end

	return ids
end

--============================================================
-- CONSTRUCTION
--============================================================

function AnimationController.new(character: Model, controller, overrides: { [string]: any }?)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	assert(humanoid, "[AnimationController] Humanoid introuvable")

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local self = setmetatable({}, AnimationController)
	self.character = character
	self.controller = controller
	self.humanoid = humanoid
	self.animator = animator
	self.config = Config.Animation
	self._alive = true
	self._tracks = {}
	self._currentName = nil
	self._connections = {}

	-- Priorité : surcharges explicites > script Animate > valeurs de repli
	local ids = {}
	for name, id in FALLBACK_IDS do
		ids[name] = id
	end
	for name, id in harvestFromAnimateScript(character) do
		ids[name] = id
	end
	if overrides then
		for name, id in overrides do
			ids[name] = id
		end
	end
	self.ids = ids

	self:_disableDefaultAnimate()
	self:_loadTracks()
	self:_bindEvents()

	return self
end

--[[
	Désactive le script Animate par défaut, sinon il se battrait avec nous
	(il essaie en permanence de rejouer son idle).
]]
function AnimationController:_disableDefaultAnimate()
	local animate = self.character:FindFirstChild("Animate")
	if animate and animate:IsA("BaseScript") then
		self._defaultAnimate = animate
		animate.Disabled = true
	end

	-- on coupe aussi les pistes qu'il aurait déjà lancées
	for _, track in self.animator:GetPlayingAnimationTracks() do
		track:Stop(0.1)
	end
end

function AnimationController:_loadTracks()
	local priorities = {
		idle = Enum.AnimationPriority.Core,
		walk = Enum.AnimationPriority.Movement,
		run = Enum.AnimationPriority.Movement,
		crouch = Enum.AnimationPriority.Movement,
		slide = Enum.AnimationPriority.Movement,
		wallRun = Enum.AnimationPriority.Movement,
		jump = Enum.AnimationPriority.Action,
		fall = Enum.AnimationPriority.Movement,
		land = Enum.AnimationPriority.Action,
		climb = Enum.AnimationPriority.Movement,
	}

	for name, id in self.ids do
		if type(id) ~= "string" or id == "" then
			continue
		end

		local animation = Instance.new("Animation")
		animation.Name = name
		animation.AnimationId = id

		-- Un ID invalide ne doit pas casser tout le personnage
		local ok, track = pcall(function()
			return self.animator:LoadAnimation(animation)
		end)

		if ok and track then
			track.Priority = priorities[name] or Enum.AnimationPriority.Movement
			track.Looped = name ~= "jump" and name ~= "land"
			self._tracks[name] = track
		else
			warn(`[AnimationController] animation "{name}" ({id}) illisible : {track}`)
		end
	end
end

function AnimationController:_bindEvents()
	local controller = self.controller

	table.insert(
		self._connections,
		controller:on("Jumped", function()
			self:playOneShot("jump")
		end)
	)

	table.insert(
		self._connections,
		controller:on("Landed", function(velocity: Vector3)
			-- réception marquée seulement si l'impact est réel
			if math.abs(velocity.Y) > self.config.LandImpactSpeed then
				self:playOneShot("land")
			end
		end)
	)
end

--============================================================
-- LECTURE
--============================================================

--[[ Joue une animation ponctuelle par-dessus la locomotion. ]]
function AnimationController:playOneShot(name: string, speed: number?)
	local track = self._tracks[name]
	if not track then
		return
	end
	track:Stop(0)
	track:Play(self.config.OneShotFadeTime)
	track:AdjustSpeed(speed or 1)
end

--[[
	Choisit la piste correspondant à l'état, avec repli si l'animation
	personnalisée n'a pas été fournie.
]]
function AnimationController:_resolveTrack(state: string, snapshot): (string?, number)
	local speed = snapshot.horizontalSpeed
	local config = self.config

	if state == "WallRunning" then
		return self:_firstAvailable({ "wallRun", "run" }), math.max(speed / config.RunReferenceSpeed, 0.6)
	elseif state == "Sliding" then
		return self:_firstAvailable({ "slide", "fall" }), 1
	elseif state == "Airborne" then
		local rising = snapshot.velocity:Dot(snapshot.upVector) > 1
		if rising then
			return self:_firstAvailable({ "jump", "fall" }), 1
		end
		return self:_firstAvailable({ "fall", "jump" }), 1
	elseif state == "Crouching" then
		local name = self:_firstAvailable({ "crouch", "walk" })
		return name, math.max(speed / config.WalkReferenceSpeed, 0.4)
	elseif state == "Running" then
		return self:_firstAvailable({ "run", "walk" }), math.max(speed / config.RunReferenceSpeed, 0.5)
	elseif state == "Walking" then
		return self:_firstAvailable({ "walk", "run" }), math.max(speed / config.WalkReferenceSpeed, 0.5)
	end

	return self:_firstAvailable({ "idle" }), 1
end

function AnimationController:_firstAvailable(candidates: { string }): string?
	for _, name in candidates do
		if self._tracks[name] then
			return name
		end
	end
	return nil
end

--============================================================
-- BOUCLE
--============================================================

function AnimationController:step(_dt: number)
	if not self._alive or not self.character.Parent then
		return
	end
	if self.humanoid.Health <= 0 then
		return
	end

	local snapshot = self.controller:snapshot()
	local targetName, speedScale = self:_resolveTrack(snapshot.state, snapshot)

	if targetName ~= self._currentName then
		local previous = self._currentName and self._tracks[self._currentName]
		if previous then
			previous:Stop(self.config.CrossfadeTime)
		end

		local nextTrack = targetName and self._tracks[targetName]
		if nextTrack then
			nextTrack:Play(self.config.CrossfadeTime)
		end
		self._currentName = targetName
	end

	-- La vitesse de lecture suit la vitesse réelle : sans ça le personnage
	-- « patine », ses pieds glissent sur le sol.
	local current = self._currentName and self._tracks[self._currentName]
	if current then
		current:AdjustSpeed(math.clamp(speedScale, 0.25, self.config.MaxPlaybackSpeed))
	end
end

function AnimationController:destroy()
	if not self._alive then
		return
	end
	self._alive = false

	for _, disconnect in self._connections do
		pcall(disconnect)
	end
	table.clear(self._connections)

	for _, track in self._tracks do
		pcall(function()
			track:Stop(0.1)
			track:Destroy()
		end)
	end
	table.clear(self._tracks)

	-- on rend la main au script Animate d'origine
	if self._defaultAnimate and self._defaultAnimate.Parent then
		self._defaultAnimate.Disabled = false
	end
end

return AnimationController
