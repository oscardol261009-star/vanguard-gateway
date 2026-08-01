--!nonstrict
--[[
	PhysicsClient.client.luau
	À placer dans StarterPlayer > StarterPlayerScripts.

	Branche le contrôleur avancé sur le personnage local et convertit les
	entrées (clavier, manette) en direction relative à la caméra.

	Le personnage local appartient au client au sens de la propriété réseau :
	le simuler ici est donc à la fois correct et sans latence. Le serveur
	reste libre de valider les positions de son côté.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local AdvancedPhysics = require(ReplicatedStorage:WaitForChild("AdvancedPhysics"))
local VectorUtil = AdvancedPhysics.VectorUtil

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local controller = nil
local handle = nil
local gamepadMove = Vector3.zero

--============================================================
-- ENTRÉES
--============================================================

local KEY_VECTORS = {
	[Enum.KeyCode.W] = Vector3.new(0, 0, -1),
	[Enum.KeyCode.S] = Vector3.new(0, 0, 1),
	[Enum.KeyCode.A] = Vector3.new(-1, 0, 0),
	[Enum.KeyCode.D] = Vector3.new(1, 0, 0),
}

local function readInputVector(): Vector3
	local vector = gamepadMove

	if UserInputService.KeyboardEnabled then
		local keyboard = Vector3.zero
		for keyCode, contribution in KEY_VECTORS do
			if UserInputService:IsKeyDown(keyCode) then
				keyboard += contribution
			end
		end
		if keyboard.Magnitude > 0 then
			vector = keyboard
		end
	end

	return VectorUtil.clampMagnitude(vector, 1)
end

--[[ Convertit une entrée locale en direction monde, relative à la caméra. ]]
local function toWorldDirection(input: Vector3, up: Vector3): Vector3
	if input.Magnitude < 1e-3 then
		return Vector3.zero
	end

	local cameraCF = camera.CFrame
	local forward = VectorUtil.projectOnPlane(cameraCF.LookVector, up)
	local right = VectorUtil.projectOnPlane(cameraCF.RightVector, up)

	-- caméra regardant droit vers le haut/bas : on rattrape avec son axe UP
	if forward.Magnitude < 1e-3 then
		forward = VectorUtil.projectOnPlane(cameraCF.UpVector, up)
	end

	forward = VectorUtil.safeUnit(forward)
	right = VectorUtil.safeUnit(right)

	return VectorUtil.safeUnit(forward * -input.Z + right * input.X) * math.min(input.Magnitude, 1)
end

--============================================================
-- ACTIONS
--============================================================

local function handleJump(_actionName: string, state: Enum.UserInputState)
	if not controller then
		return Enum.ContextActionResult.Pass
	end
	if state == Enum.UserInputState.Begin then
		controller:requestJump()
	elseif state == Enum.UserInputState.End then
		controller:cutJump()
	end
	return Enum.ContextActionResult.Sink
end

local function handleSprint(_actionName: string, state: Enum.UserInputState)
	if controller then
		controller:setSprinting(state == Enum.UserInputState.Begin)
	end
	return Enum.ContextActionResult.Pass
end

local function handleCrouch(_actionName: string, state: Enum.UserInputState)
	if controller then
		controller:setCrouching(state == Enum.UserInputState.Begin)
	end
	return Enum.ContextActionResult.Pass
end

local function bindActions()
	ContextActionService:BindAction("PhysicsJump", handleJump, true, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)
	ContextActionService:BindAction(
		"PhysicsSprint",
		handleSprint,
		true,
		Enum.KeyCode.LeftShift,
		Enum.KeyCode.ButtonL3
	)
	ContextActionService:BindAction(
		"PhysicsCrouch",
		handleCrouch,
		true,
		Enum.KeyCode.LeftControl,
		Enum.KeyCode.C,
		Enum.KeyCode.ButtonB
	)
end

local function unbindActions()
	ContextActionService:UnbindAction("PhysicsJump")
	ContextActionService:UnbindAction("PhysicsSprint")
	ContextActionService:UnbindAction("PhysicsCrouch")
end

UserInputService.InputChanged:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.Thumbstick1 then
		local position = input.Position
		-- zone morte : sans elle, la manette dérive en permanence
		if math.abs(position.X) < 0.15 and math.abs(position.Y) < 0.15 then
			gamepadMove = Vector3.zero
		else
			gamepadMove = Vector3.new(position.X, 0, -position.Y)
		end
	end
end)

--============================================================
-- CYCLE DE VIE DU PERSONNAGE
--============================================================

local function teardown()
	if handle then
		handle.disconnect()
		handle = nil
	end
	if controller then
		controller:destroy()
		controller = nil
	end
	unbindActions()
end

local function setup(character: Model)
	teardown()

	character:WaitForChild("HumanoidRootPart", 10)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?

	controller = AdvancedPhysics.CharacterController.new(character)
	handle = AdvancedPhysics.register(controller)
	bindActions()

	-- Exemple : piloter les animations depuis l'état de locomotion
	controller:on("StateChanged", function(newState: string)
		if RunService:IsStudio() then
			print(`[Physics] état : {newState}`)
		end
	end)

	controller:on("Landed", function(velocity: Vector3)
		local impactSpeed = -velocity.Y
		if impactSpeed > 90 and humanoid then
			-- dégâts de chute proportionnels à l'excédent de vitesse
			humanoid:TakeDamage(math.min((impactSpeed - 90) * 0.5, 100))
		end
	end)

	if humanoid then
		humanoid.Died:Connect(teardown)
	end
end

if player.Character then
	setup(player.Character)
end
player.CharacterAdded:Connect(setup)
player.CharacterRemoving:Connect(teardown)

--============================================================
-- BOUCLE D'ENTRÉES
--============================================================

-- On lit les entrées dans PreRender (juste après la caméra) puis on les
-- pousse au contrôleur, qui les consommera dans PreSimulation.
RunService.PreRender:Connect(function()
	if not controller then
		return
	end

	local snapshot = controller:snapshot()
	local input = readInputVector()

	controller:setMoveInput(toWorldDirection(input, snapshot.upVector))
	controller:setLookDirection(camera.CFrame.LookVector)
end)
