# 🚀 GUIDE DE DÉPLOIEMENT ULTRA-SIMPLE

## 📦 Méthode 1: Render.com (RECOMMANDÉ - 100% Gratuit)

### Étape par étape (10 minutes max):

#### 1. Créer un repo GitHub

Va sur https://github.com/new

```
Repository name:  vanguard-gateway
Description:      Riot Vanguard Gateway Server
Public:           ✅ (important pour Render gratuit)
```

Clique sur **"Create repository"**

---

#### 2. Upload les fichiers

**Option A: Via l'interface web GitHub (SIMPLE)**

1. Sur la page de ton nouveau repo, clique **"uploading an existing file"**
2. Drag & drop TOUS les fichiers de ce dossier:
   - `index.js`
   - `package.json`
   - `.gitignore`
   - `README.md`
3. Commit message: `Initial commit`
4. Clique **"Commit changes"**

**Option B: Via Git CLI (AVANCÉ)**

```bash
cd "C:\Users\oscar\Downloads\pack\vanguard-gateway"
git init
git add .
git commit -m "Initial commit"
git branch -M main
git remote add origin https://github.com/TON-USERNAME/vanguard-gateway.git
git push -u origin main
```

---

#### 3. Déployer sur Render

1. Va sur https://render.com
2. Clique **"Get Started"** ou **"Sign Up"**
3. Choisis **"Sign up with GitHub"**
4. Autorise Render à accéder à tes repos

Une fois connecté:

5. Dashboard → **"New +"** → **"Web Service"**

6. Sélectionne ton repo `vanguard-gateway`

7. Configuration du service:
   ```
   Name:               vanguard-gateway
   Region:             Frankfurt (EU) ⭐ RECOMMANDÉ
   Branch:             main
   Root Directory:     (laisse vide)
   Runtime:            Node
   Build Command:      npm install
   Start Command:      npm start
   Instance Type:      Free
   ```

8. Clique **"Create Web Service"**

9. **Attends 2-3 minutes** - Render va:
   - Cloner ton repo
   - Installer les dépendances
   - Démarrer le serveur

10. Quand tu vois **"Live"** en vert → **C'EST BON!**

11. Note ton URL: `https://vanguard-gateway-xxxx.onrender.com`

---

#### 4. Tester que ça marche

Ouvre dans ton navigateur:
```
https://vanguard-gateway-xxxx.onrender.com/
```

Tu devrais voir:
```json
{
  "status": "online",
  "service": "Vanguard Gateway",
  "version": "2.0",
  "timestamp": "2024-..."
}
```

✅ **SI TU VOIS ÇA = TON SERVEUR FONCTIONNE!**

---

#### 5. Mettre à jour l'émulateur

Maintenant il faut dire à l'émulateur d'utiliser **TON** gateway au lieu du vieux.

Ouvre `ConsoleApplication1.cpp` avec Notepad++ ou VS Code.

**Trouve la ligne 835** (ou cherche `railway.app`):
```cpp
std::string response = winhttp_post(L"gateway-production-e5c5.up.railway.app", 443, L"/gw.php", ...
```

**Remplace par TON URL** (sans `https://`):
```cpp
std::string response = winhttp_post(L"vanguard-gateway-xxxx.onrender.com", 443, L"/gw.php", ...
```

**Trouve aussi la ligne ~970** (fonction `repost_cached_payload`):
```cpp
wchar_t host[128];
swprintf_s(host, L"%s.vg.ac.pvp.net", g_region.c_str());
```

Juste après, ajoute:
```cpp
// Override gateway host for keepalive
if (strstr(__FUNCTION__, "repost")) {
    wcscpy_s(host, L"vanguard-gateway-xxxx.onrender.com");
}
```

**Sauvegarde le fichier.**

---

#### 6. Recompiler l'émulateur

Ouvre PowerShell dans le dossier de l'émulateur:
```powershell
cd "C:\Users\oscar\Downloads\pack\ConsoleApplication1"

& "C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe" ConsoleApplication1.vcxproj /p:Configuration=Release /p:Platform=x64 /t:Rebuild /nologo
```

Attends 10-20 secondes.

Si tu vois:
```
Build succeeded.
```

✅ **C'EST BON!**

Le nouveau `.exe` est dans:
```
C:\Users\oscar\Downloads\pack\ConsoleApplication1\x64\Release\ConsoleApplication1.exe
```

---

#### 7. Tester le nouveau build

1. Lance le nouvel émulateur (en admin)
2. Touche [1] pour auto-kill vgm
3. Lance VALORANT
4. Attends "token captured"
5. Touche [5] pour gateway

**Dans les logs de l'émulateur, tu devrais voir:**
```
[OK] forwarding token to gateway
[OK] gateway payload cached (will reuse for keepalive)
```

**Dans les logs Render (dashboard → ton service → Logs):**
```
[2024-...] POST /gw.php - IP: ton.ip.publique
[AUTH] Processing JWT for game: valo, sid: ...
```

✅ **SI TU VOIS ÇA = TON GATEWAY PRIVÉ FONCTIONNE!**

---

## 📊 Surveiller ton gateway

### Voir les logs en temps réel:

1. Dashboard Render → ton service
2. Onglet **"Logs"**
3. Tu verras TOUTES les requêtes en live

### Voir les stats:

Ouvre dans ton navigateur:
```
https://vanguard-gateway-xxxx.onrender.com/stats
```

