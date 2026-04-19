import { test, expect } from '@playwright/test';
import path from 'path';

const BASE_URL = 'http://localhost:4040';
const SCREENSHOT_DIR = path.resolve(__dirname, '../../../screenshots/billing');

const viewports = {
  mobile:  { width: 375, height: 812 },
  tablet:  { width: 768, height: 1024 },
  desktop: { width: 1440, height: 900 },
};

const tabs = [
  { name: 'overview', url: '/subscription?tab=overview' },
  { name: 'plans',    url: '/subscription?tab=plans' },
  { name: 'payment',  url: '/subscription?tab=payment' },
  { name: 'history',  url: '/subscription?tab=history' },
];

test.describe('Billing & Subscription Visual Tests', () => {
  test.beforeEach(async ({ page }) => {
    // Authenticate via dev login
    await page.goto(`${BASE_URL}/dev/login`);
    await page.waitForLoadState('networkidle');

    // Click first available user link to log in
    const userLink = page.locator('a[href*="/dev/login"]').first();
    const loginLinks = page.locator('a').filter({ hasText: /log\s*in|student|user/i });
    const count = await loginLinks.count();

    if (count > 0) {
      await loginLinks.first().click();
    } else {
      // Fallback: click any link that looks like a login action
      const allLinks = page.locator('main a, .container a, [data-role="user"] a, button');
      const linkCount = await allLinks.count();
      if (linkCount > 0) {
        await allLinks.first().click();
      }
    }

    await page.waitForLoadState('networkidle');
  });

  for (const [vpName, vpSize] of Object.entries(viewports)) {
    for (const tab of tabs) {
      test(`${tab.name} tab at ${vpName} (${vpSize.width}px)`, async ({ page }) => {
        await page.setViewportSize(vpSize);
        await page.goto(`${BASE_URL}${tab.url}`);
        await page.waitForLoadState('networkidle');

        // Wait for content to render
        await page.waitForTimeout(1000);

        const filename = `${tab.name}-${vpName}-${vpSize.width}px.png`;
        await page.screenshot({
          path: path.join(SCREENSHOT_DIR, filename),
          fullPage: true,
        });
      });
    }
  }
});
