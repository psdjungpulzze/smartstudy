// End-to-end production OAuth verification for funsheep.com
// Tests: signup via Interactor, login, course creation, test creation
import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';
import { loadCredentials } from './lib/load-credentials.mjs';

const env = loadCredentials([
  'TEST_ACCOUNT_PASSWORD',
  'TEST_STUDENT_EMAIL', 'TEST_STUDENT_USERNAME', 'TEST_STUDENT_NAME',
  'TEST_PARENT1_EMAIL', 'TEST_PARENT1_USERNAME', 'TEST_PARENT1_NAME',
  'TEST_PARENT2_EMAIL', 'TEST_PARENT2_USERNAME', 'TEST_PARENT2_NAME',
]);

const BASE = '/home/pulzze/Documents/GitHub/personal/funsheep/screenshots';

const ACCOUNTS = [
  { role: 'student', email: env.TEST_STUDENT_EMAIL, password: env.TEST_ACCOUNT_PASSWORD, name: env.TEST_STUDENT_NAME, username: env.TEST_STUDENT_USERNAME },
  { role: 'parent1', email: env.TEST_PARENT1_EMAIL, password: env.TEST_ACCOUNT_PASSWORD, name: env.TEST_PARENT1_NAME, username: env.TEST_PARENT1_USERNAME },
  { role: 'parent2', email: env.TEST_PARENT2_EMAIL, password: env.TEST_ACCOUNT_PASSWORD, name: env.TEST_PARENT2_NAME, username: env.TEST_PARENT2_USERNAME },
];

const results = {
  task1_signup: {},
  task2_login: {},
  task3_course: {},
  task4_test: {},
  errors: [],
  notes: [],
};

async function shot(page, taskDir, name) {
  const fp = path.join(BASE, taskDir, `${Date.now()}-${name}.png`);
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
    const bodyText = (await page.locator('body').innerText().catch(() => '')).slice(0, 400);
    console.log(`[${label}] url=${url} title=${title}`);
    if (bodyText) console.log(`[${label}] body: ${bodyText.replace(/\s+/g, ' ').slice(0, 300)}`);
    return { url, title, body: bodyText };
  } catch (e) {
    console.log(`[${label}] dump failed: ${e.message}`);
    return null;
  }
}

