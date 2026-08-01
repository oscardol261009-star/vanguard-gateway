--!nonstrict
--[[
	GravityField.luau
	Gravité arbitraire : planètes sphériques, murs "walkable", zones
	anti-gravité, trous noirs.

	Fonctionnement : Roblox applique toujours sa gravité verticale. On la
	*compense* avec une force opposée, puis on ajoute la gravité voulue.
	Résultat : `workspace.Gravity` peut rester à sa valeur par défaut et
	seuls les objets enregistrés changent de comportement.
]]

local Config = require(script.Parent.Parent.Config)
local VectorUtil = require(script.Parent.Parent.Util.VectorUtil)

local GravityField = {}

export type FieldKind = "Directional" | "Point" | "Sphere" | "Box" | "Custom"

export type Field = {
	id: string,
	kind: FieldKind,
	priority: number,
	strength: number,
	direction: Vector3?,
	origin: Vector3?,
	radius: number?,
	falloff: string,
	part: BasePart?,
	compute: ((position: Vector3) -> Vector3?)?,
	blend: number,
	enabled: boolean,
}

local fields: { Field } = {}
local nextId = 0

--============================================================
-- ENREGISTREMENT
--============================================================

--[[
	Ajoute un champ. Renvoie son identifiant, à passer à `remove`.

	Exemples :
		-- planète
		GravityField.add({ kind = "Point", origin = planet.Position,
		                   radius = 400, strength = 196.2 })
		-- couloir où l'on marche au plafond
		GravityField.add({ kind = "Box", part = zone,
		                   direction = Vector3.yAxis, strength = 120 })
]]
function GravityField.add(definition): string
	nextId += 1
	local id = definition.id or `field_{nextId}`

	local field: Field = {
		id = id,
		kind = definition.kind,
		priority = definition.priority or 0,
		strength = definition.strength or Config.Environment.DefaultGravity,
		direction = definition.direction,
		origin = definition.origin,
		radius = definition.radius,
		falloff = definition.falloff or "None",
		part = definition.part,
		compute = definition.compute,
		blend = definition.blend or 1,
		enabled = true,
	}

	table.insert(fields, field)
	table.sort(fields, function(a, b)
		return a.priority > b.priority
	end)
	return id
end

function GravityField.remove(id: string)
	for index = #fields, 1, -1 do
		if fields[index].id == id then
			table.remove(fields, index)
		end
	end
end

function GravityField.get(id: string): Field?
	for _, field in fields do
		if field.id == id then
			return field
		end
	end
	return nil
end

function GravityField.clear()
	table.clear(fields)
end

--============================================================
-- ÉVALUATION
--============================================================

local function falloffFactor(kind: string, distance: number, radius: number): number
	if kind == "Linear" then
		return math.clamp(1 - distance / math.max(radius, 1e-3), 0, 1)
	elseif kind == "InverseSquare" then
		-- normalisé pour valoir 1 à 10 % du rayon, évite la singularité en 0
		local reference = math.max(radius * 0.1, 1e-3)
		return math.clamp((reference * reference) / math.max(distance * distance, 1e-6), 0, 1)
	end
	return 1
end

local function contains(field: Field, position: Vector3): boolean
	if field.kind == "Directional" or field.kind == "Custom" then
		return true
	elseif field.kind == "Point" or field.kind == "Sphere" then
		local origin = field.origin or (field.part and field.part.Position) or Vector3.zero
		local radius = field.radius or math.huge
		return (position - origin).Magnitude <= radius
	elseif field.kind == "Box" then
		local part = field.part
		if not part then
			return false
		end
		local localPoint = part.CFrame:PointToObjectSpace(position)
		local half = part.Size * 0.5
		return math.abs(localPoint.X) <= half.X
			and math.abs(localPoint.Y) <= half.Y
			and math.abs(localPoint.Z) <= half.Z
	end
	return false
end

local function evaluate(field: Field, position: Vector3): Vector3?
	if field.kind == "Custom" and field.compute then
		return field.compute(position)
	end

	if field.kind == "Directional" or field.kind == "Box" then
		local direction = VectorUtil.safeUnit(field.direction or -Vector3.yAxis)
		return direction * field.strength
	end

	if field.kind == "Point" or field.kind == "Sphere" then
		local origin = field.origin or (field.part and field.part.Position) or Vector3.zero
		local delta = origin - position
		local distance = delta.Magnitude
		if distance < 1e-4 then
			return Vector3.zero
		end
		local factor = falloffFactor(field.falloff, distance, field.radius or distance)
		return (delta / distance) * (field.strength * factor)
	end

	return nil
