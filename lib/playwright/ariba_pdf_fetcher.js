#!/usr/bin/env node
// SAP Ariba PDF Fetcher - Node.js Playwright script
// Called by Sap::AribaScraperService when Ruby playwright gem is unavailable
// Handles Ariba 2-step login and post-login redirect chain

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

function log(msg) {
  console.log(`[${new Date().toISOString()}] ${msg}`);
}

async function saveScreenshot(page, name) {
  const screenshotPath = path.join(OUTPUT_DIR, `ariba_${name}.png`);
  try {
    await page.screenshot({ path: screenshotPath, fullPage: true });
    log(`Screenshot: ${screenshotPath}`);
  } catch (e) {
    log(`Screenshot failed (${name}): ${e.message}`);
  }
}

async function waitForStableUrl(page, timeoutMs = 30000) {
  // Wait until the URL stops changing (all redirects complete)
  const start = Date.now();
  let lastUrl = page.url();
  let stableCount = 0;

  while (Date.now() - start < timeoutMs) {
    await page.waitForTimeout(1000);
    const currentUrl = page.url();
    if (currentUrl === lastUrl) {
      stableCount++;
      if (stableCount >= 3) {
        log(`URL stable for 3s: ${currentUrl}`);
        return;
      }
    } else {
      log(`URL changed: ${currentUrl}`);
      lastUrl = currentUrl;
      stableCount = 0;
    }
  }
  log(`URL stabilization timeout (last: ${lastUrl})`);
}

async function performLogin(page) {
  log("Login required...");

  // Ariba Supplier Login: Username and Password on same page
  // Fill BOTH fields first, then click Login button

  // Fill Username
  try {
    const userField = await page.waitForSelector(
      'input[name="UserName"], input[type="email"], #username, input[name="username"], input[placeholder*="User Name"]',
      { timeout: 15000, state: "visible" }
    );
    if (userField) {
      await userField.fill(USERNAME);
      log("Username entered");
    }
  } catch (e) {
    log(`Username field not found: ${e.message}`);
    return false;
  }

  // Fill Password (on same page)
  let passwordFilled = false;
  try {
    const passField = await page.waitForSelector(
      'input[type="password"], input[name="Password"], input[placeholder*="Password"]',
      { timeout: 5000, state: "visible" }
    );
    if (passField) {
      await passField.fill(PASSWORD);
      passwordFilled = true;
      log("Password entered (same page)");
    }
  } catch (e) {
    log("Password not visible on same page, will try after submit...");
  }

  await saveScreenshot(page, "01_credentials_filled");

  if (passwordFilled) {
    // Both fields filled - click Login
    const loginBtn = await page.$('button:has-text("Login"), button[type="submit"], input[type="submit"], .loginButton, #loginButton');
    if (loginBtn) {
      await Promise.allSettled([
        page.waitForNavigation({ timeout: 60000 }).catch(() => {}),
        loginBtn.click(),
      ]);
      log("Login submitted (single-page)");
    }
  } else {
    // 2-step login fallback: submit username first, then password
    log("Trying 2-step login...");
    const submitBtn = await page.$('button[type="submit"], input[type="submit"], #nextBtn, .submitBtn');
    if (submitBtn) {
      await Promise.allSettled([
        page.waitForNavigation({ timeout: 15000 }).catch(() => {}),
        submitBtn.click(),
      ]);
      log("Username submitted");
      await page.waitForTimeout(3000);
    }

    // Now try to fill password
    try {
      const passField = await page.waitForSelector(
        'input[type="password"]',
        { timeout: 10000, state: "visible" }
      );
      if (passField) {
        await passField.fill(PASSWORD);
        log("Password entered (step 2)");
      }
    } catch (e) {
      // Force-show hidden password fields
      log("Force-showing password field...");
      try {
        await page.evaluate(() => {
          document.querySelectorAll('input[type="password"]').forEach((f) => {
            f.classList.remove("displayNone");
            f.style.display = "block";
            f.style.visibility = "visible";
            f.style.opacity = "1";
            let parent = f.parentElement;
            for (let i = 0; i < 5 && parent; i++) {
              parent.style.display = "block";
              parent.style.visibility = "visible";
              parent.classList.remove("displayNone");
              parent = parent.parentElement;
            }
          });
        });
        const passField = await page.waitForSelector('input[type="password"]', { timeout: 5000 });
        if (passField) await passField.fill(PASSWORD);
      } catch (e2) {
        log(`Password field not found: ${e2.message}`);
        await saveScreenshot(page, "02_password_failed");
        return false;
      }
    }

    // Submit login
    const loginBtn = await page.$('button[type="submit"], input[type="submit"], .submitBtn');
    if (loginBtn) {
      await Promise.allSettled([
        page.waitForNavigation({ timeout: 60000 }).catch(() => {}),
        loginBtn.click(),
      ]);
      log("Login submitted (2-step)");
    }
  }

  // Wait for all redirects to complete (Ariba does multiple redirects after login)
  await waitForStableUrl(page, 45000);
  await saveScreenshot(page, "03_after_login");

  log(`Post-login URL: ${page.url()}`);
  log(`Post-login title: ${await page.title()}`);

  return true;
}

