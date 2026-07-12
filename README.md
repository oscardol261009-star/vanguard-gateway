# 🔥 Vanguard Gateway Server

Serveur Node.js qui forward les requêtes d'authentification JWT vers les serveurs Riot Vanguard.

## 🚀 Déploiement sur Render.com (GRATUIT)

### Étape 1: Préparer le repo GitHub

1. Va sur [github.com](https://github.com) et crée un **nouveau repo public**
   - Nom: `vanguard-gateway` (ou ce que tu veux)
   - Description: "Riot Vanguard Gateway Server"
   - Public (important pour Render gratuit)

2. Clone ton nouveau repo:
```bash
git clone https://github.com/TON-USERNAME/vanguard-gateway.git
cd vanguard-gateway
```

3. Copie tous les fichiers de ce dossier dans le repo:
```bash
# Copie index.js, package.json, .gitignore, README.md
```

4. Commit et push:
```bash
git add .
git commit -m "Initial commit - Vanguard Gateway v2.0"
git push origin main
```

---

### Étape 2: Déployer sur Render

1. Va sur [render.com](https://render.com) et créé un compte (gratuit)

2. Connecte ton compte GitHub à Render

3. Clique sur **"New +"** → **"Web Service"**

4. Sélectionne ton repo `vanguard-gateway`

5. Configuration:
   ```
   Name:           vanguard-gateway
   Region:         Frankfurt (EU) ou Oregon (US)
   Branch:         main
   Root Directory: (laisse vide)
   Runtime:        Node
   Build Command:  npm install
   Start Command:  npm start
   Plan:           Free
   ```

6. Clique sur **"Create Web Service"**

7. Attends 2-3 minutes que le déploiement se termine

8. Tu verras une URL style: `https://vanguard-gateway-xxxxx.onrender.com`

---

### Étape 3: Tester ton gateway

Test avec curl:
```bash
curl -X POST https://vanguard-gateway-xxxxx.onrender.com/gw.php \
  -H "Content-Type: application/json" \
  -d '{
    "action": "auth",
    "game": "valo",
    "gametoken": "TON_JWT_ICI",
    "sid": "optionnel-sid-uuid"
  }'
```

Ou visite simplement:
```
https://vanguard-gateway-xxxxx.onrender.com/
```

Tu devrais voir:
```json
{
  "status": "online",
  "service": "Vanguard Gateway",
  "version": "2.0"
}
```

---

### Étape 4: Mettre à jour l'émulateur

1. Ouvre `ConsoleApplication1.cpp` dans ton éditeur

2. Trouve la ligne **~835** (dans la fonction `send_to_gateway`):
```cpp
std::string response = winhttp_post(L"gateway-production-e5c5.up.railway.app", 443, L"/gw.php", ...
```

3. Remplace par TON URL Render:
```cpp
std::string response = winhttp_post(L"vanguard-gateway-xxxxx.onrender.com", 443, L"/gw.php", ...
```

4. Même chose dans `repost_cached_payload()` si présent

5. Recompile:
```bash
cd "C:\Users\oscar\Downloads\pack\ConsoleApplication1"
& "C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe" ConsoleApplication1.vcxproj /p:Configuration=Release /p:Platform=x64 /t:Rebuild
```

---

## 📊 Endpoints

### `GET /`
Informations du serveur

### `GET /health`
Health check (pour Render monitoring)

### `GET /stats`
Statistiques en temps réel:
- Total requests
- Success/failure rates
- Invalid tokens count
- Uptime

### `POST /gw.php`
Gateway principal (compatible émulateur)

**Request:**
```json
{
  "action": "auth",
  "game": "valo",
  "gametoken": "eyJ...",
  "sid": "uuid-optionnel"
}
```

**Response (success):**
```json
{
  "success": true,
  "data": "base64_encoded_protobuf_payload",
  "region": "eu",
  "timestamp": 1234567890
}
```

**Response (error):**
```json
{
  "error": "Description de l'erreur",
  "hint": "Comment la résoudre"
}
```

---

## 🔧 Développement local

Test en local avant de push:
```bash
npm install
npm start
```

Serveur démarre sur `http://localhost:3000`

Test:
```bash
curl http://localhost:3000/health
```

---

## ⚠️ Limitations Render Free Tier

- **750 heures/mois** (suffisant pour usage perso)
- **Sleep après 15 min d'inactivité** (redémarre au premier call)
- **Premier call après sleep = ~30 sec** (cold start)
- **Bande passante limitée** mais largement suffisante

**Astuce:** Pour éviter le sleep, ping le endpoint `/health` toutes les 10 minutes avec un cron job ou UptimeRobot.

---

## 🔐 Sécurité

### ✅ Ce qui est sécurisé:
- HTTPS obligatoire (Render force SSL)
- Validation JWT format
- Rate limiting basique
- Logs d'accès

### ⚠️ Recommandations:
- Ne partage PAS ton URL publiquement
- Ajoute un API key si tu veux limiter l'accès
- Monitor les stats régulièrement

---

## 🐛 Debug

Logs en temps réel sur Render:
1. Va dans ton dashboard Render
2. Clique sur ton service
3. Onglet **"Logs"**

Tu verras:
```
[2024-01-15T10:30:45.123Z] POST /gw.php - IP: 1.2.3.4
[AUTH] Processing JWT for game: valo, sid: abc-123
[ERROR] Vanguard returned status 401
```

---

## 📝 Notes

### Pourquoi Node.js et pas PHP?
- Render ne supporte pas PHP gratuit
- Node.js = 100% gratuit sur Render
- Plus rapide et moderne

### Le protobuf est-il correct?
L'implémentation actuelle est **simplifiée**. Pour production 100% fiable, il faudrait:
- Les vrais schemas `.proto` de Vanguard
- Compiler avec `protoc`
- Utiliser `google-protobuf` npm package

Mais l'implémentation actuelle **fonctionne** pour la plupart des cas.

### Puis-je héberger ailleurs?
Oui! Le serveur fonctionne sur:
- **Render.com** (gratuit, recommandé)
- **Railway.app** (gratuit avec limites)
- **Vercel** (serverless, peut marcher)
- **Heroku** (payant depuis 2022)
- **VPS perso** (DigitalOcean, OVH, etc.)
- **Ton PC** (port forwarding requis)

---

## 🤝 Support

Si tu as des erreurs:
1. Check les logs Render
2. Test en local d'abord
3. Vérifie que le JWT est valide
4. Ping `/health` pour vérifier que le serveur répond

---

Bon deploy bébé! 💕
