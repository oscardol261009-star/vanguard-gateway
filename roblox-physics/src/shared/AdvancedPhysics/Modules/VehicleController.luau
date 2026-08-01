--!nonstrict
--[[
	VehicleController.luau
	Véhicule à suspension par raycast ("raycast vehicle"), le modèle utilisé
	par la quasi-totalité des jeux de course.

	Il n'y a aucune roue physique : quatre rayons partent du châssis, et
	à chaque contact on applique trois forces au point de contact :
	  1. suspension    — ressort/amortisseur le long de la normale
	  2. adhérence latérale — annule le glissement de côté (le "rail" du pneu)
	  3. traction/freinage  — pousse ou freine le long de l'axe de la roue

	Avantages : pas de contraintes instables, pas de roues qui se coincent,
	un comportement identique quel que soit le framerate, et un réglage
	entièrement paramétrique (raideur, grip, transfert de charge).

	Le "cercle de friction" limite la somme vectorielle des forces du pneu à
	µ × charge : accélérer à fond en virage fait donc naturellement décrocher.

	USAGE
		local car = VehicleController.new(chassis, {
			wheels = {
				{ offset = Vector3.new(-3,-1, 5), radius = 1.5, steer = true,  drive = false },
				{ offset = Vector3.new( 3,-1, 5), radius = 1.5, steer = true,  drive = false },
				{ offset = Vector3.new(-3,-1,-5), radius = 1.5, steer = false, drive = true  },
				{ offset = Vector3.new( 3,-1,-5), radius = 1.5, steer = false, drive = true  },
			},
		})
		AdvancedPhysics.register(car)
		car:setThrottle(1) ; car:setSteer(-1) ; car:setBrake(0)
]]

local Config = require(script.Parent.Parent.Config)
local RaycastUtil = require(script.Parent.Parent.Util.RaycastUtil)
local VectorUtil = require(script.Parent.Parent.Util.VectorUtil)

local VehicleController = {}
VehicleController.__index = VehicleController

--============================================================
-- CONSTRUCTION
--============================================================

function VehicleController.new(chassis: BasePart, options)
	options = options or {}
	local self = setmetatable({}, VehicleController)

	self.chassis = chassis
	self.config = Config.merge(Config.Vehicle, options.overrides)
	self._alive = true

	-- Entrées, toutes dans [-1, 1] ou [0, 1]
	self._throttle = 0
	self._steerInput = 0
	self._brake = 0
	self._handbrake = false
	self._steerAngle = 0

	self._wheels = {}
	for index, definition in options.wheels or {} do
		self._wheels[index] = {
			def = definition,
			grounded = false,
			compression = 0,
			suspensionLength = self.config.SuspensionRestLength,
			previousLength = self.config.SuspensionRestLength,
			contactPoint = Vector3.zero,
			contactNormal = Vector3.yAxis,
			normalForce = 0,
			steerAngle = 0,
			spinAngle = 0,
			slipRatio = 0,
			slipAngle = 0,
			instance = definition.model,
		}
	end

	-- Barres anti-roulis : paires gauche/droite fournies par l'appelant
	-- sous forme d'index, ex. { {1,2}, {3,4} }
	self._antiRollPairs = options.antiRollPairs or {}

	local ignoreList: { Instance } = { chassis }
	local root = chassis:FindFirstAncestorOfClass("Model")
	if root then
		table.insert(ignoreList, root)
	end
	for _, wheel in self._wheels do
		if wheel.instance then
			table.insert(ignoreList, wheel.instance)
		end
	end
	if options.ignore then
		for _, instance in options.ignore do
			table.insert(ignoreList, instance)
		end
	end

	self._rayParams = RaycastUtil.params(ignoreList)

	return self
end

--============================================================
-- ENTRÉES
--============================================================

function VehicleController:setThrottle(value: number)
	self._throttle = math.clamp(value, -1, 1)
end

function VehicleController:setSteer(value: number)
	self._steerInput = math.clamp(value, -1, 1)
end

function VehicleController:setBrake(value: number)
	self._brake = math.clamp(value, 0, 1)
end

function VehicleController:setHandbrake(active: boolean)
	self._handbrake = active
end

function VehicleController:getSpeed(): number
	return self.chassis.AssemblyLinearVelocity.Magnitude
end

