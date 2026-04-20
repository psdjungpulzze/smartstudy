// Retry login-through-end-of-flow now that we know:
// - Landing page = login form (Username + Password), NOT email+password
// - Registration was local, not OAuth (no redirect to auth.interactor.com)
// - Registration shows "Check your email" — try logging in anyway to see if verification is hard-blocked

const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const BASE = 'https://funsheep.com';
const PASSWORD = 'Abcdef123456#';
const SCREENSHOTS_ROOT = '/home/pulzze/Documents/GitHub/personal/funsheep/screenshots';

function shot(page, dir, name) {
  const p = path.join(SCREENSHOTS_ROOT, dir, `${name}.png`);
  fs.mkdirSync(path.dirname(p), { recursive: true });
  return page.screenshot({ path: p, fullPage: true }).then(() => p);
}

async function safeClick(page, selectors, timeout = 4000) {
  for (const sel of selectors) {
    try {
      const el = await page.waitForSelector(sel, { timeout: 1500, state: 'visible' });
      if (el) { await el.click(); return sel; }
    } catch {}
  }
  return null;
}

async function findInput(page, selectors) {
  for (const sel of selectors) {
    try {
      const el = await page.waitForSelector(sel, { timeout: 1500, state: 'visible' });
      if (el) return el;
    } catch {}
  }
  return null;
}

const out = { tried: [], login: {}, course: {}, test: {} };

async function tryLogin(browser, identifier) {
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await ctx.newPage();
  const dir = 'prod-verify-login';
  const r = { status: 'pending', notes: [], screenshots: [], identifier };
  try {
    console.log(`\n--- Login attempt: ${identifier} ---`);
    await page.goto(BASE, { waitUntil: 'domcontentloaded', timeout: 30000 });
    r.screenshots.push(await shot(page, dir, `try_${identifier.replace(/[^a-z0-9]/gi, '_')}_01_landing`));

    const userField = await findInput(page, [
      'input[name="username"]',
      'input[name="user"]',
      'input[name*="user"]',
      'input[placeholder*="sername" i]',
      'input[type="text"]:first-of-type',
    ]);
    const passField = await findInput(page, [
      'input[type="password"]',
      'input[name="password"]',
    ]);

    if (!userField || !passField) {
      r.status = 'fail';
      r.notes.push('Login form fields not found on landing page');
      return { r, ctx, page };
    }

    await userField.fill(identifier);
    await passField.fill(PASSWORD);
    r.screenshots.push(await shot(page, dir, `try_${identifier.replace(/[^a-z0-9]/gi, '_')}_02_filled`));

    await safeClick(page, [
      'button:has-text("Let\'s Go")',
      'button[type="submit"]',
      'button:has-text("Log in")',
      'button:has-text("Login")',
      'button:has-text("Sign in")',
      'input[type="submit"]',
    ]);

    await page.waitForLoadState('networkidle', { timeout: 15000 }).catch(() => {});
    await page.waitForTimeout(3000);
    r.screenshots.push(await shot(page, dir, `try_${identifier.replace(/[^a-z0-9]/gi, '_')}_03_after`));
    console.log(`  final url: ${page.url()}`);

    const body = await page.evaluate(() => document.body.innerText).catch(() => '');
    const urlChanged = page.url() !== BASE + '/' && page.url() !== BASE;
    const stillOnLogin = /welcome back/i.test(body) || /username/i.test(body.slice(0, 200));

    if (urlChanged && !stillOnLogin) {
      r.status = 'pass';
      r.notes.push(`Logged in. URL: ${page.url()}`);
    } else if (/verify|check your email|not verified/i.test(body)) {
      r.status = 'blocked_verification';
      r.notes.push(`Email verification required: ${body.slice(0, 400).replace(/\s+/g, ' ')}`);
    } else if (/invalid|incorrect|wrong|error|not found/i.test(body)) {
      r.status = 'fail';
      r.notes.push(`Error: ${body.slice(0, 400).replace(/\s+/g, ' ')}`);
    } else {
      r.status = 'unclear';
      r.notes.push(`URL: ${page.url()}`);
      r.notes.push(`Body: ${body.slice(0, 400).replace(/\s+/g, ' ')}`);
    }
    return { r, ctx, page };
  } catch (e) {
    r.status = 'error';
    r.notes.push(`Exception: ${e.message}`);
    return { r, ctx, page };
  }
}

