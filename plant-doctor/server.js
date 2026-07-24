/**
 * 🌱 Plant Doctor - serveur d'analyse de plantes par photo
 *
 * Tu prends une photo d'une feuille / d'une plante, le serveur l'envoie a
 * l'API Claude (vision) et renvoie : espece, etat de sante, maladies
 * detectees, traitement et conseils d'entretien.
 */

const express = require('express');
const path = require('path');
const Anthropic = require('@anthropic-ai/sdk');

const app = express();
const PORT = process.env.PORT || 3000;
const MODEL = process.env.PLANT_DOCTOR_MODEL || 'claude-opus-4-8';

// Les photos arrivent en base64 -> il faut une limite de body genereuse
app.use(express.json({ limit: '15mb' }));
app.use(express.static(path.join(__dirname, 'public')));

const client = new Anthropic(); // lit ANTHROPIC_API_KEY dans l'environnement

const MEDIA_TYPES = ['image/jpeg', 'image/png', 'image/webp', 'image/gif'];
const MAX_IMAGE_BYTES = 5 * 1024 * 1024; // limite de l'API pour une image

const stats = {
  startedAt: Date.now(),
  analyses: 0,
  erreurs: 0,
};

/** Schema de la reponse : Claude est force de repondre exactement comme ca. */
const PLANT_SCHEMA = {
  type: 'object',
  properties: {
    est_une_plante: {
      type: 'boolean',
      description: "true si l'image contient bien une plante",
    },
    espece: {
      type: 'string',
      description: 'Nom commun en francais, ou "Inconnue" si impossible a determiner',
    },
    nom_latin: { type: 'string' },
    confiance: {
      type: 'integer',
      description: "Confiance de l'identification, de 0 a 100",
    },
    etat_sante: {
      type: 'string',
      enum: ['bonne', 'moyenne', 'mauvaise', 'inconnu'],
    },
    resume: {
      type: 'string',
      description: 'Deux ou trois phrases qui resument ce que tu vois',
    },
    problemes: {
      type: 'array',
      description: 'Maladies, carences, parasites ou erreurs de culture reperes',
      items: {
        type: 'object',
        properties: {
          nom: { type: 'string' },
          gravite: { type: 'string', enum: ['faible', 'moyenne', 'elevee'] },
          symptomes: { type: 'string' },
          traitement: { type: 'string' },
        },
        required: ['nom', 'gravite', 'symptomes', 'traitement'],
        additionalProperties: false,
      },
    },
    entretien: {
      type: 'object',
      properties: {
        lumiere: { type: 'string' },
        arrosage: { type: 'string' },
        sol: { type: 'string' },
        temperature: { type: 'string' },
        engrais: { type: 'string' },
      },
      required: ['lumiere', 'arrosage', 'sol', 'temperature', 'engrais'],
      additionalProperties: false,
    },
    actions_prioritaires: {
      type: 'array',
      description: 'Les 1 a 3 choses a faire tout de suite',
      items: { type: 'string' },
    },
    toxique_animaux: {
      type: 'string',
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
  additionalProperties: false,
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
    return { error: `Format non supporte (${mediaType}). Utilise JPEG, PNG, WebP ou GIF.` };
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

app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    service: 'plant-doctor',
    model: MODEL,
    apiKey: process.env.ANTHROPIC_API_KEY ? 'configuree' : 'MANQUANTE',
    uptime: Math.floor((Date.now() - stats.startedAt) / 1000),
    analyses: stats.analyses,
    erreurs: stats.erreurs,
  });
});

app.post('/api/analyze', async (req, res) => {
  if (!process.env.ANTHROPIC_API_KEY) {
    return res.status(500).json({
      error: "ANTHROPIC_API_KEY n'est pas configuree sur le serveur.",
      hint: 'Ajoute la variable d\'environnement dans Render (Environment > Add Environment Variable).',
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

  try {
    const response = await client.messages.create({
      model: MODEL,
      max_tokens: 4000,
      system: SYSTEM_PROMPT,
      messages: [
        {
          role: 'user',
          content: [
            {
              type: 'image',
              source: {
                type: 'base64',
                media_type: parsed.mediaType,
                data: parsed.data,
              },
            },
            { type: 'text', text: question },
          ],
        },
      ],
      output_config: {
        format: {
          type: 'json_schema',
          schema: PLANT_SCHEMA,
        },
      },
    });

    const text = response.content
      .filter((block) => block.type === 'text')
      .map((block) => block.text)
      .join('');

    let result;
    try {
      result = JSON.parse(text);
    } catch (e) {
      stats.erreurs++;
      console.error('[PLANT] Reponse non parsable:', text.slice(0, 500));
      return res.status(502).json({ error: "Reponse illisible du modele, reessaie." });
    }

    stats.analyses++;
    const ms = Date.now() - started;
    console.log(
      `[PLANT] ${result.espece} | sante=${result.etat_sante} | ${result.problemes.length} probleme(s) | ${ms}ms`
    );

    res.json({
      ...result,
      meta: {
        model: MODEL,
        duree_ms: ms,
        tokens: response.usage,
      },
    });
  } catch (err) {
    stats.erreurs++;
    console.error('[PLANT] Erreur API:', err.message);

    if (err instanceof Anthropic.AuthenticationError) {
      return res.status(500).json({ error: 'Cle API invalide ou expiree.' });
    }
    if (err instanceof Anthropic.RateLimitError) {
      return res.status(429).json({ error: 'Trop de requetes, attends quelques secondes.' });
    }
    if (err instanceof Anthropic.BadRequestError) {
      return res.status(400).json({ error: `Requete refusee par l'API : ${err.message}` });
    }
    if (err instanceof Anthropic.APIError) {
      return res.status(502).json({ error: `Erreur API Claude : ${err.message}` });
    }
    res.status(500).json({ error: 'Erreur interne du serveur.' });
  }
});

app.listen(PORT, () => {
  console.log('🌱 Plant Doctor');
  console.log(`   http://localhost:${PORT}`);
  console.log(`   modele : ${MODEL}`);
  console.log(
    `   cle API : ${process.env.ANTHROPIC_API_KEY ? 'OK' : 'MANQUANTE (export ANTHROPIC_API_KEY=...)'}`
  );
});
