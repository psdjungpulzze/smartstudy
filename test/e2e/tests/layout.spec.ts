import { test, expect } from '@playwright/test';
import { loginAs } from './helpers';

test.describe('Layout', () => {
  test('app bar is visible with logo', async ({ page }) => {
    await loginAs(page, 'student');

    // AppBar is a <header> with fixed positioning
    const header = page.locator('header');
    await expect(header).toBeVisible();

    // Logo text "StudySmart" should be in the header
    await expect(header.getByText('StudySmart')).toBeVisible();
  });

  test('left sidebar is visible with navigation', async ({ page }) => {
    await loginAs(page, 'student');

    // Sidebar is an <aside> element
    const sidebar = page.locator('aside');
    await expect(sidebar).toBeVisible();

    // Should contain navigation links
    const navLinks = sidebar.locator('nav a');
    expect(await navLinks.count()).toBeGreaterThan(0);
  });

  test('sidebar shows correct navigation for student role', async ({ page }) => {
    await loginAs(page, 'student');

    const sidebar = page.locator('aside');
    await expect(sidebar.getByText('Dashboard')).toBeVisible();
    await expect(sidebar.getByText('My Courses')).toBeVisible();
    await expect(sidebar.getByText('Assessments')).toBeVisible();
    await expect(sidebar.getByText('Quick Test')).toBeVisible();
    await expect(sidebar.getByText('Study Guides')).toBeVisible();
  });

  test('sidebar shows correct navigation for parent role', async ({ page }) => {
    await loginAs(page, 'parent');

    const sidebar = page.locator('aside');
    await expect(sidebar.getByText('Dashboard')).toBeVisible();
    await expect(sidebar.getByText('Children')).toBeVisible();
    await expect(sidebar.getByText('Reports')).toBeVisible();
  });

  test('sidebar shows correct navigation for teacher role', async ({ page }) => {
    await loginAs(page, 'teacher');

    const sidebar = page.locator('aside');
    await expect(sidebar.getByText('Dashboard')).toBeVisible();
    await expect(sidebar.getByText('My Classes')).toBeVisible();
    await expect(sidebar.getByText('Students')).toBeVisible();
    await expect(sidebar.getByText('Reports')).toBeVisible();
  });

  test('feedback emoji section is visible at bottom of sidebar', async ({ page }) => {
    await loginAs(page, 'student');

    const sidebar = page.locator('aside');
    // The feedback section has "How are you feeling?" text
    await expect(sidebar.getByText('How are you feeling?')).toBeVisible();

    // Should have 5 feedback buttons
    const feedbackButtons = sidebar.locator('button[aria-label]').filter({
      has: page.locator('text=/Very unhappy|Unhappy|Neutral|Happy|Very happy/'),
    });
    // Alternative: check for buttons with the emoji aria-labels
    const emojiButtons = sidebar.locator(
      'button[aria-label="Very unhappy"], button[aria-label="Unhappy"], button[aria-label="Neutral"], button[aria-label="Happy"], button[aria-label="Very happy"]',
    );
    expect(await emojiButtons.count()).toBe(5);
  });
});