async function createCourse(page) {
  const dir = 'prod-verify-course';
  const r = { status: 'pending', notes: [], screenshots: [] };
  try {
    console.log(`\n=== Create course ===`);
    await page.waitForTimeout(1500);
    r.screenshots.push(await shot(page, dir, '01_dashboard'));
    console.log(`  dashboard url: ${page.url()}`);

    const clicked = await safeClick(page, [
      'a[href*="course"][href*="new"]',
      'a[href*="courses/new"]',
      'button:has-text("+ Create")',
      'a:has-text("+ Create")',
      'button:has-text("Create Course")',
      'a:has-text("Create Course")',
      'button:has-text("New Course")',
      'a:has-text("New Course")',
      'button:has-text("Create")',
      'a:has-text("Create")',
      '[aria-label*="create" i]',
    ], 6000);
    if (!clicked) {
      r.notes.push('No Create button found on dashboard');
      r.screenshots.push(await shot(page, dir, '02_no_create'));
      r.status = 'fail';
      return r;
    }
    r.notes.push(`Clicked: ${clicked}`);
    await page.waitForTimeout(2500);
    r.screenshots.push(await shot(page, dir, '02_after_click'));

    // If a menu appeared, click "Course"
    const courseClick = await safeClick(page, [
      '[role="menuitem"]:has-text("Course")',
      'li:has-text("Course")',
      'button:has-text("Course")',
      'a:has-text("Course")',
    ], 2000);
    if (courseClick) {
      r.notes.push(`Course picked via: ${courseClick}`);
      await page.waitForTimeout(2000);
      r.screenshots.push(await shot(page, dir, '03_course_form'));
    }

    const titleField = await findInput(page, [
      'input[name="course[title]"]',
      'input[name="course[name]"]',
      'input[name="course[subject]"]',
      'input[name="title"]',
      'input[name="name"]',
      'input[name*="subject"]',
      'input[placeholder*="title" i]',
      'input[placeholder*="subject" i]',
      'input[placeholder*="course" i]',
      'input[placeholder*="name" i]',
      'input[type="text"]',
    ]);
    if (titleField) {
      await titleField.fill('Algebra 1');
      r.notes.push('Filled title');
    } else {
      r.notes.push('No title field found');
    }
    r.screenshots.push(await shot(page, dir, '04_form_filled'));

    const submitted = await safeClick(page, [
      'button[type="submit"]',
      'button:has-text("Create")',
      'button:has-text("Save")',
      'button:has-text("Submit")',
      'button:has-text("Continue")',
      'button:has-text("Next")',
    ]);
    r.notes.push(`Submitted via: ${submitted}`);
    await page.waitForLoadState('networkidle', { timeout: 20000 }).catch(() => {});
    await page.waitForTimeout(5000);
    r.screenshots.push(await shot(page, dir, '05_after_submit'));

    const body = await page.evaluate(() => document.body.innerText).catch(() => '');
    r.notes.push(`Final URL: ${page.url()}`);
    if (/algebra|created|success|ready|course/i.test(body.slice(0, 2000)) && !/error/i.test(body.slice(0, 500))) {
      r.status = 'pass';
    } else {
      r.status = 'unclear';
      r.notes.push(`Body: ${body.slice(0, 400).replace(/\s+/g, ' ')}`);
    }
  } catch (e) {
    r.status = 'error';
    r.notes.push(`Exception: ${e.message}`);
  }
  return r;
}

