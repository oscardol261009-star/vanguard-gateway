# Discord Status Rotator

⚠️ **Attention** : ce script automatise un compte utilisateur Discord (selfbot). Cela viole les
[Conditions d'utilisation de Discord](https://discord.com/terms) et peut entraîner le
bannissement de ton compte. À utiliser à tes propres risques, sur ton propre compte uniquement.

## Ce que ça fait

Fait tourner en boucle le statut personnalisé de ton compte Discord (texte + emoji) ainsi que ton
statut de présence (en ligne / absent / ne pas déranger), à intervalle régulier, à partir de
simples fichiers texte que tu édites toi-même.

## Configuration

- `texts.txt` : une phrase de statut par ligne. Édite-le comme tu veux.
- `emojis.txt` : un emoji par ligne (optionnel, laisse vide pour aucun emoji).
- `status-config.json` :
  - `intervalSeconds` : délai entre deux changements (en secondes).
  - `emojiMode` : `"perStatus"` (l'emoji change à chaque statut) ou `"perCycle"` (l'emoji ne
    change qu'après un cycle complet de `texts.txt`).
  - `presenceRotation` : liste de statuts de présence à faire tourner
    (`online`, `idle`, `dnd`).

Les 3 fichiers sont rechargés automatiquement dès que tu les modifies : pas besoin de relancer le
script.

## Installation

```bash
npm install
cp .env.example .env
```

Mets ton token de compte Discord dans `.env` :

```
DISCORD_TOKEN=ton_token_ici
```

Pour récupérer ton token : ouvre Discord dans le navigateur, DevTools (F12) → onglet Network →
filtre `science` ou `messages` → header `Authorization`. Ne le partage JAMAIS.

## Lancer

```bash
npm run status
```
