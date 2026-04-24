// Phase 0.5 study-loop-closure production QA
// Runs Playwright against https://funsheep.com, logs in as the prod test
// student, runs the diagnostic twice, and captures screenshots of the 4
// features under review.
//
// Secrets are read from .env.credentials at the repo root; never logged.

import { chromium } from 'playwright';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const REPO_ROOT = path.resolve(__dirname, '..', '..');
const SHOT_DIR = path.join(REPO_ROOT, 'screenshots', 'phase-0.5-qa', 'retry');
fs.mkdirSync(SHOT_DIR, { recursive: true });

// --- load credentials from .env.credentials without dotenv dependency ---
const credPath = path.join(REPO_ROOT, '.env.credentials');
const credRaw = fs.readFileSync(credPath, 'utf8');
const creds = {};
for (const line of credRaw.split(/\r?\n/)) {
  const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/);
  if (!m) continue;
  let v = m[2];
  if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) {
    v = v.slice(1, -1);
  }
  creds[m[1]] = v;
}
// Resolve ${VAR} and $VAR references (single-pass is enough for our file;
// iterate a few times for safety in case of chained refs).
for (let pass = 0; pass < 4; pass++) {
  for (const k of Object.keys(creds)) {
    creds[k] = creds[k].replace(/\$\{([A-Z0-9_]+)\}|\$([A-Z0-9_]+)/g, (_, a, b) => {
      const name = a || b;
      return creds[name] !== undefined ? creds[name] : (process.env[name] || '');
    });
  }
}
const EMAIL = creds.PROD_TEST_STUDENT_EMAIL;
const PASSWORD = creds.PROD_TEST_STUDENT_PASSWORD;
if (!EMAIL || !PASSWORD) {
  console.error('Missing PROD_TEST_STUDENT_EMAIL / PROD_TEST_STUDENT_PASSWORD in .env.credentials');
  process.exit(2);
}

const BASE = 'https://funsheep.com';
const COURSE_ID = 'd44628ca-6579-48da-a83b-466e12b1c19b'; // AP Biology

const findings = {
  weak_topics_cta: { status: 'PENDING', notes: '' },
  inline_explanation: { status: 'PENDING', notes: '' },
  skill_badge: { status: 'PENDING', notes: '' },
  readiness_delta: { status: 'PENDING', notes: '' },
  misc: [],
};

function log(msg) {
  const ts = new Date().toISOString().slice(11, 19);
  console.log(`[${ts}] ${msg}`);
}

async function shot(page, name) {
  const p = path.join(SHOT_DIR, name);
  await page.screenshot({ path: p, fullPage: true });
  log(`  shot -> ${path.relative(REPO_ROOT, p)}`);
  return p;
}

async function checkOverflow(page, label) {
  const overflow = await page.evaluate(() => {
    return document.documentElement.scrollWidth > document.documentElement.clientWidth + 1;
  });
  if (overflow) findings.misc.push(`Horizontal overflow at ${label}`);
}

async function login(page) {
  log(`Navigating to ${BASE}/auth/login`);
  await page.goto(`${BASE}/auth/login`, { waitUntil: 'networkidle' });
  // Ensure student role chip is selected (should be default)
  const studentChip = page.locator('[phx-value-role="student"]').first();
  if (await studentChip.count()) await studentChip.click().catch(() => {});

  await page.fill('input[name="login[username]"]', EMAIL);
  await page.fill('input[name="login[password]"]', PASSWORD);
  await shot(page, 'dbg-login-filled.png');
  await page.click('button[type="submit"]');
  // Wait a generous window for either redirect or an error to appear
  await Promise.race([
    page.waitForURL((u) => !/\/auth\/login/.test(u.toString()), { timeout: 30000 }),
    page.waitForSelector('text=/Invalid|incorrect|failed|error/i', { timeout: 30000 }).catch(() => {}),
  ]).catch(() => {});
  await page.waitForLoadState('networkidle').catch(() => {});
  const url = page.url();
  log(`  post-login url: ${url}`);
  if (/\/auth\/login/.test(url)) {
    await shot(page, 'dbg-login-after.png');
    const err = await page.locator('text=/Invalid|incorrect|failed|error/i').first().textContent().catch(() => '');
    throw new Error(`Login failed; still on /auth/login. err="${err}"`);
  }
}

