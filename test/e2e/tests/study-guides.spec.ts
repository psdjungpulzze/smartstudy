import { test, expect } from '@playwright/test';
import { loginAs } from './helpers';

test.describe('Study Guides', () => {
  test.beforeEach(async ({ page }) => {
    await loginAs(page, 'student');
  });

  test('study guides list page renders', async ({ page }) => {
    await page.goto('/study-guides');
    await expect(page.locator('h1')).toHaveText('Study Guides');
  });

  test('shows "Generate New" section', async ({ page }) => {
    await page.goto('/study-guides');
    await expect(page.getByText('Generate New Guide')).toBeVisible();
    // Should have a schedule dropdown and generate button
    await expect(page.locator('select[name="schedule_id"]')).toBeVisible();
    await expect(
      page.getByRole('button', { name: /Generate/i }),
    ).toBeVisible();
  });
});
