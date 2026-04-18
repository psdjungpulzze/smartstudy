import { test, expect } from '@playwright/test';
import { loginAs } from './helpers';

test.describe('Readiness Dashboard', () => {
  test.beforeEach(async ({ page }) => {
    await loginAs(page, 'student');
  });

  test('readiness dashboard loads for a valid test schedule or shows appropriate state', async ({
    page,
  }) => {
    // First check if there are any test schedules
    await page.goto('/tests');

    const readinessLinks = page.locator('a[href*="/readiness"]');
    if (await readinessLinks.count() > 0) {
      await readinessLinks.first().click();
      // Should show readiness dashboard content
      await expect(
        page
          .getByText(/Readiness/i)
          .or(page.getByText(/Score/i))
          .or(page.getByText(/Chapter/i)),
      ).toBeVisible({ timeout: 10000 });
    } else {
      // No test schedules - just verify the test list page rendered
      await expect(page.locator('h1')).toBeVisible();
    }
  });
});
