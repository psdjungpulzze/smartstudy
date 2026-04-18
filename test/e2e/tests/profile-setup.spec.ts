import { test, expect } from '@playwright/test';
import { loginAs, liveSelectOption, pushLiveEvent } from './helpers';

test.describe('Profile Setup', () => {
  test.beforeEach(async ({ page }) => {
    await loginAs(page, 'student');
    await page.goto('/profile/setup');
    await page.waitForLoadState('networkidle');
    // Wait for LiveView to be fully connected
    await page.waitForSelector('[data-phx-main].phx-connected', { timeout: 5000 });
  });

  test('profile setup page shows Step 1 (Demographics)', async ({ page }) => {
    await expect(page.locator('h1')).toHaveText('Profile Setup');
    // The h2 heading "Demographics" is shown for step 1
    await expect(page.getByRole('heading', { name: 'Demographics' })).toBeVisible();
  });

  test('step indicator shows 3 steps', async ({ page }) => {
    const main = page.locator('main');
    await expect(main.getByRole('heading', { name: 'Demographics' })).toBeVisible();
    // The step dots have labels
    await expect(main.locator('text=Hobbies')).toBeVisible();
    await expect(main.locator('text=Materials')).toBeVisible();
  });

  test('country dropdown loads options', async ({ page }) => {
    const countrySelect = page.locator('select[name="country_id"]');
    await expect(countrySelect).toBeVisible();
    const options = countrySelect.locator('option');
    expect(await options.count()).toBeGreaterThanOrEqual(1);
  });

  test('can navigate to Step 2 (hobbies) after filling required fields', async ({ page }) => {
    // Get the first country value
    const firstCountryValue = await page
      .locator('select[name="country_id"] option:not([value=""])')
      .first()
      .getAttribute('value');

    if (firstCountryValue) {
      // Use liveSelectOption to properly trigger LiveView events
      await liveSelectOption(
        page,
        'select[name="country_id"]',
        firstCountryValue,
        'select_country',
        'country_id',
      );
    }

    // Select grade via LiveView event
    await pushLiveEvent(page, 'update_field', { field: 'selected_grade', value: '10' });
    await page.waitForTimeout(300);

    // Click "Next"
    await page.getByRole('button', { name: 'Next' }).click();

    // Should now show Step 2 content
    await expect(
      page.getByRole('heading', { name: 'Your Hobbies' }),
    ).toBeVisible({ timeout: 5000 });
  });

  test('Step 2 shows hobby section when navigated', async ({ page }) => {
    // Fill required fields
    const firstCountryValue = await page
      .locator('select[name="country_id"] option:not([value=""])')
      .first()
      .getAttribute('value');

    if (firstCountryValue) {
      await liveSelectOption(
        page,
        'select[name="country_id"]',
        firstCountryValue,
        'select_country',
        'country_id',
      );
    }

    await pushLiveEvent(page, 'update_field', { field: 'selected_grade', value: '10' });
    await page.waitForTimeout(300);

    await page.getByRole('button', { name: 'Next' }).click();
    await expect(
      page.getByRole('heading', { name: 'Your Hobbies' }),
    ).toBeVisible({ timeout: 5000 });

    // Should show hobby selection description
    await expect(
      page.getByText('Select hobbies to help us personalize'),
    ).toBeVisible();
  });

  test('can navigate to Step 3 (upload) from Step 2', async ({ page }) => {
    // Fill step 1 required fields
    const firstCountryValue = await page
      .locator('select[name="country_id"] option:not([value=""])')
      .first()
      .getAttribute('value');

    if (firstCountryValue) {
      await liveSelectOption(
        page,
        'select[name="country_id"]',
        firstCountryValue,
        'select_country',
        'country_id',
      );
    }

    await pushLiveEvent(page, 'update_field', { field: 'selected_grade', value: '10' });
    await page.waitForTimeout(300);

    // Go to step 2
    await page.getByRole('button', { name: 'Next' }).click();
    await expect(
      page.getByRole('heading', { name: 'Your Hobbies' }),
    ).toBeVisible({ timeout: 5000 });

    // Go to step 3
    await page.getByRole('button', { name: 'Next' }).click();
    await expect(
      page.getByRole('heading', { name: 'Upload Materials' }),
    ).toBeVisible({ timeout: 5000 });
  });
});
