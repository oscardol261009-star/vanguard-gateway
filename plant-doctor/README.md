# 🌱 Plant Doctor

Tu prends une plante en photo avec ton téléphone → tu reçois :

- l'**espèce** (nom commun + nom latin) avec un score de confiance
- l'**état de santé** et les **maladies / carences / parasites** visibles
- le **traitement** concret pour chaque problème
- les **conditions d'entretien** (lumière, arrosage, sol, température, engrais)
- la **toxicité** pour les chats et les chiens

L'analyse tourne sur l'API Claude en mode vision. Aucun matériel à acheter, aucun
capteur : le téléphone et le navigateur suffisent.

---

## 🚀 Déploiement sur Render (gratuit)

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
ANTHROPIC_API_KEY = sk-ant-...
```

(clé à créer sur <https://console.anthropic.com> → API Keys)

4. **Create Web Service**, ~2 min, puis ouvre l'URL sur ton téléphone :
   `https://plant-doctor-xxxx.onrender.com`

> Le `Root Directory: plant-doctor` est obligatoire, sinon Render lance le gateway
> Vanguard qui est à la racine du repo.

---

## 💻 En local

```bash
cd plant-doctor
npm install
export ANTHROPIC_API_KEY=sk-ant-...
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
{ "status": "ok", "model": "claude-opus-4-8", "apiKey": "configuree", "analyses": 3 }
```

### `POST /api/analyze`

**Requête**

```json
{
  "image": "data:image/jpeg;base64,/9j/4AAQ...",
  "note": "les feuilles jaunissent depuis 2 semaines"
}
```

- `image` : data-URL ou base64 brut, JPEG/PNG/WebP/GIF, **5 Mo max**
  (le front redimensionne automatiquement à 1400 px avant l'envoi)
- `note` : optionnel, 500 caractères max

**Réponse**

```json
{
  "est_une_plante": true,
  "espece": "Monstera deliciosa",
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
  "meta": { "model": "claude-opus-4-8", "duree_ms": 7412 }
}
```

Le format est garanti par un JSON Schema envoyé à l'API (structured outputs) :
la réponse a toujours exactement ces champs.

**Erreurs** : `400` image invalide · `429` rate limit · `500` clé API manquante ·
`502` erreur côté API Claude.

---

## ⚙️ Variables d'environnement

| Variable | Obligatoire | Défaut | Rôle |
|---|---|---|---|
| `ANTHROPIC_API_KEY` | ✅ | — | Clé API Anthropic |
| `PORT` | ❌ | `3000` | Port d'écoute (Render le fournit) |
| `PLANT_DOCTOR_MODEL` | ❌ | `claude-opus-4-8` | Modèle utilisé |

La clé n'est **jamais** dans le code ni envoyée au navigateur : le front appelle le
serveur, le serveur appelle Claude.

---

## 🗂️ Structure

```
plant-doctor/
├── server.js          # Express + appel vision Claude + schéma JSON
├── package.json
├── public/
│   └── index.html     # front mobile (caméra, aperçu, résultats, historique)
└── README.md
```

L'historique des 12 dernières analyses est stocké en `localStorage`, côté téléphone.

---

## ⚠️ Bon à savoir

- Free tier Render : le service s'endort après 15 min → premier appel ~30 s.
- Une analyse coûte quelques centimes d'API selon la taille de l'image.
- L'IA se trompe : ne consomme jamais une plante sur la seule base de ce diagnostic.

---

## 🔮 Idées de suite

- Suivi d'une plante dans le temps (photos datées + courbe de santé)
- Rappels d'arrosage calculés depuis l'espèce détectée
- Mode « jardin » : plusieurs plantes sur une photo
- Export PDF du diagnostic