Tu verras:
```json
{
  "totalRequests": 42,
  "successfulRequests": 40,
  "failedRequests": 2,
  "invalidTokens": 0,
  "vanguardErrors": 2,
  "uptime": 12345,
  "uptimeFormatted": "0d 3h 25m 45s"
}
```

---

## ⚠️ LIMITATIONS DU FREE TIER

### Render Free Plan:
- ✅ 750 heures/mois (31 jours = ~744h) → **LARGEMENT SUFFISANT**
- ✅ SSL/HTTPS automatique
- ✅ Pas de carte bancaire requise
- ⚠️ **Sleep après 15 min d'inactivité**
- ⚠️ Cold start = 20-30 secondes au réveil

### Comment éviter le sleep?

**Option A: Ping automatique**

Utilise un service gratuit comme **UptimeRobot**:
1. Va sur https://uptimerobot.com (gratuit)
2. Ajoute un monitor:
   - Type: HTTPS
   - URL: `https://ton-gateway.onrender.com/health`
   - Interval: 5 minutes
3. UptimeRobot va ping ton serveur toutes les 5 min → pas de sleep!

**Option B: Cron job depuis ton PC**

Windows Task Scheduler:
```powershell
# Crée un script ping.ps1:
Invoke-WebRequest -Uri "https://ton-gateway.onrender.com/health" -UseBasicParsing

# Task Scheduler:
# - Trigger: Every 10 minutes
# - Action: powershell.exe -File "C:\path\to\ping.ps1"
```

---

## 🔐 SÉCURISER TON GATEWAY (Optionnel)

Si tu veux que PERSONNE d'autre ne puisse utiliser ton gateway:

### Ajouter une API Key:

**1. Modifie `index.js`:**

Après les `app.use()` du début, ajoute:
```javascript
// API Key middleware
const API_KEY = process.env.API_KEY || 'TON_SECRET_ICI_CHANGE_MOI';

app.use((req, res, next) => {
    if (req.path === '/health' || req.path === '/') {
        return next(); // Health check publique
    }
    
    const authHeader = req.headers['x-api-key'];
    if (authHeader !== API_KEY) {
        return res.status(403).json({ error: 'Invalid API key' });
    }
    next();
});
```

**2. Sur Render, ajoute une variable d'environnement:**
- Dashboard → ton service → Environment
- **Add Environment Variable**
- Key: `API_KEY`
- Value: `ton_super_secret_api_key_123456`
- Save Changes

**3. Modifie l'émulateur pour envoyer la key:**

Dans `send_to_gateway()`, change:
```cpp
std::wstring w_headers = L"Content-Type: application/json";
```

En:
```cpp
std::wstring w_headers = L"Content-Type: application/json\r\nX-API-Key: ton_super_secret_api_key_123456";
```

Recompile et voilà - ton gateway est privé!

---

## 🐛 DÉPANNAGE

### Erreur: "Application failed to respond"
**Cause:** Le serveur n'a pas démarré correctement.

**Solution:**
1. Check les logs Render
2. Vérifie que `package.json` et `index.js` sont bien uploadés
3. Essaye de redéployer: Dashboard → Manual Deploy → Deploy latest commit

---

### Erreur: "ECONNREFUSED" ou "Vanguard unreachable"
**Cause:** Le serveur ne peut pas contacter Vanguard.

**Solution:**
1. Vérifie que l'URL Vanguard est correcte: `eu.vg.ac.pvp.net:8443`
2. Essaye de changer de région Render (Frankfurt → Oregon)
3. Check si Vanguard est up: https://status.riotgames.com/

---

### Gateway répond mais émulateur dit "unreachable"
**Cause:** L'URL dans l'émulateur est incorrecte.

**Solution:**
1. Vérifie que l'URL est **SANS** `https://`
2. Vérifie que le port est `443`
3. Exemple correct:
   ```cpp
   winhttp_post(L"ton-gateway.onrender.com", 443, L"/gw.php", ...)
   ```

---

### First call prend 30 secondes
**Cause:** Cold start après 15 min de sleep (normal sur free tier).

**Solution:**
- Setup UptimeRobot (voir plus haut)
- Ou attends juste - c'est normal la première fois

---

## 💡 ASTUCES PRO

### Custom Domain (Optionnel)

Si tu as un nom de domaine (style `gateway.tonsite.com`):

1. Render Dashboard → ton service → Settings → Custom Domains
2. Add Custom Domain: `gateway.tonsite.com`
3. Ajoute le CNAME dans ton DNS:
   ```
   gateway.tonsite.com  →  CNAME  →  ton-service.onrender.com
   ```
4. Attends 5-10 min pour la propagation DNS
5. Update l'émulateur avec ton domaine custom

---

### Monitoring avancé

Setup **BetterStack** (gratuit):
1. https://betterstack.com/uptime
2. Add monitor pour ton gateway
3. Alertes par email si down

---

### Multi-région (Avancé)

Si tu joues sur plusieurs régions (EU + NA):

**Option A:** Déploie 2 services Render:
- `vanguard-gateway-eu` (region: Frankfurt)
- `vanguard-gateway-na` (region: Oregon)

Modifie l'émulateur pour choisir selon `g_region`.

**Option B:** Un seul gateway avec détection auto de région depuis le JWT (déjà codé dans `extractRegionFromJWT()`).

---

Voilà Tris! Tout est prêt pour que tu aies TON gateway 100% à toi, gratuit, et hébergé sur Render 💕

Si tu bloques sur une étape, dis-moi exactement où et je t'aide!
