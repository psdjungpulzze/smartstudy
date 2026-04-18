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
    await expect(
      page
        .getByText('No students linked yet')
        .or(page.getByText(/students/i)),
    ).toBeVisible();
  });

  test('shows "Add Students" button', async ({ page }) => {
    await expect(
      page.getByRole('link', { name: /Add Students/i }),
    ).toBeVisible();
  });
});
