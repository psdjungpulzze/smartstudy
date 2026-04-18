import { test, expect } from '@playwright/test';

test.describe('Dev Login Page', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/dev/login');
  });

  test('shows 4 role cards', async ({ page }) => {
    // Each role card is a <form> with a submit button
    const roleForms = page.locator('form:has(input[name="role"])');
    await expect(roleForms).toHaveCount(4);
  });

  test('clicking Student card redirects to /dashboard', async ({ page }) => {
    const form = page.locator('form:has(input[name="role"][value="student"])');
    await form.locator('button[type="submit"]').click();
    await page.waitForURL('**/dashboard');
    expect(page.url()).toContain('/dashboard');
  });

  test('clicking Parent card redirects to /parent', async ({ page }) => {
    const form = page.locator('form:has(input[name="role"][value="parent"])');
    await form.locator('button[type="submit"]').click();
    await page.waitForURL('**/parent');
    expect(page.url()).toContain('/parent');
  });

  test('clicking Teacher card redirects to /teacher', async ({ page }) => {
    const form = page.locator('form:has(input[name="role"][value="teacher"])');
    await form.locator('button[type="submit"]').click();
    await page.waitForURL('**/teacher');
    expect(page.url()).toContain('/teacher');
  });

  test('clicking Admin card redirects to /admin', async ({ page }) => {
    const form = page.locator('form:has(input[name="role"][value="admin"])');
    await form.locator('button[type="submit"]').click();
    await page.waitForURL('**/admin');
    expect(page.url()).toContain('/admin');
  });
});