async function openOrCreateSchedule(page) {
  log(`Loading schedules for course ${COURSE_ID}`);
  await page.goto(`${BASE}/courses/${COURSE_ID}/tests`, { waitUntil: 'networkidle' });
  await shot(page, '01-schedules-list.png');

  // Collect all schedule ids from the list (there may be multiple stale ones
  // from earlier runs). Walk them newest-first — the last id in document order
  // is typically the most recent — and pick the first one whose assess page
  // shows either a usable question UI or the "still processing" state.
  const scheduleIds = await page.evaluate(() => {
    const ids = [];
    const seen = new Set();
    for (const a of document.querySelectorAll('a[href*="/tests/"]')) {
      const m = (a.getAttribute('href') || '').match(/\/tests\/([0-9a-f-]{36})/);
      if (m && !seen.has(m[1])) { ids.push(m[1]); seen.add(m[1]); }
    }
    return ids;
  });
  log(`  schedules on list: ${scheduleIds.join(', ')}`);
  // Prefer the newest (last) schedule in the list; keep a fallback list.
  const candidates = [...scheduleIds].reverse();
  for (const scheduleId of candidates) {
    log(`  checking existing schedule ${scheduleId}`);
    await page.goto(`${BASE}/courses/${COURSE_ID}/tests/${scheduleId}/assess`, { waitUntil: 'networkidle' });
    const haveAnswer = await page.locator('button[phx-click="select_answer"], textarea[name="answer"]').first().count();
    const stillProcessing = await page.locator('text=/Course is still processing|still being built|validating questions/i').count();
    const empty = await page.locator('text=/No questions for the selected chapters/i').count();
    if (haveAnswer > 0 || stillProcessing > 0) {
      log(`  using schedule ${scheduleId} (haveAnswer=${haveAnswer}, processing=${stillProcessing})`);
      return;
    }
    if (empty > 0) {
      log(`  schedule ${scheduleId} is stuck with "No questions" — trying next`);
      continue;
    }
  }
  log('  no usable existing schedule; will create one');

  log('  no existing schedule; creating new one');
  // Click "Schedule New Test" on the schedules list page if present; otherwise navigate
  const scheduleNewBtn = page.locator('a:has-text("Schedule New Test"), button:has-text("Schedule New Test")').first();
  if (await scheduleNewBtn.count()) {
    await scheduleNewBtn.click();
    await page.waitForLoadState('networkidle').catch(() => {});
  } else {
    await page.goto(`${BASE}/courses/${COURSE_ID}/tests/new`, { waitUntil: 'networkidle' });
  }
  await shot(page, '01b-schedule-new.png');

  // The main schedule form is the first <form phx-submit="save">. Scope all
  // field lookups to it because the Test Format form reuses name="name".
  const form = page.locator('form[phx-submit="save"]').first();
  await form.waitFor({ state: 'visible', timeout: 15000 });

  // Test Name
  const nameInput = form.locator('input[name="name"]').first();
  await nameInput.fill('QA Diagnostic ' + Date.now());

  // Test Date (30 days out, yyyy-mm-dd for type=date)
  const dateInput = form.locator('input[name="test_date"]').first();
  const d = new Date();
  d.setDate(d.getDate() + 30);
  const iso = d.toISOString().slice(0, 10);
  await dateInput.fill(iso);
  // Dispatch input + change so LiveView phx-change picks it up
  await dateInput.dispatchEvent('input');
  await dateInput.dispatchEvent('change');

  // Select All chapters (scoped to main form area)
  const selectAll = page.locator('button[phx-click="select_all_chapters"]').first();
  if (await selectAll.count()) {
    await selectAll.click().catch(() => {});
    await page.waitForTimeout(500);
  }

  // Submit the main form's "Schedule Test" button
  const submit = form.locator('button:has-text("Schedule Test")').first();
  await submit.waitFor({ state: 'visible', timeout: 15000 });
  await shot(page, '01b2-prefilled.png');
  await submit.click();
  // Wait for navigation away from /new
  await page.waitForURL((u) => !/\/tests\/new/.test(u.toString()), { timeout: 30000 }).catch(() => {});
  await page.waitForLoadState('networkidle').catch(() => {});
  await shot(page, '01c-post-create.png');
  log(`  after schedule create, url: ${page.url()}`);

  // If we ended up back on the list page, navigate to the NEWEST schedule's assess.
  if (/\/tests$/.test(page.url())) {
    await page.waitForLoadState('networkidle').catch(() => {});
    // Pull all schedule IDs from the list. The newest one is the second card
    // (previous is the stale "QA Diagnostic 1776998703147"); choose the LAST one.
    const ids = await page.evaluate(() => {
      const hrefs = Array.from(document.querySelectorAll('a[href*="/tests/"]'))
        .map((a) => a.getAttribute('href') || '');
      const ids = new Set();
      for (const h of hrefs) {
        const m = h.match(/\/tests\/([0-9a-f-]{36})/);
        if (m) ids.add(m[1]);
      }
      return Array.from(ids);
    });
    log(`  schedules on list: ${ids.join(', ')}`);
    // The one we just created is the one that wasn't there before — for
    // robustness, pick any id whose nearby card contains our "QA Diagnostic <ts>"
    // name; fall back to last.
    let chosen = ids[ids.length - 1];
    const newishName = (await form.locator('input[name="name"]').inputValue().catch(() => '')) || '';
    if (newishName) {
      const m2 = await page.evaluate((name) => {
        const cards = Array.from(document.querySelectorAll('a[href*="/tests/"]'));
        for (const a of cards) {
          const root = a.closest('div,article,li,section') || document.body;
          if (root.textContent && root.textContent.includes(name)) {
            const m = (a.getAttribute('href') || '').match(/\/tests\/([0-9a-f-]{36})/);
            if (m) return m[1];
          }
        }
        return null;
      }, newishName).catch(() => null);
      if (m2) chosen = m2;
    }
    log(`  chosen new schedule id: ${chosen}`);
    await page.goto(`${BASE}/courses/${COURSE_ID}/tests/${chosen}/assess`, { waitUntil: 'networkidle' });
  }
}

