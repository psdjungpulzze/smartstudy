// CommonJS twin of lib/load-credentials.mjs — same behavior, `require`-compatible.
// Reads .env.credentials at the repo root and merges into process.env.
// The .env.credentials file is gitignored (see .gitignore line 70).

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

function repoRoot() {
  return execSync('git rev-parse --show-toplevel', { encoding: 'utf8' }).trim();
}

function parseEnvFile(filePath) {
  const raw = fs.readFileSync(filePath, 'utf8');
  const out = {};
  for (const rawLine of raw.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) continue;
    const eq = line.indexOf('=');
    if (eq < 0) continue;
    const key = line.slice(0, eq).trim();
    let value = line.slice(eq + 1).trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    value = value.replace(/\$\{(\w+)\}/g, (_, varName) =>
      out[varName] !== undefined ? out[varName] : process.env[varName] || ''
    );
    out[key] = value;
  }
  return out;
}

function loadCredentials(requiredKeys = []) {
  const envPath = path.join(repoRoot(), '.env.credentials');
  if (!fs.existsSync(envPath)) {
    throw new Error(
      `.env.credentials not found at ${envPath}. ` +
        `Copy values from a teammate or the project secret vault.`
    );
  }
  const parsed = parseEnvFile(envPath);
  for (const [k, v] of Object.entries(parsed)) {
    if (process.env[k] === undefined) process.env[k] = v;
  }
  const missing = requiredKeys.filter((k) => !process.env[k]);
  if (missing.length > 0) {
    throw new Error(
      `Missing required keys in ${envPath}: ${missing.join(', ')}. ` +
        `Add them to .env.credentials and retry.`
    );
  }
  const result = { ...parsed };
  for (const k of requiredKeys) result[k] = process.env[k];
  return result;
}

module.exports = { loadCredentials };
