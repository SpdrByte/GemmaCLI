/**
 * lib/voice_live.js - Multimodal Live Voice-Only Framework
 * Uses realtime_input for low-latency two-way audio conversation.
 */
const { spawn } = require('child_process');
const fs   = require('fs');
const path = require('path');
const os   = require('os');
const WebSocket = require('ws');
const readline = require('readline');

// ─── Keyboard Listener ────────────────────────────────────────────────────────
readline.emitKeypressEvents(process.stdin);
if (process.stdin.isTTY) {
    process.stdin.setRawMode(true);
}

process.stdin.on('keypress', (str, key) => {
    if (key.name === 'escape') {
        log('INFO', 'SYS', 'Escape pressed. Closing session...');
        process.exit(0);
    }
    if (key.ctrl && key.name === 'c') {
        process.exit(0);
    }
});

// ─── Log directory ────────────────────────────────────────────────────────────
const PREFERRED_LOG_DIR = path.join('C:\\Users\\kevin\\Documents\\AI\\GemmaCLI\\temp');
let LOG_DIR;
try {
    if (!fs.existsSync(PREFERRED_LOG_DIR)) fs.mkdirSync(PREFERRED_LOG_DIR, { recursive: true });
    LOG_DIR = PREFERRED_LOG_DIR;
} catch (_) {
    LOG_DIR = os.tmpdir();
}

const RUN_TS   = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
const LOG_FILE = path.join(LOG_DIR, `voice_run_${RUN_TS}.log`);

function log(level, category, msg, extra) {
    const ts    = new Date().toISOString();
    const line  = `[${ts}] [${level}] [${category}] ${msg}`;
    const full  = extra !== undefined
        ? line + '\n    DATA: ' + JSON.stringify(extra, null, 2).replace(/\n/g, '\n    ')
        : line;

    fs.appendFileSync(LOG_FILE, full + '\n');
    const colors = { DEBUG: '\x1b[90m', INFO: '\x1b[36m', WARN: '\x1b[33m', ERROR: '\x1b[31m' };
    console.log((colors[level] || '') + full + '\x1b[0m');
}

log('INFO', 'STARTUP', `Voice Session log → ${LOG_FILE}`);

// ─── Args ────────────────────────────────────────────────────────────────────
const API_KEY  = process.env.GEMINI_API_KEY || process.argv[2];
const MODEL_ID = process.argv[3] || 'gemini-3.1-flash-live-preview';
const MIC_NAME = process.argv[4] || 'Microphone Array (Realtek(R) Audio)';
const VOICE_NAME = process.argv[5] || 'Puck';

if (!API_KEY) {
    log('ERROR', 'STARTUP', 'No API key provided. Set GEMINI_API_KEY or pass as first arg.');
    process.exit(1);
}

const WS_URL = `wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=${API_KEY}`;

const stats = {
    msgSent: 0,
    msgRecv: 0,
    audioInChunks: 0,
    audioOutChunks: 0,
};

