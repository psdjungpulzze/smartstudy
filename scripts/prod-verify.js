// Production verification for https://funsheep.com
// Runs: registration (3 accounts), login, course creation, test creation
// Saves screenshots under screenshots/prod-verify-<task>/

const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const BASE = 'https://funsheep.com';
const PASSWORD = 'Abcdef123456#';
const SCREENSHOTS_ROOT = '/home/pulzze/Documents/GitHub/personal/funsheep/screenshots';

const ACCOUNTS = [
  { role: 'student', email: 'clairehyj@gmail.com', label: 'Student' },
  { role: 'parent', email: 'psdjung@gmail.com', label: 'Parent' },
  { role: 'parent', email: 'jasminhhr@hotmail.com', label: 'Parent' },
];

const results = {
  registration: {},
  login: { status: 'pending', notes: [] },
  course: { status: 'pending', notes: [] },
  test: { status: 'pending', notes: [] },
  errors: [],
};

function shot(page, dir, name) {
  const p = path.join(SCREENSHOTS_ROOT, dir, `${name}.png`);
  fs.mkdirSync(path.dirname(p), { recursive: true });
  return page.screenshot({ path: p, fullPage: true }).then(() => p);
}

async function captureError(page, dir, name) {
  try {
    const p = await shot(page, dir, name);
    const bodyText = await page.evaluate(() => document.body.innerText.slice(0, 2000)).catch(() => '');
    return { screenshot: p, bodyText, url: page.url() };
  } catch (e) {
    return { error: e.message };
  }
}

