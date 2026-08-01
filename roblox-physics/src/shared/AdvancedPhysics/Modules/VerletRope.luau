--!nonstrict
--[[
	VerletRope.luau
	Cordes, chaînes, câbles et grappins simulés en Verlet.

	L'intégration de Verlet ne stocke pas la vitesse : elle la déduit de
	`position - previousPosition`. Conséquence pratique : on peut déplacer
	brutalement une particule (contrainte, collision, ancrage) sans jamais
	injecter d'énergie parasite. C'est ce qui rend les cordes Verlet aussi
	stables comparées à un système masses-ressorts classique.

	Chaque pas :
	  1. intégration      : x' = 2x - x_prev + a·dt²
	  2. contraintes      : N passes de correction de distance
	  3. collisions       : projection hors des surfaces
	  4. retour de force  : tension transmise aux objets attachés

	USAGE
		local rope = VerletRope.new({
			origin = anchor.Position,
			endPosition = hook.Position,
			segments = 20,
			attachEnd = characterRoot,   -- la corde tire le personnage
		})
		AdvancedPhysics.register(rope)
		rope:render(function(index, a, b) ... end)
]]

local Config = require(script.Parent.Parent.Config)
local GravityField = require(script.Parent.GravityField)
local RaycastUtil = require(script.Parent.Parent.Util.RaycastUtil)
local VectorUtil = require(script.Parent.Parent.Util.VectorUtil)

local VerletRope = {}
VerletRope.__index = VerletRope

--============================================================
-- CONSTRUCTION
--============================================================