async function goToAssess(page) {
  // We may have landed on readiness dashboard or a schedule detail; find "Start Assessment"
  const url = page.url();
  log(`  current url: ${url}`);
  if (!/\/assess$/.test(url)) {
    const startLink = page.locator('a:has-text("Assess"), a:has-text("Start Assessment"), a:has-text("Continue Assessment"), a:has-text("Retake Assessment"), button:has-text("Assess")').first();
    if (await startLink.count()) {
      await startLink.click();
      await page.waitForLoadState('networkidle').catch(() => {});
    } else {
      // try direct navigation via schedule_id parsed from URL
      const m = url.match(/\/tests\/([^/]+)/);
      if (m) {
        await page.goto(`${BASE}/courses/${COURSE_ID}/tests/${m[1]}/assess`, { waitUntil: 'networkidle' });
      } else {
        throw new Error('Could not locate schedule id to start assessment');
      }
    }
  }
  // If the schedule has no questions OR the course is still processing, poll.
  const noQ = page.locator('text=/No questions for the selected chapters|take an assessment first/i').first();
  const stillProcessingInit = await page.locator('text=/Course is still processing|still being built|validating questions/i').count();
  if ((await noQ.count()) || stillProcessingInit > 0) {
    log('  schedule needs generation/processing to finish');
    await shot(page, 'ax-no-questions.png');
    const genBtn = page.locator('button:has-text("Generate Questions Now"), a:has-text("Generate Questions Now")').first();
    if (await genBtn.count()) {
      log('  clicking Generate Questions Now');
      await genBtn.click();
      await page.waitForLoadState('networkidle').catch(() => {});
    }
    // Poll for up to 20 minutes for an answer control to appear.
    // Generation can go through two states: "No questions for the selected
    // chapters" → "Course is still processing" → question UI.
    const deadline = Date.now() + 20 * 60 * 1000;
    let attempt = 0;
    while (Date.now() < deadline) {
      attempt++;
      await page.waitForTimeout(5000);
      // Re-visit the assess page to pick up new state
      const curUrl = page.url();
      if (!/\/assess$/.test(curUrl)) {
        const m2 = curUrl.match(/\/tests\/([0-9a-f-]{36})/);
        if (m2) {
          await page.goto(`${BASE}/courses/${COURSE_ID}/tests/${m2[1]}/assess`, { waitUntil: 'networkidle' }).catch(() => {});
        }
      } else {
        await page.reload({ waitUntil: 'networkidle' }).catch(() => {});
      }
      const haveQ = await page.locator('button[phx-click="select_answer"], textarea[name="answer"]').first().count();
      const stillEmpty = await page.locator('text=/No questions for the selected chapters/i').count();
      const stillProcessing = await page.locator('text=/Course is still processing|still being built|validating questions/i').count();
      log(`    poll attempt ${attempt}: haveQ=${haveQ}, stillEmpty=${stillEmpty}, stillProcessing=${stillProcessing}`);
      if (haveQ > 0) {
        log('  questions ready');
        return;
      }
      if (stillEmpty === 0 && stillProcessing === 0 && attempt > 2) {
        // page changed but no answer control or known waiting state — snapshot
        await shot(page, `ax-poll-${attempt}.png`);
      }
    }
    throw new Error('Question generation timed out (20 min)');
  }
}

