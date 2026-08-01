--!nonstrict
--[[
	CharacterController.luau
	Contrôleur de personnage "capsule flottante" (floating capsule controller).

	POURQUOI PAS LE HUMANOID ?
	Le Humanoid Roblox est une boîte noire : pas de contrôle sur l'accélération,
	pas de coyote time, pas de wall run, des marches capricieuses. Ici on met le
	Humanoid en état Physics et on pilote le HumanoidRootPart à la force.

	PRINCIPE
	Le personnage ne touche jamais le sol : il *lévite* à `RideHeight` grâce à
	un ressort amorti tiré vers le bas. Ce seul mécanisme donne gratuitement :
	  - le franchissement de marches (le ressort absorbe la différence)
	  - les pentes (la normale oriente le déplacement)
	  - un contact stable, sans vibration ni accrochage sur les arêtes
	  - les plateformes mobiles (on hérite de la vélocité du sol)

	Le reste (déplacement, saut, wall run, glissade) s'ajoute sous forme de
	forces sur ce même corps rigide.

	USAGE
		local controller = CharacterController.new(character)
		AdvancedPhysics.register(controller)     -- appelle :step(dt)
		controller:setMoveInput(worldDirection)  -- Vector3 normalisé
		controller:setLookDirection(cameraLook)
		controller:requestJump()
		controller:setSprinting(true)
		controller:setCrouching(true)
]]

local Config = require(script.Parent.Parent.Config)
local GravityField = require(script.Parent.GravityField)
local RaycastUtil = require(script.Parent.Parent.Util.RaycastUtil)
local VectorUtil = require(script.Parent.Parent.Util.VectorUtil)

local CharacterController = {}
CharacterController.__index = CharacterController

--============================================================
-- CONSTRUCTION
--============================================================

function CharacterController.new(character: Model, overrides: { [string]: any }?)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	assert(root, "[CharacterController] HumanoidRootPart introuvable")

	local self = setmetatable({}, CharacterController)

	self.character = character
	self.root = root
	self.humanoid = character:FindFirstChildOfClass("Humanoid")
	self.config = Config.merge(Config.Character, overrides)

	-- Entrées
	self._moveInput = Vector3.zero
	self._lookDirection = root.CFrame.LookVector
	self._sprinting = false
	self._crouching = false
	self._jumpHeld = false

	-- État
	self._grounded = false
	self._groundNormal = Vector3.yAxis
	self._groundPart = nil
	self._platformVelocity = Vector3.zero
	self._slopeAngle = 0
	self._upVector = Vector3.yAxis
	self._state = "Idle"

	-- Chronos
	self._coyoteTimer = 0
	self._jumpBufferTimer = 0
	self._jumpSuppressTimer = 0
	self._jumpsLeft = self.config.MaxJumps
	self._wallRunTimer = 0
	self._slideTimer = 0
	self._wallNormal = Vector3.zero
	self._wallRunning = false
	self._sliding = false
	self._alive = true

	-- Événements (signaux légers : simples listes de callbacks)
	self._listeners = {
		Jumped = {},
		Landed = {},
		WallRunStarted = {},
		WallRunEnded = {},
		SlideStarted = {},
		SlideEnded = {},
		StateChanged = {},
	}

	self:_buildActuators()
	self:_takeOverHumanoid()
	self:_rebuildRaycastParams()

	return self
end

function CharacterController:_buildActuators()
	local attachment = Instance.new("Attachment")
	attachment.Name = "PhysicsControllerAttachment"
	attachment.Parent = self.root
	self._attachment = attachment

	-- Une seule VectorForce reçoit la somme de toutes les forces du frame.
	-- On la met à jour dans PreSimulation : le moteur l'applique ensuite
	-- pendant tout le pas de simulation, sous-pas internes compris.
	local force = Instance.new("VectorForce")
	force.Name = "PhysicsControllerForce"
	force.Attachment0 = attachment
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.ApplyAtCenterOfMass = true
	force.Force = Vector3.zero
	force.Parent = self.root
	self._linearForce = force

	local align = Instance.new("AlignOrientation")
	align.Name = "PhysicsControllerAlign"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.RigidityEnabled = false
	align.MaxTorque = 1e6
	align.MaxAngularVelocity = math.huge
	align.Responsiveness = self.config.TurnResponsiveness
	align.Parent = self.root
	self._alignOrientation = align
