# 🏠 House RNG Simulator (Roblox, via Rojo)

Un simulateur où tu **roll** pour tirer des maisons de rareté aléatoire. Ta
meilleure maison se construit sur ton terrain et te génère de l'argent chaque
seconde ; tu dépenses cet argent en **Chance** pour tirer des maisons plus rares.

Raretés : Cabane → Maison → Villa → Manoir → Château → Palais → **Palais d'Or**
(1 sur ~11 000).

Le code vit ici dans des fichiers `.luau`. **Rojo** les synchronise automatiquement
vers Roblox Studio : dès que le code change dans le repo, ton jeu se met à jour.

## 🎮 Boucle de jeu

- **Le marché** : une plaza avec 8 présentoirs qui font tourner une maison
  miniature chacun, changeant automatiquement toutes les 5-9 s. Approche-toi
  et **maintiens E** pour l'acheter (prix affiché au-dessus) → elle rejoint
  ton **inventaire**. Aucun bouton "roll" : tout se passe dans le monde.
- **Pose tes maisons** : sélectionne une maison dans l'inventaire (à droite)
  puis clique une **case verte** de ta grille (4×4 = 16 cases) sur ton
  terrain pour la construire. Reclique une maison posée pour la **reprendre**.
- **Chaque maison posée rapporte** de l'argent/seconde ; le total × ton
  multiplicateur de Renaissance donne ton revenu.
- **🏷️ Remise +** dépense ton argent pour réduire le prix des maisons au
  marché (jusqu'à -75 %).
- **🔄 Renaissance** : quand tu as assez d'argent, renais → l'argent repart à
  zéro mais tu gagnes **+50 % de revenu permanent**. Le coût augmente à
  chaque Renaissance.
- **Achat = petit spectacle** : rayon de lumière, particules, onde de choc et
  tremblement de caméra sur ton perso, l'intensité montant avec la rareté
  (voir `client/Reveal.luau`).
- **Vrais matériaux** : chaque rareté a ses textures (bois/brique pour les
  communes, marbre/verre pour les rares, or pour le Palais d'Or) via
  `server/HouseBuilder.luau`, réutilisé pour les maisons posées ET les
  miniatures du marché.

---

## 🔧 Installation (à faire une seule fois)

### 1. Installer Rojo sur ton PC

Ce projet contient un `aftman.toml` : si tu as **Aftman** (gestionnaire
d'outils Roblox), il installe la bonne version de Rojo tout seul.

```bash
cd vanguard-gateway/roblox-game
aftman install
```

Répond `y` s'il demande d'ajouter Aftman au PATH, puis **rouvre ton terminal**.

*(Pas d'Aftman ? `winget install Rojo.Rojo`, ou télécharge `rojo.exe` sur
<https://github.com/rojo-rbx/rojo/releases>.)*

### 2. Installer le plugin Rojo dans Studio

1. Ouvre Roblox Studio
2. Onglet **Plugins** → **Manage Plugins** → **Marketplace**
3. Cherche **« Rojo »**, installe le plugin officiel (auteur : *rojo-rbx*)
4. Un bouton **Rojo** apparaît dans la barre Plugins

---

## ▶️ Lancer la synchro (à chaque session de travail)

1. **Récupère le code** sur ton PC (une seule fois, puis `git pull` ensuite) :
   ```bash
   git clone -b claude/esp-camera-project-ideas-kf9i26 https://github.com/oscardol261009-star/vanguard-gateway.git
   cd vanguard-gateway/roblox-game
   ```

2. **Démarre le serveur Rojo** dans ce dossier :
   ```bash
   rojo serve
   ```
   Tu verras : `Rojo server listening on port 34872`.

3. **Dans Studio** : ouvre un lieu (Baseplate), clique le bouton **Rojo** →
   **Connect**. Ça doit passer au vert.

4. ✅ **Test** : regarde la fenêtre **Output** de Studio (View → Output).
   Appuie sur **Play** ▶️. Tu dois voir :
   ```
   ✅ Rojo est bien connecté — le code serveur tourne !
   ```
   et un bandeau vert **« Rojo connecté ! »** en haut de l'écran.

Si tu vois ça, le lien marche — je peux écrire le vrai jeu et il apparaîtra
tout seul dans ton Studio.

---

## 🗂️ Structure

```
roblox-game/
├── default.project.json     # dit à Rojo où mettre chaque dossier dans Studio
└── src/
    ├── server/              # → ServerScriptService (logique du jeu, autorité)
    │   └── init.server.luau
    ├── client/              # → StarterPlayerScripts (interface, contrôles)
    │   └── init.client.luau
    └── shared/              # → ReplicatedStorage.Shared (code commun)
        └── Config.luau
```

- **server/** : ce qui tourne sur le serveur (scores, argent, anti-triche…).
- **client/** : ce que voit/fait le joueur (menus, boutons, effets).
- **shared/** : réglages et code utilisés des deux côtés.

---

## ⚠️ Important

- Laisse `rojo serve` **tourner** pendant que tu bosses — c'est lui qui synchronise.
- Rojo pousse le **code** (scripts). Les objets que tu poses à la main dans Studio
  (terrain, models…) restent dans Studio. On peut faire générer le décor **par le
  code** pour que tout vienne du repo, dis-moi si tu préfères ça.
- Après un `git pull`, Rojo applique les changements automatiquement.
