import { test, expect } from '@playwright/test';
import { loginAs } from './helpers';

test.describe('Courses', () => {
  test.beforeEach(async ({ page }) => {
    await loginAs(page, 'student');
  });

  test('course search page renders', async ({ page }) => {
    await page.goto('/courses');
    await page.waitForLoadState('networkidle');
    await expect(page.locator('h1')).toHaveText('Browse Courses');
    await expect(page.getByText('Search for existing courses or create a new one')).toBeVisible();
  });

  test('course creation form renders at /courses/new', async ({ page }) => {
    await page.goto('/courses/new');
    await page.waitForLoadState('networkidle');
    await expect(page.locator('h1')).toHaveText('Create New Course');
    // Check the form fields are present
    await expect(page.getByLabel('Course Name')).toBeVisible();
    await expect(page.getByLabel('Subject')).toBeVisible();
    await expect(page.getByLabel('Grade Level')).toBeVisible();
  });

  test('can create a course with name and subject', async ({ page }) => {
    await page.goto('/courses/new');
    await page.waitForLoadState('networkidle');

    // Fill in the course form
    await page.getByLabel('Course Name').fill('Test Course E2E');
    await page.getByLabel('Subject').fill('Mathematics');
    await page.getByLabel('Grade Level').selectOption('10');

    // Submit the form
    await page.getByRole('button', { name: 'Create Course' }).click();

    // After successful creation, LiveView push_navigates to course detail
    // and shows a flash message. Check the flash or the course name heading.
    await expect(
      page.getByText('Course created successfully'),
    ).toBeVisible({ timeout: 15000 });
  });
});
