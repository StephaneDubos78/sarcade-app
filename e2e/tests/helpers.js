// Shared helpers of the end-to-end tests.
//
// - The web client is a Flutter app: its widgets become readable DOM nodes
//   (flt-semantics) once accessibility is switched on, which is what a
//   screen reader does. enableSemantics() does the same.
// - A field terminal is simulated through the server API (`Terminal`): it
//   sends positions and heartbeats, synchronises like the apps (/sync) and
//   reads the change feed. The Android emulator replaces it in step 2.
const { randomUUID } = require('node:crypto');
const { expect } = require('@playwright/test');

const API = '/api/v0.1';
const iso = (d = new Date()) => d.toISOString();

/** Creates a fresh event so that every test run starts clean. */
async function createEvent(request, name) {
  const r = await request.post(`${API}/events`, { data: { name, kind: 'exercise', summary: 'e2e' } });
  expect(r.ok(), `event created (${r.status()})`).toBeTruthy();
  return (await r.json()).id;
}

class Terminal {
  constructor(request, eventId, deviceId) {
    this.request = request; this.eventId = eventId; this.deviceId = deviceId; this.cursor = 0;
  }

  async heartbeat() {
    const r = await this.request.post(`${API}/events/${this.eventId}/devices/${this.deviceId}/heartbeat`,
      { data: { label: this.deviceId, platform: 'android', app_version: 'e2e' } });
    expect(r.ok(), 'heartbeat accepted').toBeTruthy();
  }

  async position(lat, lon) {
    const r = await this.request.post(`${API}/positions`, { data: {
      id: randomUUID(), event_id: this.eventId, device_id: this.deviceId, lat, lon, accuracy_m: 5, time: iso() } });
    expect(r.ok(), 'position accepted').toBeTruthy();
  }

  async sync(objectType, payload) {
    const r = await this.request.post(`${API}/sync`, { data: [{
      operation_id: randomUUID(), event_id: this.eventId, object_id: payload.id, object_type: objectType,
      action: 'create', client_time: iso(), payload }] });
    expect(r.ok(), 'sync answered').toBeTruthy();
    const [result] = await r.json();
    expect(result.status, `${objectType} accepted by the server`).toBe('accepted');
  }

  async send(body, { to = [], priority = 'urgent' } = {}) {
    const message = { id: randomUUID(), event_id: this.eventId, sender_id: this.deviceId,
      recipient_ids: to, priority, body, created_at: iso() };
    await this.sync('message', message);
    return message;
  }

  async ack(messageId, status = 'received') {
    await this.sync('ack', { id: randomUUID(), event_id: this.eventId, message_id: messageId,
      actor_id: this.deviceId, status, time: iso() });
  }

  /** All changes of the event (the terminal's view of the server). */
  async changes() {
    const r = await this.request.get(`${API}/events/${this.eventId}/sync/changes?after=0&limit=2000`);
    expect(r.ok()).toBeTruthy();
    return (await r.json()).changes;
  }

  async devices() {
    const r = await this.request.get(`${API}/events/${this.eventId}/devices`);
    expect(r.ok()).toBeTruthy();
    return r.json();
  }
}

/** Switches on the accessibility tree of the Flutter web app. */
async function enableSemantics(page) {
  await page.waitForSelector('flt-semantics-placeholder', { state: 'attached', timeout: 60_000 });
  await page.evaluate(() => document.querySelector('flt-semantics-placeholder').click());
  await page.waitForSelector('flt-semantics', { state: 'attached' });
}

/** First run of the web app: server, event chosen in the list, identifier. */
async function joinEvent(page, { eventName, deviceId }) {
  await page.goto('/');
  await enableSemantics(page);
  await page.getByRole('button', { name: 'Reload the event list' }).click();
  await page.getByRole('button', { name: /^Event/ }).click();
  await page.getByRole('menuitem', { name: new RegExp(`^${eventName}`) }).click();
  // Typed again until Flutter holds it: a first entry is sometimes lost
  // while the event list reloads (« device-demo » seen on main).
  const idField = page.getByLabel('Terminal identifier');
  await expect(async () => {
    await idField.click();
    await idField.fill(deviceId);
    await expect(idField).toHaveValue(deviceId, { timeout: 2_000 });
  }).toPass({ timeout: 30_000 });
  await page.getByRole('button', { name: 'Save' }).click();
  await expect(page.getByRole('button', { name: 'Messages', exact: true })).toBeVisible();
}

async function openMessages(page) {
  await page.getByRole('button', { name: 'Messages', exact: true }).click();
  await expect(page.getByLabel('Short message')).toBeVisible();
}

/** Sends a message from the messages screen (general broadcast by default). */
async function sendMessage(page, body, { priority = 'Urgent' } = {}) {
  await page.getByRole('button', { name: /^(Routine|Urgent|Immediate)$/ }).click();
  await page.getByRole('menuitem', { name: priority }).click();
  // Typed until Flutter holds it, then sent until the field empties: on a
  // busy CI machine the click could reach Flutter before the typed text
  // (message never sent, 26-27 October 2026).
  const field = page.getByLabel('Short message');
  // The priority menu must be closed again (a click during its opening
  // animation can be lost on a busy machine, the menu then hides the page).
  await expect(async () => {
    if (!(await field.isVisible())) {
      const item = page.getByRole('menuitem', { name: priority });
      if (await item.count()) await item.first().click(); else await page.keyboard.press('Escape');
    }
    await expect(field).toBeVisible({ timeout: 2_000 });
  }).toPass({ timeout: 30_000 });
  await expect(async () => {
    await field.fill(body);
    await expect(field).toHaveValue(body, { timeout: 2_000 });
  }).toPass({ timeout: 30_000 });
  let attempt = 0;
  await expect(async () => {
    if ((await field.inputValue()) === body) {
      // Flutter may not have taken the filled text yet: from the second
      // attempt on, it is typed again key by key (real keyboard events)
      // and sent with Enter (Enter sends on a computer keyboard).
      if (attempt++ === 0) {
        await page.getByRole('button', { name: 'Send', exact: true }).click();
      } else {
        await field.click();
        await page.keyboard.press('Control+A');
        await page.keyboard.press('Delete');
        await page.keyboard.type(body, { delay: 5 });
        await page.keyboard.press('Enter');
      }
    }
    await expect(field).toHaveValue('', { timeout: 3_000 });
  }).toPass({ timeout: 45_000 });
}

/** The message card, found by its text and, optionally, its ACK line.
 * Flutter exposes a card either as a group whose accessible name holds its
 * lines (cards with a menu) or as plain text nodes: both are accepted. The
 * ACK pattern stops at the first « ACK: » after the text, i.e. the same card. */
function messageCard(page, body, ack) {
  const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const re = new RegExp(esc(body) + (ack ? `(?:(?!ACK:)[\\s\\S])*ACK: ${esc(ack)}` : ''));
  return page.getByRole('group', { name: re })
    .or(page.locator('flt-semantics').filter({ hasText: re }))
    .first();
}

module.exports = { createEvent, Terminal, enableSemantics, joinEvent, openMessages, sendMessage, messageCard };
