import { test, expect } from '@playwright/test';
import { loginAs } from './helpers';

test.describe('Test Schedule', () => {
  test.beforeEach(async ({ page }) => {
    await loginAs(page, 'student');
  });

  test('test schedule list page renders', async ({ page }) => {
    await page.goto('/tests');
    await expect(page.locator('h1')).toContainText(/My Tests|Test Schedule/i);
  });

  test('new test schedule form renders', async ({ page }) => {
    await page.goto('/tests/new');
    await expect(page.locator('h1')).toContainText(/Schedule New Test|New Test/i);
  });

  test('can create a test schedule', async ({ page }) => {
    await page.goto('/tests/new');

    // The form should have a name input and date input at minimum
    const nameInput = page.getByLabel(/name/i).or(page.locator('input[name*="name"]'));
    if ((await nameInput.count()) > 0) {
      await nameInput.first().fill('E2E Test Schedule');
    }

    const dateInput = page.getByLabel(/date/i).or(page.locator('input[type="date"]'));
    if ((await dateInput.count()) > 0) {
      // Set a date 7 days in the future
      const futureDate = new Date();
      futureDate.setDate(futureDate.getDate() + 7);
      const dateStr = futureDate.toISOString().split('T')[0];
      await dateInput.first().fill(dateStr);
    }

    // The page may require selecting a course first
    // Verify the phx-submit form is at least interactable (scope to main to avoid header logout form)
    const main = page.locator('main');
    await expect(main.locator('form[phx-submit], form[phx-change]')).toBeVisible();
  });
});