end

--[[
	Accélération gravitationnelle (studs/s²) au point donné.
	Le champ actif de plus haute priorité gagne ; `blend` permet de le
	mélanger avec la gravité par défaut pour des transitions douces.
]]
function GravityField.sample(position: Vector3): Vector3
	local default = Vector3.new(0, -workspace.Gravity, 0)

	for _, field in fields do
		if not field.enabled then
			continue
		end
		if not contains(field, position) then
			continue
		end
		local acceleration = evaluate(field, position)
		if acceleration then
			if field.blend >= 1 then
				return acceleration
			end
			return default:Lerp(acceleration, math.clamp(field.blend, 0, 1))
		end
	end

	return default
end

--[[ Vecteur "haut" local : opposé de la gravité. Sert au contrôleur. ]]
function GravityField.upVector(position: Vector3): Vector3
	local gravity = GravityField.sample(position)
	if gravity.Magnitude < 1e-4 then
		return Vector3.yAxis
	end
	return -gravity.Unit
end

--[[ Vrai si un champ personnalisé est actif ici (sinon : gravité standard). ]]
function GravityField.isCustomAt(position: Vector3): boolean
	for _, field in fields do
		if field.enabled and contains(field, position) then
			return true
		end
	end
	return false
end

--============================================================
-- APPLICATION AUX ASSEMBLAGES
--============================================================

local Binding = {}
Binding.__index = Binding

export type Binding = typeof(setmetatable(
	{} :: {
		part: BasePart,
		force: VectorForce,
		attachment: Attachment,
		alignOrientation: AlignOrientation?,
		_ownsAttachment: boolean,
		_alive: boolean,
	},
	Binding
))

--[[
	Lie un assemblage aux champs de gravité.
	`alignToSurface` fait pivoter l'objet pour que son "haut" suive la gravité
	(pratique pour un joueur ou une caisse sur une planète).
]]
function GravityField.bind(part: BasePart, alignToSurface: boolean?): Binding
	local attachment = part:FindFirstChild("GravityFieldAttachment") :: Attachment?
	local ownsAttachment = false
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name = "GravityFieldAttachment"
		attachment.Parent = part
		ownsAttachment = true
	end

	local force = Instance.new("VectorForce")
	force.Name = "GravityFieldForce"
	force.Attachment0 = attachment
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.ApplyAtCenterOfMass = true
	force.Force = Vector3.zero
	force.Parent = part

	local align: AlignOrientation? = nil
	if alignToSurface then
		align = Instance.new("AlignOrientation")
		align.Name = "GravityFieldAlign"
		align.Mode = Enum.OrientationAlignmentMode.OneAttachment
		align.Attachment0 = attachment
		align.RigidityEnabled = false
		align.MaxTorque = 1e6
		align.Responsiveness = 25
		align.Parent = part
	end

	return setmetatable({
		part = part,
		force = force,
		attachment = attachment,
		alignOrientation = align,
		_ownsAttachment = ownsAttachment,
		_alive = true,
	}, Binding)
end

function Binding.step(self: Binding, _dt: number)
	if not self._alive or not self.part.Parent then
		return
	end

	local position = self.part.Position
	local target = GravityField.sample(position)
	local default = Vector3.new(0, -workspace.Gravity, 0)

	-- on annule la gravité moteur et on injecte la nôtre
	local delta = target - default
	self.force.Force = delta * self.part.AssemblyMass

	local align = self.alignOrientation
	if align then
		local up = target.Magnitude > 1e-4 and -target.Unit or Vector3.yAxis
		local look = VectorUtil.projectOnPlane(self.part.CFrame.LookVector, up)
		if look.Magnitude < 1e-3 then
			look = VectorUtil.projectOnPlane(self.part.CFrame.RightVector, up)
		end
		if look.Magnitude > 1e-3 then
			align.CFrame = CFrame.lookAt(Vector3.zero, look.Unit, up)
		end
	end
end

function Binding.destroy(self: Binding)
	self._alive = false
	self.force:Destroy()
	if self.alignOrientation then
		self.alignOrientation:Destroy()
	end
	if self._ownsAttachment then
		self.attachment:Destroy()
	end
end

return GravityField