async function findAndDownloadPdfs(page) {
  const results = [];

  // Strategy 1: Direct PDF links
  let pdfLinks = [];
  try {
    pdfLinks = await page.$$eval(
      'a[href*=".pdf"], a[title*=".pdf"], a[href*="download"], a[href*="attachment"]',
      (els) =>
        els
          .map((el) => ({ href: el.href, text: el.textContent?.trim() || "" }))
          .filter((l) => l.href)
    );
  } catch (e) {
    log(`PDF link search failed: ${e.message}`);
  }
  const uniqueHrefs = [...new Set(pdfLinks.map((l) => l.href))];
  log(`Found ${uniqueHrefs.length} potential PDF/download links`);

  for (const pdfUrl of uniqueHrefs) {
    try {
      const [download] = await Promise.all([
        page.waitForEvent("download", { timeout: 20000 }),
        page.evaluate((url) => {
          const a = document.createElement("a");
          a.href = url;
          a.click();
        }, pdfUrl),
      ]);

      const filename = download.suggestedFilename() || `ariba_doc_${Date.now()}.pdf`;
      const savePath = path.join(OUTPUT_DIR, filename);
      await download.saveAs(savePath);

      log(`Downloaded: ${filename}`);
      results.push({ filename, path: savePath });
    } catch (dlErr) {
      log(`Download failed for ${pdfUrl}: ${dlErr.message}`);
    }
  }

  // Strategy 2: Look for print/export buttons if no PDFs found yet
  if (results.length === 0) {
    log("No direct PDF links found, trying print/export buttons...");
    try {
      const printBtns = await page.$$('button:has-text("Print"), a:has-text("Print"), button:has-text("Export"), a:has-text("Export"), button:has-text("PDF"), a:has-text("PDF")');
      for (const btn of printBtns) {
        const btnText = await btn.textContent();
        log(`Found button: "${btnText.trim()}"`);
        try {
          const [download] = await Promise.all([
            page.waitForEvent("download", { timeout: 15000 }),
            btn.click(),
          ]);

          const filename = download.suggestedFilename() || `ariba_print_${Date.now()}.pdf`;
          const savePath = path.join(OUTPUT_DIR, filename);
          await download.saveAs(savePath);
          log(`Downloaded via button: ${filename}`);
          results.push({ filename, path: savePath });
        } catch (e) {
          log(`Button click download failed: ${e.message}`);
        }
      }
    } catch (e) {
      log(`Print button search failed: ${e.message}`);
    }
  }

  // Strategy 3: Generate PDF from page content as fallback
  if (results.length === 0) {
    log("No downloads succeeded, generating PDF from page content...");
    try {
      const filename = `ariba_page_${Date.now()}.pdf`;
      const savePath = path.join(OUTPUT_DIR, filename);
      await page.pdf({
        path: savePath,
        format: "A4",
        printBackground: true,
        margin: { top: "1cm", right: "1cm", bottom: "1cm", left: "1cm" },
      });
      log(`Page PDF generated: ${filename}`);
      results.push({ filename, path: savePath });
    } catch (e) {
      log(`Page PDF generation failed: ${e.message}`);
    }
  }

  return results;
}

