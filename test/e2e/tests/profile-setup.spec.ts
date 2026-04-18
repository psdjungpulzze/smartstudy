import { test, expect } from '@playwright/test';
import { loginAs } from './helpers';

test.describe('Profile Setup', () => {
  test.beforeEach(async ({ page }) => {
    await loginAs(page, 'student');
    await page.goto('/profile/setup');
  });

  test('profile setup page shows Step 1 (Demographics)', async ({ page }) => {
    await expect(page.locator('h1')).toHaveText('Profile Setup');
    await expect(page.getByText('Demographics')).toBeVisible();
  });

  test('step indicator shows 3 steps', async ({ page }) => {
    // The step indicator has 3 step dots with labels
    await expect(page.getByText('Demographics')).toBeVisible();
    await expect(page.getByText('Hobbies')).toBeVisible();
    await expect(page.getByText('Materials')).toBeVisible();
  });

  test('country dropdown loads options', async ({ page }) => {
    const countrySelect = page.locator('select[name="country_id"]');
    await expect(countrySelect).toBeVisible();
    // Should have at least the default "Select a country" option
    const options = countrySelect.locator('option');
    expect(await options.count()).toBeGreaterThanOrEqual(1);
  });

  test('can navigate to Step 2 (hobbies) after filling required fields', async ({ page }) => {
    // Select a country (first available option)
    const countrySelect = page.locator('select[name="country_id"]');
    const countryOptions = countrySelect.locator('option:not([value=""])');

    if (await countryOptions.count() > 0) {
      const firstCountryValue = await countryOptions.first().getAttribute('value');
      if (firstCountryValue) {
        await countrySelect.selectOption(firstCountryValue);
      }
    }

    // Select a grade (required)
    const gradeSelect = page.locator('select[name="value"]:near(:text("Grade Level"))');
    // Use the phx-value-field attribute to find the right select
    const gradeDropdown = page.locator('select[phx-value-field="selected_grade"]');
    if (await gradeDropdown.count() > 0) {
      await gradeDropdown.selectOption('10');
    }

    // Click "Next"
    await page.getByRole('button', { name: 'Next' }).click();

    // Should now show Step 2 content
    await expect(page.getByText('Your Hobbies')).toBeVisible({ timeout: 5000 });
  });

  test('Step 2 shows hobby cards when navigated', async ({ page }) => {
    // Fill required fields first
    const countrySelect = page.locator('select[name="country_id"]');
    const countryOptions = countrySelect.locator('option:not([value=""])');

    if (await countryOptions.count() > 0) {
      const firstCountryValue = await countryOptions.first().getAttribute('value');
      if (firstCountryValue) {
        await countrySelect.selectOption(firstCountryValue);
      }
    }

    const gradeDropdown = page.locator('select[phx-value-field="selected_grade"]');
    if (await gradeDropdown.count() > 0) {
      await gradeDropdown.selectOption('10');
    }

    await page.getByRole('button', { name: 'Next' }).click();
    await expect(page.getByText('Your Hobbies')).toBeVisible({ timeout: 5000 });

    // Should show hobby selection area (may have cards or empty state)
    await expect(
      page.getByText('Select hobbies to help us personalize'),
    ).toBeVisible();
  });

  test('can navigate to Step 3 (upload) from Step 2', async ({ page }) => {
    // Fill step 1 required fields
    const countrySelect = page.locator('select[name="country_id"]');
    const countryOptions = countrySelect.locator('option:not([value=""])');

    if (await countryOptions.count() > 0) {
      const firstCountryValue = await countryOptions.first().getAttribute('value');
      if (firstCountryValue) {
        await countrySelect.selectOption(firstCountryValue);
      }
    }

    const gradeDropdown = page.locator('select[phx-value-field="selected_grade"]');
    if (await gradeDropdown.count() > 0) {
      await gradeDropdown.selectOption('10');
    }

    // Go to step 2
    await page.getByRole('button', { name: 'Next' }).click();
    await expect(page.getByText('Your Hobbies')).toBeVisible({ timeout: 5000 });

    // Go to step 3
    await page.getByRole('button', { name: 'Next' }).click();
    await expect(page.getByText('Upload Materials')).toBeVisible({ timeout: 5000 });
  });
});
