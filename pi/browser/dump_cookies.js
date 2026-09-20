async (page) => {
  const cookies = await page.context().cookies(['https://takeout.google.com', 'https://accounts.google.com', 'https://www.google.com', 'https://youtube.com']);
  const lines = ['# Netscape HTTP Cookie File'];
  for (const c of cookies) {
    const dom = c.domain;
    const sub = dom.startsWith('.') ? 'TRUE' : 'FALSE';
    const exp = (c.expires && c.expires > 0) ? Math.floor(c.expires) : 0;
    lines.push([dom, sub, c.path, c.secure ? 'TRUE' : 'FALSE', String(exp), c.name, c.value].join('\t'));
  }
  return lines.join('\n');
}
