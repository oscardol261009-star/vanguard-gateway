--!nonstrict
--[[
	CameraEffects.luau
	Le « game feel » d'un jeu de parkour.

	Ce module ne change aucune mécanique : il rend la vitesse *lisible*. C'est
	précisément ce qui sépare un contrôleur correct d'un jeu qui donne envie
	d'y rejouer. Quatre effets, tous pilotés par des ressorts amortis pour
	rester fluides quel que soit le framerate :

	  - FOV dynamique  : le champ de vision s'ouvre avec la vitesse. Le cerveau
	                     interprète l'élargissement comme de l'accélération.
	  - Inclinaison    : la caméra roule dans les virages et penche fortement
	                     en wall run, ce qui rend le mur « lisible ».
	  - Encaissement   : la caméra plonge à l'atterrissage, proportionnellement
	                     à l'impact.
	  - Abaissement    : la caméra descend en glissade et en accroupi.

	Le module s'accroche APRÈS la caméra par défaut (RenderPriority.Camera + 1)
	et applique ses effets en décalage relatif : la caméra Roblox continue de
	fonctionner normalement, on ne fait que la décorer.
]]

local RunService = game:GetService("RunService")

local Config = require(script.Parent.Parent.Config)
local Spring = require(script.Parent.Parent.Util.Spring)
local VectorUtil = require(script.Parent.Parent.Util.VectorUtil)

local CameraEffects = {}
CameraEffects.__index = CameraEffects

--============================================================
-- CONSTRUCTION
--============================================================

function CameraEffects.new(controller, camera: Camera?, overrides: { [string]: any }?)
	local self = setmetatable({}, CameraEffects)

	self.controller = controller
	self.camera = camera or workspace.CurrentCamera
	self.config = Config.merge(Config.Camera, overrides)
	self._alive = true

	self.baseFieldOfView = self.config.BaseFieldOfView

	-- Un ressort par canal : ils évoluent indépendamment et se composent.
	self._fovSpring = Spring.number(self.config.FovFrequency, 1, 0)
	self._rollSpring = Spring.number(self.config.RollFrequency, 0.7, 0)
	self._dipSpring = Spring.number(self.config.DipFrequency, 0.45, 0)
	self._heightSpring = Spring.number(self.config.HeightFrequency, 1, 0)

	self._connections = {}
	self:_bindEvents()
	self:_bindRender()

	return self
end

function CameraEffects:_bindEvents()
	local controller = self.controller

	table.insert(
		self._connections,
		controller:on("Landed", function(velocity: Vector3)
			local impact = math.abs(velocity.Y)
			if impact < self.config.DipMinImpactSpeed then
				return
			end
			-- l'encaissement croît avec l'impact, mais sature : une chute de
			-- 500 studs ne doit pas envoyer la caméra sous la map
			local intensity = math.clamp(
				(impact - self.config.DipMinImpactSpeed) / self.config.DipReferenceSpeed,
				0,
				1
			)
			self._dipSpring:impulse(-self.config.DipStrength * intensity)
		end)
	)

	table.insert(
		self._connections,
		controller:on("Jumped", function()
			self._dipSpring:impulse(self.config.JumpKick)
		end)
	)

	-- La normale du mur détermine de quel côté pencher.
	table.insert(
		self._connections,
		controller:on("WallRunStarted", function(normal: Vector3)
			self._wallNormal = normal
		end)
	)

	table.insert(
		self._connections,
		controller:on("WallRunEnded", function()
			self._wallNormal = nil
		end)
	)
end

function CameraEffects:_bindRender()
	-- Après la caméra par défaut : on lit sa CFrame finale et on la décore.
	RunService:BindToRenderStep(
		"AdvancedPhysicsCameraEffects",
		Enum.RenderPriority.Camera.Value + 1,
		function(deltaTime)
			self:_render(deltaTime)
		end
	)
end

--============================================================
-- RENDU
--============================================================

function CameraEffects:_updateTargets()
	local snapshot = self.controller:snapshot()
	local config = self.config
	local speed = snapshot.horizontalSpeed

	-- ---- FOV ----
	-- On ne compte que la vitesse au-delà de la marche : marcher ne doit rien
	-- déformer, seul le sprint et la glissade ouvrent le champ.
	local excess = math.max(speed - config.FovStartSpeed, 0)
	local ratio = math.clamp(excess / math.max(config.FovReferenceSpeed, 1e-3), 0, 1)
	self._fovSpring.target = ratio * config.FovMaxIncrease

	-- ---- Inclinaison ----
	local rollTarget = 0
	if snapshot.state == "WallRunning" then
		-- signe selon le côté du mur : on penche « vers » le mur
		local right = self.camera.CFrame.RightVector
		local side = math.sign(self._wallNormal and self._wallNormal:Dot(right) or 1)
		rollTarget = -side * config.WallRunRoll
	elseif snapshot.state == "Sliding" then
		rollTarget = config.SlideRoll
	else
		-- léger roulis dans les virages, proportionnel au déplacement latéral
		local velocity = VectorUtil.projectOnPlane(snapshot.velocity, snapshot.upVector)
		if velocity.Magnitude > 1 then
			local lateral = velocity.Unit:Dot(self.camera.CFrame.RightVector)
			rollTarget = -lateral * config.StrafeRoll * math.clamp(speed / config.FovReferenceSpeed, 0, 1)
		end
	end
	self._rollSpring.target = rollTarget

	-- ---- Hauteur ----
	if snapshot.state == "Sliding" then
		self._heightSpring.target = -config.SlideHeightDrop
	elseif snapshot.state == "Crouching" then
		self._heightSpring.target = -config.CrouchHeightDrop
	else
		self._heightSpring.target = 0
	end

	-- l'encaissement revient toujours à zéro : il n'est qu'une impulsion
	self._dipSpring.target = 0
end

function CameraEffects:_render(deltaTime: number)
	if not self._alive then
		return
	end
	local camera = self.camera
	if not camera or not camera.Parent then
		return
	end

	local ok = pcall(function()
		self:_updateTargets()
	end)
	if not ok then
		return
	end

	local dt = math.min(deltaTime, Config.General.MaxDeltaTime)
	local fov = self._fovSpring:update(dt)
	local roll = self._rollSpring:update(dt)
	local dip = self._dipSpring:update(dt)
	local height = self._heightSpring:update(dt)

	camera.FieldOfView = math.clamp(self.baseFieldOfView + fov, 1, 120)

	-- Décalage relatif : la caméra par défaut garde le contrôle de la
	-- position et de la visée, on n'ajoute qu'une transformation locale.
	camera.CFrame = camera.CFrame
		* CFrame.new(0, height + dip, 0)
		* CFrame.Angles(0, 0, math.rad(roll))
end

--[[
	Le contrôleur connaît la normale du mur mais ne l'expose pas dans son
	snapshot ; on la reçoit via l'événement de wall run.
]]
function CameraEffects:setWallNormal(normal: Vector3?)
	self._wallNormal = normal
end

--[[
	Le module tourne sur RenderStep, pas sur l'ordonnanceur physique :
	:step() existe pour rester compatible avec AdvancedPhysics.register().
]]
function CameraEffects:step(_dt: number) end

function CameraEffects:destroy()
	if not self._alive then
		return
	end
	self._alive = false

	pcall(function()
		RunService:UnbindFromRenderStep("AdvancedPhysicsCameraEffects")
	end)

	for _, disconnect in self._connections do
		pcall(disconnect)
	end
	table.clear(self._connections)

	if self.camera and self.camera.Parent then
		self.camera.FieldOfView = self.baseFieldOfView
	end
end

return CameraEffects
