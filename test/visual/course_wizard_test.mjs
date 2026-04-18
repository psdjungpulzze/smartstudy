import { chromium } from 'playwright';
import { mkdirSync } from 'fs';
import { join } from 'path';

const SCREENSHOT_DIR = '/home/pulzze/Documents/GitHub/personal/studysmart/test/visual/screenshots';
mkdirSync(SCREENSHOT_DIR, { recursive: true });

const BASE_URL = 'http://localhost:4000';

async function run() {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport: { width: 1440, height: 900 } });
  const page = await context.newPage();

  try {
    // Step 1: Navigate to dev login
    console.log('1. Navigating to dev login...');
    await page.goto(`${BASE_URL}/dev/login`, { waitUntil: 'networkidle' });
    await page.screenshot({ path: join(SCREENSHOT_DIR, '01-dev-login.png'), fullPage: false });
    console.log('   Screenshot: 01-dev-login.png');

    // Step 2: Click the Student role card
    console.log('2. Clicking Student role card...');
    await page.getByRole('button', { name: 'Student Access courses,' }).click();
    await page.waitForURL('**/dashboard**', { timeout: 10000 });
    await page.screenshot({ path: join(SCREENSHOT_DIR, '02-student-dashboard.png'), fullPage: false });
    console.log('   Screenshot: 02-student-dashboard.png');

    // Step 3: Navigate to /courses/new
    console.log('3. Navigating to /courses/new...');
    await page.goto(`${BASE_URL}/courses/new`, { waitUntil: 'networkidle' });
    await page.waitForTimeout(1000); // Wait for LiveView to mount
    await page.screenshot({ path: join(SCREENSHOT_DIR, '03-step1-empty.png'), fullPage: true });
    console.log('   Screenshot: 03-step1-empty.png');

    // Step 4: Fill in Course Name
    // LiveView phx-change on standalone inputs doesn't respond to Playwright events.
    // Use LiveView's internal pushEvent API to set field values server-side.
    console.log('4. Filling in fields via LiveView pushEvent...');

    await page.evaluate(() => {
      return new Promise((resolve) => {
        const mainEl = document.querySelector('[data-phx-main]');
        const view = window.liveSocket.getViewByEl(mainEl);

        // Use pushWithReply which is the internal method that actually sends over the channel
        // pushEvent(type, el, targetCtx, event, payload, cid)
        const courseInput = document.querySelector('input[placeholder="e.g., AP Calculus AB"]');
        const subjectInput = document.querySelector('input[placeholder="e.g., Mathematics, Biology, History"]');
        const gradeSelect = document.querySelector('select[phx-value-field="selected_grade"]');

        // For phx-change, LiveView serializes the input's name=value plus phx-value-* attrs
        // The channel message type for phx-change is "event" with event name from phx-change attr
        view.pushWithReply(null, "event", {
          type: "change",
          event: "update_field",
          value: {field: "course_name", value: "AP Biology"}
        });

        setTimeout(() => {
          view.pushWithReply(null, "event", {
            type: "change",
            event: "update_field",
            value: {field: "subject", value: "Biology"}
          });
        }, 100);

        setTimeout(() => {
          view.pushWithReply(null, "event", {
            type: "change",
            event: "update_field",
            value: {field: "selected_grade", value: "10"}
          });
        }, 200);

        setTimeout(resolve, 500);
      });
    });

    await page.waitForTimeout(1000);
    // Check if values appear in the re-rendered DOM
    const courseVal = await page.inputValue('input[placeholder="e.g., AP Calculus AB"]');
    const subjectVal = await page.inputValue('input[placeholder="e.g., Mathematics, Biology, History"]');
    console.log(`   Values after pushWithReply: course="${courseVal}", subject="${subjectVal}"`);

    await page.screenshot({ path: join(SCREENSHOT_DIR, '04-step1-filled.png'), fullPage: true });
    console.log('   Screenshot: 04-step1-filled.png');

    // Step 5: Click Next to go to Step 2
    console.log('5. Clicking Next to go to Step 2 (Hobbies)...');
    await page.locator('button[phx-click="next_step"]').click();
    await page.waitForTimeout(1000); // Wait for LiveView to update

    await page.screenshot({ path: join(SCREENSHOT_DIR, '05-step2-hobbies.png'), fullPage: true });
    console.log('   Screenshot: 05-step2-hobbies.png');

    // Check if we actually moved to step 2
    const pageContent = await page.textContent('body');
    if (pageContent.includes('Hobbies') && (pageContent.includes('Select Your Hobbies') || pageContent.includes('hobby'))) {
      console.log('   Successfully moved to Step 2!');
    } else if (pageContent.includes('Course name is required') || pageContent.includes('Subject is required') || pageContent.includes('Grade level is required')) {
      console.log('   WARNING: Validation errors - still on Step 1');
      // Try scrolling to see validation errors
      await page.evaluate(() => window.scrollTo(0, 0));
      await page.screenshot({ path: join(SCREENSHOT_DIR, '05b-validation-errors.png'), fullPage: true });
      console.log('   Screenshot: 05b-validation-errors.png');
    }

    // Step 6: If on Step 2, click Next to go to Step 3
    const step2Check = await page.locator('text=Select Your Hobbies').count();
    if (step2Check > 0 || pageContent.includes('Hobbies & Interests')) {
      console.log('6. On Step 2 - Clicking Next to go to Step 3 (Materials)...');
      await page.locator('button[phx-click="next_step"]').click();
      await page.waitForTimeout(1000);
      await page.screenshot({ path: join(SCREENSHOT_DIR, '06-step3-materials.png'), fullPage: true });
      console.log('   Screenshot: 06-step3-materials.png');
    }

  } catch (err) {
    console.error('Error:', err.message);
    await page.screenshot({ path: join(SCREENSHOT_DIR, 'error-screenshot.png'), fullPage: true });
    console.log('   Error screenshot saved');
  } finally {
    await browser.close();
  }
}

run();
