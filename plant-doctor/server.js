/**
 * 🌱 Plant Doctor - serveur d'analyse de plantes par photo
 *
 * Tu prends une photo d'une feuille / d'une plante, le serveur l'envoie a
 * l'API Google Gemini (vision) et renvoie : espece, etat de sante, maladies
 * detectees, traitement et conseils d'entretien.
 *
 * Pas de SDK : l'API REST est appelee avec le fetch natif de Node 18+.
 */

const express = require('express');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;
const MODEL = process.env.PLANT_DOCTOR_MODEL || 'gemini-2.5-flash';
const API_KEY = process.env.GEMINI_API_KEY || process.env.GOOGLE_API_KEY;
const API_BASE = 'https://generativelanguage.googleapis.com/v1beta/models';

// Les photos arrivent en base64 -> il faut une limite de body genereuse
app.use(express.json({ limit: '15mb' }));
app.use(express.static(path.join(__dirname, 'public')));

const MEDIA_TYPES = ['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'];
const MAX_IMAGE_BYTES = 5 * 1024 * 1024;
const TIMEOUT_MS = 90000;

const stats = {
  startedAt: Date.now(),
  analyses: 0,
  erreurs: 0,
};

/**
 * Schema de la reponse : Gemini est force de repondre exactement comme ca.
 * Sous-ensemble OpenAPI accepte par l'API -> pas de additionalProperties ici.
 */
const PLANT_SCHEMA = {
  type: 'OBJECT',
  properties: {
    est_une_plante: {
      type: 'BOOLEAN',
      description: "true si l'image contient bien une plante",
    },
    espece: {
      type: 'STRING',
      description: 'Nom commun en francais, ou "Inconnue" si impossible a determiner',
    },
    nom_latin: { type: 'STRING' },
    confiance: {
      type: 'INTEGER',
      description: "Confiance de l'identification, de 0 a 100",
    },
    etat_sante: {
      type: 'STRING',
      enum: ['bonne', 'moyenne', 'mauvaise', 'inconnu'],
    },
    resume: {
      type: 'STRING',
      description: 'Deux ou trois phrases qui resument ce que tu vois',
    },
    problemes: {
      type: 'ARRAY',
      description: 'Maladies, carences, parasites ou erreurs de culture reperes',
      items: {
        type: 'OBJECT',
        properties: {
          nom: { type: 'STRING' },
          gravite: { type: 'STRING', enum: ['faible', 'moyenne', 'elevee'] },
          symptomes: { type: 'STRING' },
          traitement: { type: 'STRING' },
        },
        required: ['nom', 'gravite', 'symptomes', 'traitement'],
        propertyOrdering: ['nom', 'gravite', 'symptomes', 'traitement'],
      },
    },
    entretien: {
      type: 'OBJECT',
      properties: {
        lumiere: { type: 'STRING' },
        arrosage: { type: 'STRING' },
        sol: { type: 'STRING' },
        temperature: { type: 'STRING' },
        engrais: { type: 'STRING' },
      },
      required: ['lumiere', 'arrosage', 'sol', 'temperature', 'engrais'],
      propertyOrdering: ['lumiere', 'arrosage', 'sol', 'temperature', 'engrais'],
    },
    actions_prioritaires: {
      type: 'ARRAY',
      description: 'Les 1 a 3 choses a faire tout de suite',
      items: { type: 'STRING' },
    },
    toxique_animaux: {
      type: 'STRING',
      description: 'Toxicite pour chats/chiens, ou "inconnu"',
    },
  },
  required: [
    'est_une_plante',
    'espece',
    'nom_latin',
    'confiance',
    'etat_sante',
    'resume',
    'problemes',
    'entretien',
    'actions_prioritaires',
    'toxique_animaux',
  ],
  propertyOrdering: [
    'est_une_plante',
    'espece',
    'nom_latin',
    'confiance',
    'etat_sante',
    'resume',
    'problemes',
    'entretien',
    'actions_prioritaires',
    'toxique_animaux',
  ],
};

