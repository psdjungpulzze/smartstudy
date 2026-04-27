#!/usr/bin/env node
/**
 * Visual test: Course creation form — Generation Brief switching
 *
 * Verifies that typing different course names correctly switches the
 * Generation Brief content and detected-test banner.
 */

const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');

const BASE_URL = 'http://localhost:4040';
const SCREENSHOT_DIR = '/home/pulzze/Documents/GitHub/personal/funsheep/screenshots/course-form-test';

fs.mkdirSync(SCREENSHOT_DIR, { recursive: true });

async function screenshot(page, name) {
  const filePath = path.join(SCREENSHOT_DIR, `${name}.png`);
  await page.screenshot({ path: filePath, fullPage: false });
  console.log(`Screenshot: ${filePath}`);
  return filePath;
}

async function waitForLiveView(page, ms = 1800) {
  // Wait for any pending LiveView patches to settle
  await page.waitForTimeout(ms);
}

async function getBriefValue(page) {
  return page.evaluate(() => {
    const ta = document.querySelector('textarea');
    return ta ? ta.value : null;
  });
}

async function getBannerText(page) {
  return page.evaluate(() => {
    // Look for the green detection banner
    const banner = document.querySelector('.bg-green-50, [class*="green-50"]');
    return banner ? banner.textContent.trim().replace(/\s+/g, ' ') : null;
  });
}

async function getSubjectValue(page) {
  return page.evaluate(() => {
    const input = document.querySelector('input[name="course[subject]"]') ||
                  document.querySelector('input[placeholder*="Biology"]');
    // That placeholder is on course name, find subject differently
    const inputs = Array.from(document.querySelectorAll('input[type="text"]'));
    // subject is the second text input
    return inputs[1] ? inputs[1].value : null;
  });
}

async function typeCourseName(page, name) {
  const selector = 'input[placeholder*="AP Biology"]';
  // Triple-click to select all
  await page.click(selector, { clickCount: 3 });
  await page.keyboard.press('Backspace');
  // Type character by character so LiveView hooks fire
  await page.type(selector, name, { delay: 80 });
  // Wait for debounce + LiveView round trip
  await waitForLiveView(page, 2200);
}