end

--[[
	Le Humanoid continue d'exister (animations, santé, nom au-dessus de la tête)
	mais ne pilote plus la physique.
]]
function CharacterController:_takeOverHumanoid()
	local humanoid = self.humanoid
	if not humanoid then
		return
	end

	local disabled = {
		Enum.HumanoidStateType.Running,
		Enum.HumanoidStateType.RunningNoPhysics,
		Enum.HumanoidStateType.Climbing,
		Enum.HumanoidStateType.Jumping,
		Enum.HumanoidStateType.Freefall,
		Enum.HumanoidStateType.Landed,
		Enum.HumanoidStateType.FallingDown,
		Enum.HumanoidStateType.GettingUp,
		Enum.HumanoidStateType.Flying,
	}
	for _, state in disabled do
		humanoid:SetStateEnabled(state, false)
	end

	humanoid.AutoRotate = false
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.UseJumpPower = true
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)

	-- Si quelque chose force un autre état (siège, dégâts), on reprend la main.
	self._stateConnection = humanoid.StateChanged:Connect(function(_, new)
		if not self._alive then
			return
		end
		if new ~= Enum.HumanoidStateType.Physics and new ~= Enum.HumanoidStateType.Dead then
			humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		end
	end)
end

function CharacterController:_rebuildRaycastParams()
	self._rayParams = RaycastUtil.params({ self.character }, nil, true)
end

--============================================================
-- ÉVÉNEMENTS
--============================================================

function CharacterController:on(eventName: string, callback: (...any) -> ()): () -> ()
	local bucket = self._listeners[eventName]
	assert(bucket, `[CharacterController] événement inconnu : {eventName}`)
	table.insert(bucket, callback)
	return function()
		local index = table.find(bucket, callback)
		if index then
			table.remove(bucket, index)
		end
	end
end

function CharacterController:_emit(eventName: string, ...)
	for _, callback in self._listeners[eventName] do
		task.spawn(callback, ...)
	end
end

function CharacterController:_setState(newState: string)
	if self._state == newState then
		return
	end
	local previous = self._state
	self._state = newState
	self:_emit("StateChanged", newState, previous)
end

--============================================================
-- ENTRÉES
--============================================================

--[[ Direction de déplacement souhaitée, en espace monde (norme <= 1). ]]
function CharacterController:setMoveInput(direction: Vector3)
	self._moveInput = VectorUtil.clampMagnitude(VectorUtil.sanitize(direction), 1)
end

--[[ Direction du regard : oriente le personnage. ]]
function CharacterController:setLookDirection(direction: Vector3)
	local flat = VectorUtil.projectOnPlane(direction, self._upVector)
	if flat.Magnitude > 1e-3 then
		self._lookDirection = flat.Unit
	end
end

function CharacterController:setSprinting(active: boolean)
	self._sprinting = active
end

function CharacterController:setCrouching(active: boolean)
	self._crouching = active
end

--[[ À appeler quand le joueur presse Espace. Mis en mémoire tampon. ]]
function CharacterController:requestJump()
	self._jumpBufferTimer = self.config.JumpBuffer
	self._jumpHeld = true
end

--[[ À appeler quand le joueur relâche Espace (saut à hauteur variable). ]]
function CharacterController:releaseJump()
	self._jumpHeld = false
end

--============================================================
-- LECTURE D'ÉTAT
--============================================================

function CharacterController:isGrounded(): boolean
	return self._grounded
end

function CharacterController:getState(): string
	return self._state
end

