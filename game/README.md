# 🏙️ City Walk — balade 3D dans ta ville

Un jeu de balade en vue première personne dans **n'importe quelle vraie ville**. Les
bâtiments, rues, trottoirs, parcs et rivières sont construits en direct depuis les
données d'OpenStreetMap, puis extrudés en 3D.

Rien à installer, rien à acheter, rien à compiler.

## Lancer le jeu

Double-clique sur `game/index.html`. C'est tout.

Le jeu a besoin d'une connexion internet au premier chargement d'un quartier (il
interroge l'API Overpass d'OpenStreetMap), puis garde les données en cache local.

Si ton navigateur bloque quelque chose en `file://`, sers le dossier :

```bash
cd game
python3 -m http.server 8000
# puis ouvre http://localhost:8000
```

## Choisir sa ville

Trois façons :

- **Chercher** — tape « Lyon, Place Bellecour » ou « Bruxelles Grand-Place » et
  choisis un résultat.
- **Ma position** — le navigateur demande ta géolocalisation et charge ton quartier.
- **Par URL** — `index.html?lat=45.7640&lon=4.8357&r=900&q=Lyon&auto=1`
  (`r` = rayon en mètres, `auto=1` démarre sans passer par le menu).

La zone va de 500 m (quartier, rapide) à 2 km (très lourd). Commence en 900 m.

## Commandes

| Touche | Action |
| --- | --- |
| `ZQSD` / `WASD` / flèches | marcher |
| souris | regarder (clique pour capturer le curseur) |
| `Maj` | courir |
| `Espace` | sauter — monter en mode vol |
| `C` / `Ctrl` | descendre en mode vol |
| `F` | mode vol (pour voir la ville d'en haut) |
| `[` `]` | reculer / avancer l'heure de 30 min |
| `T` | faire défiler le temps automatiquement |
| `P` | capture d'écran (PNG téléchargé) |
| `H` | masquer l'interface |
| `Échap` | pause |

## Ce qui est simulé

- **Bâtiments** — hauteur réelle si le tag `height` ou `building:levels` existe,
  sinon estimée d'après le type de bâtiment, avec une variation déterministe (le
  même bâtiment garde toujours la même allure).
- **Façades** — fenêtres générées dans le shader à partir de la position monde :
  grille d'étages, allumage aléatoire mais stable la nuit, toitures assombries,
  soubassement plus sombre au niveau de la rue.
- **Voirie** — chaussée, trottoirs, marquage axial en pointillés, chemins piétons
  et pistes cyclables, largeur déduite du type de voie et du nombre de voies.
- **Mobilier urbain** — lampadaires tous les ~34 m, dont les plus proches du
  joueur reçoivent de vraies lumières ponctuelles (pool réaffecté en continu).
- **Végétation** — arbres d'alignement le long des rues et semis dans les parcs
  et bois, en `InstancedMesh`, écartés automatiquement des murs.
- **Cycle jour/nuit** — course solaire, ciel en dégradé avec halo, étoiles,
  brume atmosphérique et exposition qui s'adaptent à l'heure.
- **Collisions** — impossible de traverser un bâtiment ; glissement le long des
  murs, gravité et saut. En vol, on peut passer au-dessus des toits.

## Comment ça marche

```
index.html          tout le jeu (HTML + CSS + JS, un seul fichier)
vendor/three.min.js  Three.js r150 embarqué (aucun CDN, fonctionne hors-ligne)
```

Le pipeline, au chargement :

1. **Géocodage** du lieu via Nominatim (uniquement si tu utilises la recherche).
2. **Requête Overpass** sur une bbox autour du point : bâtiments, voies, eau,
   espaces verts, avec géométrie inline (`out geom`). Trois serveurs Overpass
   sont essayés en cascade, et le résultat est mis en cache dans `localStorage`.
3. **Projection** lat/lon → mètres (équirectangulaire locale, centrée sur le
   point choisi — largement assez précis à l'échelle d'une ville).
4. **Extrusion** de chaque emprise en `ExtrudeGeometry`, puis **fusion** de tout
   en un seul `BufferGeometry` avec couleurs par sommet : la ville entière tient
   en un appel de rendu.
5. **Grille spatiale** (cellules de 20 m) des emprises au sol pour les collisions,
   testées en point-dans-polygone plus distance aux arêtes.

Si Overpass est injoignable, le jeu génère une ville de secours procédurale pour
rester jouable.

## Limites connues

- Les bâtiments définis comme **relations** OSM (cours intérieures, multipolygones)
  sont ignorés — seules les `way` fermées sont extrudées.
- Le terrain est **plat** : pas de relief, les données d'élévation ne sont pas
  chargées.
- Pas d'intérieurs, pas de circulation, pas de piétons.
- La qualité du rendu dépend entièrement de la qualité du mapping OSM local :
  dans un quartier peu cartographié, les hauteurs sont estimées.

## Pistes pour aller plus loin

- Relief réel à partir de tuiles d'élévation (Copernicus / SRTM).
- Toits en pente selon `roof:shape`, et vraies textures de façade.
- Vélo ou voiture, avec suivi du graphe routier.
- Mode multijoueur : positions partagées via WebSocket.
- Occlusion culling par îlot pour tenir 60 fps sur des zones de 2 km.