async function createTest(page) {
  const dir = 'prod-verify-test';
  const r = { status: 'pending', notes: [], screenshots: [] };
  try {
    console.log(`\n=== Create test ===`);
    r.screenshots.push(await shot(page, dir, '01_course_detail'));

    const clicked = await safeClick(page, [
      'a:has-text("Create Test")',
      'button:has-text("Create Test")',
      'a:has-text("New Test")',
      'button:has-text("New Test")',
      'a:has-text("Create Assessment")',
      'button:has-text("Create Assessment")',
      'a:has-text("New Assessment")',
      'button:has-text("New Assessment")',
      'a:has-text("Quiz")',
      'button:has-text("Quiz")',
      'a:has-text("Test")',
      'button:has-text("Test")',
      'a:has-text("Assessment")',
      'button:has-text("Assessment")',
      'a:has-text("Add")',
      'button:has-text("Add")',
    ], 6000);
    if (!clicked) {
      r.notes.push('No Create Test button found');
      r.status = 'fail';
      return r;
    }
    r.notes.push(`Clicked: ${clicked}`);
    await page.waitForTimeout(2500);
    r.screenshots.push(await shot(page, dir, '02_after_click'));

    const titleField = await findInput(page, [
      'input[name*="title"]',
      'input[name*="name"]',
      'input[placeholder*="title" i]',
      'input[placeholder*="name" i]',
      'input[type="text"]',
    ]);
    if (titleField) {
      await titleField.fill('Chapter 1 Quiz');
      r.notes.push('Filled test title');
    }
    r.screenshots.push(await shot(page, dir, '03_form_filled'));

    const submitted = await safeClick(page, [
      'button[type="submit"]',
      'button:has-text("Create")',
      'button:has-text("Save")',
      'button:has-text("Submit")',
      'button:has-text("Continue")',
      'button:has-text("Next")',
    ]);
    r.notes.push(`Submitted via: ${submitted}`);
    await page.waitForLoadState('networkidle', { timeout: 20000 }).catch(() => {});
    await page.waitForTimeout(5000);
    r.screenshots.push(await shot(page, dir, '04_after_submit'));

    const body = await page.evaluate(() => document.body.innerText).catch(() => '');
    r.notes.push(`Final URL: ${page.url()}`);
    if (/created|success|quiz|test|assessment/i.test(body.slice(0, 2000)) && !/error/i.test(body.slice(0, 500))) {
      r.status = 'pass';
    } else {
      r.status = 'unclear';
      r.notes.push(`Body: ${body.slice(0, 400).replace(/\s+/g, ' ')}`);
    }
  } catch (e) {
    r.status = 'error';
    r.notes.push(`Exception: ${e.message}`);
  }
  return r;
}

(async () => {
  const browser = await chromium.launch({ headless: true });

  // Try both username 'clairehyj' and full email as identifiers
  const candidates = ['clairehyj', 'clairehyj@gmail.com'];
  let loggedIn = null;
  for (const id of candidates) {
    const attempt = await tryLogin(browser, id);
    out.tried.push({ id, status: attempt.r.status, notes: attempt.r.notes });
    if (attempt.r.status === 'pass') {
      loggedIn = attempt;
      break;
    }
    await attempt.ctx.close();
  }

  if (loggedIn) {
    out.login = loggedIn.r;
    out.course = await createCourse(loggedIn.page);
    if (out.course.status === 'pass' || out.course.status === 'unclear') {
      out.test = await createTest(loggedIn.page);
    } else {
      out.test = { status: 'skipped', notes: ['Course step did not pass'] };
    }
    await loggedIn.ctx.close();
  } else {
    out.login = { status: 'fail', notes: ['All login attempts failed', ...out.tried.map(t => `${t.id}: ${t.status} — ${t.notes.join(' | ')}`)] };
    out.course = { status: 'skipped', notes: ['Login failed'] };
    out.test = { status: 'skipped', notes: ['Login failed'] };
  }

  await browser.close();
  fs.writeFileSync(path.join(SCREENSHOTS_ROOT, 'prod-verify-login-results.json'), JSON.stringify(out, null, 2));
  console.log('\n\n=== RESULT ===');
  console.log(JSON.stringify(out, null, 2));
})();
