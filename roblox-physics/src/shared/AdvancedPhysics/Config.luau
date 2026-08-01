--!strict
--[[
	Config.luau
	Toutes les constantes réglables du framework, au même endroit.

	Unités : Roblox travaille en studs. 1 stud ~= 0.28 m.
	Les formules aéro/hydro utilisent des SI (kg, m, m/s) puis convertissent,
	d'où les facteurs STUDS_PER_METER.
]]

local Config = {}

--============================================================
-- GÉNÉRAL
--============================================================

Config.General = {
	-- dt maximum accepté par l'ordonnanceur : évite qu'un freeze de 2 s
	-- ne téléporte tout le monde à travers la map.
	MaxDeltaTime = 1 / 15,
	-- pas de simulation interne pour les projectiles / cordes
	FixedSubStep = 1 / 120,
	MaxSubSteps = 8,
}

--============================================================
-- ENVIRONNEMENT
--============================================================

Config.Environment = {
	StudsPerMeter = 3.5714286, -- 1 stud = 0.28 m
	AirDensity = 1.225, -- kg/m³ au niveau de la mer
	WaterDensity = 1000, -- kg/m³
	DefaultGravity = 196.2, -- studs/s² (valeur Roblox par défaut)
	Wind = Vector3.zero, -- vent global, studs/s
}

--============================================================
-- PERSONNAGE
-- Contrôleur "capsule flottante" : le personnage lévite au-dessus du sol
-- grâce à un ressort, ce qui donne gratuitement les marches, les pentes
-- et un contact parfaitement stable.
--============================================================

Config.Character = {
	-- Suspension
	RideHeight = 3.0, -- distance souhaitée entre le centre du root et le sol
	RideSpringStrength = 220, -- raideur (par unité de masse)
	RideSpringDamper = 26, -- amortissement (par unité de masse)
	ProbeExtra = 1.5, -- longueur de raycast au-delà de RideHeight
	ProbeRadius = 1.2, -- rayon du spherecast de détection du sol
	MaxStepHeight = 2.5, -- hauteur de marche franchissable
	MaxSlopeAngle = 55, -- au-delà : on glisse
	SlideAcceleration = 90, -- accélération subie sur une pente trop raide

	-- Déplacement
	WalkSpeed = 16,
	RunSpeed = 26,
	CrouchSpeed = 8,
	GroundAcceleration = 160, -- studs/s²
	GroundDeceleration = 220,
	AirAcceleration = 45,
	AirDrag = 0.35, -- traînée horizontale en l'air (1/s)
	MaxGroundForce = 12000, -- garde-fou anti-explosion
	TurnResponsiveness = 28, -- vitesse d'alignement de l'orientation

	-- Saut
	JumpHeight = 9.5, -- hauteur cible, convertie en vitesse via la gravité
	MaxJumps = 2, -- 1 = simple, 2 = double saut
	CoyoteTime = 0.12, -- on peut encore sauter après avoir quitté le sol
	JumpBuffer = 0.15, -- un saut demandé un peu trop tôt est mémorisé
	JumpSuppressTime = 0.18, -- suspension désactivée après un saut
	VariableJumpCut = 0.45, -- vitesse conservée si on relâche le saut
	FallGravityScale = 1.35, -- chute plus lourde = meilleur game feel
	LowJumpGravityScale = 1.8, -- saut relâché tôt = retombée rapide

	-- Murs
	WallCheckDistance = 2.2,
	WallRunEnabled = true,
	WallRunMinSpeed = 14,
	WallRunGravityScale = 0.25,
	WallRunMaxTime = 2.0,
	WallRunStickForce = 30,
	WallJumpVerticalSpeed = 42,
	WallJumpHorizontalSpeed = 40,

	-- Glissade
	SlideEnabled = true,
	SlideMinSpeed = 20,
	SlideFriction = 0.6, -- 1/s
	SlideSlopeBoost = 55,
	SlideMaxTime = 1.6,

	-- Divers
	InheritPlatformVelocity = true,
	PushOtherParts = true, -- réaction sur le sol (Newton 3)
	MaxPushForce = 4000,
}

--============================================================
-- PROJECTILES
--============================================================

Config.Projectile = {
	Mass = 0.0095, -- ~9.5 g (calibre 9 mm)
	DragCoefficient = 0.3,
	CrossSection = 6.4e-5, -- m²
	GravityScale = 1,
	MagnusCoefficient = 0.00035,
	Lifetime = 6,
	MaxDistance = 4000,
	MinSpeed = 20,
	Penetrations = 0,
	PenetrationPower = 0,
	Ricochets = 0,
	RicochetMaxAngle = 25, -- rebond seulement en incidence rasante
	Restitution = 0.5,
	TangentFriction = 0.25,
}

--============================================================
-- VÉHICULE
--============================================================

Config.Vehicle = {
	SuspensionRestLength = 2.2,
	SuspensionStiffness = 55000, -- N/stud (par roue, avant répartition)
	SuspensionDamping = 4200,
	SuspensionMaxCompression = 0.92,
	MaxSteerAngle = 32, -- degrés
	SteerSpeed = 4.5, -- rad/s de rotation du volant
	SteerSpeedFalloff = 0.55, -- réduction du braquage à haute vitesse
	EnginePower = 34000,
	MaxSpeed = 220, -- studs/s
	BrakeForce = 42000,
	HandbrakeForce = 26000,
	TireGripForward = 2.2,
	TireGripLateral = 3.4,
	TireLoadSensitivity = 0.85, -- < 1 : le grip augmente moins vite que la charge
	AntiRollStiffness = 9000,
	DownforceCoefficient = 0.55,
	AeroDragCoefficient = 0.9,
	RolloverAssist = 0.15,
}

--============================================================
-- CORDES / VERLET
--============================================================

Config.Rope = {
	Segments = 24,
	ConstraintIterations = 8,
	Damping = 0.995, -- amortissement Verlet (1 = aucun)
	Stiffness = 1.0, -- 0..1
	CollisionRadius = 0.15,
	CollisionFriction = 0.55,
	CollisionBounce = 0.1,
	MaxStretch = 1.04, -- limite d'élongation avant tension
	TensionForce = 900, -- force de rappel appliquée aux extrémités attachées
}

--============================================================
-- EXPLOSIONS / FORCES
--============================================================

Config.Force = {
	ExplosionRadius = 40,
	ExplosionImpulse = 180, -- par unité de masse à distance nulle
	ExplosionFalloff = "InverseSquare",
	ExplosionUpBias = 0.35,
	ExplosionLineOfSight = true,
	AttractorFalloff = "InverseSquare",
}

--[[
	Fusionne des surcharges dans une copie d'une table de config.
	N'écrase que les clés déjà connues : une faute de frappe lève une erreur
	plutôt que de rester silencieuse.
]]
function Config.merge<T>(base: T, overrides: { [string]: any }?): T
	local result = table.clone(base :: any)
	if overrides then
		for key, value in overrides do
			if result[key] == nil then
				error(`[AdvancedPhysics] clé de configuration inconnue : "{key}"`, 3)
			end
			result[key] = value
		end
	end
	return (result :: any) :: T
end

return Config
