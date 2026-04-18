import { test, expect, Page } from '@playwright/test';

const BASE = 'http://localhost:4000';
const SCREENSHOT_DIR = '/home/pulzze/Documents/GitHub/personal/studysmart/screenshots/course-wizard-test';

// Override config to not start webserver since we use port 4000
test.use({ baseURL: BASE });

async function loginAsStudent(page: Page) {
  await page.goto(`${BASE}/dev/login`);
  await page.getByText('Student', { exact: true }).click();
  await page.waitForURL('**/dashboard');
}

test.describe('Course Wizard - Cascading Selects', () => {
  test.beforeEach(async ({ page }) => {
    await loginAsStudent(page);
  });

  test('US cascade: Country > State > District > School and full wizard flow', async ({ page }) => {
    await page.goto(`${BASE}/courses/new`);
    await page.waitForLoadState('networkidle');

    // Screenshot Step 1 initial
    await page.screenshot({ path: `${SCREENSHOT_DIR}/03-step1-initial.png`, fullPage: true });

    // Select United States
    await page.selectOption('select[name="country_id"]', { label: 'United States' });
    await page.waitForTimeout(1000);
    await page.screenshot({ path: `${SCREENSHOT_DIR}/05-after-country-us.png`, fullPage: true });

    // Verify states populated
    const stateOptions = await page.locator('select[name="state_id"] option').count();
    console.log(`State options after selecting US: ${stateOptions}`);
    expect(stateOptions).toBeGreaterThan(1);

    // Select California
    await page.selectOption('select[name="state_id"]', { label: 'California' });
    await page.waitForTimeout(1000);
    await page.screenshot({ path: `${SCREENSHOT_DIR}/06-after-state-california.png`, fullPage: true });

    // Verify districts populated
    const districtOptions = await page.locator('select[name="district_id"] option').count();
    console.log(`District options after selecting California: ${districtOptions}`);
    expect(districtOptions).toBeGreaterThan(1);

    // Select Cupertino Union School District
    await page.selectOption('select[name="district_id"]', { label: 'Cupertino Union School District' });
    await page.waitForTimeout(1000);
    await page.screenshot({ path: `${SCREENSHOT_DIR}/07-after-district-cupertino.png`, fullPage: true });

    // Verify schools populated
    const schoolOptions = await page.locator('select[name="school_id"] option').count();
    console.log(`School options after selecting Cupertino district: ${schoolOptions}`);
    expect(schoolOptions).toBeGreaterThan(1);

    // Select first available school
    const schoolSelect = page.locator('select[name="school_id"]');
    const schoolOptionTexts = await schoolSelect.locator('option').allTextContents();
    console.log('Available schools:', schoolOptionTexts);
    const firstSchoolOpt = schoolSelect.locator('option:not([value=""])').first();
    const schoolValue = await firstSchoolOpt.getAttribute('value');
    if (schoolValue) {
      await page.selectOption('select[name="school_id"]', schoolValue);
    }
    await page.waitForTimeout(500);

    // Scroll to top to fill course fields
    await page.evaluate(() => window.scrollTo(0, 0));
    await page.waitForTimeout(300);

    // Fill Course Name
    const courseNameInput = page.locator('input[placeholder*="AP Calculus"]');
    await courseNameInput.fill('AP Calculus AB');
    await courseNameInput.dispatchEvent('change');
    await page.waitForTimeout(500);

    // Fill Subject
    const subjectInput = page.locator('input[placeholder*="Mathematics"]');
    await subjectInput.fill('Mathematics');
    await subjectInput.dispatchEvent('change');
    await page.waitForTimeout(500);

    // Select Grade 11 - find the grade select near the "Grade Level" label
    const gradeSelect = page.locator('select').filter({ has: page.locator('option:has-text("College")') });
    await gradeSelect.selectOption('11');
    await page.waitForTimeout(500);

    // Screenshot completed Step 1
    await page.screenshot({ path: `${SCREENSHOT_DIR}/10-step1-completed.png`, fullPage: true });

    // Click Next
    await page.click('button:has-text("Next")');
    await page.waitForTimeout(1000);

    // Screenshot Step 2 (Hobbies)
    await page.screenshot({ path: `${SCREENSHOT_DIR}/12-step2-hobbies.png`, fullPage: true });

    // Count hobbies
    const hobbyButtons = await page.locator('button[phx-click="toggle_hobby"]').count();
    console.log(`Number of hobbies displayed: ${hobbyButtons}`);
    expect(hobbyButtons).toBeGreaterThan(0);

    // Select 3 hobbies
    const hobbyBtns = page.locator('button[phx-click="toggle_hobby"]');
    if (hobbyButtons >= 1) await hobbyBtns.nth(0).click();
    await page.waitForTimeout(300);
    if (hobbyButtons >= 2) await hobbyBtns.nth(1).click();
    await page.waitForTimeout(300);
    if (hobbyButtons >= 3) await hobbyBtns.nth(2).click();
    await page.waitForTimeout(500);

    // Screenshot after selecting hobbies
    await page.screenshot({ path: `${SCREENSHOT_DIR}/14-step2-hobbies-selected.png`, fullPage: true });

    // Click Next to Step 3
    await page.click('button:has-text("Next")');
    await page.waitForTimeout(1000);

    // Screenshot Step 3 (Materials)
    await page.screenshot({ path: `${SCREENSHOT_DIR}/16-step3-materials.png`, fullPage: true });

    // Click Add Course to submit (it's inside a form, so click the submit button)
    await page.click('button:has-text("Add Course")');
    await page.waitForTimeout(3000);

    // Screenshot result
    await page.screenshot({ path: `${SCREENSHOT_DIR}/18-after-submit.png`, fullPage: true });

    // Check URL
    const url = page.url();
    console.log(`After submit URL: ${url}`);
  });

  test('South Korea cascade: Country > Seoul > Gangnam > School', async ({ page }) => {
    await page.goto(`${BASE}/courses/new`);
    await page.waitForLoadState('networkidle');

    // Select South Korea
    await page.selectOption('select[name="country_id"]', { label: 'South Korea' });
    await page.waitForTimeout(1000);

    // List state options
    const stateTexts = await page.locator('select[name="state_id"] option').allTextContents();
    console.log('South Korea states:', stateTexts);
    await page.screenshot({ path: `${SCREENSHOT_DIR}/19-korea-states.png`, fullPage: true });

    // Select Seoul
    const seoulOption = stateTexts.find(t => t.includes('Seoul') || t.includes('\uC11C\uC6B8'));
    if (seoulOption) {
      await page.selectOption('select[name="state_id"]', { label: seoulOption.trim() });
      await page.waitForTimeout(1000);

      // List district options
      const districtTexts = await page.locator('select[name="district_id"] option').allTextContents();
      console.log('Seoul districts:', districtTexts);
      await page.screenshot({ path: `${SCREENSHOT_DIR}/20-korea-seoul-districts.png`, fullPage: true });

      // Find Gangnam
      const gangnamOption = districtTexts.find(t => t.includes('Gangnam') || t.includes('\uAC15\uB0A8'));
      if (gangnamOption) {
        await page.selectOption('select[name="district_id"]', { label: gangnamOption.trim() });
        await page.waitForTimeout(1000);

        // List schools
        const schoolTexts = await page.locator('select[name="school_id"] option').allTextContents();
        console.log('Gangnam schools:', schoolTexts);
        await page.screenshot({ path: `${SCREENSHOT_DIR}/21-korea-gangnam-schools.png`, fullPage: true });
      } else {
        console.log('WARN: No Gangnam district found, selecting first available');
        const firstDistrict = page.locator('select[name="district_id"] option:not([value=""])').first();
        const distVal = await firstDistrict.getAttribute('value');
        if (distVal) {
          await page.selectOption('select[name="district_id"]', distVal);
          await page.waitForTimeout(1000);
          const schoolTexts = await page.locator('select[name="school_id"] option').allTextContents();
          console.log('First district schools:', schoolTexts);
          await page.screenshot({ path: `${SCREENSHOT_DIR}/21-korea-first-district-schools.png`, fullPage: true });
        }
      }
    } else {
      console.log('WARN: No Seoul state found');
    }

    // Final Korea cascade screenshot
    await page.screenshot({ path: `${SCREENSHOT_DIR}/22-korea-cascade-final.png`, fullPage: true });
  });
});