function CharacterController:snapshot()
	local velocity = self.root.AssemblyLinearVelocity
	return {
		state = self._state,
		grounded = self._grounded,
		velocity = velocity,
		horizontalSpeed = VectorUtil.projectOnPlane(velocity, self._upVector).Magnitude,
		upVector = self._upVector,
		groundNormal = self._groundNormal,
		slopeAngle = self._slopeAngle,
		coyoteTimeLeft = self._coyoteTimer,
		jumpsLeft = self._jumpsLeft,
	}
end

--============================================================
-- DÉTECTION
--============================================================

function CharacterController:_probeGround()
	local config = self.config
	local root = self.root
	local up = self._upVector
	local distance = config.RideHeight + config.ProbeExtra

	local result, averagedNormal =
		RaycastUtil.groundProbe(root.Position, up, distance, config.ProbeRadius, self._rayParams, 4)

	local wasGrounded = self._grounded

	if not result then
		self._grounded = false
		self._groundPart = nil
		self._platformVelocity = Vector3.zero
		self._groundNormal = up
		self._slopeAngle = 0
		return nil
	end

	local normal = averagedNormal
	local slopeAngle = VectorUtil.angleBetween(normal, up)

	self._groundNormal = normal
	self._slopeAngle = slopeAngle
	self._groundPart = result.Instance

	if config.InheritPlatformVelocity and result.Instance and not result.Instance.Anchored then
		self._platformVelocity = VectorUtil.velocityAtPoint(result.Instance, result.Position)
	elseif config.InheritPlatformVelocity and result.Instance and result.Instance.Anchored then
		-- une plateforme ancrée peut quand même bouger (Tween/CFrame) :
		-- AssemblyLinearVelocity est alors nul, ce qui est le comportement voulu
		self._platformVelocity = Vector3.zero
	else
		self._platformVelocity = Vector3.zero
	end

	local withinRide = result.Distance <= config.RideHeight + config.MaxStepHeight * 0.5
	local walkable = slopeAngle <= config.MaxSlopeAngle
	self._grounded = withinRide and walkable and self._jumpSuppressTimer <= 0

	if self._grounded and not wasGrounded then
		self._jumpsLeft = config.MaxJumps
		self:_emit("Landed", self.root.AssemblyLinearVelocity)
	end

	return result
end

function CharacterController:_probeWalls()
	if not self.config.WallRunEnabled then
		self._wallNormal = Vector3.zero
		return
	end

	local root = self.root
	local up = self._upVector
	local origin = root.Position
	local distance = self.config.WallCheckDistance

	local forward = VectorUtil.projectOnPlane(self._lookDirection, up)
	if forward.Magnitude < 1e-3 then
		self._wallNormal = Vector3.zero
		return
	end
	forward = forward.Unit
	local right = forward:Cross(up).Unit

	local candidates = { right * distance, -right * distance, forward * distance }
	local best: RaycastResult? = nil

	for _, offset in candidates do
		local result = workspace:Raycast(origin, offset, self._rayParams)
		if result then
			-- on ne veut que des murs quasi verticaux
			local angle = VectorUtil.angleBetween(result.Normal, up)
			if angle > 65 and angle < 115 then
				if not best or result.Distance < best.Distance then
					best = result
				end
			end
		end
	end

	self._wallNormal = best and best.Normal or Vector3.zero
	self._wallPart = best and best.Instance or nil
end

--============================================================
-- BOUCLE
--============================================================

