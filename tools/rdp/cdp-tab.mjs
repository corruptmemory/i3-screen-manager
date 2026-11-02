// Drives the one browser tab whose URL starts with the given prefix, over raw CDP.
// Other tabs are never attached to or printed. Needs Node 21+ for the built-in WebSocket.
//   node cdp-tab.mjs [--port N] <url-prefix> '<json array of steps>'
// Steps: {op:"shot",file} {op:"click",x,y} {op:"type",text} {op:"focus"} {op:"wait",ms}
//        {op:"key",key,code,vk,ctrl,shift,holdMs,commands} {op:"eval",expr,label,gesture}
//        {op:"copyTiming",token,holdMs} {op:"front"}
// "focus" emulates page focus for this attach only. Coordinates are CSS pixels, so divide
// screenshot pixels by devicePixelRatio. See docs/agent-guide/remote-desktop.md.
import { writeFileSync } from "node:fs";

const args = process.argv.slice(2);
let port = 9222;
if (args[0] === "--port") { port = Number(args[1]); args.splice(0, 2); }
const [prefix, stepsJson] = args;
if (!prefix || !stepsJson) {
  console.error("usage: cdp-tab.mjs [--port N] <url-prefix> '<json steps>'");
  process.exit(2);
}
const steps = JSON.parse(stepsJson);
const tabs = await (await fetch(`http://127.0.0.1:${port}/json`)).json();
const matches = tabs.filter((t) => t.type === "page" && t.url.startsWith(prefix));
if (matches.length !== 1) {
  console.error(`expected exactly one tab under ${prefix}, found ${matches.length}`);
  process.exit(2);
}
const ws = new WebSocket(matches[0].webSocketDebuggerUrl);
await new Promise((ok, no) => {
  ws.addEventListener("open", ok, { once: true });
  ws.addEventListener("error", no, { once: true });
});

let id = 0;
const waiting = new Map();
ws.addEventListener("message", (e) => {
  const m = JSON.parse(e.data);
  if (m.id && waiting.has(m.id)) { waiting.get(m.id)(m); waiting.delete(m.id); }
});
const send = (method, params = {}) => new Promise((ok, no) => {
  const n = ++id;
  const timer = setTimeout(() => no(new Error(`${method}: timed out`)), 15000);
  waiting.set(n, (m) => {
    clearTimeout(timer);
    if (m.error) no(new Error(`${method}: ${m.error.message}`));
    else ok(m.result);
  });
  ws.send(JSON.stringify({ id: n, method, params }));
});
const pause = (ms) => new Promise((ok) => setTimeout(ok, ms));

const SHIFTED = { "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7", "*": "8", "(": "9", ")": "0", _: "-", "+": "=", ":": ";", '"': "'", "<": ",", ">": ".", "?": "/" };
const PUNCT = { "-": [189, "Minus"], "=": [187, "Equal"], ";": [186, "Semicolon"], "'": [222, "Quote"], ",": [188, "Comma"], ".": [190, "Period"], "/": [191, "Slash"] };

function describe(ch) {
  if (ch === " ") return { vk: 32, code: "Space", shift: false };
  if (ch === "\n") return { vk: 13, code: "Enter", shift: false, key: "Enter", text: "\r" };
  if (/[a-z]/.test(ch)) return { vk: ch.toUpperCase().charCodeAt(0), code: `Key${ch.toUpperCase()}`, shift: false };
  if (/[A-Z]/.test(ch)) return { vk: ch.charCodeAt(0), code: `Key${ch}`, shift: true };
  if (/[0-9]/.test(ch)) return { vk: ch.charCodeAt(0), code: `Digit${ch}`, shift: false };
  const base = SHIFTED[ch] ?? ch;
  const shift = ch in SHIFTED;
  if (/[0-9]/.test(base)) return { vk: base.charCodeAt(0), code: `Digit${base}`, shift };
  if (PUNCT[base]) return { vk: PUNCT[base][0], code: PUNCT[base][1], shift };
  throw new Error(`no key mapping for ${JSON.stringify(ch)}`);
}

async function shiftEvent(type) {
  await send("Input.dispatchKeyEvent", { type, key: "Shift", code: "ShiftLeft", windowsVirtualKeyCode: 16, modifiers: type === "rawKeyDown" ? 8 : 0 });
}

async function typeChar(ch) {
  const d = describe(ch);
  const key = d.key ?? ch;
  const text = d.text ?? ch;
  if (d.shift) await shiftEvent("rawKeyDown");
  const modifiers = d.shift ? 8 : 0;
  await send("Input.dispatchKeyEvent", { type: "keyDown", key, code: d.code, windowsVirtualKeyCode: d.vk, text, unmodifiedText: text, modifiers });
  await send("Input.dispatchKeyEvent", { type: "keyUp", key, code: d.code, windowsVirtualKeyCode: d.vk, modifiers });
  if (d.shift) await shiftEvent("keyUp");
  await pause(25);
}

