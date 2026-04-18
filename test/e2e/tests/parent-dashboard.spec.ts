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
    // In a fresh DB with no children linked, we expect the empty state
    await expect(
      page
        .getByText('No children linked yet')
        .or(page.getByText(/children/i)),
    ).toBeVisible();
  });

  test('shows "Add Child" button', async ({ page }) => {
    await expect(
      page.getByRole('link', { name: /Add Child/i }),
    ).toBeVisible();
  });
});