async function attemptSignup(context, account, taskDir) {
  const page = await context.newPage();
  const info = { attempted: true, steps: [], errors: [], screenshots: [], finalUrl: null };
  try {
    console.log(`\n=== SIGNUP: ${account.email} ===`);
    await page.goto('https://funsheep.com/', { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.waitForTimeout(2000);
    info.steps.push(`landed at ${page.url()}`);
    info.screenshots.push(await shot(page, taskDir, `${account.role}-01-landed`));
    const d1 = await dumpPage(page, `${account.role}-landed`);

    // Check if we're on auth.interactor.com
    if (!page.url().startsWith('https://auth.interactor.com')) {
      info.errors.push(`Expected auth.interactor.com, got: ${page.url()}`);
    }

    // Look for sign-up link / toggle
    const signupSelectors = [
      'text=/sign up/i',
      'text=/create account/i',
      'text=/register/i',
      'a[href*="signup"]',
      'a[href*="register"]',
      'button:has-text("Sign up")',
    ];
    let clickedSignup = false;
    for (const sel of signupSelectors) {
      try {
        const el = page.locator(sel).first();
        if (await el.isVisible({ timeout: 1000 })) {
          await el.click();
          clickedSignup = true;
          info.steps.push(`clicked signup via selector: ${sel}`);
          await page.waitForTimeout(2000);
          break;
        }
      } catch {}
    }
    if (!clickedSignup) {
      info.errors.push('No signup link/button found — Interactor may not expose signup on this app');
    }
    info.screenshots.push(await shot(page, taskDir, `${account.role}-02-signup-form`));
    await dumpPage(page, `${account.role}-signup-form`);

    // Interactor signup form has: Username, Email address, Password.
    // Fill by field order (it's the most reliable across label/placeholder variations).
    const allInputs = page.locator('form input');
    const inputCount = await allInputs.count().catch(() => 0);
    info.steps.push(`form input count: ${inputCount}`);
    let usernameFilled = false, emailFilled = false, pwFilled = false;
    try {
      // Try by name/id/placeholder first
      usernameFilled = await tryFill(page, [
        'input[name="username" i]', 'input[id*="username" i]', 'input[placeholder*="username" i]',
      ], account.username);
      emailFilled = await tryFill(page, [
        'input[type="email"]', 'input[name="email"]', 'input[id*="email" i]', 'input[placeholder*="email" i]',
      ], account.email);
      pwFilled = await tryFill(page, [
        'input[type="password"]', 'input[name="password"]',
      ], account.password);
      // Fallback: fill by position if named selectors failed
      if (!usernameFilled && inputCount >= 3) {
        await allInputs.nth(0).fill(account.username);
        usernameFilled = true;
      }
      if (!emailFilled && inputCount >= 3) {
        await allInputs.nth(1).fill(account.email);
        emailFilled = true;
      }
      if (!pwFilled && inputCount >= 3) {
        await allInputs.nth(2).fill(account.password);
        pwFilled = true;
      }
    } catch (e) {
      info.errors.push(`fill exception: ${e.message}`);
    }
    info.steps.push(`fields filled: username=${usernameFilled} email=${emailFilled} pw=${pwFilled}`);

    info.screenshots.push(await shot(page, taskDir, `${account.role}-03-filled`));

    // Submit — prefer text-based to avoid clicking the Google SSO button
    const submitSelectors = [
      'button:has-text("Create account")',
      'button:has-text("Create Account")',
      'button:has-text("Sign up")',
      'button:has-text("Register")',
      'form button[type="submit"]',
      'button[type="submit"]',
      'input[type="submit"]',
    ];
    let submitted = false;
    for (const sel of submitSelectors) {
      try {
        const el = page.locator(sel).first();
        if (await el.isVisible({ timeout: 1000 })) {
          await el.click();
          submitted = true;
          info.steps.push(`submitted via: ${sel}`);
          break;
        }
      } catch {}
    }
    if (!submitted) info.errors.push('No submit button found');
    await page.waitForTimeout(5000);
    info.screenshots.push(await shot(page, taskDir, `${account.role}-04-submitted`));
    const d2 = await dumpPage(page, `${account.role}-after-submit`);

    // Wait for possible redirect back to funsheep.com
    try {
      await page.waitForURL(/funsheep\.com|auth\.interactor\.com/, { timeout: 15000 });
    } catch {}
    await page.waitForTimeout(3000);
    info.finalUrl = page.url();
    info.screenshots.push(await shot(page, taskDir, `${account.role}-05-final`));
    await dumpPage(page, `${account.role}-final`);

    // Detect email-verification wall
    const bodyText = (await page.locator('body').innerText().catch(() => '')).toLowerCase();
    if (/verify.{0,20}email|confirm.{0,20}email|check.{0,20}inbox/.test(bodyText)) {
      info.errors.push('Email verification required — cannot proceed');
      info.emailVerificationRequired = true;
    }
    if (/invalid_redirect_uri|invalid_scope|access_denied|organization_not_found/.test(bodyText)) {
      info.errors.push(`OAuth error body: ${bodyText.slice(0, 300)}`);
    }
  } catch (e) {
    info.errors.push(`exception: ${e.message}`);
  } finally {
    await page.close();
  }
  return info;
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

async function attemptLogin(context, account, taskDir) {
  const page = await context.newPage();
  const info = { attempted: true, steps: [], errors: [], screenshots: [], finalUrl: null, finalPath: null };
  try {
    console.log(`\n=== LOGIN: ${account.email} ===`);
    await page.goto('https://funsheep.com/', { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.waitForTimeout(3000);
    info.screenshots.push(await shot(page, taskDir, `login-01-start`));
    await dumpPage(page, 'login-start');

    // Interactor login uses Username, not Email
    let userFilled = await tryFill(page, [
      'input[name="username" i]', 'input[id*="username" i]', 'input[placeholder*="username" i]',
    ], account.username);
    if (!userFilled) {
      // Fallback: first visible text-like input in form
      try {
        const first = page.locator('form input:not([type="password"]):not([type="hidden"])').first();
        if (await first.isVisible({ timeout: 1000 })) {
          await first.fill(account.username);
          userFilled = true;
        }
      } catch {}
    }
    const pwFilled = await tryFill(page, ['input[type="password"]', 'input[name="password"]'], account.password);
    info.steps.push(`username=${userFilled} pw=${pwFilled}`);
    info.screenshots.push(await shot(page, taskDir, `login-02-filled`));

    const submitSelectors = [
      'button:has-text("Sign in")',
      'button:has-text("Log in")',
      'form button[type="submit"]',
      'button[type="submit"]',
      'input[type="submit"]',
    ];
    for (const sel of submitSelectors) {
      try {
        const el = page.locator(sel).first();
        if (await el.isVisible({ timeout: 1000 })) {
          await el.click();
          info.steps.push(`submitted: ${sel}`);
          break;
        }
      } catch {}
    }
    await page.waitForTimeout(6000);
    try {
      await page.waitForURL(/funsheep\.com/, { timeout: 15000 });
    } catch {}
    await page.waitForTimeout(3000);
    info.finalUrl = page.url();
    try { info.finalPath = new URL(page.url()).pathname; } catch {}
    info.screenshots.push(await shot(page, taskDir, `login-03-dashboard`));
    await dumpPage(page, 'login-final');
  } catch (e) {
    info.errors.push(`exception: ${e.message}`);
  } finally {
    await page.close();
  }
  return info;
}

async function attemptCreateCourse(page, taskDir) {
  const info = { attempted: true, steps: [], errors: [], screenshots: [], finalUrl: null, created: false };
  try {
    console.log(`\n=== COURSE CREATION ===`);
    info.screenshots.push(await shot(page, taskDir, 'course-01-dashboard'));

    // Look for Create button
    const createSelectors = [
      'button:has-text("Create")',
      'a:has-text("Create")',
      'text=/\\+.{0,3}Create/i',
      'a[href*="/courses/new"]',
      'a[href*="/course/new"]',
    ];
    let clicked = false;
    for (const sel of createSelectors) {
      try {
        const el = page.locator(sel).first();
        if (await el.isVisible({ timeout: 1500 })) {
          await el.click();
          clicked = true;
          info.steps.push(`clicked create: ${sel}`);
          await page.waitForTimeout(2000);
          break;
        }
      } catch {}
    }
    if (!clicked) {
      // Try direct URL
      await page.goto('https://funsheep.com/courses/new', { waitUntil: 'domcontentloaded', timeout: 20000 });
      await page.waitForTimeout(2000);
      info.steps.push('navigated to /courses/new directly');
    }
    info.screenshots.push(await shot(page, taskDir, 'course-02-new-form'));
    await dumpPage(page, 'course-new-form');

    // Fill form
    const titleFilled = await tryFill(page, [
      'input[name*="title" i]', 'input[name*="subject" i]', 'input[name*="name" i]', 'input[id*="course_title" i]', 'input[id*="subject" i]',
    ], '7th Grade Math');
    await tryFill(page, ['textarea[name*="description" i]', 'textarea'], 'Algebra and geometry basics');
    info.steps.push(`title filled: ${titleFilled}`);
    info.screenshots.push(await shot(page, taskDir, 'course-03-filled'));

    const submitSelectors = [
      'button[type="submit"]',
      'button:has-text("Create")',
      'button:has-text("Save")',
    ];
    for (const sel of submitSelectors) {
      try {
        const el = page.locator(sel).first();
        if (await el.isVisible({ timeout: 1000 })) {
          await el.click();
          info.steps.push(`submitted: ${sel}`);
          break;
        }
      } catch {}
    }
    await page.waitForTimeout(6000);
    info.finalUrl = page.url();
    info.screenshots.push(await shot(page, taskDir, 'course-04-after-submit'));
    const d = await dumpPage(page, 'course-after-submit');
    if (d && /7th grade math|created/i.test(d.body)) {
      info.created = true;
    }
  } catch (e) {
    info.errors.push(`exception: ${e.message}`);
  }
  return info;
}

async function attemptCreateTest(page, taskDir) {
  const info = { attempted: true, steps: [], errors: [], screenshots: [], finalUrl: null, created: false };
  try {
    console.log(`\n=== TEST CREATION ===`);
    info.screenshots.push(await shot(page, taskDir, 'test-01-before'));
    await dumpPage(page, 'test-before');

    const createSelectors = [
      'button:has-text("Create Test")',
      'a:has-text("Create Test")',
      'button:has-text("New Test")',
      'a:has-text("New Test")',
      'button:has-text("Add Test")',
      'button:has-text("Create")',
    ];
    let clicked = false;
    for (const sel of createSelectors) {
      try {
        const el = page.locator(sel).first();
        if (await el.isVisible({ timeout: 1500 })) {
          await el.click();
          clicked = true;
          info.steps.push(`clicked: ${sel}`);
          await page.waitForTimeout(2500);
          break;
        }
      } catch {}
    }
    if (!clicked) info.errors.push('No test-creation entrypoint visible');

    info.screenshots.push(await shot(page, taskDir, 'test-02-form'));
    await dumpPage(page, 'test-form');

    const titleFilled = await tryFill(page, [
      'input[name*="title" i]', 'input[name*="name" i]', 'input[id*="test_title" i]',
    ], 'Sample Algebra Quiz');
    info.steps.push(`title filled: ${titleFilled}`);
    info.screenshots.push(await shot(page, taskDir, 'test-03-filled'));

    const submitSelectors = ['button[type="submit"]', 'button:has-text("Create")', 'button:has-text("Save")'];
    for (const sel of submitSelectors) {
      try {
        const el = page.locator(sel).first();
        if (await el.isVisible({ timeout: 1000 })) {
          await el.click();
          info.steps.push(`submitted: ${sel}`);
          break;
        }
      } catch {}
    }
    await page.waitForTimeout(6000);
    info.finalUrl = page.url();
    info.screenshots.push(await shot(page, taskDir, 'test-04-after'));
    const d = await dumpPage(page, 'test-after');
    if (d && /algebra quiz|test created/i.test(d.body)) info.created = true;
  } catch (e) {
    info.errors.push(`exception: ${e.message}`);
  }
  return info;
}

(async () => {
  const browser = await chromium.launch({ headless: true });

  // ---- TASK 1: Signup each account (fresh context per account) ----
  for (const acct of ACCOUNTS) {
    const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
    try {
      results.task1_signup[acct.role] = await attemptSignup(ctx, acct, 'prod-oauth-verify-v2-task1');
    } catch (e) {
      results.task1_signup[acct.role] = { error: e.message };
    }
    await ctx.close();
  }

  // ---- TASK 2: Login as student (fresh context) ----
  const student = ACCOUNTS[0];
  const studentCtx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  try {
    results.task2_login = await attemptLogin(studentCtx, student, 'prod-oauth-verify-v2-task2');
  } catch (e) {
    results.task2_login = { error: e.message };
  }

  // ---- TASK 3 + 4: Reuse student context (stay logged in) ----
  let studentPage;
  try {
    studentPage = await studentCtx.newPage();
    // Go to dashboard
    await studentPage.goto('https://funsheep.com/dashboard', { waitUntil: 'domcontentloaded', timeout: 30000 }).catch(() => {});
    await studentPage.waitForTimeout(3000);
    const dashInfo = await dumpPage(studentPage, 'task3-start');
    results.task3_course = await attemptCreateCourse(studentPage, 'prod-oauth-verify-v2-task3');
    results.task4_test = await attemptCreateTest(studentPage, 'prod-oauth-verify-v2-task4');
  } catch (e) {
    results.errors.push(`task3/4 exception: ${e.message}`);
  } finally {
    if (studentPage) await studentPage.close();
    await studentCtx.close();
  }

  await browser.close();

  const outFile = path.join(BASE, 'prod-oauth-verify-v2-results.json');
  fs.writeFileSync(outFile, JSON.stringify(results, null, 2));
  console.log(`\n=== RESULTS WRITTEN TO ${outFile} ===`);
  console.log(JSON.stringify(results, null, 2));
})();
