# AdvancedPhysics — Framework de physique avancée pour Roblox (LuauU)

Système de physique complet et modulaire pour Roblox Studio, écrit en Luau.
Chaque module est indépendant : tu peux ne prendre que le contrôleur de
personnage, ou que la balistique, sans traîner le reste.

| Module | Ce qu'il fait |
|---|---|
| `CharacterController` | Contrôleur capsule flottante : marches, pentes, coyote time, double saut, wall run, glissade, plateformes mobiles |
| `AnimationController` | Animations pilotées par l'état du contrôleur, avec fondus et vitesse de lecture asservie |
| `CameraEffects` | FOV dynamique, inclinaison en wall run, encaissement à l'atterrissage |
| `ProjectileSystem` | Balistique par raycast : traînée quadratique, effet Magnus, pénétration des matériaux, ricochets |
| `VehicleController` | Véhicule à suspension raycast : ressorts, ellipse de friction, barres anti-roulis, appui aéro |
| `GravityField` | Gravité arbitraire : planètes sphériques, zones, marcher au plafond |
| `VerletRope` | Cordes et grappins en intégration de Verlet, avec retour de tension |
| `ForceEffects` | Explosions avec ligne de vue, cônes de souffle, attracteurs/tourbillons |
| `Buoyancy` | Flottabilité (Archimède) avec houle et tangage multi-points |
| `Aerodynamics` / `Integrator` / `Spring` | Solveurs réutilisables (RK4, Verlet, ressorts amortis) |

---

## Installation

**→ Guide détaillé pas à pas : [INSTALL.md](INSTALL.md)**

En résumé, deux options :

### Option A — Le fichier `.rbxmx` (aucune installation)

Télécharge `AdvancedPhysics.rbxmx`, puis dans Studio : clic droit sur
`Workspace` → **Insert from File...**. Toute l'arborescence arrive d'un coup ;
il ne reste qu'à déplacer les trois éléments à leur place. Idéal pour tester.

### Option B — Rojo (pour développer dans la durée)

```bash
cd roblox-physics
rojo serve          # puis "Connect" depuis le plugin Rojo dans Studio
```

Édition dans VS Code, synchronisation live avec Studio, historique Git.
L'arborescence est décrite dans `default.project.json` :

```
ReplicatedStorage/AdvancedPhysics        <- src/shared/AdvancedPhysics
ServerScriptService/PhysicsServer        <- src/server/PhysicsServer.server.luau
StarterPlayerScripts/PhysicsClient       <- src/client/PhysicsClient.client.luau
```

---

## Démarrage rapide

```lua
local AdvancedPhysics = require(game.ReplicatedStorage.AdvancedPhysics)

-- 1. Contrôleur de personnage (dans un LocalScript)
local controller = AdvancedPhysics.CharacterController.new(character)
AdvancedPhysics.register(controller)          -- appelle :step(dt) chaque frame

controller:setMoveInput(directionMonde)       -- Vector3, norme <= 1
controller:setLookDirection(camera.CFrame.LookVector)
controller:requestJump()
controller:setSprinting(true)
```

Tout objet exposant `:step(dt)` peut être enregistré :

```lua
local handle = AdvancedPhysics.register(monObjet)
handle.disconnect()                            -- ou AdvancedPhysics.unregister(monObjet)
AdvancedPhysics.destroy(monObjet)              -- désenregistre + appelle :destroy()
```

L'ordonnanceur tourne sur `RunService.PreSimulation`, **avant** le pas physique
du moteur : les forces posées sont prises en compte dans la même image. Avec
`Heartbeat`, tout le contrôleur aurait une image de retard.

---

## Le contrôleur de personnage

### Pourquoi ne pas utiliser le Humanoid ?

Le `Humanoid` est une boîte noire : aucun contrôle sur l'accélération, pas de
coyote time, pas de wall run, un franchissement de marches capricieux. Ici le
Humanoid est mis en état `Physics` (il garde les animations, la santé, le nom
au-dessus de la tête) et c'est nous qui pilotons le `HumanoidRootPart` à la force.

### Le principe : la capsule flottante

Le personnage **ne touche jamais le sol**. Il lévite à `RideHeight` grâce à un
ressort amorti tiré vers le bas. Ce seul mécanisme donne gratuitement :

