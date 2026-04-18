import { test, expect } from '@playwright/test';
import { loginAs } from './helpers';

test.describe('Teacher Dashboard', () => {
  test.beforeEach(async ({ page }) => {
    await loginAs(page, 'teacher');
  });

  test('teacher dashboard shows welcome message', async ({ page }) => {
    await expect(page.locator('h1')).toHaveText('Teacher Dashboard');
    await expect(page.getByText(/Welcome/i)).toBeVisible();
  });

  test('shows empty state when no students linked', async ({ page }) => {
    const main = page.locator('main');
    await expect(
      main.getByText('No students linked yet'),
    ).toBeVisible();
  });

  test('shows "Add Students" button', async ({ page }) => {
    const main = page.locator('main');
    await expect(
      main.getByRole('link', { name: /Add Students/i }),
    ).toBeVisible();
  });
});
