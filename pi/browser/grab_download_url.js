async (page) => {
  const dlPromise = page.waitForEvent('download', { timeout: 30000 });
  await page.getByRole('link', { name: 'Download' }).first().click();
  const dl = await dlPromise;
  const url = dl.url();
  console.log('DOWNLOAD_URL: ' + url);
  try { await dl.cancel(); } catch (e) { console.log('cancel: ' + e.message); }
  return 'DONE';
}
