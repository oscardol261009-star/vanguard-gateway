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
        
        // Construire le payload protobuf simulé
        // NOTE: Ceci est une implémentation simplifiée
        // Pour production, utiliser google-protobuf avec les vrais schemas Vanguard
        const protobufPayload = buildVanguardProtobuf(gametoken, sid);
        
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

// Helper: Construire payload protobuf Vanguard
function buildVanguardProtobuf(jwt, sid) {
    // Implémentation simplifiée
    // En production, utiliser le vrai schema protobuf de Vanguard
    
    const jwtBytes = Buffer.from(jwt, 'utf-8');
    const sidBytes = sid ? Buffer.from(sid, 'utf-8') : Buffer.alloc(0);
    
    // Structure basique (à adapter selon le vrai schema):
    // Field 1 (varint): version = 1
    // Field 2 (length-delimited): JWT string
    // Field 3 (length-delimited): SID string (optionnel)
    
    const parts = [];
    
    // Version field (field number 1, wire type 0 = varint)
    parts.push(Buffer.from([0x08, 0x01])); // field 1, value 1
    
    // JWT field (field number 2, wire type 2 = length-delimited)
    const jwtLengthVarint = encodeVarint(jwtBytes.length);
    parts.push(Buffer.from([0x12])); // field 2, wire type 2
    parts.push(jwtLengthVarint);
    parts.push(jwtBytes);
    
    // SID field si présent (field number 3, wire type 2)
    if (sidBytes.length > 0) {
        const sidLengthVarint = encodeVarint(sidBytes.length);
        parts.push(Buffer.from([0x1A])); // field 3, wire type 2
        parts.push(sidLengthVarint);
        parts.push(sidBytes);
    }
    
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
