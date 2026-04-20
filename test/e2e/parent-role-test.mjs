import { chromium } from 'playwright';

const SCREENSHOT_DIR = '/home/pulzze/Documents/GitHub/personal/funsheep/screenshots/parent-role-routing';
const EMAIL = 'psdjung@gmail.com';
const PASSWORD = 'Abcdef123456#';

(async () => {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    viewport: { width: 1440, height: 900 },
  });
  const page = await context.newPage();

  const logs = [];
  page.on('console', (msg) => logs.push(`[console:${msg.type()}] ${msg.text()}`));
  page.on('framenavigated', (frame) => {
    if (frame === page.mainFrame()) logs.push(`[nav] ${frame.url()}`);
  });

  try {
    console.log('Step 1: Navigate to https://funsheep.com');
    await page.goto('https://funsheep.com', { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.screenshot({ path: `${SCREENSHOT_DIR}/01-funsheep-landing.png`, fullPage: true });
    console.log('Landed at:', page.url());

    // If there is an explicit login/sign-in button, click it. Otherwise the page may already have auto-redirected.
    const loginButton = page.locator('a:has-text("Sign in"), a:has-text("Log in"), a:has-text("Login"), button:has-text("Sign in"), button:has-text("Log in")').first();
    try {
      await loginButton.waitFor({ state: 'visible', timeout: 3000 });
      console.log('Found login button, clicking...');
      await loginButton.click();
    } catch (_) {
      console.log('No explicit login button — may already be in OAuth redirect chain.');
    }

    // Wait for auth.interactor.com
    console.log('Step 2: Wait for auth.interactor.com redirect');
    await page.waitForURL(/auth\.interactor\.com/, { timeout: 30000 });
    console.log('Arrived at auth:', page.url());
    await page.screenshot({ path: `${SCREENSHOT_DIR}/02-auth-login-form.png`, fullPage: true });

    // Fill email field
    console.log('Step 3: Fill login form');
    const emailField = page.locator('input[type="email"], input[name="email"], input[name="username"], input[id*="email" i]').first();
    await emailField.waitFor({ state: 'visible', timeout: 15000 });
    await emailField.fill(EMAIL);

    const passwordField = page.locator('input[type="password"]').first();
    await passwordField.fill(PASSWORD);

    await page.screenshot({ path: `${SCREENSHOT_DIR}/03-auth-filled.png`, fullPage: true });

    // Submit
    const submitBtn = page.locator('button[type="submit"], input[type="submit"]').first();
    await submitBtn.click();
    console.log('Submitted login form.');

    // Handle possible consent screen
    try {
      await page.waitForLoadState('domcontentloaded', { timeout: 15000 });
      const consent = page.locator('button:has-text("Authorize"), button:has-text("Allow"), button:has-text("Continue"), button:has-text("Approve")').first();
      await consent.waitFor({ state: 'visible', timeout: 5000 });
      console.log('Consent screen found — clicking authorize');
      await page.screenshot({ path: `${SCREENSHOT_DIR}/04-consent.png`, fullPage: true });
      await consent.click();
    } catch (_) {
      console.log('No consent screen — skipping.');
    }

    // Wait for redirect back to funsheep.com
    console.log('Step 4: Wait for redirect back to funsheep.com');
    await page.waitForURL(/funsheep\.com/, { timeout: 30000 });
    // Allow potential client-side role redirect to fire
    await page.waitForLoadState('networkidle', { timeout: 15000 }).catch(() => {});
    // Extra wait for any JS-based redirects
    await page.waitForTimeout(3000);

    const finalUrl = page.url();
    console.log('FINAL URL:', finalUrl);
    await page.screenshot({ path: `${SCREENSHOT_DIR}/05-final-landing.png`, fullPage: true });

    // Capture h1 and main content for evidence
    let h1Text = '(no h1)';
    try { h1Text = await page.locator('h1').first().innerText({ timeout: 3000 }); } catch (_) {}
    let mainText = '(no main)';
    try { mainText = (await page.locator('main').first().innerText({ timeout: 3000 })).slice(0, 800); } catch (_) {}
    const title = await page.title();

    console.log('\n========== RESULT ==========');
    console.log('FINAL URL:', finalUrl);
    console.log('TITLE:', title);
    console.log('H1:', h1Text);
    console.log('MAIN (first 800 chars):');
    console.log(mainText);
    console.log('============================\n');

    // Dump nav log
    console.log('Navigation log:');
    logs.filter((l) => l.startsWith('[nav]')).forEach((l) => console.log(' ', l));
  } catch (err) {
    console.error('ERROR:', err.message);
    try { await page.screenshot({ path: `${SCREENSHOT_DIR}/ERROR.png`, fullPage: true }); } catch (_) {}
    console.log('URL at error:', page.url());
    process.exitCode = 1;
  } finally {
    await browser.close();
  }
})();
