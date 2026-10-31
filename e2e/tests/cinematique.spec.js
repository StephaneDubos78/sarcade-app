// Revue de cinématique (vault, 31 Oct 2026), point E: on every pull request,
// the ways out of the main screens at the three sizes (phone, tablet,
// computer). Each scenario opens a screen, leaves it, and checks the map
// answers a drag. Buttons are found by their stable identifier (point B,
// flt-semantics-identifier), whatever the language.
const { test, expect, request: apiRequest } = require('@playwright/test');
const { createEvent, Terminal, joinEvent } = require('./helpers');

const RUN = `${Date.now()}`.slice(-6);
const SIZES = [
  { n: 'tel', width: 390, height: 844 },
  { n: 'tab', width: 820, height: 1180 },
  { n: 'pc', width: 1440, height: 900 },
];

/** Centre of the node of [id], or null when it is not on screen. */
async function centreOf(page, id) {
  return page.evaluate((id) => {
    const e = [...document.querySelectorAll(`[flt-semantics-identifier="${id}"]`)].find((x) => x.getBoundingClientRect().width > 2);
    if (!e) return null; const r = e.getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
  }, id);
}
async function tapId(page, id) {
  let at = null;
  await expect(async () => { at = await centreOf(page, id); expect(at, `${id} on screen`).not.toBeNull(); }).toPass({ timeout: 15_000 });
  await page.mouse.click(at.x, at.y); await page.waitForTimeout(800);
}
/** True when some node shows [text] (in its label or its text). */
async function textShown(page, text) {
  return page.evaluate((text) => [...document.querySelectorAll('flt-semantics')]
    .some((x) => ((x.getAttribute('aria-label') || '') + ' ' + (x.textContent || '')).includes(text) && x.getBoundingClientRect().width > 2), text);
}
/** Any node whose label is exactly [label] (button, chip, list item). */
async function tapLabel(page, label) {
  let at = null;
  await expect(async () => {
    at = await page.evaluate((label) => {
      const e = [...document.querySelectorAll('flt-semantics')].find((x) => ((x.getAttribute('aria-label') || x.textContent || '').trim().replace(/\s+/g, ' ')) === label
        && x.getBoundingClientRect().width > 2);
      if (!e) return null; const r = e.getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
    }, label);
    expect(at, `« ${label} » on screen`).not.toBeNull();
  }).toPass({ timeout: 15_000 });
  await page.mouse.click(at.x, at.y); await page.waitForTimeout(800);
}
async function tapName(page, name) {
  await page.getByRole('button', { name, exact: true }).first().click(); await page.waitForTimeout(800);
}
/** Position of the TEL-01 marker label on the map. */
async function marker(page) {
  return page.evaluate(() => {
    const e = [...document.querySelectorAll('flt-semantics')].find((x) => x.childElementCount === 0 && /TEL-01/.test(x.textContent || '')
      && x.getBoundingClientRect().width < 300 && x.getBoundingClientRect().height < 120);
    if (!e) return null; const r = e.getBoundingClientRect(); return { x: r.x, y: r.y };
  });
}
/** The map shows and a drag moves it (20 steps: a faster drag of the robot
 *  is not taken as a drag by Flutter). The map is put back afterwards. */
async function expectMapFree(page, size, what) {
  await expect(page.locator('[flt-semantics-identifier="map.map-layers"]'), `${what}: map shown`).toHaveCount(1, { timeout: 10_000 });
  const x = size.width * 0.3, y = size.height * 0.45;
  const before = await marker(page);
  expect(before, `${what}: TEL-01 on the map`).not.toBeNull();
  await page.mouse.move(x, y); await page.mouse.down(); await page.mouse.move(x + 70, y + 50, { steps: 20 }); await page.mouse.up();
  await page.waitForTimeout(700);
  const after = await marker(page);
  await page.mouse.move(x + 70, y + 50); await page.mouse.down(); await page.mouse.move(x, y, { steps: 20 }); await page.mouse.up();
  await page.waitForTimeout(400);
  expect(after && Math.abs(after.x - before.x) + Math.abs(after.y - before.y), `${what}: the map moves under a drag`).toBeGreaterThan(20);
}
/** Point menu: long press on a phone or a tablet, right click on a computer. */
async function pointMenu(page, size) {
  const x = size.width * 0.3, y = size.height * 0.35;
  if (size.n === 'pc') { await page.mouse.click(x, y, { button: 'right' }); }
  else { await page.mouse.move(x, y); await page.mouse.down(); await page.waitForTimeout(900); await page.mouse.up(); }
  await page.waitForTimeout(800);
}

