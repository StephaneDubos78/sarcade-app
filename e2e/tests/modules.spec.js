// Modules per event (card « Séparer le Core et les modules », step 2, 31 Oct
// 2026): an event « family » shows neither bearing, resection nor APRS; an
// exercise (ADRASEC module) shows them. Buttons found by their stable
// identifiers.
const { test, expect, request: apiRequest } = require('@playwright/test');
const { joinEvent } = require('./helpers');

const RUN = `${Date.now()}`.slice(-6);
const API = '/api/v0.1';

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
const shown = (page, id) => page.locator(`[flt-semantics-identifier="${id}"]`);

for (const c of [{ kind: 'family', adrasec: false }, { kind: 'exercise', adrasec: true }]) {
  test(`event « ${c.kind} »: ADRASEC entries ${c.adrasec ? 'shown' : 'hidden'}`, async ({ browser, baseURL }) => {
    const api = await apiRequest.newContext({ baseURL });
    const name = `E2E modules ${c.kind} ${RUN}`;
    const r = await api.post(`${API}/events`, { data: { name, kind: c.kind } });
    expect(r.ok()).toBeTruthy();
    expect((await r.json()).settings?.modules ?? (await (await api.get(`${API}/events/${(await r.json()).id}`)).json()).settings.modules)
      .toEqual(c.adrasec ? ['adrasec'] : []);
    const page = await browser.newPage({ baseURL, locale: 'en-US', viewport: { width: 1440, height: 900 } });
    await joinEvent(page, { eventName: name, deviceId: `MOD-${c.kind}` });
    await page.waitForTimeout(3000);
    // Point menu (right click on a computer).
    await page.mouse.click(700, 300, { button: 'right' }); await page.waitForTimeout(900);
    await expect(shown(page, 'point.measure')).toHaveCount(1, { timeout: 10_000 });
    await expect(shown(page, 'point.bearing')).toHaveCount(c.adrasec ? 1 : 0);
    await page.keyboard.press('Escape'); await page.waitForTimeout(600);
    // Tools.
    await tapId(page, 'nav.tools');
    await expect(shown(page, 'tool.routes')).toHaveCount(1, { timeout: 10_000 });
    await expect(shown(page, 'tool.resection')).toHaveCount(c.adrasec ? 1 : 0);
    await page.close(); await api.dispose();
  });
}