async function takeDiagnostic(page, { wrongFirst }) {
  // Loops: select an option, submit, next, until summary appears.
  let qIndex = 0;
  const seenWrong = { done: false };
  while (true) {
    await page.waitForLoadState('networkidle').catch(() => {});
    // summary?
    const summaryMarker = page.locator('text=/Assessment Complete|Your Score|Overall Score|Topic Results|Practice Weak Topics|Back to Tests/i').first();
    if (await summaryMarker.count()) {
      log(`  summary detected after ${qIndex} questions`);
      return;
    }

    qIndex++;
    // Pick an answer
    const mcqOpts = page.locator('button[phx-click="select_answer"][phx-value-answer]');
    const mcqCount = await mcqOpts.count();
    const textarea = page.locator('textarea[name="answer"]');
    const tfBtns = page.locator('button[phx-click="select_answer"][phx-value-answer="True"], button[phx-click="select_answer"][phx-value-answer="False"]');

    if (await tfBtns.count()) {
      await tfBtns.first().click();
    } else if (mcqCount > 0) {
      // on question 1 if wrongFirst: intentionally pick last option (likely wrong)
      const pickIdx = (wrongFirst && !seenWrong.done && qIndex === 1) ? mcqCount - 1 : 0;
      await mcqOpts.nth(pickIdx).click();
    } else if (await textarea.count()) {
      await textarea.fill('I do not know.');
    } else {
      // Could be transient LiveView re-render — retry a few times
      let found = false;
      for (let r = 0; r < 6 && !found; r++) {
        await page.waitForTimeout(1500);
        const c1 = await page.locator('button[phx-click="select_answer"][phx-value-answer]').count();
        const c2 = await page.locator('textarea[name="answer"]').count();
        if (c1 + c2 > 0) { found = true; break; }
      }
      if (!found) {
        log(`  q${qIndex}: no known answer control; snapshotting and bailing`);
        await shot(page, `err-q${qIndex}-no-controls.png`);
        throw new Error(`q${qIndex}: no answer controls`);
      }
      // reroute to the known branch on next loop iteration
      qIndex--;
      continue;
    }

    // Submit
    const submit = page.locator('button[phx-click="submit_answer"]').first();
    await submit.click();
    // wait for feedback card
    await page.waitForSelector('button[phx-click="next_question"]', { timeout: 30000 }).catch(() => {});

    // On the first question (wrong), capture the feedback card for inline explanation verification
    if (wrongFirst && !seenWrong.done && qIndex === 1) {
      seenWrong.done = true;
      // Check "Why" label
      const whyBlock = page.locator('text=Why').first();
      const hasWhy = await whyBlock.count();
      const correctAnswerTxt = page.locator('text=/Correct answer:/i').first();
      const hasCorrect = await correctAnswerTxt.count();
      await shot(page, '03-wrong-feedback.png');
      findings.inline_explanation.notes = `hasCorrectAnswerText=${!!hasCorrect}, hasWhyLabel=${!!hasWhy}`;
      if (hasWhy && hasCorrect) {
        // Verify Why is visible without opening tutor (we never clicked Tutor)
        findings.inline_explanation.status = 'PASS';
      } else if (hasCorrect && !hasWhy) {
        findings.inline_explanation.status = 'FAIL';
        findings.inline_explanation.notes += ' — feedback card rendered but no "Why" explanation block';
      } else {
        findings.inline_explanation.status = 'NOT_VISIBLE';
      }

      // Also check skill badge on this card's question stem area
      const badge = page.locator('text=/Practicing:\\s*\\S/').first();
      const hasBadge = await badge.count();
      const badgeText = hasBadge ? (await badge.textContent())?.trim() : null;
      findings.skill_badge.notes = `badgeFound=${!!hasBadge}${badgeText ? ', text="' + badgeText + '"' : ''}`;
      if (hasBadge) findings.skill_badge.status = 'PASS';
      else findings.skill_badge.status = 'NOT_VISIBLE';
    }

    // Next
    const next = page.locator('button[phx-click="next_question"]').first();
    if (await next.count()) {
      await next.click();
    }
    if (qIndex > 40) {
      log('  bailing: exceeded 40 questions');
      return;
    }
  }
}