- **les marches** — le ressort absorbe la différence de hauteur, aucun code dédié
- **les pentes** — la normale du sol oriente le déplacement
- **un contact stable** — pas de vibration, pas d'accrochage sur les arêtes
- **les plateformes mobiles** — on hérite de la vélocité du sol au point de contact

Une sonde multi-rayons (un rayon central + une couronne) moyenne la normale :
sans elle, la normale saute d'une face à l'autre sur les arêtes et le
personnage tremble.

### API

```lua
controller:setMoveInput(worldDirection)   -- direction monde, norme <= 1
controller:setLookDirection(direction)
controller:requestJump()                  -- mémorisé (jump buffer)
controller:releaseJump()
controller:cutJump()                      -- coupe le saut en cours (hauteur variable)
controller:setSprinting(bool)
controller:setCrouching(bool)             -- + vitesse = glissade

controller:isGrounded()
controller:getState()                     -- "Idle" | "Walking" | "Running" | ...
controller:snapshot()                     -- table complète d'état
controller:destroy()                      -- rend la main au Humanoid

controller:on("Landed", function(velocity) end)
controller:on("Jumped", function(kind) end)          -- "Ground" | "Air" | "Wall"
controller:on("StateChanged", function(new, old) end)
controller:on("WallRunStarted", function(normal) end)
controller:on("SlideStarted", function(speed) end)
```

### Le game feel, en trois réglages

| Réglage | Effet |
|---|---|
| `FallGravityScale` (1.35) | La chute est plus lourde que la montée. C'est **le** correctif n°1 d'un saut qui « flotte ». |
| `LowJumpGravityScale` (1.8) | Touche relâchée tôt → retombée rapide. Donne le saut à hauteur variable. |
| `CoyoteTime` + `JumpBuffer` | On peut sauter juste après avoir quitté le bord, et un saut demandé un peu trop tôt est mémorisé. Le joueur ne « rate » plus ses sauts. |

Le saut vise une **hauteur** (`JumpHeight`), pas une vitesse : `v = √(2gh)`.
Changer la gravité ne casse donc pas le réglage. Et la composante verticale est
*remplacée*, pas ajoutée : un saut lancé pendant une chute monte aussi haut
qu'un saut à l'arrêt.

---

## Animations

Le script `Animate` que Roblox insère dans chaque personnage lit
`Humanoid.MoveDirection` et les états du Humanoid. Comme le contrôleur met le
Humanoid en état `Physics`, `Animate` croit le personnage immobile : **plus
aucune animation ne se joue**. `AnimationController` le désactive et rejoue les
pistes lui-même.

```lua
local animator = AdvancedPhysics.AnimationController.new(character, controller)
AdvancedPhysics.register(animator)
```

Les IDs d'animation sont **récupérés dans le script `Animate` du personnage**
plutôt que codés en dur : ça marche pour R6 comme pour R15, et ça respecte le
pack d'animations que le joueur a équipé sur son avatar.

La vitesse de lecture suit la vitesse réelle du personnage — sans ça il
« patine », ses pieds glissent sur le sol.

### Ajouter des animations de parkour

Roblox ne fournit **pas** d'animation de glissade, de wall run ni de réception.
Crée-les dans l'éditeur d'animation (ou prends-en dans la Boîte à outils),
publie-les, puis passe leurs IDs :

```lua
AdvancedPhysics.AnimationController.new(character, controller, {
    slide   = "rbxassetid://TON_ID",
    wallRun = "rbxassetid://TON_ID",
    land    = "rbxassetid://TON_ID",
    crouch  = "rbxassetid://TON_ID",
})
```

Sans ID fourni, chaque état retombe sur une animation existante (la glissade
utilise la chute, le wall run utilise la course) : rien ne casse, c'est juste
moins spectaculaire.

---

## Caméra : le « game feel »

`CameraEffects` ne change aucune mécanique, il rend la vitesse **lisible** —
c'est précisément ce qui sépare un contrôleur correct d'un jeu de parkour qui
donne envie d'y rejouer.

```lua
local effects = AdvancedPhysics.CameraEffects.new(controller, workspace.CurrentCamera)
```

| Effet | Ce qu'il apporte |
|---|---|
| FOV dynamique | Le champ s'ouvre avec la vitesse. Le cerveau lit l'élargissement comme de l'accélération. Inactif à la marche. |
| Inclinaison | La caméra penche vers le mur en wall run — le mur devient lisible — et roule légèrement dans les virages. |
| Encaissement | Plongée à l'atterrissage, proportionnelle à l'impact, saturée pour qu'une chute de 500 studs ne passe pas sous la map. |
| Abaissement | La caméra descend en glissade et en accroupi. |

