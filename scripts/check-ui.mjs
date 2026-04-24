#!/usr/bin/env node
// Visual health check for a running FunSheep dev server.
//
// Launches headless Chromium, navigates to <baseUrl><path>, waits for
// <selector>, captures page errors, and exits 0 on success. Use this to
// catch "PID is up but the UI is broken" scenarios that HTTP-code checks miss.
//
// Usage: node scripts/check-ui.mjs <baseUrl> [<path>] [<selector>]
// Example: node scripts/check-ui.mjs http://localhost:4040 /auth/login "#login-username"
//
// Exit codes:
//   0  page rendered and selector found, no JS errors
//   1  navigation failed / HTTP >= 400 / selector timed out
//   2  page loaded but uncaught JS errors on the page
//   3  chromium browser binary not installed

import { chromium } from 'playwright';

const baseUrl = process.argv[2] || 'http://localhost:4040';
const path = process.argv[3] || '/auth/login';
const selector = process.argv[4] || '#login-username';
const timeoutMs = parseInt(process.env.CHECK_UI_TIMEOUT || '15000', 10);

const url = baseUrl.replace(/\/$/, '') + path;

let browser;
try {
  browser = await chromium.launch({ headless: true });
} catch (e) {
  console.error(`chromium launch failed: ${e.message}`);
  console.error('Install the browser binary: npx playwright install chromium');
  process.exit(3);
}

const page = await browser.newPage();
const pageErrors = [];
page.on('pageerror', (err) => pageErrors.push(`pageerror: ${err.message}`));
page.on('console', (msg) => {
  if (msg.type() === 'error') pageErrors.push(`console.error: ${msg.text()}`);
});

try {
  const resp = await page.goto(url, { waitUntil: 'domcontentloaded', timeout: timeoutMs });
  if (!resp) {
    console.error(`no response from ${url}`);
    process.exit(1);
  }
  const status = resp.status();
  if (status >= 400) {
    console.error(`HTTP ${status} at ${url}`);
    process.exit(1);
  }
  await page.waitForSelector(selector, { timeout: timeoutMs });

  if (pageErrors.length > 0) {
    console.error(`UI rendered at ${url} but had JS errors:`);
    for (const err of pageErrors) console.error(`  ${err}`);
    process.exit(2);
  }

  console.log(`OK ${url} (HTTP ${status}, selector ${JSON.stringify(selector)} found)`);
  process.exit(0);
} catch (e) {
  console.error(`FAIL ${url}: ${e.message}`);
  if (pageErrors.length > 0) {
    console.error('  JS errors seen before failure:');
    for (const err of pageErrors) console.error(`    ${err}`);
  }
  process.exit(1);
} finally {
  await browser.close();
}
