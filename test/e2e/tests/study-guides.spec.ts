import { test, expect } from '@playwright/test';
import { loginAs } from './helpers';

test.describe('Study Guides', () => {
  test.beforeEach(async ({ page }) => {
    await loginAs(page, 'student');
  });

  test('study guides list page renders', async ({ page }) => {
    await page.goto('/study-guides');
    await page.waitForLoadState('networkidle');
    const main = page.locator('main');
    await expect(main.locator('h1')).toHaveText('Study Guides');
  });

  test('shows "Generate New" section', async ({ page }) => {
    await page.goto('/study-guides');
    await page.waitForLoadState('networkidle');
    const main = page.locator('main');
    await expect(main.getByText('Generate New Guide')).toBeVisible();
    // Should have a schedule dropdown and generate button
    await expect(main.locator('select[name="schedule_id"]')).toBeVisible();
    await expect(
      main.getByRole('button', { name: /Generate/i }),
    ).toBeVisible();
  });
});