function CharacterController:step(dt: number)
	if not self._alive then
		return
	end
	local root = self.root
	if not root.Parent then
		return
	end
	if self.humanoid and self.humanoid.Health <= 0 then
		self._linearForce.Force = Vector3.zero
		return
	end

	dt = math.min(dt, Config.General.MaxDeltaTime)
	if dt <= 0 then
		return
	end

	-- Le "haut" vient des champs de gravité : marcher sur une planète
	-- ou au plafond ne demande aucun code supplémentaire.
	self._upVector = GravityField.upVector(root.Position)

	self._coyoteTimer = math.max(0, self._coyoteTimer - dt)
	self._jumpBufferTimer = math.max(0, self._jumpBufferTimer - dt)
	self._jumpSuppressTimer = math.max(0, self._jumpSuppressTimer - dt)

	local groundResult = self:_probeGround()
	self:_probeWalls()

	if self._grounded then
		self._coyoteTimer = self.config.CoyoteTime
	end

	local mass = root.AssemblyMass
	local velocity = root.AssemblyLinearVelocity
	local totalForce = Vector3.zero

	self:_updateSlide(dt, velocity)
	self:_updateWallRun(dt, velocity)

	totalForce += self:_rideSpringForce(groundResult, velocity, mass, dt)
	totalForce += self:_movementForce(velocity, mass, dt)
	totalForce += self:_gravityForce(velocity, mass)
	totalForce += self:_slopeSlideForce(mass)
	totalForce += self:_wallRunForce(velocity, mass)

	self:_handleJump(velocity, mass)
	self:_updateOrientation()
	self:_updateLocomotionState(velocity)

	totalForce = VectorUtil.sanitize(totalForce)
	self._linearForce.Force = VectorUtil.clampMagnitude(totalForce, self.config.MaxGroundForce * math.max(mass, 1))
end

--============================================================
-- SUSPENSION
--============================================================

function CharacterController:_rideSpringForce(groundResult: RaycastResult?, velocity: Vector3, mass: number, dt: number): Vector3
	if not groundResult or self._jumpSuppressTimer > 0 then
		return Vector3.zero
	end
	local config = self.config
	-- pente trop raide : pas de suspension, on glisse
	if self._slopeAngle > config.MaxSlopeAngle then
		return Vector3.zero
	end
	if groundResult.Distance > config.RideHeight + config.MaxStepHeight then
		return Vector3.zero
	end

	local up = self._upVector
	local displacement = groundResult.Distance - config.RideHeight
	local relativeVelocity = (velocity - self._platformVelocity):Dot(up)

	local acceleration = -displacement * config.RideSpringStrength - relativeVelocity * config.RideSpringDamper
	local force = up * (acceleration * mass)

	-- Troisième loi de Newton : on repousse le sol.
	-- Sans ça on peut marcher sur une planche sans jamais la faire plier.
	if config.PushOtherParts then
		local groundPart = groundResult.Instance
		if groundPart and not groundPart.Anchored then
			local reaction = VectorUtil.clampMagnitude(-force, config.MaxPushForce)
			groundPart:ApplyImpulseAtPosition(reaction * dt, groundResult.Position)
		end
	end

	return force
end

--============================================================
-- DÉPLACEMENT
--============================================================

function CharacterController:_targetSpeed(): number
	local config = self.config
	if self._sliding then
		return 0 -- la glissade est régie par l'inertie, pas par l'entrée
	end
	if self._crouching and self._grounded then
		return config.CrouchSpeed
	end
	if self._sprinting then
		return config.RunSpeed
	end
	return config.WalkSpeed
end

