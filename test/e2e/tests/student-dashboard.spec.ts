import { test, expect } from '@playwright/test';
import { loginAs } from './helpers';

test.describe('Student Dashboard', () => {
  test.beforeEach(async ({ page }) => {
    await loginAs(page, 'student');
  });

  test('dashboard shows welcome message', async ({ page }) => {
    await expect(page.locator('h1')).toHaveText('Student Dashboard');
    // Welcome text includes the user display name
    await expect(page.locator('text=Welcome back')).toBeVisible();
  });

  test('dashboard shows "My Courses" section', async ({ page }) => {
    await expect(page.getByText('My Courses')).toBeVisible();
  });

  test('"Browse Courses" button is visible', async ({ page }) => {
    await expect(page.getByRole('link', { name: /Browse Courses/i })).toBeVisible();
  });

  test('"Create Course" button is visible', async ({ page }) => {
    await expect(page.getByRole('link', { name: /Create Course/i })).toBeVisible();
  });
});