const SYSTEM_PROMPT = `Tu es botaniste et phytopathologiste. On te montre la photo d'une plante.

Ta mission :
1. Identifier l'espece (nom commun francais + nom latin) et donner une confiance honnete.
2. Evaluer l'etat de sante a partir de ce qui est REELLEMENT visible sur la photo
   (taches, jaunissement, necroses, parasites, port de la plante, substrat).
3. Lister les problemes avec leur gravite et un traitement concret et applicable.
4. Donner les conditions d'entretien ideales pour cette espece.

Regles :
- Si l'image ne montre pas de plante, mets est_une_plante a false et reste bref.
- N'invente jamais un symptome que tu ne vois pas. Si la photo est floue, sombre ou
  trop cadree, dis-le dans le resume et baisse la confiance.
- Si la plante est en bonne sante, renvoie une liste de problemes vide.
- Reponds toujours en francais, ton direct, pas de blabla.`;

/** Nettoie une data-URL ou du base64 brut. */
function parseImage(payload) {
  if (typeof payload !== 'string' || payload.length === 0) {
    return { error: "Aucune image recue (champ 'image' manquant)." };
  }

  let mediaType = 'image/jpeg';
  let data = payload.trim();

  const dataUrl = data.match(/^data:([a-zA-Z0-9/+.-]+);base64,(.*)$/s);
  if (dataUrl) {
    mediaType = dataUrl[1].toLowerCase();
    data = dataUrl[2];
  }

  data = data.replace(/\s/g, '');

  if (!MEDIA_TYPES.includes(mediaType)) {
    return { error: `Format non supporte (${mediaType}). Utilise JPEG, PNG, WebP ou HEIC.` };
  }
  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(data)) {
    return { error: "L'image n'est pas du base64 valide." };
  }

  const bytes = Math.floor((data.length * 3) / 4);
  if (bytes > MAX_IMAGE_BYTES) {
    return { error: 'Image trop lourde (max 5 Mo). Reduis la resolution avant envoi.' };
  }

  return { mediaType, data };
}

/** Traduit une erreur HTTP de l'API en message clair + code a renvoyer au front. */
function mapApiError(status, body) {
  const message = (body && body.error && body.error.message) || `HTTP ${status}`;

  if (status === 400 && /API key not valid|API_KEY_INVALID/i.test(message)) {
    return { code: 500, error: 'Cle API Gemini invalide. Verifie GEMINI_API_KEY sur Render.' };
  }
  if (status === 401 || status === 403) {
    return { code: 500, error: `Acces refuse par Google : ${message}` };
  }
  if (status === 429) {
    return {
      code: 429,
      error: 'Quota Gemini atteint. Attends une minute (le palier gratuit est limite par minute).',
    };
  }
  if (status === 400) {
    return { code: 400, error: `Requete refusee par Gemini : ${message}` };
  }
  return { code: 502, error: `Erreur API Gemini : ${message}` };
}

app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    service: 'plant-doctor',
    moteur: 'gemini',
    model: MODEL,
    apiKey: API_KEY ? 'configuree' : 'MANQUANTE',
    uptime: Math.floor((Date.now() - stats.startedAt) / 1000),
    analyses: stats.analyses,
    erreurs: stats.erreurs,
  });
});

