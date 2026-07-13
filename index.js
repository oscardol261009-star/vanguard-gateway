// Vanguard Gateway Server - Node.js
// Hébergeable sur Render.com gratuitement

const express = require('express');
const https = require('https');
const http = require('http');

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware pour parser JSON
app.use(express.json({ limit: '10mb' }));
app.use(express.text({ limit: '10mb' }));

// CORS headers pour autoriser les requêtes cross-origin
app.use((req, res, next) => {
    res.header('Access-Control-Allow-Origin', '*');
    res.header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.header('Access-Control-Allow-Headers', 'Content-Type, Authorization');
    if (req.method === 'OPTIONS') {
        return res.sendStatus(200);
    }
    next();
});

// Logging middleware
app.use((req, res, next) => {
    const timestamp = new Date().toISOString();
    console.log(`[${timestamp}] ${req.method} ${req.path} - IP: ${req.ip}`);
    next();
});

// Helper: Base64 URL-safe decode
function base64UrlDecode(str) {
    str = str.replace(/-/g, '+').replace(/_/g, '/');
    while (str.length % 4) {
        str += '=';
    }
    return Buffer.from(str, 'base64').toString('utf-8');
}

// Helper: Base64 URL-safe encode
function base64UrlEncode(str) {
    return Buffer.from(str)
        .toString('base64')
        .replace(/\+/g, '-')
        .replace(/\//g, '_')
        .replace(/=/g, '');
}

// Helper: Valider JWT format
function isValidJWT(token) {
    if (!token || typeof token !== 'string') return false;
    const parts = token.split('.');
    if (parts.length !== 3) return false;
    if (!token.startsWith('eyJ')) return false;
    return true;
}

// Helper: Extraire expiration du JWT
function getJWTExpiration(token) {
    try {
        const parts = token.split('.');
        if (parts.length !== 3) return null;
        const payload = JSON.parse(base64UrlDecode(parts[1]));
        return payload.exp || null;
    } catch (e) {
        return null;
    }
}

// Helper: Vérifier si JWT est expiré
function isJWTExpired(token) {
    const exp = getJWTExpiration(token);
    if (!exp) return true;
    const now = Math.floor(Date.now() / 1000);
    return now >= exp;
}

// Helper: Forward vers Vanguard avec retry logic
function forwardToVanguard(region, payload, callback) {
    const host = `${region}.vg.ac.pvp.net`;
    const port = 8443;
    const path = '/vanguard/v1/gateway';
    
    const options = {
        hostname: host,
        port: port,
        path: path,
        method: 'POST',
        headers: {
            'Content-Type': 'application/x-protobuf',
            'Content-Length': Buffer.byteLength(payload),
            'User-Agent': 'RiotClient/63.0.9.4909983 (Windows;10;;Professional, x64)'
        },
        rejectUnauthorized: false // Important: Vanguard utilise des certs custom
    };
    
    let attempts = 0;
    const maxAttempts = 3;
    
    function tryRequest() {
        attempts++;
        
        const req = https.request(options, (res) => {
            let data = [];
            
            res.on('data', (chunk) => {
                data.push(chunk);
            });
            
            res.on('end', () => {
                const responseBuffer = Buffer.concat(data);
                callback(null, {
                    statusCode: res.statusCode,
                    headers: res.headers,
                    body: responseBuffer
                });
            });
        });
        
        req.on('error', (err) => {
            console.error(`[ERROR] Vanguard request failed (attempt ${attempts}/${maxAttempts}):`, err.message);
            if (attempts < maxAttempts) {
                setTimeout(tryRequest, 1000 * attempts); // Backoff: 1s, 2s, 3s
            } else {
                callback(err, null);
            }
        });
        
        req.on('timeout', () => {
            console.error(`[TIMEOUT] Vanguard request timed out (attempt ${attempts}/${maxAttempts})`);
            req.destroy();
            if (attempts < maxAttempts) {
                setTimeout(tryRequest, 1000 * attempts);
            } else {
                callback(new Error('Request timeout'), null);
            }
        });
        
        req.setTimeout(15000); // 15 second timeout
        req.write(payload);
        req.end();
    }
    
    tryRequest();
}

// Route: Health check
app.get('/', (req, res) => {
    res.json({
        status: 'online',
        service: 'Vanguard Gateway',
        version: '2.0',
        timestamp: new Date().toISOString(),
        endpoints: {
            '/gw.php': 'POST - Main gateway endpoint',
            '/health': 'GET - Health check',
            '/stats': 'GET - Server statistics'
        }
    });
});

app.get('/health', (req, res) => {
    res.json({ status: 'healthy', uptime: process.uptime() });
});

// Stats tracking
let stats = {
    totalRequests: 0,
    successfulRequests: 0,
    failedRequests: 0,
    invalidTokens: 0,
    vanguardErrors: 0,
    startTime: Date.now()
};

app.get('/stats', (req, res) => {
    res.json({
        ...stats,
        uptime: process.uptime(),
        uptimeFormatted: formatUptime(process.uptime())
    });
});

function formatUptime(seconds) {
    const d = Math.floor(seconds / 86400);
    const h = Math.floor((seconds % 86400) / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    const s = Math.floor(seconds % 60);
    return `${d}d ${h}h ${m}m ${s}s`;
}

// Route principale: /gw.php (compatible avec l'émulateur existant)
app.post('/gw.php', async (req, res) => {
    stats.totalRequests++;
    
    try {
        const { action, game, gametoken, sid } = req.body;
        
        // Validation basique
        if (!action || !game || !gametoken) {
            stats.failedRequests++;
            return res.status(400).json({
                error: 'Missing required fields',
                required: ['action', 'game', 'gametoken']
            });
        }
        
        if (action !== 'auth' || game !== 'valo') {
            stats.failedRequests++;
            return res.status(400).json({
                error: 'Invalid action or game',
                supported: { action: 'auth', game: 'valo' }
            });
        }
        
        // Valider JWT
        if (!isValidJWT(gametoken)) {
            stats.invalidTokens++;
            stats.failedRequests++;
            return res.status(400).json({
                error: 'Invalid JWT format',
                hint: 'JWT must start with eyJ and contain 3 parts separated by dots'
            });
        }
        
        // Vérifier expiration (soft check - on laisse Vanguard décider en final)
        if (isJWTExpired(gametoken)) {
            console.log('[WARN] JWT appears expired by claim, forwarding anyway for Vanguard to decide');
        }
        
        console.log(`[AUTH] Processing JWT for game: ${game}, sid: ${sid || 'none'}`);
        
        const rawProtobuf = buildVanguardProtobuf(gametoken, sid);
        
        // Clé publique officielle de Vanguard
        const vanguardPublicKey = "-----BEGIN PUBLIC KEY-----\n" +
            "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAz7Vh5LOgV9FxsyeXlvP6O\n" +
            "IfD0BFDv65A4wG6pgKO5EbJ6zSxsnU/fkFJeSjE8hJxX2CeEV9XODahl2ofF/jfTv\n" +
            "2GhQIJt7ePFT6s4M6ZmDiU/FC5nlJREA3FmQy7VYzPhCy0tLJOaFtZSgi3Scx2az5\n" +
            "AJEPP/XKyphY0hF1UFw8dUgVa/NQvXZtgTtnt+8WRcBwDcryKsQIepK4u6xBLYdhR\n" +
            "+U6zuQ3KcudI3/Ov4glRYem/XjtGBpGlPLdxbT60tPthcBcWDPWbza9FdrrhhRzNR\n" +
            "3bFxreqQW2j1o+SW55+WoDJ5ZhLsdcoUkJL7Ecex+vrzJD3eI8fiEz2TaWOJwIDAQAB\n" +
            "-----END PUBLIC KEY-----";

        const protobufPayload = buildPayload(rawProtobuf, vanguardPublicKey, "\x03");
        
        // Détecter région depuis le JWT (ou utiliser EU par défaut)
        const region = extractRegionFromJWT(gametoken) || 'eu';
        
        // Forward vers Vanguard
        forwardToVanguard(region, protobufPayload, (err, vanguardResponse) => {
            if (err) {
                stats.vanguardErrors++;
                stats.failedRequests++;
                console.error('[ERROR] Vanguard forward failed:', err.message);
                return res.status(503).json({
                    error: 'Vanguard server unreachable',
                    details: err.message
                });
            }
            
            if (vanguardResponse.statusCode === 200) {
                stats.successfulRequests++;
                
                // Encoder la réponse en base64 URL-safe
                const encodedPayload = base64UrlEncode(vanguardResponse.body.toString('binary'));
                
                return res.json({
                    success: true,
                    data: encodedPayload,
                    region: region,
                    timestamp: Date.now()
                });
            } else {
                stats.failedRequests++;
                console.error(`[ERROR] Vanguard returned status ${vanguardResponse.statusCode}`);
                return res.status(vanguardResponse.statusCode).json({
                    error: 'Vanguard authentication failed',
                    statusCode: vanguardResponse.statusCode,
                    hint: getVanguardErrorHint(vanguardResponse.statusCode)
                });
            }
        });
        
    } catch (error) {
        stats.failedRequests++;
        console.error('[EXCEPTION] Gateway error:', error);
        res.status(500).json({
            error: 'Internal gateway error',
            message: error.message
        });
    }
});

const crypto = require('crypto');

// Helper: Encapsuler et chiffrer le payload (identique à gateway.php build_payload)
function buildPayload(data, pubkey, typeByte) {
    const key = crypto.randomBytes(32);
    const iv = crypto.randomBytes(12);
    
    const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
    const ciphertext = Buffer.concat([cipher.update(data), cipher.final()]);
    const tag = cipher.getAuthTag();
    
    const rsaEncKey = crypto.publicEncrypt({
        key: pubkey,
        padding: crypto.constants.RSA_PKCS1_OAEP_PADDING,
        oaepHash: 'sha512'
    }, key);
    
    // Header Riot Games standard
    const ritoHeader = Buffer.from('52470100', 'hex');
    const ritoPayload = Buffer.concat([ritoHeader, rsaEncKey, iv, ciphertext, tag]);
    
    const outerWrapper = Buffer.concat([
        Buffer.from([0x08, typeByte.charCodeAt(0)]),
        Buffer.from([0x12]),
        encodeVarint(ritoPayload.length),
        ritoPayload
    ]);
    
    return outerWrapper;
}

// Helper: Construire le vrai payload protobuf Vanguard AuthenticationRequest
function buildVanguardProtobuf(jwt, sid) {
    const parts = [];
    
    // 1. machineId (field 1, string)
    const machineId = "my doc whitelisted hwid 0o0o0o0o0";
    const machineIdBytes = Buffer.from(machineId, 'utf-8');
    parts.push(Buffer.from([0x0A]));
    parts.push(encodeVarint(machineIdBytes.length));
    parts.push(machineIdBytes);
    
    // 2. field2 (field 2, submessage Sub2)
    // Sub2: a=1 (field 1), b=2 (field 2), version="10.0.19045" (field 3)
    const sub2Parts = [];
    sub2Parts.push(Buffer.from([0x08, 0x01])); // a=1
    sub2Parts.push(Buffer.from([0x10, 0x02])); // b=2
    const osVerBytes = Buffer.from("10.0.19045", 'utf-8');
    sub2Parts.push(Buffer.from([0x1A]));
    sub2Parts.push(encodeVarint(osVerBytes.length));
    sub2Parts.push(osVerBytes);
    const sub2Message = Buffer.concat(sub2Parts);
    parts.push(Buffer.from([0x12]));
    parts.push(encodeVarint(sub2Message.length));
    parts.push(sub2Message);
    
    // 3. gameToken (field 3, string)
    const jwtBytes = Buffer.from(jwt, 'utf-8');
    parts.push(Buffer.from([0x1A]));
    parts.push(encodeVarint(jwtBytes.length));
    parts.push(jwtBytes);
    
    // 4. externalSid (field 4, string)
    if (sid) {
        const sidBytes = Buffer.from(sid, 'utf-8');
        parts.push(Buffer.from([0x22]));
        parts.push(encodeVarint(sidBytes.length));
        parts.push(sidBytes);
    }
    
    // 5. clientRsaPublicKey (field 5, string)
    const clientPublicKey = "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAxeE1IYzUyaLOGSNGW5aWW0E8te3f\nJfBf8BYimapm/H69YNBl29ZCSf0ntyy6PMqXcEXGim5NfDjJ6CWa9y6+BG1/KpNWYBe3qLw3\nu+Zdg4LdkkVANWiSPAcaI/MIpVsnVjve7xzuHk1ZAlil3haA2r2C0mBIHX4EIJozNoWk9M4O\nzsRHWNmKh4icjHTJoE+5tX/D1RNgCmPnKVGS+40cX6cXWqX0I1v8eIV2k6uH9e6Ut8aSVQeV\n01upa2Kq1WYjsD6Gw9SM3C980tP1cXvqjmOKOqv12Dzo8nwBVr8MbuC86XIHtT9NtOFB4ogF\n2+55HtCL+PUGdf0S/dGM7c746QIDAQAB\n";
    const clientPubKeyBytes = Buffer.from(clientPublicKey, 'utf-8');
    parts.push(Buffer.from([0x2A]));
    parts.push(encodeVarint(clientPubKeyBytes.length));
    parts.push(clientPubKeyBytes);
    
    // 6. gameId (field 6, string)
    const gameIdBytes = Buffer.from("com.riotgames.valorant", 'utf-8');
    parts.push(Buffer.from([0x32]));
    parts.push(encodeVarint(gameIdBytes.length));
    parts.push(gameIdBytes);
    
    // 7. bootState (field 7, varint)
    parts.push(Buffer.from([0x38, 0x03]));
    
    // 8 & 9. version1 & version2 (field 8 & 9, submessage vg_version)
    // vg_version: a=1, b=18, c=3, d=77
    const vgVerParts = [];
    vgVerParts.push(Buffer.from([0x08, 0x01]));  // a=1
    vgVerParts.push(Buffer.from([0x10, 0x12]));  // b=18
    vgVerParts.push(Buffer.from([0x18, 0x03]));  // c=3
    vgVerParts.push(Buffer.from([0x20, 0x4D]));  // d=77 (0x4D = 77)
    const vgVerMessage = Buffer.concat(vgVerParts);
    
    parts.push(Buffer.from([0x42]));
    parts.push(encodeVarint(vgVerMessage.length));
    parts.push(vgVerMessage);
    
    parts.push(Buffer.from([0x4A]));
    parts.push(encodeVarint(vgVerMessage.length));
    parts.push(vgVerMessage);
    
    return Buffer.concat(parts);
}

// Helper: Encoder varint (protobuf)
function encodeVarint(value) {
    const bytes = [];
    while (value > 127) {
        bytes.push((value & 0x7F) | 0x80);
        value >>>= 7;
    }
    bytes.push(value);
    return Buffer.from(bytes);
}

// Helper: Extraire région du JWT
function extractRegionFromJWT(jwt) {
    try {
        const parts = jwt.split('.');
        const payload = JSON.parse(base64UrlDecode(parts[1]));
        
        // Riot JWT contient souvent "affinity" ou "region" dans les claims
        if (payload.affinity) return payload.affinity.toLowerCase();
        if (payload.region) return payload.region.toLowerCase();
        if (payload.pp && payload.pp.r) return payload.pp.r.toLowerCase();
        
        // Fallback: détecter depuis l'issuer ou audience
        if (payload.iss && payload.iss.includes('eu')) return 'eu';
        if (payload.aud && payload.aud.includes('eu')) return 'eu';
        
    } catch (e) {
        console.log('[WARN] Could not extract region from JWT, defaulting to EU');
    }
    return 'eu';
}

// Helper: Hints pour erreurs Vanguard
function getVanguardErrorHint(statusCode) {
    const hints = {
        400: 'Malformed protobuf payload',
        401: 'Invalid or expired JWT token',
        403: 'Account banned or restricted',
        429: 'Rate limited by Vanguard',
        500: 'Vanguard internal server error',
        503: 'Vanguard service unavailable'
    };
    return hints[statusCode] || 'Unknown error';
}

// Self-ping toutes les 14 minutes pour garder Render éveillé (free tier = sleep après 15min)
const RENDER_URL = process.env.RENDER_EXTERNAL_URL || null;
if (RENDER_URL) {
    setInterval(() => {
        const url = new URL(RENDER_URL + '/health');
        const mod = url.protocol === 'https:' ? https : http;
        const req = mod.get({ hostname: url.hostname, path: url.pathname, port: url.port || (url.protocol === 'https:' ? 443 : 80) }, () => {
            console.log('[KEEPALIVE] Self-ping sent to keep Render awake');
        });
        req.on('error', () => {});
        req.end();
    }, 14 * 60 * 1000);
}

// Graceful shutdown
process.on('SIGTERM', () => {
    console.log('[SHUTDOWN] SIGTERM received, closing server...');
    server.close(() => {
        console.log('[SHUTDOWN] Server closed');
        process.exit(0);
    });
});

process.on('SIGINT', () => {
    console.log('[SHUTDOWN] SIGINT received, closing server...');
    server.close(() => {
        console.log('[SHUTDOWN] Server closed');
        process.exit(0);
    });
});

// Start server
const server = app.listen(PORT, '0.0.0.0', () => {
    console.log('════════════════════════════════════════════════════════');
    console.log('  🔥 VANGUARD GATEWAY SERVER');
    console.log('════════════════════════════════════════════════════════');
    console.log(`  Status    : ONLINE`);
    console.log(`  Port      : ${PORT}`);
    console.log(`  Version   : 2.0`);
    console.log(`  Node.js   : ${process.version}`);
    console.log(`  Platform  : ${process.platform}`);
    console.log(`  Started   : ${new Date().toISOString()}`);
    console.log('════════════════════════════════════════════════════════');
    console.log('  Endpoints:');
    console.log('    POST /gw.php    - Main gateway');
    console.log('    GET  /health    - Health check');
    console.log('    GET  /stats     - Statistics');
    console.log('════════════════════════════════════════════════════════');
});
