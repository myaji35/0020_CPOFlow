#!/usr/bin/env node
// SAP Ariba PDF Fetcher - Node.js Playwright script
// Called by Sap::AribaScraperService when Ruby playwright gem is unavailable

const { chromium } = require("playwright");
const fs = require("fs");
const path = require("path");

const USERNAME = process.env.ARIBA_USERNAME;
const PASSWORD = process.env.ARIBA_PASSWORD;
const TARGET_URL = process.env.ARIBA_TARGET_URL;
const OUTPUT_DIR = process.env.ARIBA_OUTPUT_DIR || "/tmp/ariba_pdfs";
const OUTPUT_FILE = process.argv[2] || "/tmp/ariba_results.json";

if (!USERNAME || !PASSWORD || !TARGET_URL) {
  console.error("Missing required env: ARIBA_USERNAME, ARIBA_PASSWORD, ARIBA_TARGET_URL");
  process.exit(1);
}

fs.mkdirSync(OUTPUT_DIR, { recursive: true });

(async () => {
  const browser = await chromium.launch({
    headless: true,
    args: ["--no-sandbox", "--disable-setuid-sandbox"],
  });

  const context = await browser.newContext({
    userAgent:
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36",
    acceptDownloads: true,
  });

  const page = await context.newPage();
  const results = [];

  try {
    console.log(`Navigating to: ${TARGET_URL}`);
    await page.goto(TARGET_URL, { waitUntil: "domcontentloaded", timeout: 30000 });

    // Check if login required
    const passwordField = await page.$('input[type="password"]');
    const isLoginPage = passwordField || page.url().includes("login") || page.url().includes("Authenticator");

    if (isLoginPage) {
      console.log("Login required, performing login...");
      const userField = await page.waitForSelector(
        'input[name="UserName"], input[type="email"], #username',
        { timeout: 5000 }
      );
      if (userField) await userField.fill(USERNAME);

      const passField = await page.waitForSelector('input[type="password"]', { timeout: 5000 });
      if (passField) await passField.fill(PASSWORD);

      await page.click('button[type="submit"]');
      await page.waitForLoadState("networkidle", { timeout: 30000 });

      // Re-navigate after login
      await page.goto(TARGET_URL, { waitUntil: "networkidle", timeout: 60000 });
    }

    await page.waitForTimeout(3000);

    // Find PDF links
    const pdfLinks = await page.$$eval(
      'a[href*=".pdf"], a[title*=".pdf"]',
      (els) => els.map((el) => el.href).filter(Boolean)
    );
    const uniquePdfLinks = [...new Set(pdfLinks)];
    console.log(`Found ${uniquePdfLinks.length} PDF links`);

    // Download each PDF
    for (const pdfUrl of uniquePdfLinks) {
      try {
        const [download] = await Promise.all([
          page.waitForEvent("download", { timeout: 15000 }),
          page.goto(pdfUrl),
        ]);

        const filename = download.suggestedFilename() || `ariba_doc_${Date.now()}.pdf`;
        const savePath = path.join(OUTPUT_DIR, filename);
        await download.saveAs(savePath);

        console.log(`Downloaded: ${filename}`);
        results.push({ filename, path: savePath });
      } catch (dlErr) {
        console.error(`Download failed for ${pdfUrl}: ${dlErr.message}`);
      }
    }
  } catch (err) {
    console.error(`Error: ${err.message}`);
  } finally {
    await browser.close();
  }

  fs.writeFileSync(OUTPUT_FILE, JSON.stringify(results, null, 2));
  console.log(`Results written to ${OUTPUT_FILE}`);
})();
