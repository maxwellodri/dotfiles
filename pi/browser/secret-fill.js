// secret-fill.js — parameterized pass → form secret injection for the playwright MCP.
//
// Run via:  mcp({ tool: "playwright_browser_run_code_unsafe",
//                 args: '{"filename":"<dotfiles>/pi/browser/secret-fill.js"}' })
//
// Reads JSON params from ~/Downloads/pi/secret-fill.params.json (the agent writes
// it per run and deletes it afterwards). The secret itself never touches the
// params file, the agent transcript, or this script's return value: it goes
// gpg → pass (host child process) → CDP → page, end to end.
//
// params:
//   entry      required  pass entry name, e.g. "bank"      → `pass show bank`
//   pass       required  CSS selector of the secret field
//   user       optional  CSS selector of a non-secret field (e.g. username)
//   userValue  optional  value for `user` — plaintext, NON-secret only
//   submit     optional  CSS selector of the submit control — strongly
//                        recommended: a populated field must not survive into
//                        any snapshot (snapshot/click results expose field
//                        values; see web-browser-use skill)
//   otp        optional  true → `pass otp <entry>` (TOTP code) instead of
//                        `pass show <entry>` (first line = password)
//   sequential optional  true → pressSequentially() instead of fill(), for
//                        keystroke-fussy fields
//
// Depends on the CJS build of @playwright/mcp (process.mainModule) — the pin in
// pi/mcp.json is what keeps the vm → host realm hop below working.
async (page) => {
  // the vm sandbox has no require/import — hop to the host realm via page's class
  const hostFunction = page.constructor.constructor;
  const hostRequire = hostFunction('return process.mainModule.require')();
  const { execFileSync } = hostRequire('node:child_process');
  const fs = hostRequire('node:fs');
  const os = hostRequire('node:os');
  const path = hostRequire('node:path');

  const paramsPath = path.join(os.homedir(), 'Downloads', 'pi', 'secret-fill.params.json');
  let params;
  try {
    params = JSON.parse(fs.readFileSync(paramsPath, 'utf8'));
  } catch (e) {
    throw new Error('cannot read ' + paramsPath + ' — write the params file first (' + e.message + ')');
  }
  if (!params.entry || !params.pass) {
    throw new Error('params need at least "entry" and "pass"');
  }

  // resolve every selector BEFORE fetching the secret — fail with fields empty
  for (const sel of [params.pass, params.user, params.submit].filter(Boolean)) {
    if ((await page.locator(sel).count()) === 0) {
      throw new Error('selector matches nothing: ' + sel);
    }
  }

  let secret;
  try {
    const out = execFileSync('pass',
      [params.otp ? 'otp' : 'show', params.entry],
      { encoding: 'utf8', timeout: 15000 });
    secret = params.otp ? out.trim() : out.split('\n')[0].trim(); // line 1 = password
  } catch (e) {
    throw new Error('pass failed for "' + params.entry + '": ' + String(e.message).split('\n')[0]);
  }
  if (!secret) throw new Error('pass returned an empty first line for "' + params.entry + '"');

  if (params.user) await page.fill(params.user, String(params.userValue ?? ''));
  if (params.sequential) {
    await page.locator(params.pass).pressSequentially(secret);
  } else {
    await page.fill(params.pass, secret);
  }
  const ok = (await page.inputValue(params.pass)) === secret;

  let submitted = false;
  if (ok && params.submit) {
    await page.click(params.submit);
    await page.waitForLoadState('domcontentloaded').catch(() => {});
    submitted = true;
  }

  // derived facts only — never the secret
  const result = { ok, submitted, url: page.url() };
  if (!submitted) {
    result.hint = 'secret field still populated — do NOT snapshot or use click/type next ' +
      '(they attach snapshots that expose field values); submit or clear the field first';
  }
  return result;
}
