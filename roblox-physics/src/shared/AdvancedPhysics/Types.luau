--!strict
--[[
	Types.luau
	Définitions de types partagées par tous les modules du framework.

	Tout est exporté pour pouvoir écrire :
		local Types = require(AdvancedPhysics.Types)
		local info: Types.GroundInfo = ...
]]

local Types = {}

--============================================================
-- SOL / COLLISIONS
--============================================================

export type GroundInfo = {
	grounded: boolean, -- true si le sol est exploitable (pente <= limite)
	touching: boolean, -- true si quelque chose est sous les pieds (même trop pentu)
	normal: Vector3, -- normale du sol (monde)
	position: Vector3, -- point de contact
	distance: number, -- distance entre l'origine du raycast et le sol
	slopeAngle: number, -- angle en degrés entre la normale et le "up" courant
	instance: BasePart?, -- pièce touchée
	platformVelocity: Vector3, -- vélocité du sol au point de contact (plateformes mobiles)
}

export type WallInfo = {
	touching: boolean,
	normal: Vector3,
	position: Vector3,
	distance: number,
	instance: BasePart?,
}

--============================================================
-- RESSORTS
--============================================================

export type VectorSpring = {
	position: Vector3,
	velocity: Vector3,
	target: Vector3,
	frequency: number,
	damping: number,
	update: (self: VectorSpring, dt: number) -> Vector3,
	impulse: (self: VectorSpring, velocity: Vector3) -> (),
	reset: (self: VectorSpring, value: Vector3) -> (),
}

export type NumberSpring = {
	position: number,
	velocity: number,
	target: number,
	frequency: number,
	damping: number,
	update: (self: NumberSpring, dt: number) -> number,
	impulse: (self: NumberSpring, velocity: number) -> (),
	reset: (self: NumberSpring, value: number) -> (),
}

--============================================================
-- CHAMPS DE GRAVITÉ
--============================================================

export type GravityFieldKind = "Directional" | "Point" | "Sphere" | "Box" | "Custom"

export type GravityFieldDef = {
	id: string?,
	kind: GravityFieldKind,
	priority: number?, -- le plus grand gagne quand plusieurs champs se recouvrent
	strength: number?, -- accélération en studs/s²
	direction: Vector3?, -- pour "Directional"
	origin: Vector3?, -- pour "Point" / "Sphere"
	radius: number?, -- portée (Point / Sphere)
	falloff: ("None" | "Linear" | "InverseSquare")?,
	part: BasePart?, -- pour "Box" : la zone suit cette pièce
	compute: ((position: Vector3) -> Vector3?)?, -- pour "Custom"
	blend: number?, -- 0..1, mélange avec la gravité par défaut
}

--============================================================
-- PROJECTILES
--============================================================

export type ProjectileHit = {
	instance: BasePart,
	position: Vector3,
	normal: Vector3,
	material: Enum.Material,
	distance: number,
	velocity: Vector3, -- vélocité du projectile au moment de l'impact
	speed: number,
	penetrationsLeft: number,
	ricochetsLeft: number,
}

export type ProjectileDef = {
	position: Vector3,
	velocity: Vector3,

	mass: number?, -- kg (défaut 0.01)
	dragCoefficient: number?, -- Cd (défaut 0.3, sphère lisse ~0.47)
	crossSection: number?, -- m² (défaut 5e-5)
	gravityScale: number?, -- multiplicateur de gravité (défaut 1)
	spin: Vector3?, -- rad/s, produit l'effet Magnus
	magnusCoefficient: number?,

	lifetime: number?, -- secondes (défaut 5)
	maxDistance: number?, -- studs
	minSpeed: number?, -- en dessous, le projectile meurt

	penetrations: number?, -- nb de surfaces traversables
	penetrationPower: number?, -- studs d'épaisseur perçables au total
	ricochets: number?, -- nb de rebonds
	ricochetMaxAngle: number?, -- degrés : au-delà, pas de rebond
	restitution: number?, -- élasticité du rebond 0..1
	tangentFriction: number?, -- perte tangentielle au rebond 0..1

	raycastParams: RaycastParams?,
	radius: number?, -- > 0 => spherecast au lieu de raycast

	onUpdate: ((position: Vector3, velocity: Vector3, dt: number) -> ())?,
	onHit: ((hit: ProjectileHit) -> ("Stop" | "Penetrate" | "Ricochet" | "Ignore")?)?,
	onTerminate: ((position: Vector3, reason: string) -> ())?,

	userData: any?,
}

--============================================================
-- VÉHICULES
--============================================================

export type WheelDef = {
	offset: Vector3, -- position de l'ancrage dans l'espace du châssis
	radius: number,
	steer: boolean?, -- roue directrice
	drive: boolean?, -- roue motrice
	brakeBias: number?, -- 0..1, répartition du freinage
	handbrake: boolean?, -- affectée par le frein à main
	model: BasePart?, -- visuel optionnel, positionné automatiquement
}

export type WheelState = {
	def: WheelDef,
	grounded: boolean,
	compression: number, -- 0..1
	suspensionLength: number,
	contactPoint: Vector3,
	contactNormal: Vector3,
	normalForce: number,
	steerAngle: number, -- radians
	spinAngle: number, -- radians, pour l'affichage
	slipRatio: number,
	slipAngle: number,
	instance: BasePart?,
}

--============================================================
-- CONTRÔLEUR DE PERSONNAGE
--============================================================

export type LocomotionState =
	"Idle"
	| "Walking"
	| "Running"
	| "Crouching"
	| "Sliding"
	| "Airborne"
	| "WallRunning"
	| "Swimming"

export type CharacterSnapshot = {
	state: LocomotionState,
	grounded: boolean,
	velocity: Vector3,
	horizontalSpeed: number,
	upVector: Vector3,
	groundNormal: Vector3,
	slopeAngle: number,
	coyoteTimeLeft: number,
	jumpsLeft: number,
}

--============================================================
-- ORDONNANCEUR
--============================================================

export type Steppable = {
	step: (self: any, dt: number) -> (),
	destroy: ((self: any) -> ())?,
}

return Types
