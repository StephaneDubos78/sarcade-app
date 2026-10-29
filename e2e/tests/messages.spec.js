// Step 1 of « Tests automatiques de bout en bout » (vault, 25 October 2026):
// scenarios 1 to 3, the PCO on the web client, ADR78-01 simulated through
// the API (the Android emulator replaces it in step 2).
const { test, expect, request: apiRequest } = require('@playwright/test');
const { createEvent, Terminal, joinEvent, openMessages, sendMessage, messageCard } = require('./helpers');

const RUN = `${Date.now()}`.slice(-6);
const EVENT_NAME = `E2E ${RUN}`;

const consoleLines = [];

test.describe.serial('PCO (web) and a field terminal', () => {
  let eventId, field, page, api;

  test.beforeAll(async ({ browser, baseURL }) => {
    api = await apiRequest.newContext({ baseURL });
    eventId = await createEvent(api, EVENT_NAME);
    field = new Terminal(api, eventId, 'ADR78-01');
    page = await browser.newPage({ baseURL, locale: 'en-US', viewport: { width: 1280, height: 900 } });
    // Browser console kept for the failure message (CI artifacts are not
    // always reachable): Flutter prints its exceptions there.
    page.on('console', (m) => { if (['error', 'warning'].includes(m.type()) || /Exception|Error|SARCADE error/.test(m.text())) consoleLines.push(`${m.type()}: ${m.text()}`.slice(0, 1500)); });
    page.on('pageerror', (e) => consoleLines.push(`pageerror: ${e.message}`.slice(0, 400)));
  });

  test.afterAll(async () => { await page?.close(); await api?.dispose(); });

  test('1. both terminals join the event and see each other', async ({}, testInfo) => {
    // The field terminal is already out (position sent), then the PCO joins.
    await field.heartbeat();
    await field.position(48.8049, 2.1204);
    await joinEvent(page, { eventName: EVENT_NAME, deviceId: 'PCO' });

    // The PCO sees the field terminal in its operators list.
    await expect(page.getByRole('group', { name: /^Operators \([1-9]/ })).toBeVisible();
    // The server knows the PCO (heartbeat of the web client).
    await expect.poll(async () => (await field.devices()).map((d) => d.device_id), { timeout: 60_000 })
      .toContain('PCO');
    await testInfo.attach('pco-map', { body: await page.screenshot(), contentType: 'image/png' });
  });

  test('2. PCO → field: urgent broadcast received, ACK back on the PCO', async ({}, testInfo) => {
    const body = `E2E urgent from PCO ${RUN}`;
    await openMessages(page);
    try {
      await sendMessage(page, body, { priority: 'Urgent' });
    } catch (e) {
      const screen = await page.locator('flt-semantics-host').innerText().catch(() => '?');
      throw new Error(`${e.message}\nscreen: ${screen.replace(/\s+/g, ' ').slice(0, 1200)}\nconsole:\n${consoleLines.slice(-15).join('\n')}`);
    }

    // The field terminal receives it through the server.
    let received;
    try {
      await expect.poll(async () => {
        received = (await field.changes()).find((c) => c.object_type === 'message' && c.payload.body === body);
        return received?.payload;
      }, { timeout: 60_000 }).toMatchObject({ sender_id: 'PCO', priority: 'urgent', recipient_ids: [] });
    } catch (e) {
      const screen = await page.locator('flt-semantics-host').innerText().catch(() => '?');
      const messages = (await field.changes()).filter((c) => c.object_type === 'message').map((c) => `${c.payload.sender_id}: ${c.payload.body}`);
      throw new Error(`message not on the server\nexpected: ${body}\nmessages of the event on the server: ${JSON.stringify(messages)}`
        + `\nscreen: ${screen.replace(/\s+/g, ' ').slice(0, 1200)}\nconsole:\n${consoleLines.slice(-25).join('\n')}`);
    }

    // It acknowledges; the PCO sees « received by 1 » under its bubble.
    await field.ack(received.payload.id, 'received');
    await expect(messageCard(page, body, 'received by 1')).toBeVisible({ timeout: 60_000 });
    await testInfo.attach('pco-ack', { body: await page.screenshot(), contentType: 'image/png' });
  });

  test('3. field → PCO: direct message shown on the PCO, acknowledged automatically', async ({}, testInfo) => {
    const body = `E2E urgent from ADR78-01 ${RUN}`;
    const message = await field.send(body, { to: ['PCO'], priority: 'urgent' });

    await expect(messageCard(page, body)).toBeVisible({ timeout: 60_000 });

    // The PCO's « received » acknowledgement reaches the server.
    await expect.poll(async () => (await field.changes()).some((c) => c.object_type === 'ack'
      && c.payload.message_id === message.id && c.payload.actor_id === 'PCO' && c.payload.status === 'received'),
    { timeout: 60_000 }).toBe(true);
    await testInfo.attach('pco-received', { body: await page.screenshot(), contentType: 'image/png' });
  });
});
