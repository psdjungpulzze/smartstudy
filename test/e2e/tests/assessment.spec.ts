import { test, expect } from '@playwright/test';
import { loginAs } from './helpers';

test.describe('Assessment', () => {
  test.beforeEach(async ({ page }) => {
    await loginAs(page, 'student');
  });

  test('assessment page loads (may show error if no schedule)', async ({ page }) => {
    // Assessment requires a schedule_id, so navigating to /tests first
    await page.goto('/tests');

    // Check if there are any test schedules with assessment links
    const assessLinks = page.locator('a[href*="/assess"]');
    if (await assessLinks.count() > 0) {
      await assessLinks.first().click();
      // Should show the assessment page with a question or empty state
      await expect(
        page
          .getByText(/Assessment/i)
          .or(page.getByText(/no questions/i))
          .or(page.getByText(/Question/i)),
      ).toBeVisible({ timeout: 10000 });
    } else {
      // No test schedules exist - the test schedule page should at least render
      await expect(page.locator('h1')).toBeVisible();
    }
  });
});
