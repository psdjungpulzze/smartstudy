// End-to-end course creation test against prod.
// Uses correct field names from course_new_live.ex:
//   input[name="course_name"], input[name="subject"], select[name="selected_grade"]
//
// Flow: login (via existing Interactor account) → /courses/new → fill all 3 required
// fields → submit → verify navigation to /courses/:id → attempt test creation.
//
// The OAuth login uses a known-good account (clairehyj@gmail.com) created
// before the signup regression. Does not attempt signup.

import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';
import { loadCredentials } from './lib/load-credentials.mjs';

const env = loadCredentials(['TEST_ACCOUNT_PASSWORD', 'TEST_STUDENT_EMAIL', 'TEST_STUDENT_USERNAME']);

const SCREENSHOT_DIR = '/home/pulzze/Documents/GitHub/personal/funsheep/screenshots/prod-course-flow-test';
const ACCOUNT = {
  email: env.TEST_STUDENT_EMAIL,
  username: env.TEST_STUDENT_USERNAME,
  password: env.TEST_ACCOUNT_PASSWORD,
};

const results = {
  login: { ok: false, finalUrl: null, err: null },
  courseCreate: { ok: false, finalUrl: null, courseId: null, err: null },
  testCreate: { ok: false, finalUrl: null, err: null },
  screenshots: [],
  logs: [],
};

fs.mkdirSync(SCREENSHOT_DIR, { recursive: true });

async function shot(page, name) {
  const fp = path.join(SCREENSHOT_DIR, `${Date.now()}-${name}.png`);
  try { await page.screenshot({ path: fp, fullPage: true }); results.screenshots.push(fp); return fp; }
  catch (e) { return null; }
}

async function dump(page, label) {
  try {
    const url = page.url();
    const title = await page.title();
    const body = (await page.locator('body').innerText().catch(() => '')).replace(/\s+/g, ' ').slice(0, 300);
    const line = `[${label}] url=${url} title="${title}" body="${body}"`;
    console.log(line);
    results.logs.push(line);
    return { url, title, body };
  } catch (e) {
    return null;
  }
}