function CharacterController:_movementForce(velocity: Vector3, mass: number, dt: number): Vector3
	local config = self.config
	local up = self._upVector
	local input = self._moveInput

	local direction = VectorUtil.projectOnPlane(input, up)
	local hasInput = direction.Magnitude > 1e-3

	-- Sur une pente, on se déplace *le long* du sol : sans ça, monter une
	-- rampe fait décoller le personnage à chaque pas.
	if self._grounded and hasInput then
		direction = VectorUtil.projectOnPlane(direction, self._groundNormal)
	end

	local targetSpeed = self:_targetSpeed()
	local goalVelocity = (hasInput and VectorUtil.safeUnit(direction) or Vector3.zero) * targetSpeed
	if self._grounded then
		goalVelocity += VectorUtil.projectOnPlane(self._platformVelocity, up)
	end

	local currentPlanar = VectorUtil.projectOnPlane(velocity, up)
	local goalPlanar = VectorUtil.projectOnPlane(goalVelocity, up)
	local difference = goalPlanar - currentPlanar

	local accelerationLimit
	if self._sliding then
		accelerationLimit = config.SlideFriction * 60
	elseif self._grounded then
		accelerationLimit = hasInput and config.GroundAcceleration or config.GroundDeceleration
	else
		accelerationLimit = hasInput and config.AirAcceleration or 0
	end

	local requiredAcceleration = difference / dt
	local acceleration = VectorUtil.clampMagnitude(requiredAcceleration, accelerationLimit)

	local force = acceleration * mass

	-- Traînée en l'air : permet de conserver l'élan sans dériver éternellement
	if not self._grounded and not self._wallRunning then
		force -= currentPlanar * (config.AirDrag * mass)
	end

	return force
end

--============================================================
-- GRAVITÉ (mise en forme du ressenti)
--============================================================

function CharacterController:_gravityForce(velocity: Vector3, mass: number): Vector3
	local config = self.config
	local desiredGravity = GravityField.sample(self.root.Position)
	local engineGravity = Vector3.new(0, -workspace.Gravity, 0)

	local scale = 1
	if self._wallRunning then
		scale = config.WallRunGravityScale
	elseif not self._grounded then
		local vertical = velocity:Dot(self._upVector)
		if vertical < -0.1 then
			-- chute : on alourdit, un saut "flottant" est le défaut n°1 du game feel
			scale = config.FallGravityScale
		elseif vertical > 0.1 and not self._jumpHeld then
			-- saut relâché tôt : retombée accélérée
			scale = config.LowJumpGravityScale
		end
	end

	-- on annule la gravité moteur et on applique la nôtre, mise à l'échelle
	return (desiredGravity * scale - engineGravity) * mass
end

--============================================================
-- PENTES RAIDES
--============================================================

function CharacterController:_slopeSlideForce(mass: number): Vector3
	if self._groundPart == nil then
		return Vector3.zero
	end

	-- direction de plus grande pente
	local downhill = VectorUtil.projectOnPlane(-self._upVector, self._groundNormal)
	if downhill.Magnitude < 1e-3 then
		return Vector3.zero
	end
	local downhillUnit = downhill.Unit

	-- Glissade volontaire : on gagne de la vitesse en descente, ce qui permet
	-- d'enchaîner les pentes sans jamais relancer le sprint.
	if self._sliding and self._grounded then
		local steepness = math.clamp(self._slopeAngle / math.max(self.config.MaxSlopeAngle, 1e-3), 0, 1)
		return downhillUnit * (self.config.SlideSlopeBoost * steepness * mass)
	end

	-- Pente trop raide : on dévale, qu'on le veuille ou non.
	if self._grounded or self._slopeAngle <= self.config.MaxSlopeAngle then
		return Vector3.zero
	end

	local excess = math.clamp((self._slopeAngle - self.config.MaxSlopeAngle) / 30, 0, 1)
	return downhillUnit * (self.config.SlideAcceleration * excess * mass)
end

--============================================================
-- SAUT
--============================================================