app.post('/api/analyze', async (req, res) => {
  if (!API_KEY) {
    return res.status(500).json({
      error: "GEMINI_API_KEY n'est pas configuree sur le serveur.",
      hint: "Ajoute la variable d'environnement dans Render (Environment > Add Environment Variable).",
    });
  }

  const parsed = parseImage(req.body && req.body.image);
  if (parsed.error) {
    return res.status(400).json({ error: parsed.error });
  }

  const note = typeof req.body.note === 'string' ? req.body.note.slice(0, 500).trim() : '';
  const question = note
    ? `Analyse cette plante. Contexte donne par l'utilisateur : "${note}"`
    : 'Analyse cette plante.';

  const started = Date.now();
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);

  try {
    const apiRes = await fetch(`${API_BASE}/${encodeURIComponent(MODEL)}:generateContent`, {
      method: 'POST',
      signal: controller.signal,
      headers: {
        'Content-Type': 'application/json',
        'x-goog-api-key': API_KEY,
      },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: SYSTEM_PROMPT }] },
        contents: [
          {
            role: 'user',
            parts: [
              { inlineData: { mimeType: parsed.mediaType, data: parsed.data } },
              { text: question },
            ],
          },
        ],
        generationConfig: {
          responseMimeType: 'application/json',
          responseSchema: PLANT_SCHEMA,
          maxOutputTokens: 8192,
          temperature: 0.3,
        },
      }),
    });

    const body = await apiRes.json().catch(() => null);

    if (!apiRes.ok) {
      stats.erreurs++;
      console.error('[PLANT] Erreur API:', apiRes.status, JSON.stringify(body).slice(0, 400));
      const mapped = mapApiError(apiRes.status, body);
      return res.status(mapped.code).json({ error: mapped.error });
    }

    const candidate = body && body.candidates && body.candidates[0];

    if (!candidate) {
      stats.erreurs++;
      const blocked = body && body.promptFeedback && body.promptFeedback.blockReason;
      console.error('[PLANT] Pas de candidat:', JSON.stringify(body).slice(0, 400));
      return res.status(502).json({
        error: blocked
          ? `Image refusee par les filtres de securite (${blocked}).`
          : "Gemini n'a rien renvoye, reessaie.",
      });
    }

    const text = ((candidate.content && candidate.content.parts) || [])
      .map((part) => part.text || '')
      .join('');

    if (!text) {
      stats.erreurs++;
      console.error('[PLANT] Reponse vide, finishReason =', candidate.finishReason);
      return res.status(502).json({
        error:
          candidate.finishReason === 'MAX_TOKENS'
            ? 'Reponse coupee (trop longue). Reessaie avec une photo plus simple.'
            : `Reponse vide du modele (${candidate.finishReason || 'raison inconnue'}).`,
      });
    }

    let result;
    try {
      result = JSON.parse(text);
    } catch (e) {
      stats.erreurs++;
      console.error('[PLANT] Reponse non parsable:', text.slice(0, 500));
      return res.status(502).json({ error: 'Reponse illisible du modele, reessaie.' });
    }

    stats.analyses++;
    const ms = Date.now() - started;
    const nbProblemes = (result.problemes || []).length;
    console.log(
      `[PLANT] ${result.espece} | sante=${result.etat_sante} | ${nbProblemes} probleme(s) | ${ms}ms`
    );

    res.json({
      ...result,
      problemes: result.problemes || [],
      actions_prioritaires: result.actions_prioritaires || [],
      meta: {
        moteur: 'gemini',
        model: MODEL,
        duree_ms: ms,
        tokens: body.usageMetadata,
      },
    });
  } catch (err) {
    stats.erreurs++;
    if (err.name === 'AbortError') {
      console.error('[PLANT] Timeout apres', TIMEOUT_MS, 'ms');
      return res.status(504).json({ error: 'Le modele a mis trop de temps a repondre, reessaie.' });
    }
    console.error('[PLANT] Erreur:', err.message);
    res.status(500).json({ error: 'Erreur interne du serveur.' });
  } finally {
    clearTimeout(timer);
  }
});

app.listen(PORT, () => {
  console.log('🌱 Plant Doctor');
  console.log(`   http://localhost:${PORT}`);
  console.log(`   modele : ${MODEL} (Google Gemini)`);
  console.log(`   cle API : ${API_KEY ? 'OK' : 'MANQUANTE (export GEMINI_API_KEY=...)'}`);
});