function VerletRope.new(options)
	local config = Config.merge(Config.Rope, options.overrides)
	local self = setmetatable({}, VerletRope)

	self.config = config
	self._alive = true

	local segments = options.segments or config.Segments
	local origin = options.origin
	local endPosition = options.endPosition or (origin - Vector3.yAxis * 10)

	self.totalLength = options.length or (endPosition - origin).Magnitude
	self.segmentLength = self.totalLength / segments

	-- Particules : position, position précédente, masse inverse (0 = ancré)
	self.points = table.create(segments + 1)
	for index = 0, segments do
		local alpha = index / segments
		local position = origin:Lerp(endPosition, alpha)
		self.points[index + 1] = {
			position = position,
			previous = position,
			inverseMass = 1,
			anchored = false,
		}
	end

	-- Extrémité 0 ancrée par défaut (point d'accroche)
	self:setAnchor(1, origin)

	self.attachStart = options.attachStart -- BasePart tirée par le début
	self.attachEnd = options.attachEnd -- BasePart tirée par la fin
	self.collide = options.collide ~= false
	self.windInfluence = options.windInfluence or 0

	local ignoreList: { Instance } = options.ignore or {}
	if self.attachStart then
		table.insert(ignoreList, self.attachStart)
	end
	if self.attachEnd then
		table.insert(ignoreList, self.attachEnd)
	end
	self._rayParams = RaycastUtil.params(ignoreList)

	self._renderCallback = nil

	return self
end

--============================================================
-- ANCRAGES
--============================================================

--[[ Fixe une particule à une position (inverseMass = 0). ]]
function VerletRope:setAnchor(index: number, position: Vector3?)
	local point = self.points[index]
	if not point then
		return
	end
	if position then
		point.position = position
		point.previous = position
		point.inverseMass = 0
		point.anchored = true
	else
		point.inverseMass = 1
		point.anchored = false
	end
end

function VerletRope:releaseAnchor(index: number)
	self:setAnchor(index, nil)
end

function VerletRope:getPoints(): { Vector3 }
	local result = table.create(#self.points)
	for index, point in self.points do
		result[index] = point.position
	end
	return result
end

function VerletRope:firstPoint(): Vector3
	return self.points[1].position
end

function VerletRope:lastPoint(): Vector3
	return self.points[#self.points].position
end

--[[ Longueur réelle actuelle (utile pour détecter la tension). ]]
function VerletRope:currentLength(): number
	local total = 0
	for index = 1, #self.points - 1 do
		total += (self.points[index + 1].position - self.points[index].position).Magnitude
	end
	return total
end

--[[ Change la longueur au repos : sert à enrouler/dérouler un grappin. ]]
function VerletRope:setLength(length: number)
	self.totalLength = math.max(length, 0.1)
	self.segmentLength = self.totalLength / math.max(#self.points - 1, 1)
end

--============================================================
-- SIMULATION
--============================================================

function VerletRope:_integrate(dt: number)
	local damping = self.config.Damping
	local wind = Config.Environment.Wind * self.windInfluence
	local dtSquared = dt * dt

	for _, point in self.points do
		if point.inverseMass == 0 then
			continue
		end

		local acceleration = GravityField.sample(point.position) + wind
		local velocity = (point.position - point.previous) * damping

		point.previous = point.position
		point.position = point.position + velocity + acceleration * dtSquared
	end
end

function VerletRope:_solveConstraints()
	local iterations = self.config.ConstraintIterations
	local stiffness = self.config.Stiffness
	local restLength = self.segmentLength
	local pointCount = #self.points

	for _ = 1, iterations do
		for index = 1, pointCount - 1 do
			local a = self.points[index]
			local b = self.points[index + 1]

			local delta = b.position - a.position
			local distance = delta.Magnitude
			if distance < 1e-6 then
				continue
			end

			local difference = (distance - restLength) / distance
			local totalInverseMass = a.inverseMass + b.inverseMass
			if totalInverseMass <= 0 then
				continue
			end

			local correction = delta * (difference * stiffness / totalInverseMass)
			a.position += correction * a.inverseMass
			b.position -= correction * b.inverseMass
		end
	end
end

function VerletRope:_solveCollisions()
	if not self.collide then
		return
	end
	local radius = self.config.CollisionRadius
	local friction = self.config.CollisionFriction
	local bounce = self.config.CollisionBounce

	for _, point in self.points do
		if point.inverseMass == 0 then
			continue
		end

		local motion = point.position - point.previous
		local distance = motion.Magnitude
		if distance < 1e-5 then
			continue
		end

		local result = workspace:Raycast(point.previous, motion + VectorUtil.safeUnit(motion) * radius, self._rayParams)
		if not result then
			continue
		end

		local normal = result.Normal
		point.position = result.Position + normal * radius

		-- On décompose le mouvement : la partie normale rebondit, la partie
		-- tangentielle est freinée. On l'écrit dans `previous`, ce qui revient
		-- à imposer la nouvelle vitesse en Verlet.
		local normalPart = normal * motion:Dot(normal)
		local tangentPart = motion - normalPart
		local newVelocity = tangentPart * (1 - friction) - normalPart * bounce
		point.previous = point.position - newVelocity
	end
end

--[[
	Transmet la tension de la corde aux objets attachés.
	Sans ça, la corde suit l'objet mais ne le retient jamais : c'est cette
	fonction qui rend un grappin jouable.
]]
function VerletRope:_applyTension(dt: number)
	local maxLength = self.totalLength * self.config.MaxStretch

	local function pull(part: BasePart?, pointIndex: number, anchorIndex: number)
		if not part or not part.Parent then
			return
		end

		local point = self.points[pointIndex]
		local anchor = self.points[anchorIndex]

		-- la corde suit la pièce
		point.position = part.Position
		point.previous = part.Position

		local delta = anchor.position - part.Position
		local distance = delta.Magnitude
		if distance <= maxLength then
			return
		end

		local direction = delta / distance
		local overshoot = distance - maxLength
		local mass = part.AssemblyMass

		-- rappel élastique + amortissement de la vitesse d'éloignement
		local radialSpeed = -part.AssemblyLinearVelocity:Dot(direction)
		local magnitude = overshoot * self.config.TensionForce - radialSpeed * self.config.TensionForce * 0.08
		part:ApplyImpulse(direction * (math.max(magnitude, 0) * mass * dt))
	end

	pull(self.attachStart, 1, #self.points)
	pull(self.attachEnd, #self.points, 1)
end

function VerletRope:step(dt: number)
	if not self._alive then
		return
	end
	dt = math.min(dt, Config.General.MaxDeltaTime)
	if dt <= 0 then
		return
	end

	self:_integrate(dt)
	self:_solveConstraints()
	self:_solveCollisions()
	self:_solveConstraints() -- seconde passe : les collisions ont pu étirer la corde
	self:_applyTension(dt)

	if self._renderCallback then
		self._renderCallback(self)
	end
end

--============================================================
-- RENDU
--============================================================

--[[
	Enregistre un callback de rendu appelé après chaque pas.
	Le module ne crée aucun visuel lui-même : libre à toi d'utiliser des
	Beams, des Parts, un RopeConstraint ou rien du tout côté serveur.
]]
function VerletRope:render(callback: ((rope: any) -> ())?)
	self._renderCallback = callback
end

--[[
	Aide au rendu : crée des cylindres reliant les particules et retourne
	la fonction de mise à jour à passer à :render().
]]
function VerletRope:createPartRenderer(parent: Instance, thickness: number?, template: BasePart?): (rope: any) -> ()
	local radius = thickness or 0.2
	local folder = Instance.new("Folder")
	folder.Name = "RopeSegments"
	folder.Parent = parent

	local segments = {}
	for index = 1, #self.points - 1 do
		local segment: BasePart
		if template then
			segment = template:Clone()
		else
			segment = Instance.new("Part")
			segment.Material = Enum.Material.SmoothPlastic
			segment.Color = Color3.fromRGB(60, 50, 40)
		end
		segment.Name = `Segment{index}`
		segment.Size = Vector3.new(radius, radius, self.segmentLength)
		segment.Anchored = true
		segment.CanCollide = false
		segment.CanQuery = false
		segment.CanTouch = false
		segment.Massless = true
		segment.Parent = folder
		segments[index] = segment
	end

	self._renderFolder = folder

	return function(rope)
		for index, segment in segments do
			local a = rope.points[index].position
			local b = rope.points[index + 1].position
			local delta = b - a
			local length = delta.Magnitude
			if length < 1e-4 then
				segment.Transparency = 1
				continue
			end
			segment.Transparency = 0
			segment.Size = Vector3.new(radius, radius, length)
			segment.CFrame = CFrame.lookAt(a + delta * 0.5, b)
		end
	end
end

function VerletRope:destroy()
	self._alive = false
	self._renderCallback = nil
	if self._renderFolder then
		self._renderFolder:Destroy()
		self._renderFolder = nil
	end
	table.clear(self.points)
end

--============================================================
-- GRAPPIN
--============================================================

--[[
	Crée un grappin complet : corde + rétraction + tension sur le personnage.
	`retractSpeed` en studs/s ; mettre 0 pour une corde de longueur fixe.
]]
function VerletRope.createGrapple(root: BasePart, hookPosition: Vector3, options)
	options = options or {}
	local rope = VerletRope.new({
		origin = hookPosition,
		endPosition = root.Position,
		segments = options.segments or 16,
		length = options.length or (hookPosition - root.Position).Magnitude,
		attachEnd = root,
		ignore = { root.Parent },
		overrides = options.overrides,
	})

	rope.retractSpeed = options.retractSpeed or 28
	rope.minLength = options.minLength or 6

	local baseStep = rope.step
	function rope:step(dt: number)
		if self.retractSpeed > 0 then
			self:setLength(math.max(self.totalLength - self.retractSpeed * dt, self.minLength))
		end
		baseStep(self, dt)
	end

	return rope
end

return VerletRope
