import { test, expect } from '@playwright/test';
import { loginAs } from './helpers';

test.describe('Parent Dashboard', () => {
  test.beforeEach(async ({ page }) => {
    await loginAs(page, 'parent');
  });

  test('parent dashboard shows welcome message', async ({ page }) => {
    await expect(page.locator('h1')).toHaveText('Parent Dashboard');
    await expect(page.getByText(/Welcome/i)).toBeVisible();
  });

  test('shows empty state when no children linked', async ({ page }) => {
    const main = page.locator('main');
    // In a fresh DB with no children linked, we expect the empty state
    await expect(
      main.getByText('No children linked yet'),
    ).toBeVisible();
  });

  test('shows "Add Child" button', async ({ page }) => {
    const main = page.locator('main');
    await expect(
      main.getByRole('link', { name: /Add Child/i }),
    ).toBeVisible();
  });
});
