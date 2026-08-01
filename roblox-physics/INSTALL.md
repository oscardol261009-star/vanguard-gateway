# Installation dans Roblox Studio

Deux chemins. **Si tu débutes ou si tu veux juste tester : prends la méthode 1.**

---

## Méthode 1 — Le fichier `.rbxmx` (aucune installation)

C'est le plus simple : un seul fichier à glisser dans Studio. Pas de terminal,
pas de plugin, pas de Rojo.

### 1. Récupérer le fichier

Sur GitHub, ouvre `roblox-physics/AdvancedPhysics.rbxmx`, puis clique sur
**Download raw file** (l'icône de téléchargement en haut à droite).

> Attention : ne fais pas un copier-coller du texte affiché par GitHub. Il faut
> bien télécharger le fichier.

### 2. L'importer dans Studio

1. Ouvre ton jeu dans Roblox Studio.
2. Dans la fenêtre **Explorer**, clic droit sur `Workspace`.
3. Choisis **Insert from File...**
4. Sélectionne `AdvancedPhysics.rbxmx`.

Un dossier `AdvancedPhysics_Install` apparaît dans `Workspace`, contenant :

```
AdvancedPhysics_Install
├── AdvancedPhysics    (ModuleScript, avec toute l'arborescence dedans)
├── PhysicsServer      (Script)
└── PhysicsClient      (LocalScript)
```

### 3. Ranger les 3 éléments

Glisse-dépose chacun à sa place dans l'Explorer :

| Élément | Destination |
|---|---|
| `AdvancedPhysics` | `ReplicatedStorage` |
| `PhysicsServer` | `ServerScriptService` |
| `PhysicsClient` | `StarterPlayer` → `StarterPlayerScripts` |

Puis supprime le dossier `AdvancedPhysics_Install`, maintenant vide.

### 4. Tester

Appuie sur **Play**. Tu contrôles ton personnage avec le contrôleur avancé :

- **ZQSD / WASD** — se déplacer
- **Espace** — sauter (double saut, saut à hauteur variable)
- **Maj gauche** — sprinter
- **Ctrl gauche** ou **C** — s'accroupir ; en courant, ça déclenche une glissade
- **Espace en l'air contre un mur** — wall jump ; en courant le long d'un mur, wall run

En mode Studio, la console affiche l'état de locomotion en direct
(`Idle`, `Running`, `Airborne`, `Sliding`, `WallRunning`...).

### Après une modification des sources

Le `.rbxmx` est **généré**, il ne se met pas à jour tout seul. Si tu modifies
les fichiers `.luau` du dépôt, régénère-le :

```bash
cd roblox-physics
python3 tools/build-rbxmx.py
```

---

## Méthode 2 — Rojo (pour travailler dans la durée)

À privilégier si tu comptes vraiment développer le jeu : tu édites les fichiers
dans VS Code, et Studio se met à jour **en direct** à chaque sauvegarde. Tu
gardes aussi l'historique Git, ce que la méthode 1 ne permet pas.

### 1. Installer le plugin Studio

Dans Studio : onglet **Plugins** → **Manage Plugins** → cherche « Rojo » →
installe le plugin officiel (éditeur : `Rojo`).

### 2. Installer la ligne de commande

Choisis **une** de ces options :

- **Rokit** (gestionnaire de versions, recommandé) :
  ```bash
  rokit add rojo-rbx/rojo
  rokit install
  ```
- **Binaire direct** : télécharge l'exécutable pour ton OS depuis
  <https://github.com/rojo-rbx/rojo/releases> et place-le dans ton PATH.
- **Cargo** (si tu as Rust) : `cargo install rojo`

Vérifie : `rojo --version`

### 3. Lancer

```bash
cd roblox-physics
rojo serve
```

Puis dans Studio : ouvre le panneau **Rojo** (onglet Plugins) et clique
**Connect**. L'arborescence décrite dans `default.project.json` est créée
automatiquement, et chaque sauvegarde d'un `.luau` se répercute instantanément.

### Générer un fichier au lieu de servir en direct

```bash
rojo build -o AdvancedPhysics.rbxl     # une place complète, à ouvrir dans Studio
```

---

## Laquelle choisir ?

| | Méthode 1 (`.rbxmx`) | Méthode 2 (Rojo) |
|---|---|---|
| Installation | aucune | plugin + CLI |
| Mise en place | ~1 minute | ~10 minutes |
| Édition du code | dans Studio | dans VS Code, synchro live |
| Suivi Git | non | oui |
| Pour qui | tester, débuter | développer sérieusement |

Rien ne t'empêche de commencer par la méthode 1 pour voir si le système te
plaît, et de passer à Rojo ensuite.

---

## En cas de problème

**« Le personnage ne bouge pas »**
Vérifie que `AdvancedPhysics` est bien dans `ReplicatedStorage` (pas ailleurs) et
que `PhysicsClient` est bien un **LocalScript** dans `StarterPlayerScripts`.
Regarde la console (F9) : le module affiche une erreur explicite s'il ne trouve
pas le `HumanoidRootPart`.

**« Attempt to index nil with 'Util' » ou un require qui échoue**
La hiérarchie sous `AdvancedPhysics` n'est pas respectée. Les noms des dossiers
`Util`, `Solvers`, `Modules` et de chaque ModuleScript doivent être **exacts**
(majuscules comprises). C'est précisément pour ça que le `.rbxmx` existe :
il garantit la structure.

**« Le personnage tremble ou s'enfonce dans le sol »**
`RideHeight` (3.0 par défaut) est calibré pour un rig R15 standard. Si tu as un
personnage de taille inhabituelle, ajuste-le :

```lua
local controller = AdvancedPhysics.CharacterController.new(character, {
    RideHeight = 2.4,
})
```

**« Le saut est trop mou / trop sec »**
Joue sur `JumpHeight`, `FallGravityScale` et `LowJumpGravityScale`
(voir la section « game feel » du README).