Tout passe par des ressorts amortis, donc reste fluide quel que soit le
framerate. Le module s'accroche **après** la caméra par défaut
(`RenderPriority.Camera + 1`) et n'applique qu'un décalage relatif : la caméra
Roblox continue de fonctionner normalement.

---

## Balistique

Un projectile rapide avec une vraie `Part` traverse les murs : à 3000 studs/s
et 60 FPS, il parcourt 50 studs entre deux images. On simule donc le projectile
mathématiquement et on relie chaque paire de positions par un raycast — aucune
collision ne peut être manquée.

```lua
AdvancedPhysics.ProjectileSystem.fire({
    position = muzzle.WorldPosition,
    velocity = direction * 900,

    penetrations = 2,        -- surfaces traversables
    penetrationPower = 5,    -- budget total d'épaisseur, en studs
    ricochets = 1,
    spin = Vector3.new(0, 240, 0),   -- effet Magnus : la balle courbe

    onUpdate = function(position, velocity, dt)
        tracer.CFrame = CFrame.new(position)     -- le rendu t'appartient
    end,

    onHit = function(hit)
        -- retourne "Stop" | "Penetrate" | "Ricochet" | "Ignore"
        -- ou nil pour laisser le système décider
        print(hit.instance, hit.speed, hit.incidenceAngle)
        return nil
    end,
})
```

L'intégration est en **RK4** et non en Euler : l'accélération dépend fortement
de la vitesse (traînée quadratique, Magnus), un Euler dériverait visiblement.
Les ricochets ne sont acceptés qu'en incidence rasante (`RicochetMaxAngle`),
comme une vraie balle.

Pour dessiner un arc de grenade sans rien simuler :

```lua
local points, hitResult = AdvancedPhysics.ProjectileSystem.predictPath({
    position = origin, velocity = throwVelocity,
})
```

Et pour viser une cible :

```lua
local Integrator = AdvancedPhysics.Integrator
local v = Integrator.solveLaunchVelocity(origin, target, gravity, 2.5)  -- en 2.5 s
local v = Integrator.solveBallisticArc(origin, target, 200, 196.2)      -- à vitesse imposée
```

---

## Véhicule

Aucune roue physique : quatre rayons partent du châssis, et à chaque contact on
applique trois forces au point de contact — suspension, adhérence latérale,
traction/freinage. C'est le modèle utilisé par la quasi-totalité des jeux de
course : pas de contraintes instables, pas de roue qui se coince, comportement
identique quel que soit le framerate.

```lua
local car = AdvancedPhysics.VehicleController.new(chassis, {
    wheels = {
        { offset = Vector3.new(-3, -1,  5), radius = 1.5, steer = true,  model = wheelFL },
        { offset = Vector3.new( 3, -1,  5), radius = 1.5, steer = true,  model = wheelFR },
        { offset = Vector3.new(-3, -1, -5), radius = 1.5, drive = true,  model = wheelRL },
        { offset = Vector3.new( 3, -1, -5), radius = 1.5, drive = true,  model = wheelRR },
    },
    antiRollPairs = { {1, 2}, {3, 4} },
})
AdvancedPhysics.register(car)

car:setThrottle(1) ; car:setSteer(-0.5) ; car:setBrake(0) ; car:setHandbrake(true)
```

L'**ellipse de friction** limite la réserve d'adhérence du pneu : accélérer à
fond en plein virage fait donc naturellement décrocher l'arrière. Le braquage
se réduit avec la vitesse, sans quoi un coup de volant à 200 studs/s
provoquerait un tête-à-queue immédiat.

---

## Gravité personnalisée

Roblox applique toujours sa gravité verticale. On la **compense** avec une force
opposée puis on ajoute la gravité voulue : `workspace.Gravity` peut donc rester
à sa valeur par défaut, seuls les objets concernés changent de comportement.

```lua
-- Planète : on marche sur toute la surface, y compris à l'envers
AdvancedPhysics.GravityField.add({
    kind = "Point", origin = planet.Position,
    radius = 400, strength = 196.2, priority = 10,
})

-- Couloir où l'on marche au plafond
AdvancedPhysics.GravityField.add({
    kind = "Box", part = zone,
    direction = Vector3.yAxis, strength = 120, priority = 20,
})
```

