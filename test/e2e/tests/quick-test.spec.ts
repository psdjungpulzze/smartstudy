import { test, expect } from '@playwright/test';
import { loginAs } from './helpers';

test.describe('Quick Test', () => {
  test.beforeEach(async ({ page }) => {
    await loginAs(page, 'student');
  });

  test('quick test page loads', async ({ page }) => {
    await page.goto('/quick-test');
    await page.waitForLoadState('networkidle');
    // The h1 is inside the main content area
    const main = page.locator('main');
    await expect(main.locator('h1')).toHaveText('Quick Test');
  });

  test('shows empty state or card depending on questions in DB', async ({ page }) => {
    await page.goto('/quick-test');
    await page.waitForLoadState('networkidle');

    const main = page.locator('main');
    // The page should show either a "No Questions Available" message or a question card
    await expect(
      main
        .getByText(/No Questions Available/i)
        .or(main.getByText(/Question/i)),
    ).toBeVisible({ timeout: 10000 });
  });
});