for (const size of SIZES) {
  test.describe.serial(`cinématique ${size.n}`, () => {
    let page, api;
    const compact = size.n === 'tel';

    test.beforeAll(async ({ browser, baseURL }) => {
      api = await apiRequest.newContext({ baseURL });
      const name = `E2E cinematique ${size.n} ${RUN}`;
      const eventId = await createEvent(api, name);
      const t1 = new Terminal(api, eventId, 'TEL-01'); await t1.heartbeat(); await t1.position(48.8049, 2.1204);
      page = await browser.newPage({ baseURL, locale: 'en-US', viewport: { width: size.width, height: size.height } });
      await joinEvent(page, { eventName: name, deviceId: `CIN-${size.n}` });
      await page.waitForTimeout(2500);
      await expectMapFree(page, size, 'start');
    });
    test.afterAll(async () => { await page?.close(); await api?.dispose(); });

    test('every section, then « Carte »', async () => {
      const ids = compact ? ['nav.messages', 'nav.teams', 'nav.tools', 'nav.more'] : ['nav.messages', 'nav.teams', 'nav.files', 'nav.tools', 'nav.settings'];
      for (const id of ids) {
        await tapId(page, id);
        await tapId(page, 'nav.map');
        await expectMapFree(page, size, `${id} › Carte`);
      }
    });

    test('Itinéraires and Résection: ✕ and « Carte » give the map back', async () => {
      for (const tool of ['tool.routes', 'tool.resection']) {
        await tapId(page, 'nav.tools'); await tapId(page, tool);
        await tapName(page, 'Close');
        await expectMapFree(page, size, `${tool} › ✕`);
        await tapId(page, 'nav.tools'); await tapId(page, tool);
        await tapId(page, 'nav.map');
        await expectMapFree(page, size, `${tool} › Carte`);
      }
    });

    test('« Sélectionner une zone »: the map moves, « Carte » leaves it (C1)', async () => {
      await pointMenu(page, size);
      await tapId(page, 'point.select');
      await expectMapFree(page, size, 'selection mode, drag');
      await tapId(page, 'nav.map');
      await expect(page.getByText('Tap objects, or long press then drag for a rectangle')).toHaveCount(0);
      await expectMapFree(page, size, 'selection › Carte');
    });

    test('converter « Touch the map »: « Carte » and Escape end it (N1, N2)', async () => {
      const exits = compact ? ['Carte'] : ['Carte', 'Escape'];
      for (const exit of exits) {
        await tapId(page, 'nav.tools'); await tapId(page, 'tool.converter');
        await tapLabel(page, 'Touch the map');
        await expect.poll(() => textShown(page, 'point to convert'), { timeout: 10_000 }).toBe(true);
        if (exit === 'Carte') await tapId(page, 'nav.map'); else { await page.keyboard.press('Escape'); await page.waitForTimeout(700); }
        await expect.poll(() => textShown(page, 'point to convert'), { timeout: 5_000 }).toBe(false);
        await expectMapFree(page, size, `converter pick › ${exit}`);
      }
    });

    test('Escape closes an empty drawing bar (N1)', async () => {
      if (compact) test.skip(true, 'no keyboard on a phone');
      await tapId(page, 'map.drawing-tools');
      await expect(page.getByRole('button', { name: 'Close the tools' }).first()).toBeVisible({ timeout: 10_000 });
      await page.keyboard.press('Escape'); await page.waitForTimeout(700);
      await expect(page.getByRole('button', { name: 'Close the tools' })).toHaveCount(0);
      await expectMapFree(page, size, 'drawing bar › Échap');
    });

    test('point menu and base map sheet close with Escape', async () => {
      if (compact) test.skip(true, 'no keyboard on a phone');
      await pointMenu(page, size);
      await page.keyboard.press('Escape'); await page.waitForTimeout(700);
      await expectMapFree(page, size, 'point menu › Échap');
      await tapId(page, 'map.map-layers');
      await page.keyboard.press('Escape'); await page.waitForTimeout(700);
      await expectMapFree(page, size, 'base map › Échap');
    });
  });
}
