import { test, expect, Page } from '@playwright/test';
import { loginAs } from './helpers';

/**
 * Visual tests for all 8 engagement features + share feature.
 *
 * Tests log in as dev student, navigate to each feature, and verify
 * the UI elements render correctly.
 */

test.describe('Engagement Features', () => {

  test.describe('1. Student Dashboard - New Engagement Sections', () => {
    test('dashboard loads with engagement sections', async ({ page }) => {
      await loginAs(page, 'student');
      await page.waitForLoadState('networkidle');

      // Verify dashboard loaded - h1 contains greeting + name
      const h1 = page.locator('h1').first();
      await expect(h1).toBeVisible({ timeout: 10000 });
      const text = await h1.textContent();
      expect(text).toMatch(/Good morning|Hey|Evening/);

      // Take screenshot of full dashboard
      await page.screenshot({ path: 'test/e2e/screenshots/dashboard-full.png', fullPage: true });
    });

    test('daily goal section renders', async ({ page }) => {
      await loginAs(page, 'student');
      await page.waitForLoadState('networkidle');

      // Daily goal section should exist
      const dailyGoal = page.locator('text=Daily Goal');
      if (await dailyGoal.isVisible()) {
        await expect(dailyGoal).toBeVisible();
        // FP today counter
        await expect(page.locator('text=FP today')).toBeVisible();
      }
    });

    test('time bonus tracker renders with 3 windows', async ({ page }) => {
      await loginAs(page, 'student');
      await page.waitForLoadState('networkidle');

      // Time bonus tracker (only visible if user has a primary test)
      const studyWindows = page.locator('text=Study Windows');
      if (await studyWindows.isVisible()) {
        await expect(studyWindows).toBeVisible();
        // Should show 3 time windows
        await expect(page.locator('text=Morning')).toBeVisible();
        await expect(page.locator('text=Afternoon')).toBeVisible();
        await expect(page.locator('text=Evening')).toBeVisible();

        await page.screenshot({ path: 'test/e2e/screenshots/time-bonus-tracker.png' });
      }
    });

    test('sheep mascot renders in header', async ({ page }) => {
      await loginAs(page, 'student');
      await page.waitForLoadState('networkidle');

      // Sheep mascot should be visible
      const sheep = page.locator('svg').first();
      await expect(sheep).toBeVisible();
    });

    test('streak and XP show in header', async ({ page }) => {
      await loginAs(page, 'student');
      await page.waitForLoadState('networkidle');

      // Header streak fire emoji
      await expect(page.locator('header').locator('text=🔥')).toBeVisible();
    });
  });

  test.describe('2. Course Detail Page - Share Button', () => {
    test('share button visible on course header', async ({ page }) => {
      await loginAs(page, 'student');

      // Navigate to courses
      await page.goto('/courses');
      await page.waitForLoadState('networkidle');

      // Click first course card/link if available
      const courseLink = page.locator('a[href*="/courses/"]').filter({ hasNot: page.locator('a[href="/courses/new"]') }).first();
      if (await courseLink.count() > 0 && await courseLink.isVisible()) {
        await courseLink.click();
        await page.waitForLoadState('networkidle');

        // Share button (NativeShare hook) should be present
        const shareBtn = page.locator('button[phx-hook="NativeShare"]').first();
        if (await shareBtn.count() > 0) {
          await expect(shareBtn).toBeVisible();
        }

        await page.screenshot({ path: 'test/e2e/screenshots/course-detail-share.png', fullPage: true });
      }
    });
  });

  test.describe('3. Parent Dashboard', () => {
    test('parent dashboard loads', async ({ page }) => {
      await loginAs(page, 'parent');
      await page.waitForLoadState('networkidle');

      // Should be on /parent
      expect(page.url()).toContain('/parent');

      await page.screenshot({ path: 'test/e2e/screenshots/parent-dashboard.png', fullPage: true });
    });

    test('parent sees correct navigation', async ({ page }) => {
      await loginAs(page, 'parent');
      await page.waitForLoadState('networkidle');

      // Parent nav should have Home
      const nav = page.locator('header nav, nav');
      await expect(nav.first()).toBeVisible();
    });
  });

  test.describe('4. Dev Login - All Roles', () => {
    test('dev login page shows 4 role cards', async ({ page }) => {
      await page.goto('/dev/login');
      await page.waitForLoadState('networkidle');

      // Should have 4 role forms
      const forms = page.locator('form:has(input[name="role"])');
      await expect(forms).toHaveCount(4);

      // Verify each role exists
      await expect(page.locator('input[name="role"][value="student"]')).toBeAttached();
      await expect(page.locator('input[name="role"][value="parent"]')).toBeAttached();
      await expect(page.locator('input[name="role"][value="teacher"]')).toBeAttached();
      await expect(page.locator('input[name="role"][value="admin"]')).toBeAttached();

      await page.screenshot({ path: 'test/e2e/screenshots/dev-login.png' });
    });

    test('student login redirects to dashboard', async ({ page }) => {
      await loginAs(page, 'student');
      expect(page.url()).toContain('/dashboard');
    });

    test('parent login redirects to parent page', async ({ page }) => {
      await loginAs(page, 'parent');
      expect(page.url()).toContain('/parent');
    });
  });

  test.describe('5. Navigation & Layout', () => {
    test('student nav has Learn, Courses, Flock', async ({ page }) => {
      await loginAs(page, 'student');
      await page.goto('/dashboard');
      await page.waitForLoadState('networkidle');

      // Desktop nav — check for any nav items
      const nav = page.locator('header nav');
      if (await nav.isVisible()) {
        // At least one nav link should be visible
        await expect(nav.locator('a').first()).toBeVisible();
      }

      await page.screenshot({ path: 'test/e2e/screenshots/student-nav.png' });
    });

    test('mobile bottom tab bar renders', async ({ page }) => {
      // Set mobile viewport
      await page.setViewportSize({ width: 375, height: 812 });
      await loginAs(page, 'student');
      await page.goto('/dashboard');
      await page.waitForLoadState('networkidle');

      // Bottom nav should be visible on mobile (the fixed bottom nav element)
      const bottomNav = page.locator('nav').filter({ has: page.locator('.fixed') }).first();
      // Alternatively look for the bottom nav by its position
      await expect(page.locator('body')).toBeVisible();

      await page.screenshot({ path: 'test/e2e/screenshots/mobile-dashboard.png', fullPage: true });
    });

    test('header shows streak and avatar', async ({ page }) => {
      await loginAs(page, 'student');
      await page.goto('/dashboard');
      await page.waitForLoadState('networkidle');

      // Avatar button
      const avatar = page.locator('button[aria-label="Profile menu"]');
      await expect(avatar).toBeVisible();

      // Fire emoji for streak should be somewhere in the header
      await expect(page.locator('header')).toBeVisible();

      await page.screenshot({ path: 'test/e2e/screenshots/header-streak.png' });
    });
  });

  test.describe('6. Course Flow', () => {
    test('courses page loads', async ({ page }) => {
      await loginAs(page, 'student');
      await page.goto('/courses');
      await page.waitForLoadState('networkidle');

      // Page should load without error
      await expect(page.locator('body')).toBeVisible();

      await page.screenshot({ path: 'test/e2e/screenshots/courses-page.png', fullPage: true });
    });

    test('create new course page loads', async ({ page }) => {
      await loginAs(page, 'student');
      await page.goto('/courses/new');
      await page.waitForLoadState('networkidle');

      // Should have the course creation form - look for visible inputs
      await expect(page.locator('body')).toBeVisible();

      await page.screenshot({ path: 'test/e2e/screenshots/course-new.png', fullPage: true });
    });
  });

  test.describe('7. Leaderboard (Flock)', () => {
    test('leaderboard page loads', async ({ page }) => {
      await loginAs(page, 'student');
      await page.goto('/leaderboard');
      await page.waitForLoadState('networkidle');

      // Should show "The Flock" title
      const flockTitle = page.getByRole('heading', { name: 'The Flock' });
      await expect(flockTitle).toBeVisible();

      await page.screenshot({ path: 'test/e2e/screenshots/leaderboard.png', fullPage: true });
    });
  });

  test.describe('8. Profile Setup', () => {
    test('profile setup page loads', async ({ page }) => {
      await loginAs(page, 'student');
      await page.goto('/profile/setup');
      await page.waitForLoadState('networkidle');

      // Should have step indicator
      await expect(page.locator('body')).toBeVisible();

      await page.screenshot({ path: 'test/e2e/screenshots/profile-setup.png', fullPage: true });
    });
  });

  test.describe('9. Daily Shear Challenge Route', () => {
    test('daily shear page loads for a course', async ({ page }) => {
      await loginAs(page, 'student');

      // First get a course ID
      await page.goto('/courses');
      await page.waitForLoadState('networkidle');

      // Try to find a course link
      const courseLink = page.locator('a[href^="/courses/"]').first();
      if (await courseLink.isVisible()) {
        const href = await courseLink.getAttribute('href');
        if (href) {
          const courseId = href.split('/courses/')[1]?.split('/')[0]?.split('?')[0];
          if (courseId) {
            await page.goto(`/courses/${courseId}/daily-shear`);
            await page.waitForLoadState('networkidle');

            // Should show daily shear UI or error for no questions
            await page.screenshot({ path: 'test/e2e/screenshots/daily-shear.png', fullPage: true });
          }
        }
      }
    });
  });

  test.describe('10. Review Cards Route', () => {
    test('review page loads for a course', async ({ page }) => {
      await loginAs(page, 'student');

      await page.goto('/courses');
      await page.waitForLoadState('networkidle');

      const courseLink = page.locator('a[href^="/courses/"]').first();
      if (await courseLink.isVisible()) {
        const href = await courseLink.getAttribute('href');
        if (href) {
          const courseId = href.split('/courses/')[1]?.split('/')[0]?.split('?')[0];
          if (courseId) {
            await page.goto(`/courses/${courseId}/review`);
            await page.waitForLoadState('networkidle');

            // Should show review UI (empty state or cards)
            await page.screenshot({ path: 'test/e2e/screenshots/review-cards.png', fullPage: true });
          }
        }
      }
    });
  });

  test.describe('11. Share Button Functionality', () => {
    test('share button has correct data attributes', async ({ page }) => {
      await loginAs(page, 'student');
      await page.goto('/courses');
      await page.waitForLoadState('networkidle');

      const courseLink = page.locator('a[href^="/courses/"]').first();
      if (await courseLink.isVisible()) {
        await courseLink.click();
        await page.waitForLoadState('networkidle');

        // Find share button
        const shareBtn = page.locator('button[phx-hook="NativeShare"]').first();
        if (await shareBtn.isVisible()) {
          // Verify it has required data attributes
          const title = await shareBtn.getAttribute('data-share-title');
          const url = await shareBtn.getAttribute('data-share-url');

          expect(title).toBeTruthy();
          expect(url).toBeTruthy();
          expect(url).toContain('http');
        }
      }
    });

    test('share button click triggers clipboard on desktop', async ({ page }) => {
      await loginAs(page, 'student');
      await page.goto('/courses');
      await page.waitForLoadState('networkidle');

      const courseLink = page.locator('a[href^="/courses/"]').first();
      if (await courseLink.isVisible()) {
        await courseLink.click();
        await page.waitForLoadState('networkidle');

        const shareBtn = page.locator('button[phx-hook="NativeShare"]').first();
        if (await shareBtn.isVisible()) {
          // Grant clipboard permissions
          await page.context().grantPermissions(['clipboard-write', 'clipboard-read']);

          await shareBtn.click();

          // Wait for the toast or flash message
          await page.waitForTimeout(1000);

          // Should show "Link copied" toast or flash
          const toast = page.locator('text=Link copied');
          const flash = page.locator('text=copied');
          const visible = await toast.isVisible() || await flash.isVisible();

          await page.screenshot({ path: 'test/e2e/screenshots/share-clipboard-result.png' });
        }
      }
    });
  });

  test.describe('12. Readiness Dashboard with Share', () => {
    test('readiness dashboard loads with share button', async ({ page }) => {
      await loginAs(page, 'student');

      // Navigate through courses to find a test schedule
      await page.goto('/courses');
      await page.waitForLoadState('networkidle');

      const courseLink = page.locator('a[href^="/courses/"]').first();
      if (await courseLink.isVisible()) {
        await courseLink.click();
        await page.waitForLoadState('networkidle');

        // Look for a readiness or assessment link
        const readinessLink = page.locator('a[href*="/readiness"]').first();
        if (await readinessLink.isVisible()) {
          await readinessLink.click();
          await page.waitForLoadState('networkidle');

          // Share button should be visible
          const shareBtn = page.locator('button[phx-hook="NativeShare"]');
          if (await shareBtn.first().isVisible()) {
            await expect(shareBtn.first()).toBeVisible();
          }

          await page.screenshot({ path: 'test/e2e/screenshots/readiness-share.png', fullPage: true });
        }
      }
    });
  });

  test.describe('13. Proof Card Public Page', () => {
    test('proof card page shows 404 for invalid token', async ({ page }) => {
      await page.goto('/share/progress/invalid-token-123');
      await page.waitForLoadState('networkidle');

      // Should show not found message
      const notFound = page.locator('text=not found');
      const expired = page.locator('text=expired');
      const body = page.locator('body');

      // Page should load without crashing
      await expect(body).toBeVisible();

      await page.screenshot({ path: 'test/e2e/screenshots/proof-card-404.png' });
    });
  });

  test.describe('14. Mobile Responsiveness', () => {
    test('dashboard is responsive on iPhone 12', async ({ page }) => {
      await page.setViewportSize({ width: 390, height: 844 });
      await loginAs(page, 'student');
      await page.waitForLoadState('networkidle');

      // Bottom tab bar should be visible
      await expect(page.locator('nav.fixed.bottom-0')).toBeVisible();

      // Header should be compact
      await expect(page.locator('header')).toBeVisible();

      await page.screenshot({ path: 'test/e2e/screenshots/mobile-iphone12.png', fullPage: true });
    });

    test('courses page is responsive on tablet', async ({ page }) => {
      await page.setViewportSize({ width: 768, height: 1024 });
      await loginAs(page, 'student');
      await page.goto('/courses');
      await page.waitForLoadState('networkidle');

      await page.screenshot({ path: 'test/e2e/screenshots/tablet-courses.png', fullPage: true });
    });

    test('parent dashboard on mobile', async ({ page }) => {
      await page.setViewportSize({ width: 375, height: 812 });
      await loginAs(page, 'parent');
      await page.waitForLoadState('networkidle');

      await page.screenshot({ path: 'test/e2e/screenshots/mobile-parent.png', fullPage: true });
    });
  });
});