function CharacterController:_handleJump(velocity: Vector3, mass: number)
	local config = self.config
	local up = self._upVector

	-- Saut mural : prioritaire, il relance le joueur loin du mur
	if self._jumpBufferTimer > 0 and (self._wallRunning or (self._wallNormal.Magnitude > 0 and not self._grounded)) then
		self._jumpBufferTimer = 0
		self._jumpSuppressTimer = config.JumpSuppressTime
		self:_stopWallRun()

		local vertical = velocity:Dot(up)
		local impulse = up * ((config.WallJumpVerticalSpeed - vertical) * mass)
		impulse += self._wallNormal * (config.WallJumpHorizontalSpeed * mass)
		self.root:ApplyImpulse(impulse)
		self:_emit("Jumped", "Wall")
		return
	end

	if self._jumpBufferTimer <= 0 then
		return
	end

	local canGroundJump = self._grounded or self._coyoteTimer > 0
	local canAirJump = self._jumpsLeft > 1 or (not canGroundJump and self._jumpsLeft > 0)

	if not canGroundJump and not canAirJump then
		return
	end

	self._jumpBufferTimer = 0
	self._jumpSuppressTimer = config.JumpSuppressTime
	self._coyoteTimer = 0
	self._grounded = false
	self._jumpsLeft = math.max(0, self._jumpsLeft - 1)
	self:_stopSlide()

	-- v = sqrt(2 g h) : on vise une hauteur, pas une vitesse magique
	local gravityMagnitude = math.max(GravityField.sample(self.root.Position).Magnitude, 1e-3)
	local jumpVelocity = math.sqrt(2 * gravityMagnitude * config.JumpHeight)

	-- on *remplace* la composante verticale : un saut depuis une chute
	-- doit monter aussi haut qu'un saut à l'arrêt
	local vertical = velocity:Dot(up)
	self.root:ApplyImpulse(up * ((jumpVelocity - vertical) * mass))

	self:_emit("Jumped", canGroundJump and "Ground" or "Air")
end

--[[
	Coupe le saut si la touche est relâchée pendant la montée.
	Appelé depuis releaseJump via le prochain step (voir _gravityForce),
	mais on offre aussi une coupure immédiate plus nette.
]]
function CharacterController:cutJump()
	local up = self._upVector
	local velocity = self.root.AssemblyLinearVelocity
	local vertical = velocity:Dot(up)
	if vertical > 0 then
		local target = vertical * self.config.VariableJumpCut
		self.root:ApplyImpulse(up * ((target - vertical) * self.root.AssemblyMass))
	end
	self._jumpHeld = false
end

--============================================================
-- WALL RUN
--============================================================

function CharacterController:_updateWallRun(dt: number, velocity: Vector3)
	local config = self.config
	if not config.WallRunEnabled then
		return
	end

	if self._wallRunning then
		self._wallRunTimer -= dt
		local speed = VectorUtil.projectOnPlane(velocity, self._upVector).Magnitude
		local lostWall = self._wallNormal.Magnitude < 1e-3
		if lostWall or self._grounded or self._wallRunTimer <= 0 or speed < config.WallRunMinSpeed * 0.6 then
			self:_stopWallRun()
		end
		return
	end

	if self._grounded or self._wallNormal.Magnitude < 1e-3 then
		return
	end
	if self._moveInput.Magnitude < 0.2 then
		return
	end

	local speed = VectorUtil.projectOnPlane(velocity, self._upVector).Magnitude
	if speed < config.WallRunMinSpeed then
		return
	end

	-- il faut avancer *le long* du mur, pas foncer dedans
	local along = VectorUtil.projectOnPlane(velocity, self._wallNormal)
	if along.Magnitude < config.WallRunMinSpeed * 0.5 then
		return
	end

	self._wallRunning = true
	self._wallRunTimer = config.WallRunMaxTime
	self._jumpsLeft = math.max(self._jumpsLeft, 1)
	self:_emit("WallRunStarted", self._wallNormal)
end

function CharacterController:_stopWallRun()
	if not self._wallRunning then
		return
	end
	self._wallRunning = false
	self._wallRunTimer = 0
	self:_emit("WallRunEnded")
end

function CharacterController:_wallRunForce(velocity: Vector3, mass: number): Vector3
	if not self._wallRunning or self._wallNormal.Magnitude < 1e-3 then
		return Vector3.zero
	end
	-- on colle au mur, sinon la moindre irrégularité éjecte le joueur
	local stick = -self._wallNormal * (self.config.WallRunStickForce * mass)

	-- et on conserve l'élan le long du mur
	local along = VectorUtil.projectOnPlane(velocity, self._wallNormal)
	local alongPlanar = VectorUtil.projectOnPlane(along, self._upVector)
	local boost = Vector3.zero
	if alongPlanar.Magnitude > 1e-3 then
		boost = alongPlanar.Unit * (self.config.GroundAcceleration * 0.25 * mass) * self._moveInput.Magnitude
	end

	return stick + boost
