# 🌱 Plant Doctor

Tu prends une plante en photo avec ton téléphone → tu reçois :

- l'**espèce** (nom commun + nom latin) avec un score de confiance
- l'**état de santé** et les **maladies / carences / parasites** visibles
- le **traitement** concret pour chaque problème
- les **conditions d'entretien** (lumière, arrosage, sol, température, engrais)
- la **toxicité** pour les chats et les chiens

L'analyse tourne sur l'**API Google Gemini** en mode vision. Aucun matériel à
acheter, aucun capteur : le téléphone et le navigateur suffisent. Le palier
gratuit de Gemini suffit largement pour un usage perso.

---

## 🔑 Étape 1 : la clé API (gratuite)

1. Va sur <https://aistudio.google.com/apikey>
2. **Create API key** → copie la clé
3. Ne la mets **jamais** dans le code ni dans un message : elle va uniquement
   dans une variable d'environnement (étape suivante). Si une clé fuite,
   supprime-la depuis cette même page et recrées-en une.

---

## 🚀 Étape 2 : déploiement sur Render (gratuit)

1. **New +** → **Web Service** → ce repo
2. Configuration :

```
Name:            plant-doctor
Region:          Frankfurt (EU)
Branch:          claude/esp-camera-project-ideas-kf9i26
Root Directory:  plant-doctor      <-- IMPORTANT
Runtime:         Node
Build Command:   npm install
Start Command:   npm start
Plan:            Free
```

3. Onglet **Environment** → **Add Environment Variable** :

```
GEMINI_API_KEY = ta_cle_google
```

4. **Create Web Service**, ~2 min, puis ouvre l'URL sur ton téléphone :
   `https://plant-doctor-xxxx.onrender.com`

> Le `Root Directory: plant-doctor` est obligatoire, sinon Render lance le gateway
> Vanguard qui est à la racine du repo.

---

## 💻 En local

```bash
cd plant-doctor
npm install
export GEMINI_API_KEY=ta_cle_google
npm start
```

→ <http://localhost:3000>

Vérifier que tout est branché :

```bash
curl http://localhost:3000/health
```

---

## 📡 API

### `GET /health`

```json
{ "status": "ok", "moteur": "gemini", "model": "gemini-2.5-flash", "apiKey": "configuree", "analyses": 3 }
```

### `POST /api/analyze`

**Requête**

```json
{
  "image": "data:image/jpeg;base64,/9j/4AAQ...",
  "note": "les feuilles jaunissent depuis 2 semaines"
}
```

- `image` : data-URL ou base64 brut, JPEG/PNG/WebP/HEIC, **5 Mo max**
  (le front redimensionne automatiquement à 1400 px avant l'envoi)
- `note` : optionnel, 500 caractères max

**Réponse**

```json
{
  "est_une_plante": true,
  "espece": "Monstera",
  "nom_latin": "Monstera deliciosa",
  "confiance": 92,
  "etat_sante": "moyenne",
  "resume": "Plante vigoureuse mais plusieurs feuilles basses jaunissent...",
  "problemes": [
    {
      "nom": "Excès d'arrosage",
      "gravite": "moyenne",
      "symptomes": "Jaunissement des feuilles basses, terreau détrempé",
      "traitement": "Laisser sécher les 3 premiers cm de substrat..."
    }
  ],
  "entretien": {
    "lumiere": "Lumière vive indirecte",
    "arrosage": "Une fois par semaine en été",
    "sol": "Terreau drainant avec écorce",
    "temperature": "18-27 °C",
    "engrais": "Engrais plantes vertes tous les 15 jours au printemps"
  },
  "actions_prioritaires": ["Couper les feuilles mortes", "Espacer les arrosages"],
  "toxique_animaux": "Toxique pour les chats et les chiens",
  "meta": { "moteur": "gemini", "model": "gemini-2.5-flash", "duree_ms": 7412 }
}
```

Le format est garanti par un `responseSchema` envoyé à l'API (structured output) :
la réponse a toujours exactement ces champs.

**Erreurs** : `400` image invalide · `429` quota Gemini atteint · `500` clé API
manquante ou invalide · `502` erreur côté Gemini · `504` timeout (90 s).

---

## ⚙️ Variables d'environnement

| Variable | Obligatoire | Défaut | Rôle |
|---|---|---|---|
| `GEMINI_API_KEY` | ✅ | — | Clé Google AI Studio (`GOOGLE_API_KEY` accepté aussi) |
| `PORT` | ❌ | `3000` | Port d'écoute (Render le fournit) |
| `PLANT_DOCTOR_MODEL` | ❌ | `gemini-2.5-flash` | Modèle utilisé (`gemini-2.5-pro` pour plus fin, plus lent) |

La clé n'est **jamais** dans le code ni envoyée au navigateur : le front appelle le
serveur, le serveur appelle Gemini.

---

## 🗂️ Structure

```
plant-doctor/
├── server.js          # Express + appel vision Gemini (REST, fetch natif)
├── package.json       # une seule dépendance : express
├── public/
│   ├── index.html     # front mobile (caméra live, résultats, historique)
│   └── card3d.js      # carte 3D texturée en WebGL, sans librairie
└── README.md
```

L'historique des 12 dernières analyses est stocké en `localStorage`, côté téléphone.

### Caméra live

La page ouvre directement le flux de la caméra arrière (`getUserMedia`) : on vise,
on appuie sur le déclencheur, l'analyse part toute seule. La caméra est relâchée
pendant l'analyse et quand l'onglet passe en arrière-plan.

⚠️ `getUserMedia` **exige HTTPS** (Render le fournit) ou `localhost`. Sinon la page
affiche un message clair et bascule sur l'envoi d'un fichier.

### Carte 3D

Après chaque analyse, la photo devient une plaque en volume qu'on fait tourner au
doigt : face avant la photo, face arrière une fiche générée au vol (espèce, état,
entretien), avec tranches éclairées et inertie. C'est du WebGL brut — pas de
Three.js, pas de CDN. Si le navigateur n'a pas WebGL, la carte est simplement
masquée, le reste marche.

---

## ⚠️ Bon à savoir

- Free tier Render : le service s'endort après 15 min → premier appel ~30 s.
- Free tier Gemini : limité en requêtes par minute et par jour. Si tu prends un
  `429`, attends une minute.
- L'IA se trompe : ne consomme jamais une plante sur la seule base de ce diagnostic.

---

## 🔮 Idées de suite

- Suivi d'une plante dans le temps (photos datées + courbe de santé)
- Rappels d'arrosage calculés depuis l'espèce détectée
- Mode « jardin » : plusieurs plantes sur une photo
- Export PDF du diagnostic
