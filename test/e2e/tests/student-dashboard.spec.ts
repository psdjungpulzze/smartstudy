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
    // Scope to main content; there are two "My Courses" headings (h3 card + h2 section)
    // Use h2 specifically for the section heading
    const main = page.locator('main');
    await expect(main.locator('h2', { hasText: 'My Courses' })).toBeVisible();
  });

  test('"Browse Courses" button is visible', async ({ page }) => {
    const main = page.locator('main');
    await expect(main.getByRole('link', { name: /Browse Courses/i }).first()).toBeVisible();
  });

  test('"Create Course" button is visible', async ({ page }) => {
    const main = page.locator('main');
    await expect(main.getByRole('link', { name: /Create Course/i })).toBeVisible();
  });
});