--[[ Vitesse signée le long de l'axe du véhicule (négative en marche arrière). ]]
function VehicleController:getForwardSpeed(): number
	return self.chassis.AssemblyLinearVelocity:Dot(self.chassis.CFrame.LookVector)
end

function VehicleController:getWheels()
	return self._wheels
end

--[[ Nombre de roues au sol : utile pour couper le moteur en l'air. ]]
function VehicleController:groundedWheelCount(): number
	local count = 0
	for _, wheel in self._wheels do
		if wheel.grounded then
			count += 1
		end
	end
	return count
end

--============================================================
-- DIRECTION
--============================================================

function VehicleController:_updateSteering(dt: number)
	local config = self.config
	local speed = math.abs(self:getForwardSpeed())

	-- Le braquage se réduit avec la vitesse : sans ça, un coup de volant
	-- à 200 studs/s fait faire un tête-à-queue instantané.
	local speedFactor = 1 / (1 + (speed / math.max(config.MaxSpeed, 1e-3)) * config.SteerSpeedFalloff * 4)
	local targetAngle = math.rad(config.MaxSteerAngle) * self._steerInput * speedFactor

	local maxDelta = config.SteerSpeed * dt
	self._steerAngle = math.clamp(targetAngle - self._steerAngle, -maxDelta, maxDelta) + self._steerAngle
end

--============================================================
-- SUSPENSION + PNEUS
--============================================================

function VehicleController:_stepWheel(wheel, dt: number, massPerWheel: number)
	local chassis = self.chassis
	local config = self.config
	local chassisCF = chassis.CFrame
	local up = chassisCF.UpVector

	local anchorPoint = chassisCF:PointToWorldSpace(wheel.def.offset)
	local rayLength = config.SuspensionRestLength + wheel.def.radius

	local result = workspace:Raycast(anchorPoint, -up * rayLength, self._rayParams)

	wheel.previousLength = wheel.suspensionLength

	if not result then
		wheel.grounded = false
		wheel.compression = 0
		wheel.suspensionLength = config.SuspensionRestLength
		wheel.normalForce = 0
		wheel.slipAngle = 0
		wheel.slipRatio = 0
		-- roue libre en l'air : on la fait tourner en roue-libre pour le visuel
		wheel.spinAngle += (self:getForwardSpeed() / math.max(wheel.def.radius, 1e-3)) * dt
		return
	end

	wheel.grounded = true
	wheel.contactPoint = result.Position
	wheel.contactNormal = result.Normal

	local currentLength = math.max(result.Distance - wheel.def.radius, 0)
	wheel.suspensionLength = currentLength
	local compressionDistance = config.SuspensionRestLength - currentLength
	wheel.compression = math.clamp(compressionDistance / math.max(config.SuspensionRestLength, 1e-3), 0, 1)

	-- ---- 1. Suspension (ressort + amortisseur) ----
	local contactVelocity = VectorUtil.velocityAtPoint(chassis, result.Position)
	local compressionVelocity = -contactVelocity:Dot(up)

	local springForce = compressionDistance * config.SuspensionStiffness
	local damperForce = compressionVelocity * config.SuspensionDamping
	local suspensionMagnitude = math.max(springForce + damperForce, 0)

	-- butée de compression : évite que le châssis traverse le sol
	if wheel.compression > config.SuspensionMaxCompression then
		suspensionMagnitude *= 1 + (wheel.compression - config.SuspensionMaxCompression) * 12
	end

	local suspensionForce = result.Normal * suspensionMagnitude
	wheel.normalForce = suspensionMagnitude

	chassis:ApplyImpulseAtPosition(suspensionForce * dt, result.Position)

	-- ---- 2. Repère du pneu ----
	wheel.steerAngle = wheel.def.steer and self._steerAngle or 0
	local wheelCF = chassisCF * CFrame.Angles(0, wheel.steerAngle, 0)
	local forward = VectorUtil.safeUnit(VectorUtil.projectOnPlane(wheelCF.LookVector, result.Normal))
	local right = VectorUtil.safeUnit(forward:Cross(result.Normal))
	if forward.Magnitude < 1e-3 or right.Magnitude < 1e-3 then
		return
	end

	local forwardVelocity = contactVelocity:Dot(forward)
	local lateralVelocity = contactVelocity:Dot(right)

	wheel.slipAngle = math.deg(math.atan2(lateralVelocity, math.abs(forwardVelocity) + 1e-3))
	wheel.spinAngle += (forwardVelocity / math.max(wheel.def.radius, 1e-3)) * dt

	-- Sensibilité à la charge : un pneu très chargé adhère plus, mais pas
	-- proportionnellement. C'est ce qui rend le transfert de masse important.
	local load = wheel.normalForce
	local gripScale = math.pow(math.max(load, 0) / math.max(massPerWheel * workspace.Gravity, 1e-3), config.TireLoadSensitivity)
	local maxLongitudinal = load * config.TireGripForward * gripScale
	local maxLateral = load * config.TireGripLateral * gripScale

	-- ---- 3. Force latérale (annule le glissement de côté) ----
	local desiredLateralChange = -lateralVelocity / dt
	local lateralForce = desiredLateralChange * massPerWheel * config.TireGripLateral * 0.25

	-- ---- 4. Force longitudinale (moteur / frein) ----
	local longitudinalForce = 0

	if wheel.def.drive and not self._handbrake then
		local speedRatio = math.clamp(math.abs(forwardVelocity) / math.max(config.MaxSpeed, 1e-3), 0, 1)
		-- courbe de couple : plein couple à l'arrêt, nul à la vitesse max
		local torqueCurve = 1 - speedRatio * speedRatio
		longitudinalForce += self._throttle * config.EnginePower * torqueCurve
	end

	if self._brake > 0 then
		local brakeBias = wheel.def.brakeBias or 0.5
		local brakeMagnitude = config.BrakeForce * self._brake * brakeBias
		longitudinalForce -= math.sign(forwardVelocity) * math.min(brakeMagnitude, math.abs(forwardVelocity) * massPerWheel / dt)
	end

	if self._handbrake and (wheel.def.handbrake ~= false) then
		local handbrakeMagnitude = config.HandbrakeForce
		longitudinalForce -= math.sign(forwardVelocity) * math.min(handbrakeMagnitude, math.abs(forwardVelocity) * massPerWheel / dt)
		-- frein à main : on relâche l'adhérence latérale pour permettre le drift
		lateralForce *= 0.35
	end

	-- ---- 5. Ellipse de friction ----
	-- Un pneu n'a qu'une réserve d'adhérence, et elle n'est pas la même dans
	-- les deux axes. On normalise chaque composante par sa limite propre :
	-- si le total dépasse 1, on réduit les deux proportionnellement.
	-- C'est ce qui fait décrocher la voiture quand on accélère en plein virage.
	if maxLongitudinal > 0 and maxLateral > 0 then
		local longitudinalUsage = longitudinalForce / maxLongitudinal
		local lateralUsage = lateralForce / maxLateral
		local usage = math.sqrt(longitudinalUsage * longitudinalUsage + lateralUsage * lateralUsage)
		if usage > 1 then
			longitudinalForce /= usage
			lateralForce /= usage
		end
		wheel.slipRatio = math.min(usage, 4)
	else
		longitudinalForce = 0
		lateralForce = 0
		wheel.slipRatio = 0
	end

	local tireForce = forward * longitudinalForce + right * lateralForce
	chassis:ApplyImpulseAtPosition(tireForce * dt, result.Position)

	-- Visuel : on place la roue au bout de la suspension
	local model = wheel.instance
	if model then
		local wheelPosition = anchorPoint - up * (currentLength)
		model.CFrame = CFrame.lookAt(wheelPosition, wheelPosition + forward, result.Normal)
			* CFrame.Angles(-wheel.spinAngle, 0, 0)
	end
end

--============================================================
-- BARRES ANTI-ROULIS
--============================================================

function VehicleController:_applyAntiRoll(dt: number)
	local chassis = self.chassis
	local up = chassis.CFrame.UpVector

	for _, pair in self._antiRollPairs do
		local left = self._wheels[pair[1]]
		local right = self._wheels[pair[2]]
		if not left or not right then
			continue
		end
		if not left.grounded and not right.grounded then
			continue
		end

		-- La barre transfère de la charge du côté comprimé vers l'autre :
		-- moins de roulis en virage, sans rigidifier la suspension en ligne droite.
		local difference = left.compression - right.compression
		local force = difference * self.config.AntiRollStiffness

		if left.grounded then
			chassis:ApplyImpulseAtPosition(-up * force * dt, left.contactPoint)
		end
		if right.grounded then
			chassis:ApplyImpulseAtPosition(up * force * dt, right.contactPoint)
		end
	end
end

--============================================================
-- AÉRODYNAMIQUE
--============================================================

function VehicleController:_applyAero(dt: number)
	local chassis = self.chassis
	local config = self.config
	local velocity = chassis.AssemblyLinearVelocity
	local speed = velocity.Magnitude
	if speed < 1e-3 then
		return
	end

	local mass = chassis.AssemblyMass

	-- Appui aérodynamique : colle la voiture au sol à haute vitesse
	local downforce = -chassis.CFrame.UpVector * (config.DownforceCoefficient * speed * speed * mass * 1e-3)

	-- Traînée : impose une vitesse de pointe cohérente
	local drag = -velocity.Unit * (config.AeroDragCoefficient * speed * speed * mass * 1e-4)

	chassis:ApplyImpulse((downforce + drag) * dt)

	-- Aide au redressement en l'air : évite les tonneaux incontrôlables
	if config.RolloverAssist > 0 and self:groundedWheelCount() == 0 then
		local tilt = chassis.CFrame.UpVector:Cross(Vector3.yAxis)
		chassis:ApplyAngularImpulse(tilt * (config.RolloverAssist * mass * dt * 10))
	end
end

--============================================================
-- BOUCLE
--============================================================

function VehicleController:step(dt: number)
	if not self._alive or not self.chassis.Parent then
		return
	end
	dt = math.min(dt, Config.General.MaxDeltaTime)
	if dt <= 0 then
		return
	end

	local wheelCount = #self._wheels
	if wheelCount == 0 then
		return
	end

	self:_updateSteering(dt)

	local massPerWheel = self.chassis.AssemblyMass / wheelCount
	for _, wheel in self._wheels do
		self:_stepWheel(wheel, dt, massPerWheel)
	end

	self:_applyAntiRoll(dt)
	self:_applyAero(dt)
end

function VehicleController:destroy()
	self._alive = false
	table.clear(self._wheels)
end

return VehicleController
