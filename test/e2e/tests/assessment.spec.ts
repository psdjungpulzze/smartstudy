import { test, expect } from '@playwright/test';
import { loginAs } from './helpers';

test.describe('Assessment', () => {
  test.beforeEach(async ({ page }) => {
    await loginAs(page, 'student');
  });

  test('assessment page loads (may show error if no schedule)', async ({ page }) => {
    // Assessment requires a schedule_id, so navigate to /tests first
    await page.goto('/tests');
    await page.waitForLoadState('networkidle');

    const main = page.locator('main');

    // Check if there are any test schedules with assessment links (scope to main content)
    const assessLinks = main.locator('a[href*="/assess"]');
    if ((await assessLinks.count()) > 0) {
      await assessLinks.first().click();
      await page.waitForLoadState('networkidle');
      // Should show the assessment page with a question or empty state
      await expect(
        main
          .getByText(/Assessment/i)
          .or(main.getByText(/no questions/i))
          .or(main.getByText(/Question/i)),
      ).toBeVisible({ timeout: 10000 });
    } else {
      // No test schedules exist - the test schedule page should at least render
      await expect(main.locator('h1')).toBeVisible();
    }
  });
});
