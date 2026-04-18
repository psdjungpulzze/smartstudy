import { Page, expect } from '@playwright/test';

/**
 * Login as a specific role via the dev login page.
 *
 * The dev login page renders four role cards as <form> elements
 * that POST to /dev/auth with a hidden "role" input.  Playwright
 * submits the form by clicking the <button type="submit"> inside
 * the matching form.
 */
export async function loginAs(
  page: Page,
  role: 'student' | 'parent' | 'teacher' | 'admin',
) {
  await page.goto('/dev/login');

  // Each role card is a <form> containing <input name="role" value="...">
  // Click the submit button inside the form whose hidden input matches.
  const form = page.locator(`form:has(input[name="role"][value="${role}"])`);
  await form.locator('button[type="submit"]').click();

  // Wait for redirect after login
  const expectedPaths: Record<string, string> = {
    student: '/dashboard',
    parent: '/parent',
    teacher: '/teacher',
    admin: '/admin',
  };
  await page.waitForURL(`**${expectedPaths[role]}`, { timeout: 10000 });
}

/**
 * Logout by posting DELETE to /dev/auth.
 * After logout the app typically redirects to /dev/login.
 */
export async function logout(page: Page) {
  // The logout form is in the app layout header
  const logoutForm = page.locator('form[action="/dev/auth"]:has(input[value="delete"])');

  if (await logoutForm.count() > 0) {
    await logoutForm.locator('button[type="submit"]').click();
    await page.waitForURL('**/dev/login', { timeout: 10000 });
  } else {
    // Fallback: navigate directly
    await page.goto('/dev/login');
  }
}
