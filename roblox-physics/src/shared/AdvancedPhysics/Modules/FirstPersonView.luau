--!nonstrict
--[[
	FirstPersonView.luau
	Vue première personne « corps visible », façon Mirror's Edge / Dying Light.

	DEUX APPROCHES POSSIBLES, ET POURQUOI CELLE-CI
	  1. Viewmodel : un modèle de bras séparé, collé devant la caméra. C'est le
	     standard des FPS de tir (précision du placement de l'arme), mais il
	     demande un second rig et un second jeu d'animations.
	  2. Corps réel visible (ce module) : on garde le vrai personnage et on
	     masque seulement la tête. Tu vois tes jambes en baissant les yeux, et
	     surtout **tes animations de parkour sont réutilisées telles quelles**.
	     C'est le bon choix pour un jeu de parkour.

	LE PIÈGE TECHNIQUE
	En vue première personne, Roblox force `LocalTransparencyModifier = 1` sur
	toutes les pièces du personnage, à *chaque image*. Le régler une fois ne
	sert donc à rien : il faut le réimposer dans un RenderStep, ce que fait ce
	module. C'est la raison n°1 pour laquelle « mon corps est invisible en
	première personne » revient sans arrêt.

	USAGE
		local view = FirstPersonView.new(player, character, controller)
		-- puis view:destroy() au respawn
]]

local RunService = game:GetService("RunService")

local Config = require(script.Parent.Parent.Config)

local FirstPersonView = {}
FirstPersonView.__index = FirstPersonView

local RENDER_NAME = "AdvancedPhysicsFirstPerson"

--============================================================
-- CONSTRUCTION
--============================================================

function FirstPersonView.new(player: Player, character: Model, controller, overrides: { [string]: any }?)
	local self = setmetatable({}, FirstPersonView)

	self.player = player
	self.character = character
	self.controller = controller
	self.config = Config.merge(Config.FirstPerson, overrides)
	self.camera = workspace.CurrentCamera
	self._alive = true
	self._connections = {}

	self.humanoid = character:FindFirstChildOfClass("Humanoid")

	self._previousCameraMode = player.CameraMode
	if self.config.LockFirstPerson then
		player.CameraMode = Enum.CameraMode.LockFirstPerson
	end

	self:_findNeck()
	self:_bindDescendants()
	self:_bindRender()

	return self
end

--[[
	Le Motor6D "Neck" existe sous ce nom en R6 comme en R15 : on peut donc
	incliner la tête sans se soucier du type de rig.
]]
function FirstPersonView:_findNeck()
	for _, descendant in self.character:GetDescendants() do
		if descendant:IsA("Motor6D") and descendant.Name == "Neck" then
			self._neck = descendant
			self._neckBaseC0 = descendant.C0
			return
		end
	end
end

function FirstPersonView:_bindDescendants()
	-- Un accessoire ajouté après coup (chapeau, cheveux) doit être masqué
	-- lui aussi, sinon il flotte devant l'objectif.
	table.insert(
		self._connections,
		self.character.DescendantAdded:Connect(function(descendant)
			if descendant:IsA("Motor6D") and descendant.Name == "Neck" and not self._neck then
				self._neck = descendant
				self._neckBaseC0 = descendant.C0
			end
		end)
	)
end

--============================================================
-- VISIBILITÉ
--============================================================

--[[
	Vrai si la pièce doit rester invisible depuis la vue subjective :
	la tête (on serait à l'intérieur) et tout ce qui y est accroché.
]]
function FirstPersonView:_shouldHide(instance: Instance): boolean
	if instance.Name == "Head" then
		return true
	end
	if instance:IsA("Decal") and instance.Parent and instance.Parent.Name == "Head" then
		return true
	end
	if instance:FindFirstAncestorOfClass("Accessory") then
		return self.config.HideAccessories
	end
	return false
end

function FirstPersonView:_applyVisibility()
	if not self.config.ShowBody then
		return
	end

	for _, descendant in self.character:GetDescendants() do
		if descendant:IsA("BasePart") or descendant:IsA("Decal") then
			-- LocalTransparencyModifier = 0 rend l'apparence d'origine ;
			-- il ne force pas l'opacité d'une pièce déjà transparente.
			descendant.LocalTransparencyModifier = self:_shouldHide(descendant) and 1 or 0
		end
	end
end

--============================================================
-- INCLINAISON DE LA TÊTE
--============================================================

--[[
	Sans ça, baisser les yeux ne fait rien bouger : on voit son torse figé
	de face. On répercute le tangage de la caméra sur la nuque.
]]
function FirstPersonView:_applyNeckPitch()
	local neck = self._neck
	if not neck or not self.config.TiltHead then
		return
	end
	if not neck.Parent then
		self._neck = nil
		return
	end

	local look = self.camera.CFrame.LookVector
	-- asin de la composante verticale = angle de tangage
	local pitch = math.asin(math.clamp(look.Y, -1, 1))
	pitch = math.clamp(pitch, -math.rad(self.config.MaxHeadPitch), math.rad(self.config.MaxHeadPitch))

	neck.C0 = self._neckBaseC0 * CFrame.Angles(pitch * self.config.HeadPitchScale, 0, 0)
end

--============================================================
-- BOUCLE
--============================================================

function FirstPersonView:_bindRender()
	-- Après la caméra : c'est elle qui remet la transparence à 1, il faut
	-- donc passer derrière elle pour avoir le dernier mot.
	RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 2, function()
		if not self._alive then
			return
		end
		if not self.character.Parent then
			return
		end
		if self.humanoid and self.humanoid.Health <= 0 then
			return
		end

		self:_applyVisibility()
		self:_applyNeckPitch()
	end)
end

--[[ Compatible avec AdvancedPhysics.register() ; le travail est sur RenderStep. ]]
function FirstPersonView:step(_dt: number) end

--[[ Bascule première/troisième personne à chaud (menu d'options, cinématique). ]]
function FirstPersonView:setEnabled(enabled: boolean)
	self.config.LockFirstPerson = enabled
	self.player.CameraMode = enabled and Enum.CameraMode.LockFirstPerson or Enum.CameraMode.Classic

	if not enabled then
		for _, descendant in self.character:GetDescendants() do
			if descendant:IsA("BasePart") or descendant:IsA("Decal") then
				descendant.LocalTransparencyModifier = 0
			end
		end
		if self._neck and self._neck.Parent then
			self._neck.C0 = self._neckBaseC0
		end
	end
end

function FirstPersonView:destroy()
	if not self._alive then
		return
	end
	self._alive = false

	pcall(function()
		RunService:UnbindFromRenderStep(RENDER_NAME)
	end)

	for _, connection in self._connections do
		pcall(function()
			connection:Disconnect()
		end)
	end
	table.clear(self._connections)

	if self._neck and self._neck.Parent then
		self._neck.C0 = self._neckBaseC0
	end

	if self.character.Parent then
		for _, descendant in self.character:GetDescendants() do
			if descendant:IsA("BasePart") or descendant:IsA("Decal") then
				descendant.LocalTransparencyModifier = 0
			end
		end
	end

	if self.player.Parent then
		self.player.CameraMode = self._previousCameraMode
	end
end

return FirstPersonView