Le contrôleur de personnage lit son vecteur « haut » depuis les champs de
gravité : **marcher sur une planète ne demande aucun code supplémentaire**,
saut, wall run et glissade suivent automatiquement.

Pour un objet quelconque :

```lua
local binding = AdvancedPhysics.GravityField.bind(part, true)  -- true = s'oriente
AdvancedPhysics.register(binding)
```

---

## Cordes et grappins

L'intégration de Verlet ne stocke pas la vitesse, elle la déduit de
`position - previousPosition`. On peut donc déplacer brutalement une particule
(contrainte, collision, ancrage) sans jamais injecter d'énergie parasite —
d'où la stabilité, très supérieure à un système masses-ressorts.

```lua
local grapple = AdvancedPhysics.VerletRope.createGrapple(root, hitPosition, {
    retractSpeed = 30, minLength = 8,
})
grapple:render(grapple:createPartRenderer(workspace, 0.2))
AdvancedPhysics.register(grapple)
```

La corde ne fait pas que suivre : elle **retient** l'objet attaché quand elle
est tendue (`_applyTension`). C'est ce qui rend un grappin jouable.

---

## Explosions et forces

```lua
AdvancedPhysics.ForceEffects.explode(position, {
    radius = 45, impulse = 260, upBias = 0.4,
    lineOfSight = true,          -- un mur protège vraiment
    angularImpulse = 40,         -- les débris tournoient
    onAffected = function(part, strength, direction)
        local h = part.Parent:FindFirstChildOfClass("Humanoid")
        if h then h:TakeDamage(80 * strength) end
    end,
})

AdvancedPhysics.ForceEffects.cone(origin, direction, { range = 40, halfAngle = 30 })

local vortex = AdvancedPhysics.ForceEffects.createAttractor(orb.Position, {
    radius = 60, strength = 250, swirl = 120,
})
AdvancedPhysics.register(vortex)
```

Contrairement à l'objet `Explosion` de Roblox, l'atténuation, la ligne de vue et
le biais vertical sont contrôlables, et chaque **assemblage** ne reçoit qu'une
seule impulsion (pas une par pièce).

---

## Flottabilité

```lua
local floater = AdvancedPhysics.Buoyancy.createFloater(boat, {
    surfaceY = 0, waveAmplitude = 1.2, waveLength = 60, waveSpeed = 4,
})
AdvancedPhysics.register(floater)
```

La poussée est appliquée en **plusieurs points** répartis sur la pièce : le
bateau tangue et se redresse au lieu de léviter à plat.

---

## Réglage

Tout se trouve dans `Config.luau`, groupé par domaine. Pour surcharger
ponctuellement sans toucher au fichier :

```lua
local controller = AdvancedPhysics.CharacterController.new(character, {
    WalkSpeed = 22,
    JumpHeight = 14,
    MaxJumps = 3,
})
```

`Config.merge` **lève une erreur sur une clé inconnue** : une faute de frappe
se voit immédiatement au lieu d'être ignorée silencieusement.

---

## Notes techniques

- **Propriété réseau.** Le personnage local appartient au client : le simuler
  côté client est correct et sans latence. Les projectiles du script de démo
  sont en revanche simulés **côté serveur** avec validation du point de départ.
- **`--!strict` vs `--!nonstrict`.** Les modules de maths pures sont en
  `--!strict`. Les modules qui manipulent l'arbre d'instances sont en
  `--!nonstrict` : le typage strict y imposerait un cast à chaque
  `FindFirstChild` sans rien apporter.
- **Sécurité numérique.** `dt` est borné (`Config.General.MaxDeltaTime`), les
  forces sont plafonnées et passées par `VectorUtil.sanitize` : un freeze de
  deux secondes ne téléporte personne à travers la map.
- **Ressorts.** Le solveur est semi-implicite, donc *inconditionnellement
  stable* : même à 5 FPS avec une raideur absurde, il ne diverge jamais.

## Tests

Les modules de maths pures (`VectorUtil`, `Spring`, `Integrator`) sont couverts
par 50 assertions vérifiées avec le parseur/VM Luau officiel : concordance de
RK4 avec la solution balistique analytique, stabilité du ressort à `dt = 2 s`,
respect du demi-angle de `randomInCone`, atteinte effective de la cible par
`solveBallisticArc`, bornage de `substep`.

Les 17 fichiers passent `luau-compile --only-parse` sans avertissement.
