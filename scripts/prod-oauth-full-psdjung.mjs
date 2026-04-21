// End-to-end production OAuth + feature test for verified user psdjung@gmail.com
// Tests OAuth login (parent role), dashboard exploration, course/test creation attempts, logout
import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';
import { loadCredentials } from './lib/load-credentials.mjs';

const env = loadCredentials(['TEST_ACCOUNT_PASSWORD', 'TEST_PARENT1_EMAIL', 'TEST_PARENT1_USERNAME']);

const BASE = '/home/pulzze/Documents/GitHub/personal/funsheep/screenshots';
const TASK_DIR = 'prod-oauth-full-psdjung';
const ACCOUNT = {
  email: env.TEST_PARENT1_EMAIL,
  username: env.TEST_PARENT1_USERNAME,
  password: env.TEST_ACCOUNT_PASSWORD,
  expectedRole: 'parent',
};

const results = {
  task1_login: { status: null, steps: [], errors: [], screenshots: [], finalUrl: null, jwtClaims: null },
  task2_dashboard: { status: null, steps: [], errors: [], screenshots: [], widgets: [], bodyExcerpt: null },
  task3_course_creation: { status: null, steps: [], errors: [], screenshots: [], finalUrl: null, created: false },
  task4_test_creation: { status: null, steps: [], errors: [], screenshots: [], finalUrl: null, created: false },
  task5_logout: { status: null, steps: [], errors: [], screenshots: [], finalUrl: null },
  globalErrors: [],
};

async function shot(page, name) {
  const fp = path.join(BASE, TASK_DIR, `${Date.now()}-${name}.png`);
  try {
    await page.screenshot({ path: fp, fullPage: true });
    return fp;
  } catch (e) {
    return `screenshot-failed: ${e.message}`;
  }
}

async function dumpPage(page, label) {
  try {
    const url = page.url();
    const title = await page.title().catch(() => '<no title>');
    const bodyText = (await page.locator('body').innerText().catch(() => '')).slice(0, 800);
    console.log(`[${label}] url=${url} title=${title}`);
    if (bodyText) console.log(`[${label}] body: ${bodyText.replace(/\s+/g, ' ').slice(0, 400)}`);
    return { url, title, body: bodyText };
  } catch (e) {
    console.log(`[${label}] dump failed: ${e.message}`);
    return null;
  }
}

async function tryFill(page, selectors, value) {
  for (const sel of selectors) {
    try {
      const el = page.locator(sel).first();
      if (await el.isVisible({ timeout: 500 })) {
        await el.fill(value);
        return true;
      }
    } catch {}
  }
  return false;
}

async function tryClick(page, selectors, timeoutMs = 1500) {
  for (const sel of selectors) {
    try {
      const el = page.locator(sel).first();
      if (await el.isVisible({ timeout: timeoutMs })) {
        await el.click();
        return sel;
      }
    } catch {}
  }
  return null;
}

