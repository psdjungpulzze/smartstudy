import { test, expect } from '@playwright/test';

test.describe('Dev Login Page', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/dev/login');
    await page.waitForLoadState('networkidle');
  });

  test('shows 4 role cards', async ({ page }) => {
    // Each role card is a <form> with a submit button
    const roleForms = page.locator('form:has(input[name="role"])');
    await expect(roleForms).toHaveCount(4);
  });

  test('clicking Student card redirects to /dashboard', async ({ page }) => {
    const form = page.locator('form:has(input[name="role"][value="student"])');
    const [response] = await Promise.all([
      page.waitForResponse((resp) => resp.status() === 200),
      form.locator('button[type="submit"]').click(),
    ]);
    await page.waitForLoadState('networkidle');
    expect(page.url()).toContain('/dashboard');
  });

  test('clicking Parent card redirects to /parent', async ({ page }) => {
    const form = page.locator('form:has(input[name="role"][value="parent"])');
    const [response] = await Promise.all([
      page.waitForResponse((resp) => resp.status() === 200),
      form.locator('button[type="submit"]').click(),
    ]);
    await page.waitForLoadState('networkidle');
    expect(page.url()).toContain('/parent');
  });

  test('clicking Teacher card redirects to /teacher', async ({ page }) => {
    const form = page.locator('form:has(input[name="role"][value="teacher"])');
    const [response] = await Promise.all([
      page.waitForResponse((resp) => resp.status() === 200),
      form.locator('button[type="submit"]').click(),
    ]);
    await page.waitForLoadState('networkidle');
    expect(page.url()).toContain('/teacher');
  });

  test('clicking Admin card redirects to /admin', async ({ page }) => {
    const form = page.locator('form:has(input[name="role"][value="admin"])');
    const [response] = await Promise.all([
      page.waitForResponse((resp) => resp.status() === 200),
      form.locator('button[type="submit"]').click(),
    ]);
    await page.waitForLoadState('networkidle');
    expect(page.url()).toContain('/admin');
  });
});
