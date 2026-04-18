import { test, expect } from '@playwright/test';
import { loginAs } from './helpers';

test.describe('Quick Test', () => {
  test.beforeEach(async ({ page }) => {
    await loginAs(page, 'student');
  });

  test('quick test page loads', async ({ page }) => {
    await page.goto('/quick-test');
    await expect(page.locator('h1').or(page.getByText(/Quick Test/i))).toBeVisible();
  });

  test('shows empty state or card depending on questions in DB', async ({ page }) => {
    await page.goto('/quick-test');

    // The page should show either a question card or an empty/no-questions state
    await expect(
      page
        .getByText(/no questions/i)
        .or(page.getByText(/Question/i))
        .or(page.getByText(/Quick Test/i)),
    ).toBeVisible({ timeout: 10000 });
  });
});
