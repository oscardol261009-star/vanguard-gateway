# Créer ses animations de parkour

Guide pas à pas pour fabriquer tes propres animations (course, glissade, wall
run, réception) et les brancher sur le framework.

Tout se passe dans l'éditeur d'animation de Studio — c'est du travail manuel,
il n'y a pas de raccourci par le code.

---

## 1. Créer un mannequin

Sans mannequin, pas d'éditeur d'animation.

1. Onglet **Avatar** → **Rig Builder** (ou **Créateur de Rig**)
2. Choisis **R15** → **Block Rig** (le plus simple à animer)

> Prends **R15**, pas R6. R15 a 15 articulations au lieu de 6 : c'est ce qui
> permet des poses de parkour crédibles. Et c'est le rig par défaut des joueurs.

Un `Dummy` apparaît dans le Workspace.

---

## 2. Ouvrir l'éditeur

1. Onglet **Avatar** → **Animation Editor** (**Éditeur d'animation**)
2. Clique sur le `Dummy` dans le viewport
3. Donne un nom à l'animation (ex. `Slide`) → **Créer**

Tu vois une timeline en bas et la liste des membres à gauche.

---

## 3. Animer

Le principe : tu poses le personnage à des instants clés, Studio interpole
entre les deux.

1. Place le curseur sur la timeline (ex. `0:00`)
2. Fais tourner un membre dans le viewport → une **clé** est créée automatiquement
3. Avance le curseur (ex. `0:15`), repose le personnage → nouvelle clé
4. Appuie sur ▶ pour prévisualiser

### Réglages qui comptent

| Réglage | Où | Pourquoi |
|---|---|---|
| **Boucle** | icône ⟲ en haut de la timeline | Indispensable pour course, wall run, accroupi. À **désactiver** pour saut et réception. |
| **Priorité** | menu ⋯ → *Set Animation Priority* | `Movement` pour la locomotion, `Action` pour saut/réception. Sans ça, l'animation est écrasée par une autre. |
| **Easing** | clic droit sur une clé | `Linear` fait robotique. Mets `Cubic / InOut` sur la plupart des clés. |

### Durées de référence

| Animation | Durée | Boucle |
|---|---|---|
| Course | 0.6 – 0.8 s (cycle complet, 2 pas) | oui |
| Glissade | 0.4 s d'entrée puis pose tenue | oui |
| Wall run | 0.5 – 0.7 s | oui |
| Réception | 0.3 – 0.5 s | non |
| Saut | 0.3 s | non |

> Pour une course : cale l'animation sur **20 studs/s** (la valeur de
> `RunReferenceSpeed` dans `Config.luau`). Le framework ajuste ensuite la
> vitesse de lecture automatiquement — pas besoin d'être parfait.

---

## 4. Publier

1. Menu ⋯ de l'éditeur → **Publish to Roblox** (*Publier sur Roblox*)
2. Donne un nom, publie
3. Menu ⋯ → **Export** → tu vois l'**ID** de l'animation

⚠️ **Le piège qui bloque tout le monde** : une animation ne se joue que si elle
appartient au **même compte (ou groupe) que le jeu**. Si tu publies l'animation
sur ton compte perso et que le jeu appartient à un groupe, tu auras un
`Failed to load animation` et rien ne bougera. Publie au bon endroit dès le départ.

---

## 5. Brancher les IDs

Ouvre `PhysicsClient` (dans `StarterPlayerScripts`), tout en haut :

```lua
local CUSTOM_ANIMATIONS = {
	slide   = "rbxassetid://123456789",
	wallRun = "rbxassetid://123456790",
	land    = "rbxassetid://123456791",
	crouch  = "rbxassetid://123456792",
}
```

Noms de pistes reconnus :

| Clé | Quand elle se joue |
|---|---|
| `idle` | à l'arrêt |
| `walk` | marche |
| `run` | sprint |
| `crouch` | accroupi |
| `slide` | glissade |
| `wallRun` | wall run |
| `jump` | au décollage (une fois) |
| `fall` | en chute |
| `land` | à la réception, si l'impact dépasse `LandImpactSpeed` |

Tu n'es pas obligé de toutes les fournir : `idle`, `walk`, `run`, `jump` et
`fall` sont récupérées automatiquement depuis l'avatar du joueur. Les autres
retombent sur une animation existante tant que tu n'as pas donné d'ID.

---

## Récupérer des animations toutes faites

Si tu ne veux pas animer toi-même :

- **Boîte à outils** → onglet **Modèles**, cherche « parkour animation »,
  « slide animation ». Insère le modèle, ouvre l'objet `Animation` dedans et
  copie son `AnimationId`.
- Vérifie toujours que l'animation se joue vraiment avant de construire dessus :
  beaucoup d'assets de la Boîte à outils ont des IDs morts ou appartiennent à
  un autre compte (voir le piège du point 4).

---

## Vue première personne

Le module `FirstPersonView` est déjà branché (`FIRST_PERSON = true` en haut de
`PhysicsClient`). Il utilise l'approche **corps réel visible** : on garde ton
vrai personnage et on masque seulement la tête.

Pourquoi celle-ci plutôt qu'un *viewmodel* (modèle de bras séparé collé devant
la caméra) : le viewmodel est le standard des FPS de tir, mais il demande un
second rig et un **second jeu d'animations**. Avec le corps réel, les
animations de parkour que tu viens de créer servent aux deux vues.

Le module s'occupe de deux choses que Roblox rend pénibles :

- **La transparence.** En vue subjective, Roblox force
  `LocalTransparencyModifier = 1` sur tout le personnage, à *chaque image*. Le
  régler une seule fois ne sert à rien. Le module le réimpose dans un
  RenderStep — c'est la raison n°1 du « mon corps est invisible en première
  personne ».
- **La nuque.** Sans correction, baisser les yeux ne bouge rien et tu vois ton
  torse figé de face. Le module répercute le tangage de la caméra sur le
  Motor6D `Neck` (présent sous ce nom en R6 comme en R15).

Réglages dans `Config.FirstPerson` :

```lua
ShowBody = true,          -- voir ses jambes
HideAccessories = true,   -- chapeaux/cheveux masqués : ils flottent devant l'objectif
TiltHead = true,
MaxHeadPitch = 70,
HeadPitchScale = 0.8,     -- < 1 : la tête suit partiellement, plus naturel
```

Bascule à chaud (menu d'options, cinématique) :

```lua
view:setEnabled(false)   -- repasse en troisième personne
```

### Animer pour la première personne

Deux points auxquels penser quand tu animes, si ton jeu est en vue subjective :

1. **La tête bouge la caméra.** Une animation qui secoue violemment la tête
   rendra le jeu injouable. Garde les mouvements de tête sobres.
2. **On voit surtout les bras et les jambes.** Soigne-les ; le torse et le dos
   ne seront presque jamais visibles.