(async () => {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport: { width: 1280, height: 900 } });
  const page = await context.newPage();

  // ─── Step 1: Login as Teacher ─────────────────────────────────────────────
  console.log('\n[1] Navigating to dev login...');
  await page.goto(`${BASE_URL}/dev/login`);
  await page.waitForLoadState('networkidle');

  // Find and submit the teacher form
  const teacherForm = page.locator('form').filter({ has: page.locator('input[value="teacher"]') });
  await teacherForm.locator('button[type="submit"], input[type="submit"]').click().catch(async () => {
    // If no submit button visible, submit via JS
    await page.evaluate(() => {
      const forms = Array.from(document.querySelectorAll('form'));
      const f = forms.find(form => form.querySelector('input[value="teacher"]'));
      if (f) f.submit();
    });
  });
  await page.waitForURL(`${BASE_URL}/**`, { timeout: 5000 }).catch(() => {});
  await waitForLiveView(page, 1000);
  console.log('   Logged in, current URL:', page.url());

  // ─── Step 2: Navigate to /courses/new ─────────────────────────────────────
  console.log('\n[2] Navigating to /courses/new...');
  await page.goto(`${BASE_URL}/courses/new`);
  await page.waitForLoadState('networkidle');
  await waitForLiveView(page, 800);

  // Screenshot: initial empty form
  await screenshot(page, '01-empty-form');
  console.log('   Initial form loaded.');

  // ─── Step 3: Type "SAT Math" ──────────────────────────────────────────────
  console.log('\n[3] Typing "SAT Math"...');
  await typeCourseName(page, 'SAT Math');

  const satScreenshot = await screenshot(page, '02-sat-math');
  const satBrief = await getBriefValue(page);
  const satBanner = await getBannerText(page);
  const satSubject = await page.evaluate(() => {
    const inputs = Array.from(document.querySelectorAll('input[type="text"]'));
    return inputs.map(i => ({ placeholder: i.placeholder, value: i.value }));
  });

  console.log('   Banner:', satBanner);
  console.log('   Subject inputs:', JSON.stringify(satSubject));
  console.log('   Brief (first 100):', satBrief ? satBrief.substring(0, 100) : 'EMPTY');

  // ─── Step 4: Type "AP Biology" ────────────────────────────────────────────
  console.log('\n[4] Typing "AP Biology"...');
  await typeCourseName(page, 'AP Biology');

  const apScreenshot = await screenshot(page, '03-ap-biology');
  const apBrief = await getBriefValue(page);
  const apBanner = await getBannerText(page);
  const apSubject = await page.evaluate(() => {
    const inputs = Array.from(document.querySelectorAll('input[type="text"]'));
    return inputs.map(i => ({ placeholder: i.placeholder, value: i.value }));
  });

  console.log('   Banner:', apBanner);
  console.log('   Subject inputs:', JSON.stringify(apSubject));
  console.log('   Brief (first 100):', apBrief ? apBrief.substring(0, 100) : 'EMPTY');

  // ─── Step 5: Type "My Custom Chemistry Course" ────────────────────────────
  console.log('\n[5] Typing "My Custom Chemistry Course"...');
  await typeCourseName(page, 'My Custom Chemistry Course');

  const customScreenshot = await screenshot(page, '04-custom-course');
  const customBrief = await getBriefValue(page);
  const customBanner = await getBannerText(page);
  const customSubject = await page.evaluate(() => {
    const inputs = Array.from(document.querySelectorAll('input[type="text"]'));
    return inputs.map(i => ({ placeholder: i.placeholder, value: i.value }));
  });

  console.log('   Banner:', customBanner);
  console.log('   Subject inputs:', JSON.stringify(customSubject));
  console.log('   Brief:', customBrief ? `"${customBrief.substring(0, 100)}"` : 'EMPTY (correct)');

  // ─── Results ──────────────────────────────────────────────────────────────
  console.log('\n════════════════════════════════════════');
  console.log('RESULTS SUMMARY');
  console.log('════════════════════════════════════════');

  const satBriefOk = satBrief && satBrief.toLowerCase().includes('sat');
  const apBriefOk = apBrief && apBrief.toLowerCase().includes('biology');
  const apBriefNotSat = apBrief && !apBrief.toLowerCase().includes('digital sat math');
  const customBriefEmpty = !customBrief || customBrief.trim() === '';

  console.log(`\nSAT Math:`);
  console.log(`  Banner: ${satBanner || 'NONE'}`);
  console.log(`  Generation Brief contains SAT content: ${satBriefOk ? 'YES ✓' : 'NO ✗'}`);

  console.log(`\nAP Biology (KEY FIX TO VERIFY):`);
  console.log(`  Banner: ${apBanner || 'NONE'}`);
  console.log(`  Generation Brief contains AP Biology content: ${apBriefOk ? 'YES ✓' : 'NO ✗'}`);
  console.log(`  Generation Brief is NOT the old SAT text: ${apBriefNotSat ? 'YES ✓' : 'NO ✗'}`);
  console.log(`  Brief (first 150): ${apBrief ? apBrief.substring(0, 150) : 'EMPTY'}`);

  console.log(`\nMy Custom Chemistry Course:`);
  console.log(`  Banner: ${customBanner || 'NONE (correct)'}`);
  console.log(`  Generation Brief is EMPTY: ${customBriefEmpty ? 'YES ✓' : 'NO ✗'}`);
  if (!customBriefEmpty) {
    console.log(`  Brief content (should be empty): "${customBrief.substring(0, 200)}"`);
  }

  const allPass = satBriefOk && apBriefOk && apBriefNotSat && customBriefEmpty;
  console.log(`\nOverall: ${allPass ? 'PASS ✓' : 'FAIL ✗'}`);

  console.log('\nScreenshots saved to:', SCREENSHOT_DIR);

  await browser.close();
  process.exit(allPass ? 0 : 1);
})();
