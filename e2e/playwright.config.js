// @ts-check
const { defineConfig } = require('@playwright/test');

// The server (and the web client it serves) is started by the CI job, see
// .github/workflows/ci.yml (job e2e) and e2e/README.md.
module.exports = defineConfig({
  testDir: './tests',
  timeout: 120_000,
  expect: { timeout: 30_000 },
  fullyParallel: false,
  workers: 1,
  retries: process.env.CI ? 1 : 0,
  reporter: [['list'], ['html', { open: 'never', outputFolder: 'report' }]],
  use: {
    baseURL: process.env.SARCADE_URL || 'http://localhost:8000',
    locale: 'en-US',
    viewport: { width: 1280, height: 900 },
    screenshot: 'on',
    trace: 'retain-on-failure',
    video: 'retain-on-failure',
  },
});
