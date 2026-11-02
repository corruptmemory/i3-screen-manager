// Clicks one named link on a TSPlus applications page and records what the page tries to
// launch. Long or secret-looking values are reduced to their length; request bodies are
// never read. Answer Cancel if the browser offers to open xdg-open.
//   node portal-launch-watch.mjs <url-prefix> <link text>
const [prefix, label] = process.argv.slice(2);
if (!prefix || !label) {
  console.error("usage: portal-launch-watch.mjs <url-prefix> <link text>");
  process.exit(2);
}
const tabs = await (await fetch("http://127.0.0.1:9222/json")).json();
const matches = tabs.filter((t) => t.type === "page" && t.url.startsWith(prefix));
if (matches.length !== 1) {
  console.error(`expected exactly one tab under ${prefix}, found ${matches.length}`);
  process.exit(2);
}
const ws = new WebSocket(matches[0].webSocketDebuggerUrl);
await new Promise((ok) => ws.addEventListener("open", ok, { once: true }));

const SECRET = /pass|pwd|token|secret|key|sid|session|auth|cred/i;
const short = (k, v) => (SECRET.test(k) || v.length > 24 ? `<${v.length} chars>` : v);
function clean(raw) {
  const m = /^([a-zA-Z][a-zA-Z0-9+.-]*):(.*)$/s.exec(raw);
  if (!m) return `<unparsed, ${raw.length} chars>`;
  const [, scheme, rest] = m;
  const q = rest.indexOf("?");
  const base = q < 0 ? rest : rest.slice(0, q);
  const shownBase = /^https?$/i.test(scheme) ? base : base.replace(/[^/]{25,}/g, (s) => `<${s.length} chars>`);
  if (q < 0) return `${scheme}:${shownBase}`;
  const params = new URLSearchParams(rest.slice(q + 1));
  return `${scheme}:${shownBase}?${[...params].map(([k, v]) => `${k}=${short(k, v)}`).join("&")}`;
}

let id = 0;
const waiting = new Map();
const log = (what, url) => console.log(`${what}: ${clean(url)}`);
ws.addEventListener("message", (e) => {
  const m = JSON.parse(e.data);
  if (m.id && waiting.has(m.id)) { waiting.get(m.id)(m); waiting.delete(m.id); return; }
  const p = m.params ?? {};
  if (m.method === "Page.frameRequestedNavigation") log(`frameRequestedNavigation (${p.reason}/${p.disposition})`, p.url);
  if (m.method === "Page.frameScheduledNavigation") log("frameScheduledNavigation", p.url);
  if (m.method === "Page.frameNavigated") log("frameNavigated", p.frame.url);
  if (m.method === "Page.windowOpen") log("windowOpen", p.url);
  if (m.method === "Network.requestWillBeSent" && !/\.(png|jpg|svg|css|woff2?)(\?|$)/.test(p.request.url)) log(`request ${p.request.method}`, p.request.url);
});
const send = (method, params = {}) => new Promise((ok, no) => {
  const n = ++id;
  const timer = setTimeout(() => no(new Error(`${method}: timed out`)), 12000);
  waiting.set(n, (m) => { clearTimeout(timer); m.error ? no(new Error(`${method}: ${m.error.message}`)) : ok(m.result); });
  ws.send(JSON.stringify({ id: n, method, params }));
});
const pause = (ms) => new Promise((ok) => setTimeout(ok, ms));

await send("Page.enable");
await send("Network.enable");

const found = await send("Runtime.evaluate", {
  returnByValue: true,
  expression: `(() => {
    const a = [...document.querySelectorAll("a")].find((x) => x.textContent.trim() === ${JSON.stringify(label)});
    if (!a) return null;
    const r = a.getBoundingClientRect();
    return { x: r.x + r.width / 2, y: r.y + r.height / 2, href: a.getAttribute("href"), onclick: a.getAttribute("onclick") };
  })()`,
});
const link = found.result.value;
if (!link) { console.error(`no link named ${label}`); process.exit(3); }
console.log(`link: href=${link.href} onclick=${link.onclick}`);

for (const type of ["mouseMoved", "mousePressed", "mouseReleased"]) {
  await send("Input.dispatchMouseEvent", { type, x: link.x, y: link.y, button: type === "mouseMoved" ? "none" : "left", clickCount: type === "mouseMoved" ? 0 : 1 });
}
console.log("clicked; watching for 8 s");
await pause(8000);
ws.close();
