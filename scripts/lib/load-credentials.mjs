// Minimal .env.credentials loader for prod test scripts.
// Reads KEY=VALUE pairs (with ${VAR} interpolation) into process.env and
// returns the parsed record. Credentials live in .env.credentials at the
// repo root — file is gitignored, so nothing here touches git.
//
// Usage:
//   import { loadCredentials } from './lib/load-credentials.mjs';
//   const env = loadCredentials(['TEST_ACCOUNT_PASSWORD', 'TEST_STUDENT_EMAIL']);
//   // env.TEST_ACCOUNT_PASSWORD is guaranteed present; missing keys throw.

import fs from 'fs';
import path from 'path';
import { execSync } from 'child_process';

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
    // Interpolate ${VAR} referring to earlier-defined keys (or process.env).
    value = value.replace(/\$\{(\w+)\}/g, (_, varName) => out[varName] ?? process.env[varName] ?? '');
    out[key] = value;
  }
  return out;
}

export function loadCredentials(requiredKeys = []) {
  const envPath = path.join(repoRoot(), '.env.credentials');
  if (!fs.existsSync(envPath)) {
    throw new Error(
      `.env.credentials not found at ${envPath}. ` +
        `Copy values from a teammate or the project secret vault.`
    );
  }
  const parsed = parseEnvFile(envPath);
  // Merge into process.env (don't clobber already-set values).
  for (const [k, v] of Object.entries(parsed)) {
    if (process.env[k] === undefined) process.env[k] = v;
  }
  // Fail fast on missing required keys.
  const missing = requiredKeys.filter((k) => !process.env[k]);
  if (missing.length > 0) {
    throw new Error(
      `Missing required keys in ${envPath}: ${missing.join(', ')}. ` +
        `Add them to .env.credentials and retry.`
    );
  }
  return { ...parsed, ...Object.fromEntries(requiredKeys.map((k) => [k, process.env[k]])) };
}