end

--============================================================
-- GLISSADE
--============================================================

function CharacterController:_updateSlide(dt: number, velocity: Vector3)
	local config = self.config
	if not config.SlideEnabled then
		return
	end

	local planarSpeed = VectorUtil.projectOnPlane(velocity, self._upVector).Magnitude

	if self._sliding then
		self._slideTimer -= dt
		local downhill = VectorUtil.projectOnPlane(-self._upVector, self._groundNormal)
		local onSlope = downhill.Magnitude > 0.15 and self._grounded

		-- sur une pente on garde la glissade tant que ça descend
		local expired = self._slideTimer <= 0 and not onSlope
		if not self._crouching or not self._grounded or planarSpeed < config.SlideMinSpeed * 0.4 or expired then
			self:_stopSlide()
		end
		return
	end

	if self._crouching and self._grounded and planarSpeed >= config.SlideMinSpeed then
		self._sliding = true
		self._slideTimer = config.SlideMaxTime
		self:_emit("SlideStarted", planarSpeed)
	end
end

function CharacterController:_stopSlide()
	if not self._sliding then
		return
	end
	self._sliding = false
	self._slideTimer = 0
	self:_emit("SlideEnded")
end

--============================================================
-- ORIENTATION
--============================================================

function CharacterController:_updateOrientation()
	local up = self._upVector
	local look = self._lookDirection

	-- en glissade on regarde dans le sens du mouvement, c'est plus lisible
	if self._sliding then
		local velocityDirection = VectorUtil.projectOnPlane(self.root.AssemblyLinearVelocity, up)
		if velocityDirection.Magnitude > 1e-2 then
			look = velocityDirection.Unit
		end
	end

	local flat = VectorUtil.projectOnPlane(look, up)
	if flat.Magnitude < 1e-3 then
		return
	end
	self._alignOrientation.CFrame = CFrame.lookAt(Vector3.zero, flat.Unit, up)
end

--============================================================
-- ÉTAT DE LOCOMOTION (pour piloter les animations)
--============================================================

function CharacterController:_updateLocomotionState(velocity: Vector3)
	local planarSpeed = VectorUtil.projectOnPlane(velocity, self._upVector).Magnitude

	if self._wallRunning then
		self:_setState("WallRunning")
	elseif self._sliding then
		self:_setState("Sliding")
	elseif not self._grounded then
		self:_setState("Airborne")
	elseif self._crouching then
		self:_setState("Crouching")
	elseif planarSpeed > self.config.WalkSpeed + 1 then
		self:_setState("Running")
	elseif planarSpeed > 0.6 then
		self:_setState("Walking")
	else
		self:_setState("Idle")
	end
end

--============================================================
-- NETTOYAGE
--============================================================

function CharacterController:destroy()
	if not self._alive then
		return
	end
	self._alive = false

	if self._stateConnection then
		self._stateConnection:Disconnect()
		self._stateConnection = nil
	end
	if self._linearForce then
		self._linearForce:Destroy()
	end
	if self._alignOrientation then
		self._alignOrientation:Destroy()
	end
	if self._attachment then
		self._attachment:Destroy()
	end

	local humanoid = self.humanoid
	if humanoid and humanoid.Parent then
		for _, state in Enum.HumanoidStateType:GetEnumItems() do
			if state ~= Enum.HumanoidStateType.None then
				pcall(function()
					humanoid:SetStateEnabled(state, true)
				end)
			end
		end
		humanoid.AutoRotate = true
		humanoid.WalkSpeed = 16
		humanoid.JumpPower = 50
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end

	table.clear(self._listeners)
end

return CharacterController