async function safeClick(page, selectors, timeout = 5000) {
  for (const sel of selectors) {
    try {
      const el = await page.waitForSelector(sel, { timeout: 1500, state: 'visible' });
      if (el) {
        await el.click();
        return sel;
      }
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

async function registerAccount(browser, account, index) {
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await ctx.newPage();
  const dir = 'prod-verify-registration';
  const nameSafe = account.email.replace(/[^a-z0-9]/gi, '_');
  const acctResult = { status: 'pending', notes: [], screenshots: [] };

  try {
    console.log(`\n=== Registering: ${account.email} (${account.role}) ===`);
    await page.goto(BASE, { waitUntil: 'domcontentloaded', timeout: 30000 });
    acctResult.screenshots.push(await shot(page, dir, `${index}_${nameSafe}_01_landing`));
    console.log(`  landing url: ${page.url()}`);

    // Look for Sign Up / Register / Get Started
    const signupClicked = await safeClick(page, [
      'a:has-text("Sign up")',
      'a:has-text("Sign Up")',
      'button:has-text("Sign up")',
      'button:has-text("Sign Up")',
      'a:has-text("Register")',
      'button:has-text("Register")',
      'a:has-text("Get started")',
      'a:has-text("Get Started")',
      'a:has-text("Create account")',
      'a:has-text("Create Account")',
      'a[href*="register"]',
      'a[href*="signup"]',
      'a[href*="sign_up"]',
      'a[href*="/auth"]',
      'a:has-text("Log in")',
      'a:has-text("Login")',
      'a:has-text("Sign in")',
    ]);
    console.log(`  clicked signup via: ${signupClicked}`);

    if (!signupClicked) {
      acctResult.notes.push('Could not find a Sign up / Login link on landing page');
      acctResult.screenshots.push(await shot(page, dir, `${index}_${nameSafe}_NOLINK`));
      acctResult.status = 'fail';
      return acctResult;
    }

    // Wait for redirect (likely to auth.interactor.com)
    await page.waitForLoadState('domcontentloaded', { timeout: 15000 }).catch(() => {});
    await page.waitForTimeout(2000);
    console.log(`  after click url: ${page.url()}`);
    acctResult.screenshots.push(await shot(page, dir, `${index}_${nameSafe}_02_after_signup_click`));

    // Check for oauth errors in URL/body
    const url = page.url();
    const body = await page.evaluate(() => document.body.innerText).catch(() => '');
    if (/invalid_redirect_uri|invalid_scope|unauthorized_client|invalid_client/i.test(url + ' ' + body)) {
      acctResult.notes.push(`OAuth error detected: url=${url}`);
      acctResult.notes.push(`body snippet: ${body.slice(0, 500)}`);
      acctResult.status = 'fail';
      acctResult.screenshots.push(await shot(page, dir, `${index}_${nameSafe}_OAUTH_ERROR`));
      return acctResult;
    }

    // If on login page, look for register link
    const onLoginPage = /login|sign.in/i.test(body) && !/sign.up|register|create.account/i.test(body.slice(0, 200));
    const hasRegisterLink = await page.$('a:has-text("Sign up"), a:has-text("Register"), a:has-text("Create account"), a[href*="register"], a[href*="signup"]').catch(() => null);
    if (hasRegisterLink) {
      console.log(`  found register link on login page, clicking`);
      await hasRegisterLink.click();
      await page.waitForLoadState('domcontentloaded', { timeout: 10000 }).catch(() => {});
      await page.waitForTimeout(1500);
      acctResult.screenshots.push(await shot(page, dir, `${index}_${nameSafe}_03_register_page`));
    }

    // Fill registration form
    console.log(`  searching for email field`);
    const emailField = await findInput(page, [
      'input[type="email"]',
      'input[name="email"]',
      'input[name*="email"]',
      'input[id*="email"]',
      'input[placeholder*="mail" i]',
    ]);
    if (!emailField) {
      acctResult.notes.push('No email field found on registration page');
      acctResult.screenshots.push(await shot(page, dir, `${index}_${nameSafe}_NOFORM`));
      acctResult.status = 'fail';
      return acctResult;
    }

    await emailField.fill(account.email);

    // Name field (optional)
    const nameField = await findInput(page, [
      'input[name="name"]',
      'input[name*="name"]',
      'input[id*="name"]',
      'input[placeholder*="name" i]',
    ]);
    if (nameField) {
      await nameField.fill(account.email.split('@')[0]);
    }

    const passField = await findInput(page, [
      'input[type="password"]:not([name*="confirm" i]):not([id*="confirm" i]):not([name*="2" i])',
      'input[type="password"]',
      'input[name="password"]',
    ]);
    if (!passField) {
      acctResult.notes.push('No password field found');
      acctResult.screenshots.push(await shot(page, dir, `${index}_${nameSafe}_NOPASS`));
      acctResult.status = 'fail';
      return acctResult;
    }
    await passField.fill(PASSWORD);

    // Confirm password if present
    const passFields = await page.$$('input[type="password"]');
    if (passFields.length > 1) {
      await passFields[1].fill(PASSWORD);
    }

    // Role picker (if present)
    const roleSel = account.role === 'student' ? 'Student' : 'Parent';
    const rolePicked = await safeClick(page, [
      `input[value="${roleSel.toLowerCase()}"]`,
      `input[value="${roleSel}"]`,
      `label:has-text("${roleSel}")`,
      `button:has-text("${roleSel}")`,
      `[role="radio"]:has-text("${roleSel}")`,
    ], 2000);
    if (rolePicked) {
      console.log(`  selected role ${roleSel} via ${rolePicked}`);
      acctResult.notes.push(`Role selected: ${roleSel}`);
    }

    acctResult.screenshots.push(await shot(page, dir, `${index}_${nameSafe}_04_form_filled`));

    // Submit
    const submitted = await safeClick(page, [
      'button[type="submit"]',
      'button:has-text("Sign up")',
      'button:has-text("Sign Up")',
      'button:has-text("Register")',
      'button:has-text("Create account")',
      'button:has-text("Create Account")',
      'button:has-text("Continue")',
      'input[type="submit"]',
    ]);
    console.log(`  submitted via: ${submitted}`);

    await page.waitForLoadState('domcontentloaded', { timeout: 20000 }).catch(() => {});
    await page.waitForTimeout(3000);

    const afterUrl = page.url();
    const afterBody = await page.evaluate(() => document.body.innerText).catch(() => '');
    console.log(`  after submit url: ${afterUrl}`);

    acctResult.screenshots.push(await shot(page, dir, `${index}_${nameSafe}_05_after_submit`));

    // Check for errors
    const errText = afterBody.slice(0, 1500);
    if (/error|invalid|failed|already|exists|taken/i.test(errText)) {
      acctResult.notes.push(`Possible error text: ${errText.slice(0, 400).replace(/\s+/g, ' ')}`);
    }

    // Try to skip email verification if there's such an option
    const skipClicked = await safeClick(page, [
      'a:has-text("Skip")',
      'button:has-text("Skip")',
      'a:has-text("Later")',
      'button:has-text("Later")',
      'a:has-text("Continue")',
    ], 3000);
    if (skipClicked) {
      acctResult.notes.push(`Clicked skip/later via ${skipClicked}`);
      await page.waitForTimeout(2000);
      acctResult.screenshots.push(await shot(page, dir, `${index}_${nameSafe}_06_after_skip`));
    }

    // Check if email verification is blocking
    const finalBody = await page.evaluate(() => document.body.innerText).catch(() => '');
    if (/verify.*email|email.*verif|confirmation.*email|check your (email|inbox)/i.test(finalBody)) {
      acctResult.notes.push('Email verification appears to be required (but registration submitted)');
    }

    // If redirected back to funsheep.com with session, that's a success signal
    if (page.url().includes('funsheep.com') && !/\/login|\/auth|error/i.test(page.url())) {
      acctResult.status = 'pass';
      acctResult.notes.push(`Final URL: ${page.url()}`);
    } else if (/verify|welcome|success|thanks|check/i.test(finalBody)) {
      acctResult.status = 'pass';
      acctResult.notes.push(`Registration submitted. Final URL: ${page.url()}`);
    } else if (/already|exists|taken/i.test(finalBody)) {
      acctResult.status = 'pre-existing';
      acctResult.notes.push(`Account may already exist. Final URL: ${page.url()}`);
    } else {
      acctResult.status = 'unclear';
      acctResult.notes.push(`Final URL: ${page.url()}`);
      acctResult.notes.push(`Body snippet: ${finalBody.slice(0, 300).replace(/\s+/g, ' ')}`);
    }
  } catch (e) {
    acctResult.status = 'error';
    acctResult.notes.push(`Exception: ${e.message}`);
    try { acctResult.screenshots.push(await shot(page, dir, `${index}_${nameSafe}_EXCEPTION`)); } catch {}
  } finally {
    await ctx.close();
  }
  return acctResult;
}

async function loginAsStudent(browser) {
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await ctx.newPage();
  const dir = 'prod-verify-login';
  const r = { status: 'pending', notes: [], screenshots: [] };

  try {
    console.log(`\n=== Login as student ===`);
    await page.goto(BASE, { waitUntil: 'domcontentloaded', timeout: 30000 });
    r.screenshots.push(await shot(page, dir, '01_landing'));

    const clicked = await safeClick(page, [
      'a:has-text("Log in")',
      'a:has-text("Login")',
      'a:has-text("Sign in")',
      'button:has-text("Log in")',
      'button:has-text("Login")',
      'button:has-text("Sign in")',
      'a[href*="login"]',
      'a[href*="sign_in"]',
      'a[href*="/auth"]',
    ]);
    if (!clicked) {
      r.notes.push('No login link found');
      r.status = 'fail';
      return r;
    }
    await page.waitForLoadState('domcontentloaded', { timeout: 15000 }).catch(() => {});
    await page.waitForTimeout(2000);
    r.screenshots.push(await shot(page, dir, '02_login_page'));

    const emailField = await findInput(page, [
      'input[type="email"]',
      'input[name="email"]',
      'input[name*="email"]',
      'input[id*="email"]',
    ]);
    const passField = await findInput(page, [
      'input[type="password"]',
      'input[name="password"]',
    ]);
    if (!emailField || !passField) {
      r.notes.push('Login form fields not found');
      r.screenshots.push(await shot(page, dir, '02b_noform'));
      r.status = 'fail';
      return r;
    }
    await emailField.fill('clairehyj@gmail.com');
    await passField.fill(PASSWORD);
    r.screenshots.push(await shot(page, dir, '03_filled'));

    await safeClick(page, [
      'button[type="submit"]',
      'button:has-text("Log in")',
      'button:has-text("Login")',
      'button:has-text("Sign in")',
      'button:has-text("Continue")',
      'input[type="submit"]',
    ]);

    await page.waitForLoadState('domcontentloaded', { timeout: 20000 }).catch(() => {});
    await page.waitForTimeout(4000);
    r.screenshots.push(await shot(page, dir, '04_after_submit'));
    console.log(`  final url: ${page.url()}`);

    const body = await page.evaluate(() => document.body.innerText).catch(() => '');
    if (page.url().includes('funsheep.com') && !/\/login|\/auth|error/i.test(page.url())) {
      r.status = 'pass';
      r.notes.push(`Logged in. Final URL: ${page.url()}`);
    } else if (/error|invalid|incorrect/i.test(body.slice(0, 1000))) {
      r.status = 'fail';
      r.notes.push(`Error on login: ${body.slice(0, 400).replace(/\s+/g, ' ')}`);
    } else {
      r.status = 'unclear';
      r.notes.push(`Final URL: ${page.url()}`);
      r.notes.push(`Body: ${body.slice(0, 400).replace(/\s+/g, ' ')}`);
    }

    // Keep context for course creation if logged in
    return { result: r, ctx, page };
  } catch (e) {
    r.status = 'error';
    r.notes.push(`Exception: ${e.message}`);
    try { r.screenshots.push(await shot(page, dir, 'EXCEPTION')); } catch {}
    await ctx.close();
    return { result: r, ctx: null, page: null };
  }
}

async function createCourse(page) {
  const dir = 'prod-verify-course';
  const r = { status: 'pending', notes: [], screenshots: [] };
  try {
    console.log(`\n=== Create course ===`);
    r.screenshots.push(await shot(page, dir, '01_dashboard'));

    // Look for Create button (green + Create per design system)
    const clicked = await safeClick(page, [
      'button:has-text("Create")',
      'a:has-text("Create")',
      'button:has-text("+ Create")',
      'a:has-text("+ Create")',
      'button:has-text("New Course")',
      'a:has-text("New Course")',
      'button:has-text("Create Course")',
      'a:has-text("Create Course")',
      '[aria-label*="create" i]',
      '[data-testid*="create" i]',
    ], 8000);
    if (!clicked) {
      r.notes.push('No Create button found');
      r.screenshots.push(await shot(page, dir, '02_no_create_button'));
      r.status = 'fail';
      return r;
    }
    r.notes.push(`Clicked create via: ${clicked}`);
    await page.waitForTimeout(2000);
    r.screenshots.push(await shot(page, dir, '02_after_create_click'));

    // If a menu appeared, click "Course"
    const courseClick = await safeClick(page, [
      'button:has-text("Course")',
      'a:has-text("Course")',
      '[role="menuitem"]:has-text("Course")',
      'li:has-text("Course")',
    ], 3000);
    if (courseClick) {
      r.notes.push(`Selected Course via: ${courseClick}`);
      await page.waitForTimeout(2000);
      r.screenshots.push(await shot(page, dir, '03_course_form'));
    }

    // Fill a name/title/subject
    const title = 'Algebra 1';
    const titleField = await findInput(page, [
      'input[name="title"]',
      'input[name="name"]',
      'input[name*="subject"]',
      'input[placeholder*="title" i]',
      'input[placeholder*="name" i]',
      'input[placeholder*="subject" i]',
      'input[placeholder*="course" i]',
      'textarea[name*="title"]',
      'textarea[name*="name"]',
      'input[type="text"]',
    ]);
    if (titleField) {
      await titleField.fill(title);
      r.notes.push(`Filled title: ${title}`);
    } else {
      r.notes.push('No title field found');
    }
    r.screenshots.push(await shot(page, dir, '04_form_filled'));

    // Submit
    const submitted = await safeClick(page, [
      'button[type="submit"]',
      'button:has-text("Create")',
      'button:has-text("Save")',
      'button:has-text("Submit")',
      'button:has-text("Continue")',
      'button:has-text("Next")',
    ]);
    r.notes.push(`Submitted via: ${submitted}`);

    await page.waitForLoadState('domcontentloaded', { timeout: 15000 }).catch(() => {});
    await page.waitForTimeout(4000);
    r.screenshots.push(await shot(page, dir, '05_after_submit'));

    const body = await page.evaluate(() => document.body.innerText).catch(() => '');
    if (/algebra|created|success|ready/i.test(body.slice(0, 2000))) {
      r.status = 'pass';
      r.notes.push(`Final URL: ${page.url()}`);
    } else {
      r.status = 'unclear';
      r.notes.push(`Final URL: ${page.url()}`);
      r.notes.push(`Body: ${body.slice(0, 400).replace(/\s+/g, ' ')}`);
    }
  } catch (e) {
    r.status = 'error';
    r.notes.push(`Exception: ${e.message}`);
    try { r.screenshots.push(await shot(page, dir, 'EXCEPTION')); } catch {}
  }
  return r;
}

async function createTest(page) {
  const dir = 'prod-verify-test';
  const r = { status: 'pending', notes: [], screenshots: [] };
  try {
    console.log(`\n=== Create test ===`);
    r.screenshots.push(await shot(page, dir, '01_course_detail'));

    // Look for "Create Test", "Add Test", "New Assessment", etc.
    const clicked = await safeClick(page, [
      'button:has-text("Create Test")',
      'a:has-text("Create Test")',
      'button:has-text("New Test")',
      'a:has-text("New Test")',
      'button:has-text("Add Test")',
      'a:has-text("Add Test")',
      'button:has-text("Create Assessment")',
      'a:has-text("Create Assessment")',
      'button:has-text("New Assessment")',
      'a:has-text("New Assessment")',
      'button:has-text("Test")',
      'a:has-text("Test")',
      'button:has-text("Assessment")',
      'a:has-text("Assessment")',
      'button:has-text("Quiz")',
      'a:has-text("Quiz")',
    ], 8000);
    if (!clicked) {
      r.notes.push('No Create Test/Assessment button found');
      r.screenshots.push(await shot(page, dir, '02_no_test_button'));
      r.status = 'fail';
      return r;
    }
    r.notes.push(`Clicked test via: ${clicked}`);
    await page.waitForTimeout(2000);
    r.screenshots.push(await shot(page, dir, '02_after_click'));

    // Fill form fields loosely
    const titleField = await findInput(page, [
      'input[name="title"]',
      'input[name="name"]',
      'input[placeholder*="title" i]',
      'input[placeholder*="name" i]',
      'input[type="text"]',
    ]);
    if (titleField) {
      await titleField.fill('Chapter 1 Quiz');
      r.notes.push(`Filled test title`);
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

    await page.waitForLoadState('domcontentloaded', { timeout: 15000 }).catch(() => {});
    await page.waitForTimeout(4000);
    r.screenshots.push(await shot(page, dir, '04_after_submit'));

    const body = await page.evaluate(() => document.body.innerText).catch(() => '');
    if (/created|success|quiz|test|assessment/i.test(body.slice(0, 2000))) {
      r.status = 'pass';
      r.notes.push(`Final URL: ${page.url()}`);
    } else {
      r.status = 'unclear';
      r.notes.push(`Final URL: ${page.url()}`);
      r.notes.push(`Body: ${body.slice(0, 400).replace(/\s+/g, ' ')}`);
    }
  } catch (e) {
    r.status = 'error';
    r.notes.push(`Exception: ${e.message}`);
    try { r.screenshots.push(await shot(page, dir, 'EXCEPTION')); } catch {}
  }
  return r;
}

(async () => {
  const browser = await chromium.launch({ headless: true });

  // Task 1: register 3 accounts
  for (let i = 0; i < ACCOUNTS.length; i++) {
    results.registration[ACCOUNTS[i].email] = await registerAccount(browser, ACCOUNTS[i], i + 1);
  }

  // Task 2: login as student
  const loginOut = await loginAsStudent(browser);
  results.login = loginOut.result;

  // Task 3 + 4: course & test (only if login passed)
  if (loginOut.ctx && loginOut.page && results.login.status === 'pass') {
    results.course = await createCourse(loginOut.page);
    if (results.course.status === 'pass' || results.course.status === 'unclear') {
      results.test = await createTest(loginOut.page);
    } else {
      results.test = { status: 'skipped', notes: ['Skipped because course creation did not pass'], screenshots: [] };
    }
    await loginOut.ctx.close();
  } else {
    results.course = { status: 'skipped', notes: ['Skipped because login did not pass'], screenshots: [] };
    results.test = { status: 'skipped', notes: ['Skipped because login did not pass'], screenshots: [] };
  }

  await browser.close();

  fs.writeFileSync(
    path.join(SCREENSHOTS_ROOT, 'prod-verify-results.json'),
    JSON.stringify(results, null, 2)
  );
  console.log('\n\n=== RESULTS ===');
  console.log(JSON.stringify(results, null, 2));
})();