(async () => {
  const browser = await chromium.launch({
    headless: true,
    args: [
      "--no-sandbox",
      "--disable-setuid-sandbox",
      "--disable-dev-shm-usage",
      "--disable-gpu",
    ],
  });

  const context = await browser.newContext({
    userAgent:
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    acceptDownloads: true,
    viewport: { width: 1280, height: 900 },
  });

  const page = await context.newPage();
  let results = [];

  try {
    // Step 1: Navigate to target URL
    log(`Navigating to: ${TARGET_URL}`);
    try {
      await page.goto(TARGET_URL, { waitUntil: "domcontentloaded", timeout: 60000 });
    } catch (navErr) {
      // Even if timeout, check if page loaded partially
      log(`Initial navigation issue: ${navErr.message}`);
      log(`Current URL after nav attempt: ${page.url()}`);
    }

    // Wait for page to settle
    await page.waitForTimeout(3000);
    await saveScreenshot(page, "00_initial");

    log(`Current URL: ${page.url()}`);
    log(`Page title: ${await page.title()}`);

    // Step 2: Check if login required
    const isLoginPage = await page.evaluate(() => {
      const hasPasswordField = !!document.querySelector('input[type="password"]');
      const hasUserField = !!document.querySelector('input[name="UserName"]');
      const url = window.location.href;
      return hasPasswordField || hasUserField || url.includes("login") || url.includes("Authenticator");
    });

    if (isLoginPage) {
      const loginSuccess = await performLogin(page);
      if (!loginSuccess) {
        log("Login failed, aborting");
        throw new Error("Login failed");
      }

      // After login, navigate to target URL
      // Wait a bit before re-navigating to let session cookies settle
      await page.waitForTimeout(5000);

      log(`Re-navigating to target URL: ${TARGET_URL}`);
      try {
        await page.goto(TARGET_URL, { waitUntil: "domcontentloaded", timeout: 60000 });
      } catch (renavErr) {
        log(`Re-navigation issue: ${renavErr.message}`);
        log(`Current URL: ${page.url()}`);
      }

      // Wait for all redirects to complete
      await waitForStableUrl(page, 20000);
    }

    await page.waitForTimeout(3000);
    await saveScreenshot(page, "05_target_page");

    log(`Final URL: ${page.url()}`);
    log(`Final title: ${await page.title()}`);

    // Log page content summary for debugging
    const pageInfo = await page.evaluate(() => {
      const links = document.querySelectorAll("a");
      const buttons = document.querySelectorAll("button");
      const iframes = document.querySelectorAll("iframe");
      return {
        linkCount: links.length,
        buttonCount: buttons.length,
        iframeCount: iframes.length,
        bodyTextLength: document.body?.innerText?.length || 0,
        sampleLinks: Array.from(links)
          .slice(0, 10)
          .map((a) => ({ href: a.href, text: a.textContent?.trim()?.substring(0, 50) })),
      };
    });
    log(`Page info: ${JSON.stringify(pageInfo, null, 2)}`);

    // Step 3: Find and download PDFs
    results = await findAndDownloadPdfs(page);

    // Step 4: Check iframes (Ariba often uses iframes for content)
    if (results.length === 0 && pageInfo.iframeCount > 0) {
      log(`Checking ${pageInfo.iframeCount} iframes for PDF content...`);
      const frames = page.frames();
      for (const frame of frames) {
        if (frame === page.mainFrame()) continue;
        try {
          const frameUrl = frame.url();
          log(`Checking iframe: ${frameUrl}`);
          const framePdfLinks = await frame.$$eval(
            'a[href*=".pdf"], a[href*="download"], a[href*="attachment"]',
            (els) => els.map((el) => el.href).filter(Boolean)
          );
          if (framePdfLinks.length > 0) {
            log(`Found ${framePdfLinks.length} PDF links in iframe`);
            for (const pdfUrl of framePdfLinks) {
              try {
                const [download] = await Promise.all([
                  page.waitForEvent("download", { timeout: 15000 }),
                  frame.evaluate((url) => {
                    const a = document.createElement("a");
                    a.href = url;
                    a.click();
                  }, pdfUrl),
                ]);
                const filename = download.suggestedFilename() || `ariba_iframe_${Date.now()}.pdf`;
                const savePath = path.join(OUTPUT_DIR, filename);
                await download.saveAs(savePath);
                log(`Downloaded from iframe: ${filename}`);
                results.push({ filename, path: savePath });
              } catch (e) {
                log(`Iframe download failed: ${e.message}`);
              }
            }
          }
        } catch (e) {
          log(`Iframe check failed: ${e.message}`);
        }
      }
    }

    log(`Total files collected: ${results.length}`);
  } catch (err) {
    log(`Error: ${err.message}`);
    await saveScreenshot(page, "error_final");
  } finally {
    await browser.close();
  }

  fs.writeFileSync(OUTPUT_FILE, JSON.stringify(results, null, 2));
  log(`Results written to ${OUTPUT_FILE}`);
})();