async function inspectSummary(page, { tag, expectDelta }) {
  await page.waitForLoadState('networkidle').catch(() => {});
  await checkOverflow(page, `summary-${tag}`);
  await shot(page, `04-summary-${tag}.png`);

  // Practice Weak Topics CTA
  const cta = page.locator('a:has-text("Practice Weak Topics"), button:has-text("Practice Weak Topics")').first();
  const ctaCount = await cta.count();
  const backBtn = page.locator('a:has-text("Back to Tests"), button:has-text("Back to Tests")').first();
  const retakeBtn = page.locator('a:has-text("Retake Assessment"), button:has-text("Retake Assessment")').first();

  if (tag === 'first') {
    if (ctaCount > 0) {
      // check secondary styling on back/retake: we look for border classes or smaller padding
      const backCls = (await backBtn.getAttribute('class').catch(() => '')) || '';
      const retakeCls = (await retakeBtn.getAttribute('class').catch(() => '')) || '';
      const demoted = /border/i.test(backCls) || /border/i.test(retakeCls);
      findings.weak_topics_cta.status = 'PASS';
      findings.weak_topics_cta.notes = `cta=visible; back/retake demoted=${demoted}`;
    } else {
      // No weak topics? Check if no needs-work labels on summary
      const needsWorkCount = await page.locator('text=/Needs Work/i').count();
      findings.weak_topics_cta.status = needsWorkCount > 0 ? 'FAIL' : 'NOT_VISIBLE';
      findings.weak_topics_cta.notes = `cta absent; needsWorkLabels=${needsWorkCount}`;
    }
  }

  // Readiness delta badge
  const delta = page.locator('text=/since last attempt/i').first();
  const deltaCount = await delta.count();
  if (expectDelta) {
    if (deltaCount > 0) {
      findings.readiness_delta.status = 'PASS';
      findings.readiness_delta.notes = (await delta.textContent())?.trim().slice(0, 120) || '';
    } else {
      findings.readiness_delta.status = 'FAIL';
      findings.readiness_delta.notes = 'second attempt summary did not render delta badge';
    }
  } else {
    // first attempt — must NOT show delta
    if (deltaCount > 0) {
      findings.misc.push('Delta badge shown on FIRST attempt (should require prior data)');
    }
  }

  return { ctaLocator: cta };
}