async function loginExistingUser(page) {
  console.log('\n=== LOGIN ===');
  await page.goto('https://funsheep.com/', { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(1500);
  await shot(page, 'login-01-landed');
  await dump(page, 'login-landed');

  // Should already be on auth.interactor.com/oauth/login
  if (!page.url().includes('auth.interactor.com')) {
    // Try clicking a login link
    const loginLink = page.locator('a:has-text("Log in"), a:has-text("Sign in"), button:has-text("Log in"), button:has-text("Sign in")').first();
    try { await loginLink.click({ timeout: 3000 }); await page.waitForTimeout(2000); } catch {}
  }

  await page.locator('input[name*="username" i], input[type="text"]').first().fill(ACCOUNT.username);
  await page.locator('input[type="password"]').first().fill(ACCOUNT.password);
  await shot(page, 'login-02-filled');
  await page.locator('button:has-text("Sign in"), button[type="submit"]').first().click();

  // Wait for callback back to funsheep
  try {
    await page.waitForURL(/funsheep\.com\/dashboard/, { timeout: 20000 });
    results.login.ok = true;
    results.login.finalUrl = page.url();
  } catch (e) {
    results.login.err = `did not reach /dashboard (currently at ${page.url()})`;
  }
  await shot(page, 'login-03-final');
  await dump(page, 'login-final');
}

async function createCourse(page) {
  console.log('\n=== COURSE CREATION ===');
  await page.goto('https://funsheep.com/courses/new', { waitUntil: 'domcontentloaded', timeout: 20000 });
  await page.waitForTimeout(2500);
  await shot(page, 'course-01-form');
  await dump(page, 'course-form');

  // Fill the three basic required fields.
  try {
    await page.locator('input[name="course_name"]').fill('Playwright Smoke Test Course');
    await page.waitForTimeout(400);
    await page.locator('input[name="subject"]').fill('Mathematics');
    await page.waitForTimeout(400);
    await page.locator('select[name="selected_grade"]').selectOption('7');
    // Wait for the textbook section to appear (triggered by phx-change once
    // subject + grade are both populated)
    await page.waitForTimeout(1200);
  } catch (e) {
    results.courseCreate.err = `fill failed: ${e.message}`;
    await shot(page, 'course-02-fill-error');
    return;
  }

  await shot(page, 'course-02-filled');
  await dump(page, 'course-filled');

  // Textbook is required. Use the custom-name path (the "I don't have a textbook"
  // button is currently broken — it sets textbook_mode to :none which fails
  // validation).
  try {
    await page.locator('button:has-text("My textbook isn\'t listed")').first().click({ timeout: 5000 });
    await page.waitForTimeout(700);
    // A "value" text input appears for the custom name
    await page.locator('input[name="value"]').first().fill('No textbook');
    await page.waitForTimeout(600);
    results.logs.push('[course-textbook] used custom-name mode');
  } catch (e) {
    results.courseCreate.err = `textbook selection failed: ${e.message}`;
    await shot(page, 'course-02b-textbook-error');
    return;
  }
  await shot(page, 'course-02c-textbook-set');

  // Submit
  await page.locator('button:has-text("Create Course"), form#course-form button[type="submit"]').first().click();

  // Expect navigation to /courses/:id (UUID)
  const courseIdRe = /\/courses\/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$/;
  try {
    await page.waitForURL(courseIdRe, { timeout: 15000 });
    results.courseCreate.ok = true;
    results.courseCreate.finalUrl = page.url();
    const m = page.url().match(courseIdRe);
    if (m) results.courseCreate.courseId = m[1];
  } catch (e) {
    results.courseCreate.err = `no nav to /courses/:id (at ${page.url()})`;
  }
  await shot(page, 'course-03-after-submit');
  await dump(page, 'course-after-submit');
}

async function createTest(page) {
  if (!results.courseCreate.courseId) {
    results.testCreate.err = 'no course was created; skipping';
    return;
  }
  console.log('\n=== TEST CREATION ===');
  const testsUrl = `https://funsheep.com/courses/${results.courseCreate.courseId}/tests/new`;
  await page.goto(testsUrl, { waitUntil: 'domcontentloaded', timeout: 20000 });
  await page.waitForTimeout(2500);
  await shot(page, 'test-01-form');
  const d = await dump(page, 'test-form');

  // Discover the form schema by dumping names of inputs + selects
  const fieldDump = await page.evaluate(() => {
    const out = [];
    document.querySelectorAll('input, select, textarea').forEach(el => {
      out.push(`${el.tagName.toLowerCase()}[name="${el.name || ''}"][type="${el.type || ''}"]`);
    });
    return out;
  });
  console.log('[test-form-fields]', fieldDump.join(', '));
  results.logs.push(`[test-form-fields] ${fieldDump.join(', ')}`);

  // Try best-effort fill based on common Phoenix form patterns
  const fillAttempts = [
    { selector: 'input[name*="name" i]', value: 'Smoke Test Quiz' },
    { selector: 'input[name*="title" i]', value: 'Smoke Test Quiz' },
    { selector: 'input[type="date"]', value: '2026-06-01' },
  ];
  for (const a of fillAttempts) {
    try {
      const el = page.locator(a.selector).first();
      if (await el.isVisible({ timeout: 500 })) {
        await el.fill(a.value);
        results.logs.push(`[test-fill] ${a.selector} = ${a.value}`);
      }
    } catch {}
  }

  await shot(page, 'test-02-filled');

  try {
    // Wait for LiveView to be connected (data-phx-main indicates connected)
    await page.waitForFunction(() => document.querySelector('[data-phx-main]') !== null, { timeout: 10000 }).catch(() => {});
    // Blur any focused input, then click the button via coordinate-free route
    await page.locator('input[name="test_date"]').first().blur().catch(() => {});
    await page.keyboard.press('Tab');
    await page.waitForTimeout(400);
    // Dispatch a synthetic submit event directly on the LiveView form
    const submitted = await page.evaluate(() => {
      const forms = Array.from(document.querySelectorAll('form[phx-submit]'));
      const target = forms.find(f => f.querySelector('button[type="submit"]')?.textContent?.match(/Schedule Test/i));
      if (!target) return { ok: false, reason: 'no-form' };
      const btn = target.querySelector('button[type="submit"]');
      target.requestSubmit(btn);
      return { ok: true, action: target.getAttribute('phx-submit') };
    });
    results.logs.push(`[test-submit] ${JSON.stringify(submitted)}`);
    try {
      await page.waitForURL(u => !u.toString().endsWith('/tests/new'), { timeout: 15000 });
    } catch {}
    await page.waitForTimeout(2000);
  } catch (e) {
    results.testCreate.err = `submit failed: ${e.message}`;
  }
  await shot(page, 'test-03-after-submit');
  await dump(page, 'test-after-submit');
  results.testCreate.finalUrl = page.url();

  // Heuristic: success if we navigated away from /tests/new
  if (!page.url().endsWith('/tests/new')) {
    results.testCreate.ok = true;
  } else {
    results.testCreate.err = results.testCreate.err || `stayed at ${page.url()}`;
  }
}

(async () => {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await context.newPage();

  page.on('pageerror', e => results.logs.push(`[pageerror] ${e.message}`));
  page.on('console', msg => { if (msg.type() === 'error') results.logs.push(`[console-error] ${msg.text()}`); });

  try {
    await loginExistingUser(page);
    if (results.login.ok) {
      await createCourse(page);
      if (results.courseCreate.ok) {
        await createTest(page);
      }
    }
  } catch (e) {
    results.logs.push(`[fatal] ${e.message}`);
  } finally {
    await browser.close();
  }

  const summary = {
    login: results.login,
    courseCreate: results.courseCreate,
    testCreate: results.testCreate,
    screenshotCount: results.screenshots.length,
    logTail: results.logs.slice(-15),
  };
  console.log('\n=== SUMMARY ===');
  console.log(JSON.stringify(summary, null, 2));

  fs.writeFileSync(path.join(SCREENSHOT_DIR, 'results.json'), JSON.stringify(results, null, 2));

  const anyFail = !results.login.ok || !results.courseCreate.ok || !results.testCreate.ok;
  process.exit(anyFail ? 1 : 0);
})();