// ─── Main ─────────────────────────────────────────────────────────────────────
async function main() {
    log('INFO', 'WS', `Connecting to Gemini Voice (${MODEL_ID})...`);
    const ws = new WebSocket(WS_URL);

    ws.onopen = () => {
        log('INFO', 'WS', 'WebSocket Connected.');
        
        const setupMsg = {
            setup: {
                model: `models/${MODEL_ID}`,
                systemInstruction: {
                    parts: [{
                       text: "You are a helpful, conversational AI. You are talking to the user via a live audio stream. Keep your responses concise and natural. You don't need to say 'I hear you' every time, just respond to what the user says."
                    }]
                },
                generationConfig: {
                    responseModalities: ["AUDIO"], 
                    speechConfig: {
                        voiceConfig: {
                            prebuiltVoiceConfig: { voiceName: VOICE_NAME }
                        }
                    }
                }
            }
        };
        sendMsg(ws, setupMsg, 'SETUP');
    };

    ws.onmessage = async (event) => {
        stats.msgRecv++;
        try {
            let rawData = event.data;
            if (rawData instanceof Blob) rawData = await rawData.text();
            else if (typeof rawData !== 'string') rawData = rawData.toString('utf8');

            const data = JSON.parse(rawData);
            
            if (data.setupComplete) {
                log('INFO', 'SETUP', 'Setup Complete. Listening...');
                startMicStream(ws);
            }

            if (data.serverContent) {
                const sc = data.serverContent;
                if (sc.modelTurn) {
                    sc.modelTurn.parts.forEach(part => {
                        if (part.text) {
                            console.log(`\n\x1b[34m[GEMINI]: ${part.text}\x1b[0m`);
                        }
                        if (part.inlineData && part.inlineData.mimeType.startsWith('audio/')) {
                            stats.audioOutChunks++;
                            process.stdout.write('\x1b[32m>\x1b[0m'); // Output indicator
                            playAudio(part.inlineData.data);
                        }
                    });
                }
            }

            if (data.error) log('ERROR', 'API', 'Server Error', data.error);

        } catch (e) {
            log('ERROR', 'HANDLER', `Message error: ${e.message}`);
        }
    };

    ws.onerror = (err) => log('ERROR', 'WS', 'WebSocket Error', err);
    ws.onclose = (event) => {
        log('WARN', 'WS', `WebSocket Closed. Code: ${event.code}, Reason: ${event.reason}`);
        log('INFO', 'STATS', 'Final Statistics', stats);
        process.exit(0);
    };
}

// ─── Helpers ──────────────────────────────────────────────────────────────────
function sendMsg(ws, obj, label) {
    if (ws.readyState !== WebSocket.OPEN) return;
    const json = JSON.stringify(obj);
    stats.msgSent++;
    
    const logSafe = JSON.parse(json);
    redactBase64(logSafe);
    fs.appendFileSync(LOG_FILE, `\n--- SENT #${stats.msgSent} [${label}] ---\n${JSON.stringify(logSafe, null, 2)}\n---\n`);
    
    ws.send(json);
}

function redactBase64(obj) {
    if (!obj || typeof obj !== 'object') return;
    for (const k of Object.keys(obj)) {
        if (k === 'data' && typeof obj[k] === 'string' && obj[k].length > 200) {
            obj[k] = `[BASE64 redacted]`;
        } else {
            redactBase64(obj[k]);
        }
    }
}

function startMicStream(ws) {
    log('INFO', 'MIC', `Capturing from "${MIC_NAME}"...`);
    
    // Capture 16-bit Little Endian PCM at 16kHz
    const ffmpeg = spawn('ffmpeg', [
        '-f', 'dshow',
        '-i', `audio=${MIC_NAME}`,
        '-ac', '1', 
        '-ar', '16000', 
        '-f', 's16le', 
        'pipe:1'
    ], { stdio: ['ignore', 'pipe', 'ignore'] });

    ffmpeg.stdout.on('data', (chunk) => {
        if (ws.readyState === WebSocket.OPEN) {
            stats.audioInChunks++;
            process.stdout.write('\x1b[90m<\x1b[0m'); // Input indicator
            
            const audioMessage = {
                realtime_input: {
                    audio: {
                        mime_type: 'audio/pcm;rate=16000',
                        data: chunk.toString('base64')
                    }
                }
            };
            sendMsg(ws, audioMessage, `AUDIO_IN_${stats.audioInChunks}`);
        }
    });

    ffmpeg.on('close', () => log('WARN', 'MIC', 'ffmpeg mic stream closed.'));
}

let ffplayProc = null;
function playAudio(base64) {
    const audioBuffer = Buffer.from(base64, 'base64');
    
    if (!ffplayProc) {
        // Output from Gemini is usually 24kHz mono PCM
        ffplayProc = spawn('ffplay', [
            '-nodisp', '-fflags', 'nobuffer', 
            '-f', 's16le', '-ar', '24000', '-ch_layout', 'mono', '-'
        ], { stdio: ['pipe', 'ignore', 'ignore'] });
        
        ffplayProc.on('close', () => { ffplayProc = null; });
    }
    
    if (ffplayProc?.stdin?.writable) {
        try {
            ffplayProc.stdin.write(audioBuffer);
        } catch (e) {}
    }
}

main().catch(err => log('ERROR', 'MAIN', err.message));