async function main() {
  const browser = await chromium.launch({ headless: true });
  try {
    // ---------- Desktop run: full flow ----------
    const ctxD = await browser.newContext({
      viewport: { width: 1440, height: 900 },
      colorScheme: 'light',
    });
    const page = await ctxD.newPage();
    page.on('pageerror', (e) => findings.misc.push(`pageerror: ${e.message}`));
    page.on('response', (r) => {
      if (r.status() >= 500) findings.misc.push(`5xx ${r.status()} ${r.url()}`);
    });

    await login(page);
    await shot(page, '00-dashboard.png');
    await openOrCreateSchedule(page);
    await goToAssess(page);
    await shot(page, '02-assess-q1.png');
    await checkOverflow(page, 'assess-q1');

    // Detect the hard free-tier block up front
    const quotaBlock = await page.locator('text=/Free Test Limit Reached/i').count();
    if (quotaBlock > 0) {
      findings.misc.push('BLOCKED: "Free Test Limit Reached" — cannot run diagnostic flow on this account this week');
      findings.weak_topics_cta.status = 'NOT_VISIBLE';
      findings.weak_topics_cta.notes = 'blocked by free-tier test limit; could not reach summary';
      findings.inline_explanation.status = 'NOT_VISIBLE';
      findings.inline_explanation.notes = 'blocked by free-tier test limit; could not answer a question wrong';
      findings.readiness_delta.status = 'NOT_VISIBLE';
      findings.readiness_delta.notes = 'blocked by free-tier test limit; could not complete two attempts';
      // Continue on to Practice page: badge feature is verifiable without consuming a test
      log('  paywalled; pivoting to Practice page for badge verification');
      const practiceUrls = [
        `${BASE}/courses/${COURSE_ID}/practice`,
        `${BASE}/practice`,
      ];
      let badgeFound = false;
      let practiceBody = '';
      for (const url of practiceUrls) {
        await page.goto(url, { waitUntil: 'networkidle' }).catch(() => {});
        await shot(page, `05-practice-${url.endsWith('/practice') ? 'global' : 'course'}.png`);
        await checkOverflow(page, `practice-${url}`);
        const noWeak = await page.locator('text=/No Weak Questions Found|No questions to practice|take an assessment first/i').count();
        const badge = page.locator('text=/Practicing:\\s*\\S/').first();
        if (await badge.count()) {
          findings.skill_badge.status = 'PASS';
          findings.skill_badge.notes = `practice page (${url}) badge: "${(await badge.textContent())?.trim()}"`;
          badgeFound = true;
          break;
        }
        practiceBody = (await page.textContent('main, body').catch(() => ''))?.slice(0, 300) || '';
        if (noWeak === 0) {
          // Page had content but no badge — meaningful FAIL signal
          findings.skill_badge.status = 'FAIL';
          findings.skill_badge.notes = `practice page rendered but no "Practicing:" chip. body: "${practiceBody.replace(/\s+/g,' ').slice(0,200)}"`;
          badgeFound = true; // we have a verdict
          break;
        }
      }
      if (!badgeFound) {
        findings.skill_badge.status = 'NOT_VISIBLE';
        findings.skill_badge.notes = `practice page shows "No Weak Questions Found" empty state (student has no wrong-answer history) — cannot verify badge without completed attempts. body: "${practiceBody.replace(/\s+/g,' ').slice(0,200)}"`;
      }
      // Mobile + dark mode smoke pass still meaningful
      await page.setViewportSize({ width: 375, height: 812 });
      await page.goto(`${BASE}/courses/${COURSE_ID}/practice`, { waitUntil: 'networkidle' }).catch(() => {});
      await shot(page, '11-mobile-practice.png');
      await checkOverflow(page, 'mobile-practice');
      await ctxD.close();
      return;
    }

    await takeDiagnostic(page, { wrongFirst: true });

    // First summary
    const { ctaLocator } = await inspectSummary(page, { tag: 'first', expectDelta: false });

    // Click "Practice Weak Topics" to verify practice page badge
    if ((await ctaLocator.count()) > 0) {
      log('  clicking Practice Weak Topics');
      await ctaLocator.click();
      await page.waitForLoadState('networkidle').catch(() => {});
      await shot(page, '05-practice-page.png');
      await checkOverflow(page, 'practice');
      // override skill-badge result with observation on the practice page (more authoritative)
      const badge = page.locator('text=/Practicing:\\s*\\S/').first();
      if (await badge.count()) {
        findings.skill_badge.status = 'PASS';
        findings.skill_badge.notes = `practice page badge: "${(await badge.textContent())?.trim()}"`;
      } else if (findings.skill_badge.status !== 'PASS') {
        findings.skill_badge.status = 'NOT_VISIBLE';
        findings.skill_badge.notes = 'no Practicing: chip on practice page card';
      }
    }

    // Return & retake for the readiness delta
    log('Starting SECOND diagnostic for delta verification');
    await page.goBack({ waitUntil: 'networkidle' }).catch(() => {});
    // find retake button on the summary
    const retake = page.locator('a:has-text("Retake Assessment"), button:has-text("Retake Assessment")').first();
    if (await retake.count()) {
      await retake.click();
      await page.waitForLoadState('networkidle').catch(() => {});
    } else {
      // fallback: back to schedule and start assessment again
      await page.goto(`${BASE}/courses/${COURSE_ID}/tests`, { waitUntil: 'networkidle' });
      await goToAssess(page);
    }
    await shot(page, '06-assess2-q1.png');
    await takeDiagnostic(page, { wrongFirst: false });
    await inspectSummary(page, { tag: 'second', expectDelta: true });

    await ctxD.close();

    // ---------- Mobile run: light check for overflow + badge ----------
    const ctxM = await browser.newContext({
      viewport: { width: 375, height: 812 },
      colorScheme: 'light',
      isMobile: true,
      hasTouch: true,
      deviceScaleFactor: 2,
    });
    const mPage = await ctxM.newPage();
    mPage.on('response', (r) => {
      if (r.status() >= 500) findings.misc.push(`mobile 5xx ${r.status()} ${r.url()}`);
    });
    await login(mPage);
    await mPage.goto(`${BASE}/courses/${COURSE_ID}/tests`, { waitUntil: 'networkidle' });
    await shot(mPage, '10-mobile-schedules.png');
    await checkOverflow(mPage, 'mobile-schedules');
    // Just navigate to practice directly to re-verify layout
    await mPage.goto(`${BASE}/courses/${COURSE_ID}/practice`, { waitUntil: 'networkidle' }).catch(() => {});
    await shot(mPage, '11-mobile-practice.png');
    await checkOverflow(mPage, 'mobile-practice');

    // Touch target spot check on practice page buttons
    const btns = mPage.locator('button, a[role="button"], a.bg-\\[\\#4CD964\\]');
    const bcount = Math.min(await btns.count(), 20);
    const undersized = [];
    for (let i = 0; i < bcount; i++) {
      const bb = await btns.nth(i).boundingBox().catch(() => null);
      if (bb && (bb.width < 44 || bb.height < 44)) {
        const t = (await btns.nth(i).textContent().catch(() => ''))?.trim().slice(0, 30) || '(no text)';
        undersized.push(`${Math.round(bb.width)}x${Math.round(bb.height)} "${t}"`);
      }
    }
    if (undersized.length) findings.misc.push(`Mobile touch targets <44: ${undersized.join(' | ')}`);

    // Dark mode smoke
    const ctxDark = await browser.newContext({
      viewport: { width: 1440, height: 900 },
      colorScheme: 'dark',
    });
    const dPage = await ctxDark.newPage();
    await login(dPage);
    await dPage.goto(`${BASE}/courses/${COURSE_ID}/practice`, { waitUntil: 'networkidle' }).catch(() => {});
    await shot(dPage, '12-dark-practice.png');
    await ctxM.close();
    await ctxDark.close();
  } catch (err) {
    console.error('FATAL:', err.message);
    findings.misc.push(`FATAL: ${err.message}`);
  } finally {
    await browser.close();
    const reportPath = path.join(SHOT_DIR, 'findings.json');
    fs.writeFileSync(reportPath, JSON.stringify(findings, null, 2));
    console.log('\n=== FINDINGS ===');
    console.log(JSON.stringify(findings, null, 2));
    console.log(`Saved: ${path.relative(REPO_ROOT, reportPath)}`);
  }
}

main();