// --- TASK 1: OAuth login ---
async function task1Login(page) {
  const r = results.task1_login;
  try {
    console.log('\n=== TASK 1: OAUTH LOGIN ===');
    await page.goto('https://funsheep.com/', { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.waitForTimeout(3000);
    r.screenshots.push(await shot(page, 'task1-01-landed'));
    const d1 = await dumpPage(page, 'landed');
    r.steps.push(`landed at ${d1?.url}`);

    // Should be on auth.interactor.com
    if (!page.url().startsWith('https://auth.interactor.com')) {
      r.errors.push(`Expected auth.interactor.com, got: ${page.url()}`);
    }

    // Try email first, fall back to username
    let userFilled = await tryFill(page, [
      'input[name="username" i]',
      'input[id*="username" i]',
      'input[placeholder*="username" i]',
      'input[name="email" i]',
      'input[type="email"]',
    ], ACCOUNT.email);

    if (!userFilled) {
      // Fallback: first visible non-password input
      try {
        const first = page.locator('form input:not([type="password"]):not([type="hidden"])').first();
        if (await first.isVisible({ timeout: 1500 })) {
          await first.fill(ACCOUNT.email);
          userFilled = true;
        }
      } catch {}
    }

    const pwFilled = await tryFill(page, ['input[type="password"]', 'input[name="password"]'], ACCOUNT.password);
    r.steps.push(`user filled=${userFilled} pw filled=${pwFilled}`);
    r.screenshots.push(await shot(page, 'task1-02-filled-email'));

    const submit1 = await tryClick(page, [
      'button:has-text("Sign in")',
      'button:has-text("Log in")',
      'button:has-text("Continue")',
      'form button[type="submit"]',
      'button[type="submit"]',
      'input[type="submit"]',
    ], 2000);
    r.steps.push(`submit attempt1 via: ${submit1}`);
    await page.waitForTimeout(5000);
    r.screenshots.push(await shot(page, 'task1-03-after-submit-email'));
    const afterEmail = await dumpPage(page, 'after-submit-email');

    // If still on interactor with an error about user-not-found, retry with username
    const bodyLower = (afterEmail?.body || '').toLowerCase();
    const stillOnAuth = page.url().startsWith('https://auth.interactor.com');
    const looksLikeBadEmail = /invalid|not\s*found|incorrect|doesn't\s*exist|check|try\s*again/.test(bodyLower);
    if (stillOnAuth && looksLikeBadEmail) {
      r.steps.push('email-based login appears rejected; retrying with username');
      // clear and refill
      await tryFill(page, ['input[name="username" i]', 'input[id*="username" i]', 'input[placeholder*="username" i]', 'input[type="email"]', 'input[name="email" i]'], ACCOUNT.username);
      await tryFill(page, ['input[type="password"]', 'input[name="password"]'], ACCOUNT.password);
      r.screenshots.push(await shot(page, 'task1-04-retry-username'));
      const submit2 = await tryClick(page, [
        'button:has-text("Sign in")', 'button:has-text("Log in")', 'button:has-text("Continue")',
        'form button[type="submit"]', 'button[type="submit"]', 'input[type="submit"]',
      ], 2000);
      r.steps.push(`submit attempt2 via: ${submit2}`);
      await page.waitForTimeout(6000);
      r.screenshots.push(await shot(page, 'task1-05-after-submit-username'));
    }

    // Handle OAuth consent screen if shown
    await page.waitForTimeout(2000);
    if (page.url().includes('/oauth/consent') || /authorize\s+default\s+application|this\s+app\s+will\s+be\s+able/i.test((await page.locator('body').innerText().catch(() => '')))) {
      r.steps.push('OAuth consent screen detected; clicking Authorize');
      r.screenshots.push(await shot(page, 'task1-consent-before'));
      const authBtn = await tryClick(page, [
        'button:has-text("Authorize")',
        'button:has-text("Allow")',
        'button:has-text("Accept")',
        'form button[type="submit"]:has-text("Authorize")',
        'form[action*="consent"] button[type="submit"]',
      ], 3000);
      r.steps.push(`consent Authorize clicked via: ${authBtn}`);
      await page.waitForTimeout(5000);
      r.screenshots.push(await shot(page, 'task1-consent-after'));
    }

    // Wait for funsheep redirect
    try {
      await page.waitForURL(/funsheep\.com/, { timeout: 20000 });
    } catch {}
    await page.waitForTimeout(3000);

    r.finalUrl = page.url();
    r.screenshots.push(await shot(page, 'task1-06-final-landing'));
    const finalDump = await dumpPage(page, 'task1-final');
    r.bodyExcerpt = finalDump?.body?.slice(0, 500) || null;

    // Look for JWT claims / user info in visible text
    if (finalDump?.body) {
      const email = finalDump.body.match(/[\w.+-]+@[\w.-]+\.\w+/);
      r.jwtClaims = { visibleEmail: email?.[0] || null, bodyHasPsdjung: /psdjung/i.test(finalDump.body) };
    }

    // Status
    const urlPath = (() => { try { return new URL(r.finalUrl).pathname; } catch { return ''; } })();
    r.finalPath = urlPath;
    if (page.url().startsWith('https://funsheep.com')) {
      r.status = 'PASS';
      r.steps.push(`landed on funsheep.com path: ${urlPath}`);
    } else {
      r.status = 'FAIL';
      r.errors.push(`did not reach funsheep.com; final url: ${r.finalUrl}`);
    }
  } catch (e) {
    r.errors.push(`exception: ${e.message}`);
    r.status = 'FAIL';
  }
}

// --- TASK 2: Parent dashboard exploration ---
async function task2Dashboard(page) {
  const r = results.task2_dashboard;
  try {
    console.log('\n=== TASK 2: PARENT DASHBOARD ===');
    await page.waitForTimeout(2000);
    r.screenshots.push(await shot(page, 'task2-01-dashboard'));
    const d = await dumpPage(page, 'dashboard');
    r.bodyExcerpt = d?.body?.slice(0, 800) || null;

    // Enumerate nav links / buttons
    const links = await page.locator('a, button').evaluateAll(els => els.map(el => ({
      tag: el.tagName,
      text: (el.innerText || '').trim().slice(0, 60),
      href: el.getAttribute?.('href') || null,
    })).filter(x => x.text && x.text.length > 0 && x.text.length < 60)).catch(() => []);

    // De-dup / capture a concise widget list
    const uniqueTexts = [...new Set(links.map(l => l.text))].slice(0, 40);
    r.widgets = uniqueTexts;

    // Check for "student" / "create" / "linked" terms
    const bodyLower = (d?.body || '').toLowerCase();
    r.hasLinkedStudentConcept = /linked\s*student|my\s*student|student\s*link|add\s*(a\s*)?student/i.test(d?.body || '');
    r.hasCreateCourseButton = /create\s*course|new\s*course|add\s*course/i.test(d?.body || '');
    r.hasPracticeSection = /practice|quick\s*practice/i.test(bodyLower);

    r.status = 'PASS';
    r.steps.push(`widgets captured: ${uniqueTexts.length}`);
  } catch (e) {
    r.errors.push(`exception: ${e.message}`);
    r.status = 'FAIL';
  }
}

// --- TASK 3: Course creation attempt ---
async function task3CreateCourse(page) {
  const r = results.task3_course_creation;
  try {
    console.log('\n=== TASK 3: COURSE CREATION ===');
    r.screenshots.push(await shot(page, 'task3-01-before'));

    // Try direct nav to /courses/new
    await page.goto('https://funsheep.com/courses/new', { waitUntil: 'domcontentloaded', timeout: 20000 }).catch(() => {});
    await page.waitForTimeout(3000);
    r.finalUrl = page.url();
    r.screenshots.push(await shot(page, 'task3-02-courses-new'));
    const d = await dumpPage(page, 'courses-new');
    r.bodyExcerpt = d?.body?.slice(0, 600) || null;

    const bodyLower = (d?.body || '').toLowerCase();
    const status = await page.evaluate(() => ({ status: document.readyState, title: document.title }));

    // Detect blocked / redirected / permission-denied scenarios
    if (/not\s*authorized|forbidden|permission\s*denied|access\s*denied|403/.test(bodyLower)) {
      r.status = 'BLOCKED (expected for parent role)';
      r.steps.push('permission denial detected');
      r.errors.push('parent role blocked from course creation (likely expected behavior)');
      return;
    }
    if (!/course/i.test(d?.body || '') && page.url() !== 'https://funsheep.com/courses/new') {
      r.status = 'REDIRECTED (likely role-based)';
      r.steps.push(`redirected to: ${page.url()}`);
      return;
    }

    // If a form is present, try to fill and submit
    const titleFilled = await tryFill(page, [
      'input[name*="title" i]',
      'input[name*="subject" i]',
      'input[name*="name" i]',
      'input[id*="title" i]',
      'input[id*="subject" i]',
    ], '7th Grade Math');
    r.steps.push(`title field filled: ${titleFilled}`);

    if (titleFilled) {
      await tryFill(page, ['textarea[name*="description" i]', 'textarea'], 'Algebra and geometry basics');
      r.screenshots.push(await shot(page, 'task3-03-filled'));
      const submitSel = await tryClick(page, [
        'button[type="submit"]',
        'button:has-text("Create")',
        'button:has-text("Save")',
        'button:has-text("Next")',
      ], 2000);
      r.steps.push(`submitted via: ${submitSel}`);
      await page.waitForTimeout(6000);
      r.screenshots.push(await shot(page, 'task3-04-after-submit'));
      const after = await dumpPage(page, 'course-after-submit');
      r.finalUrl = page.url();
      if (after && /7th grade math|created/i.test(after.body)) {
        r.created = true;
        r.status = 'PASS';
      } else if (/error|failed|unable/i.test(after?.body || '')) {
        r.status = 'FAIL';
        r.errors.push(`server-side error on submit: ${after?.body?.slice(0, 200)}`);
      } else {
        r.status = 'PARTIAL';
        r.steps.push('form submitted but course creation not confirmed');
      }
    } else {
      r.status = 'NO_FORM';
      r.steps.push('no course creation form visible on /courses/new');
    }
  } catch (e) {
    r.errors.push(`exception: ${e.message}`);
    r.status = 'FAIL';
  }
}

// --- TASK 4: Test creation attempt (from any accessible course) ---
async function task4CreateTest(page) {
  const r = results.task4_test_creation;
  try {
    console.log('\n=== TASK 4: TEST CREATION ===');
    // Navigate back to a dashboard where courses might be visible
    await page.goto('https://funsheep.com/', { waitUntil: 'domcontentloaded', timeout: 20000 }).catch(() => {});
    await page.waitForTimeout(3000);
    r.screenshots.push(await shot(page, 'task4-01-home'));
    const d1 = await dumpPage(page, 'task4-home');

    // Try to find a course link
    const courseLink = page.locator('a[href*="/courses/"], a[href*="/course/"]').first();
    const hasCourse = await courseLink.isVisible({ timeout: 2000 }).catch(() => false);
    if (hasCourse) {
      const href = await courseLink.getAttribute('href').catch(() => null);
      r.steps.push(`found course link: ${href}`);
      await courseLink.click().catch(() => {});
      await page.waitForTimeout(3000);
      r.screenshots.push(await shot(page, 'task4-02-course-detail'));
      const d2 = await dumpPage(page, 'course-detail');

      // Look for test-creation UI
      const testBtn = await tryClick(page, [
        'button:has-text("Create Test")',
        'a:has-text("Create Test")',
        'button:has-text("New Test")',
        'a:has-text("New Test")',
        'button:has-text("Add Test")',
        'a[href*="/tests/new"]',
        'a[href*="/test/new"]',
      ], 2000);
      r.steps.push(`test-creation entry clicked: ${testBtn}`);

      if (testBtn) {
        await page.waitForTimeout(3000);
        r.screenshots.push(await shot(page, 'task4-03-test-form'));
        const titleFilled = await tryFill(page, [
          'input[name*="title" i]', 'input[name*="name" i]', 'input[id*="test_title" i]',
        ], 'Sample Algebra Quiz');
        r.steps.push(`test title filled: ${titleFilled}`);

        if (titleFilled) {
          const submit = await tryClick(page, ['button[type="submit"]', 'button:has-text("Create")', 'button:has-text("Save")'], 2000);
          r.steps.push(`test submit via: ${submit}`);
          await page.waitForTimeout(5000);
          r.screenshots.push(await shot(page, 'task4-04-after-test'));
          const d3 = await dumpPage(page, 'task4-after-test');
          r.finalUrl = page.url();
          if (d3 && /algebra quiz|test created/i.test(d3.body)) {
            r.created = true;
            r.status = 'PASS';
          } else {
            r.status = 'PARTIAL';
          }
        } else {
          r.status = 'NO_FORM';
        }
      } else {
        r.status = 'NO_ENTRY';
        r.steps.push('no test-creation entrypoint visible in course detail (parent may be read-only)');
      }
    } else {
      r.status = 'NO_COURSE';
      r.steps.push('no course visible to enter (parent has no linked/accessible course, expected)');
      r.screenshots.push(await shot(page, 'task4-02-no-course'));
    }
    r.finalUrl = page.url();
  } catch (e) {
    r.errors.push(`exception: ${e.message}`);
    r.status = 'FAIL';
  }
}

// --- TASK 5: Logout ---
async function task5Logout(page) {
  const r = results.task5_logout;
  try {
    console.log('\n=== TASK 5: LOGOUT ===');
    r.screenshots.push(await shot(page, 'task5-01-before'));

    // Try UI logout button first
    let clicked = await tryClick(page, [
      'button:has-text("Log out")',
      'button:has-text("Logout")',
      'button:has-text("Sign out")',
      'a:has-text("Log out")',
      'a:has-text("Logout")',
      'a:has-text("Sign out")',
      'a[href*="/auth/logout"]',
      'a[href*="/logout"]',
      'form[action*="logout"] button',
    ], 2000);
    r.steps.push(`UI logout clicked: ${clicked}`);

    if (!clicked) {
      // Try clicking profile/avatar to reveal menu
      const profile = await tryClick(page, [
        'button[aria-label*="profile" i]',
        'button[aria-label*="account" i]',
        'button[aria-label*="user" i]',
        '[data-testid*="profile"]',
        '[data-testid*="avatar"]',
        'img[alt*="avatar" i]',
        'img[alt*="profile" i]',
      ], 2000);
      r.steps.push(`profile menu clicked: ${profile}`);
      if (profile) {
        await page.waitForTimeout(1500);
        clicked = await tryClick(page, [
          'button:has-text("Log out")',
          'button:has-text("Logout")',
          'button:has-text("Sign out")',
          'a:has-text("Log out")',
          'a:has-text("Logout")',
          'a:has-text("Sign out")',
          'a[href*="/auth/logout"]',
          'a[href*="/logout"]',
        ], 2000);
        r.steps.push(`UI logout clicked after menu: ${clicked}`);
      }
    }

    if (!clicked) {
      // Fallback: POST to /auth/logout via navigation
      // Build a form and submit with CSRF if needed, else GET
      r.steps.push('falling back to form POST to /auth/logout');
      await page.evaluate(() => {
        const csrfMeta = document.querySelector('meta[name="csrf-token"]');
        const token = csrfMeta ? csrfMeta.getAttribute('content') : null;
        const f = document.createElement('form');
        f.method = 'POST';
        f.action = '/auth/logout';
        if (token) {
          const input = document.createElement('input');
          input.type = 'hidden';
          input.name = '_csrf_token';
          input.value = token;
          f.appendChild(input);
        }
        const method = document.createElement('input');
        method.type = 'hidden';
        method.name = '_method';
        method.value = 'delete';
        f.appendChild(method);
        document.body.appendChild(f);
        f.submit();
      }).catch(e => r.errors.push(`fallback POST failed: ${e.message}`));
    }
    await page.waitForTimeout(6000);
    r.screenshots.push(await shot(page, 'task5-02-after-logout'));
    const d = await dumpPage(page, 'after-logout');
    r.finalUrl = page.url();

    // Navigate to / to see if session cleared (should re-start OAuth)
    await page.goto('https://funsheep.com/', { waitUntil: 'domcontentloaded', timeout: 20000 }).catch(() => {});
    await page.waitForTimeout(4000);
    r.screenshots.push(await shot(page, 'task5-03-post-logout-home'));
    const d2 = await dumpPage(page, 'post-logout-home');
    r.finalUrl = page.url();

    if (page.url().startsWith('https://auth.interactor.com') ||
        /login|sign\s*in/i.test(d2?.body || '')) {
      r.status = 'PASS';
      r.steps.push('session cleared; OAuth re-started');
    } else if (page.url().startsWith('https://funsheep.com') && !/sign\s*in|log\s*in|login/i.test(d2?.body || '')) {
      r.status = 'FAIL';
      r.errors.push('still appears logged in after logout attempt');
    } else {
      r.status = 'PARTIAL';
    }
  } catch (e) {
    r.errors.push(`exception: ${e.message}`);
    r.status = 'FAIL';
  }
}

(async () => {
  const browser = await chromium.launch({ headless: true });
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await ctx.newPage();

  // Capture console + page errors for visibility
  page.on('console', msg => {
    const t = msg.type();
    if (t === 'error' || t === 'warning') console.log(`[browser-${t}]`, msg.text().slice(0, 200));
  });
  page.on('pageerror', err => console.log('[pageerror]', err.message.slice(0, 200)));

  try {
    await task1Login(page);
    if (results.task1_login.status === 'PASS') {
      await task2Dashboard(page);
      await task3CreateCourse(page);
      await task4CreateTest(page);
      await task5Logout(page);
    } else {
      results.globalErrors.push('Skipped tasks 2-5 because login failed');
    }
  } catch (e) {
    results.globalErrors.push(`top-level exception: ${e.message}`);
  } finally {
    await ctx.close();
    await browser.close();
  }

  const outFile = path.join(BASE, 'prod-oauth-full-psdjung-results.json');
  fs.writeFileSync(outFile, JSON.stringify(results, null, 2));
  console.log(`\n=== RESULTS WRITTEN TO ${outFile} ===`);
  console.log(JSON.stringify(results, null, 2));
})();