// A synthetic Ctrl+V does not paste by itself: pass commands:["paste"] for that.
async function combo({ key, code, vk, ctrl, shift, holdMs = 30, commands }) {
  const c = code ?? `Key${key.toUpperCase()}`;
  const v = vk ?? key.toUpperCase().charCodeAt(0);
  const modifiers = (ctrl ? 2 : 0) | (shift ? 8 : 0);
  if (ctrl) await send("Input.dispatchKeyEvent", { type: "rawKeyDown", key: "Control", code: "ControlLeft", windowsVirtualKeyCode: 17, modifiers: 2 });
  if (shift) await send("Input.dispatchKeyEvent", { type: "rawKeyDown", key: "Shift", code: "ShiftLeft", windowsVirtualKeyCode: 16, modifiers });
  await send("Input.dispatchKeyEvent", { type: "rawKeyDown", key, code: c, windowsVirtualKeyCode: v, modifiers, ...(commands ? { commands } : {}) });
  await pause(holdMs);
  await send("Input.dispatchKeyEvent", { type: "keyUp", key, code: c, windowsVirtualKeyCode: v, modifiers });
  if (shift) await send("Input.dispatchKeyEvent", { type: "keyUp", key: "Shift", code: "ShiftLeft", windowsVirtualKeyCode: 16, modifiers: ctrl ? 2 : 0 });
  if (ctrl) await send("Input.dispatchKeyEvent", { type: "keyUp", key: "Control", code: "ControlLeft", windowsVirtualKeyCode: 17, modifiers: 0 });
}

await send("Page.enable");
for (const s of steps) {
  const started = Date.now();
  if (s.op === "shot") {
    const png = await send("Page.captureScreenshot", { format: "png" });
    const bytes = Buffer.from(png.data, "base64");
    writeFileSync(s.file, bytes);
    console.log(`shot ${s.file} ${bytes.length} bytes ${Date.now() - started}ms`);
  } else if (s.op === "click") {
    await send("Input.dispatchMouseEvent", { type: "mouseMoved", x: s.x, y: s.y, button: "none" });
    await send("Input.dispatchMouseEvent", { type: "mousePressed", x: s.x, y: s.y, button: "left", clickCount: 1 });
    await send("Input.dispatchMouseEvent", { type: "mouseReleased", x: s.x, y: s.y, button: "left", clickCount: 1 });
    console.log(`click ${s.x},${s.y}`);
  } else if (s.op === "type") {
    for (const ch of s.text) await typeChar(ch);
    console.log(`typed ${s.text.length} chars in ${Date.now() - started}ms`);
  } else if (s.op === "key") {
    await combo(s);
    console.log(`key ${s.ctrl ? "ctrl+" : ""}${s.shift ? "shift+" : ""}${s.key} hold ${s.holdMs ?? 30}ms`);
  } else if (s.op === "eval") {
    const r = await send("Runtime.evaluate", { expression: s.expr, returnByValue: true, awaitPromise: true, userGesture: Boolean(s.gesture) });
    const value = r.exceptionDetails ? `EXCEPTION ${r.exceptionDetails.exception?.description ?? r.exceptionDetails.text}` : r.result.value;
    console.log(`${s.label ?? "eval"}: ${typeof value === "string" ? value : JSON.stringify(value)}`);
  } else if (s.op === "front") {
    // A tab opened with /json/new can sit in the background, where a screenshot may hang.
    await send("Page.bringToFront");
  } else if (s.op === "focus") {
    await send("Emulation.setFocusEmulationEnabled", { enabled: true });
    console.log("focus emulation on for this attach");
  } else if (s.op === "copyTiming") {
    // Press Ctrl+C for holdMs and time when the token reaches the TSPlus client's clipbuffer.
    const t0 = Date.now();
    let arrived = null;
    let stop = false;
    const poller = (async () => {
      while (!stop) {
        const r = await send("Runtime.evaluate", { expression: "W.clipbuffer", returnByValue: true });
        if (String(r.result.value).includes(s.token)) { arrived = Date.now() - t0; return; }
        await pause(15);
      }
    })();
    await combo({ key: "c", ctrl: true, holdMs: s.holdMs });
    const released = Date.now() - t0;
    while (arrived === null && Date.now() - t0 < 5000) await pause(20);
    stop = true;
    await poller;
    console.log(`copy hold=${s.holdMs}ms released_at=${released}ms clipbuffer_at=${arrived ?? "never"}ms arrived_before_release=${arrived !== null && arrived < released}`);
  } else if (s.op === "wait") {
    await pause(s.ms);
  } else {
    throw new Error(`unknown step ${s.op}`);
  }
}
ws.close();
