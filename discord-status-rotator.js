// Discord Status Rotator (compte personnel / selfbot)
// Fait tourner le statut personnalisé de TON compte Discord en boucle,
// à partir de fichiers texte simples que tu édites directement.
//
// ATTENTION: automatiser un compte utilisateur viole les CGU de Discord
// (risque de bannissement du compte). Usage à tes risques.
//
// Fichiers:
//   texts.txt          - une phrase de statut par ligne
//   emojis.txt          - un emoji par ligne (optionnel, peut être vide)
//   status-config.json - intervalle, mode emoji, rotation en ligne/absent/ne pas déranger

const fs = require('fs');
const path = require('path');
const { Client } = require('discord.js-selfbot-v13');

const TOKEN = process.env.DISCORD_TOKEN;

if (!TOKEN) {
    console.error('[ERROR] Variable DISCORD_TOKEN manquante. Ajoute-la dans ton .env ou tes variables d\'environnement.');
    process.exit(1);
}

const TEXTS_PATH = path.join(__dirname, 'texts.txt');
const EMOJIS_PATH = path.join(__dirname, 'emojis.txt');
const CONFIG_PATH = path.join(__dirname, 'status-config.json');

function readLines(filePath) {
    if (!fs.existsSync(filePath)) return [];
    return fs.readFileSync(filePath, 'utf-8')
        .split('\n')
        .map(line => line.trim())
        .filter(line => line.length > 0);
}

function loadState() {
    const texts = readLines(TEXTS_PATH);
    const emojis = readLines(EMOJIS_PATH);
    const config = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf-8'));

    if (texts.length === 0) {
        throw new Error('texts.txt doit contenir au moins une ligne de statut');
    }

    return { texts, emojis, config };
}

const client = new Client();

let textIndex = 0;
let emojiIndex = 0;
let presenceIndex = 0;
let cycleCount = 0;
let rotationTimer = null;

function applyStatus(state) {
    const { texts, emojis, config } = state;

    const text = texts[textIndex % texts.length];
    const emoji = emojis.length > 0 ? emojis[emojiIndex % emojis.length] : undefined;
    const presenceList = config.presenceRotation && config.presenceRotation.length > 0
        ? config.presenceRotation
        : ['online'];
    const presence = presenceList[presenceIndex % presenceList.length];

    client.user.setPresence({
        status: presence,
        activities: [{
            name: text,
            type: 'CUSTOM_STATUS',
            state: text,
            emoji: emoji || undefined
        }]
    });

    console.log(`[STATUS] (${presence}) ${emoji ? emoji + ' ' : ''}${text}`);

    textIndex++;
    presenceIndex++;

    // Mode "perStatus": l'emoji change à chaque statut.
    // Mode "perCycle": l'emoji change seulement après un cycle complet des textes.
    if (config.emojiMode === 'perCycle') {
        if (textIndex % texts.length === 0) {
            emojiIndex++;
            cycleCount++;
        }
    } else {
        emojiIndex++;
    }
}

function startRotation(state) {
    applyStatus(state);
    rotationTimer = setInterval(() => applyStatus(state), (state.config.intervalSeconds || 15) * 1000);
}

function reload(label) {
    try {
        const state = loadState();
        clearInterval(rotationTimer);
        startRotation(state);
        console.log(`[RELOAD] ${label} rechargé`);
    } catch (e) {
        console.error('[RELOAD ERROR]', e.message);
    }
}

client.on('ready', () => {
    console.log(`[READY] Connecté en tant que ${client.user.tag}`);

    const state = loadState();
    startRotation(state);

    // Recharge automatiquement les fichiers si tu les modifies pendant que ça tourne
    fs.watchFile(TEXTS_PATH, { interval: 2000 }, () => reload('texts.txt'));
    fs.watchFile(EMOJIS_PATH, { interval: 2000 }, () => reload('emojis.txt'));
    fs.watchFile(CONFIG_PATH, { interval: 2000 }, () => reload('status-config.json'));
});

client.login(TOKEN);
