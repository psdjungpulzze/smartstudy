import { Page, expect } from '@playwright/test';

/**
 * Login as a specific role via the dev login page.
 *
 * The dev login page renders four role cards as <form> elements
 * that POST to /dev/auth with a hidden "role" input.
 */
export async function loginAs(
  page: Page,
  role: 'student' | 'parent' | 'teacher' | 'admin',
) {
  await page.goto('/dev/login');
  await page.waitForLoadState('networkidle');

  // Each role card is a <form> containing <input name="role" value="...">
  // Click the submit button inside the form whose hidden input matches.
  const form = page.locator(`form:has(input[name="role"][value="${role}"])`);
  await expect(form).toBeVisible({ timeout: 5000 });

  // Use Promise.all to handle navigation + click atomically
  await Promise.all([
    page.waitForNavigation({ timeout: 15000 }),
    form.locator('button[type="submit"]').click(),
  ]);

  // Verify we landed on the right page
  const expectedPaths: Record<string, string> = {
    student: '/dashboard',
    parent: '/parent',
    teacher: '/teacher',
    admin: '/admin',
  };

  // Wait for LiveView to mount
  await page.waitForLoadState('networkidle');
  expect(page.url()).toContain(expectedPaths[role]);
}

/**
 * Logout by navigating to dev login (clears context).
 */
export async function logout(page: Page) {
  await page.goto('/dev/login');
  await page.waitForLoadState('networkidle');
}

/**
 * Push a LiveView event via the liveSocket API.
 *
 * This is needed because Playwright's selectOption/fill may not trigger
 * LiveView's phx-change event handling for standalone elements outside forms.
 */
export async function pushLiveEvent(
  page: Page,
  eventName: string,
  payload: Record<string, unknown>,
) {
  await page.evaluate(
    ({ eventName, payload }) => {
      const phxMain = document.querySelector('[data-phx-main]') as HTMLElement;
      const view = (window as any).liveSocket.getViewByEl(phxMain);
      if (view) {
        view.pushEvent('change', phxMain, null, eventName, payload);
      }
    },
    { eventName, payload },
  );
}

/**
 * Select an option in a LiveView phx-change select element.
 *
 * Uses pushEvent to reliably trigger the LiveView event handler,
 * since Playwright's selectOption doesn't always trigger LiveView's
 * event delegation for standalone selects.
 */
export async function liveSelectOption(
  page: Page,
  selector: string,
  value: string,
  eventName: string,
  payloadKey: string,
) {
  // Set the visual value on the element
  await page.evaluate(
    ({ selector, value }) => {
      const select = document.querySelector(selector) as HTMLSelectElement;
      if (select) select.value = value;
    },
    { selector, value },
  );

  // Push the LiveView event
  await pushLiveEvent(page, eventName, { [payloadKey]: value });

  // Wait for LiveView to process
  await page.waitForTimeout(500);
}
