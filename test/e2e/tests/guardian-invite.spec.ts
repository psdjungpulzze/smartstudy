import { test, expect } from '@playwright/test';
import { loginAs } from './helpers';

test.describe('Guardian Invite', () => {
  test('guardian page renders for parent role', async ({ page }) => {
    await loginAs(page, 'parent');
    await page.goto('/guardians');

    await expect(page.locator('h1')).toHaveText('Guardian Links');
    // Parent view should show "Invite a Student" section
    await expect(page.getByText('Invite a Student')).toBeVisible();
  });

  test('shows invite form for parent', async ({ page }) => {
    await loginAs(page, 'parent');
    await page.goto('/guardians');

    // Should have an email input and "Send Invite" button
    await expect(
      page.locator('input[type="email"][name="email"]'),
    ).toBeVisible();
    await expect(
      page.getByRole('button', { name: /Send Invite/i }),
    ).toBeVisible();
  });

  test('guardian page renders for student role', async ({ page }) => {
    await loginAs(page, 'student');
    await page.goto('/guardians');

    await expect(page.locator('h1')).toHaveText('Guardian Links');
    // Student view should show "My Guardians" section
    await expect(page.getByText('My Guardians')).toBeVisible();
  });
});
