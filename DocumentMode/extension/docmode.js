// Ghost Overlay Document Workspace - an original document-editor layout for the ChatGPT app window.
// Runs only in the standalone app window (display-mode: standalone); ordinary tabs are untouched.
// Every control drives a real ChatGPT control or a local browser action (print, find, download).
// It reads the page only to display it to you; it stores nothing but your view preferences
// (chatgpt.com localStorage, shared by that site's pages in this Chrome profile) and makes no network
// requests of its own. Renaming a chat goes through ChatGPT's own Rename dialog.
(() => {
  'use strict';
  if (!matchMedia('(display-mode: standalone)').matches) return;
  if (window.__ghostDocWorkspace) return;
  window.__ghostDocWorkspace = true;

  const root = document.documentElement;
  root.setAttribute('data-ghost-docmode', '1');

  // ---- keep the site's light palette in this window (some blocks carry their own dark theme)
  const keepLight = () => { if (root.getAttribute('data-theme') !== 'light') root.setAttribute('data-theme', 'light'); };
  const lighten = (el) => {
    if (el.nodeType !== 1) return;
    if (el.getAttribute('data-theme') === 'dark') el.setAttribute('data-theme', 'light');
    el.querySelectorAll('[data-theme="dark"]').forEach(e => e.setAttribute('data-theme', 'light'));
  };
  keepLight();
  new MutationObserver(records => {
    for (const r of records) {
      if (r.type === 'attributes') { if (r.target === root) keepLight(); else lighten(r.target); }
      else r.addedNodes.forEach(lighten);
    }
  }).observe(root, { attributes: true, attributeFilter: ['data-theme'], childList: true, subtree: true });

  // ---- preferences (view settings only)
  const PREF_KEY = 'ghost-docmode-prefs';
  const prefs = Object.assign({
    zoom: 100, pageW: 'fit', toolbar: true, tabs: true, ruler: true, serif: false,
    rail: false, sidebar: false, header: false, original: false, compact: 'auto',
  }, (() => { try { return JSON.parse(localStorage.getItem(PREF_KEY)) || {}; } catch { return {}; } })());
  if (prefs.v !== 2) { prefs.v = 2; prefs.pageW = 'fit'; }   // layout v2: page fits the window by default
  const savePrefs = () => { try { localStorage.setItem(PREF_KEY, JSON.stringify(prefs)); } catch {} applyPrefs(); };
  const setAttr = (name, on) => on ? root.setAttribute(name, '') : root.removeAttribute(name);

  // ---- small helpers
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const frame = () => new Promise(r => requestAnimationFrame(() => r()));
  const label = el => el.getAttribute('aria-label') || '';
  // ChatGPT keeps recently visited pages mounted but hidden (for swipe-back navigation), so a selector
  // can match an invisible copy first. These helpers always pick what is actually on screen.
  const onScreen = el => el.getClientRects().length > 0 && el.getBoundingClientRect().width > 0;
  const shown = (s, r = document) => {
    let best = null, bw = 0;
    for (const e of r.querySelectorAll(s)) { const w = e.getBoundingClientRect().width; if (w > bw) { best = e; bw = w; } }
    return best;
  };
  const byLabel = (re, scope = document) => { const all = $$('button[aria-label]', scope).filter(b => re.test(label(b))); return all.find(onScreen) || all[0]; };
  const lastByLabel = (re, scope) => { if (!scope) return null; const all = $$('button[aria-label]', scope).filter(b => re.test(label(b))); return all[all.length - 1] || null; };

  const thread = () => shown('[data-thread-find-target=conversation]');
  const page = () => shown('[data-thread-user-message-navigation-content]');
  const header = () => shown('header[data-app-shell-titlebar]') || $('header[data-app-shell-titlebar]');
  const homeNav = () => $('nav[aria-label="Home"]');
  const editor = () => { const f = shown('form[data-chatgpt-composer]'); return (f && $('.ProseMirror', f)) || $('[data-composer-markdown] .ProseMirror') || $('.ProseMirror[contenteditable=true]'); };
  const isTemporary = () => /[?&]temporary-chat=true/.test(location.search) || !!byLabel(/^Save chat$/);

  // Real ChatGPT controls the workspace drives.
  const N = {
    newChat: () => byLabel(/^New chat$/, header() || document),
    saveTemp: () => byLabel(/^Save chat$/),
    tempToggle: () => byLabel(/temporary chat$/i),
    share: () => { const h = header(); return h && $$('button', h).find(b => /^share\b/i.test(label(b) || b.textContent.trim())); },
    chatActions: () => { const h = header(); return h && $$('button[aria-haspopup=menu]', h).find(b => label(b) === 'Chat actions'); },
    model: () => byLabel(/^Select ChatGPT model$/),
    tools: () => byLabel(/^Add files and more$/),
    dictate: () => byLabel(/^Dictate$/),
    stop: () => byLabel(/^Stop/),
    personal: () => { const h = header(); return h && $$('button[aria-haspopup=menu]', h).find(b => b.textContent.trim()); },
    profile: () => byLabel(/^Open profile menu$/),
    projectsPage: () => $('[data-sidebar-destination="builtin:projects"]'),
    homeRail: () => $('[data-sidebar-destination="builtin:home"]'),
    search: () => { const n = homeNav(); return n && byLabel(/^Search$/, n); },
    toggleSidebar: () => byLabel(/^Toggle sidebar$/),
    newProject: () => byLabel(/^Add new project$/),
    copyAnswer: () => lastByLabel(/^Copy$/, thread()),
    regenerate: () => lastByLabel(/^Regenerate response$/, thread()),
    readAloud: () => lastByLabel(/^Read aloud$|^Stop reading/, thread()),
    editPrompt: () => lastByLabel(/^Edit message$/, thread()),
    fileAny: () => fileInputs().find(i => !i.accept),
    filePhotos: () => fileInputs().find(i => i.accept === 'image/*' && i.multiple) || fileInputs().find(i => /image/.test(i.accept)),
  };

  // File inputs of the composer on screen first (a hidden page keeps its own composer and inputs).
  function fileInputs() {
    const f = shown('form[data-chatgpt-composer]'), all = $$('input[type=file]');
    return f ? all.filter(i => f.contains(i)).concat(all.filter(i => !f.contains(i))) : all;
  }
  // Press a native control the way a pointer would: Radix menus open on pointerdown, others on click.
  function press(btn) {
    if (!btn) return false;
    if (btn.getAttribute('aria-haspopup') === 'menu') {
      const o = { bubbles: true, cancelable: true, button: 0, pointerType: 'mouse', pointerId: 1, isPrimary: true };
      btn.dispatchEvent(new PointerEvent('pointerdown', o));
      btn.dispatchEvent(new PointerEvent('pointerup', o));
    } else {
      btn.click();
    }
    return true;
  }
  // Header and rail controls are folded away by default; show them while their own menu is open.
  async function revealPress(where, find) {
    const attr = 'data-gd-reveal-' + where;
    const wasShown = where === 'header' ? prefs.header : prefs.rail;
    if (!wasShown) { root.setAttribute(attr, ''); await frame(); await sleep(150); }
    const ok = press(find());
    if (!ok) { root.removeAttribute(attr); return false; }
    if (!wasShown) {
      // fold it away again once its popup has closed
      const open = () => $$('[role=menu], [role=dialog], [data-radix-popper-content-wrapper]').some(e => e.getBoundingClientRect().width > 0);
      let seen = false;
      for (let i = 0; i < 600; i++) {
        await sleep(250);
        if (open()) seen = true; else if (seen || i > 8) break;
      }
      root.removeAttribute(attr);
    }
    return true;
  }
  const navigate = (href) => {
    const a = $$('a[href]').find(x => x.getAttribute('href') === href);
    if (a) a.click(); else location.assign(href);
  };
  const newChat = () => { const b = N.newChat(); if (b) b.click(); else navigate('/'); };

  // ---- composer editing (the place you write prompts)
  function focusEditor() { const e = editor(); if (e) e.focus(); return e; }
  function insert(text) { if (!focusEditor()) return toast('The message box is not available here.'); document.execCommand('insertText', false, text); }
  function wrap(pre, post = pre) {
    if (!focusEditor()) return toast('The message box is not available here.');
    const sel = getSelection(); const t = sel.toString();
    document.execCommand('insertText', false, pre + t + post);
    if (!t) for (let i = 0; i < post.length; i++) sel.modify('move', 'backward', 'character');
  }
  function linePrefix(prefix) {
    if (!focusEditor()) return toast('The message box is not available here.');
    const sel = getSelection(); sel.collapseToStart(); sel.modify('move', 'backward', 'lineboundary');
    document.execCommand('insertText', false, prefix);
  }
  function editorKey(key, shift = false) {
    const e = focusEditor(); if (!e) return toast('The message box is not available here.');
    const ok = e.dispatchEvent(new KeyboardEvent('keydown', { key, code: 'Key' + key.toUpperCase(), ctrlKey: true, shiftKey: shift, bubbles: true, cancelable: true }));
    if (ok) document.execCommand(key === 'z' && !shift ? 'undo' : 'redo');
  }
  async function paste() {
    try { const t = await navigator.clipboard.readText(); if (t) insert(t); }
    catch { toast('Paste was blocked by the browser. Use Ctrl+V.'); }
  }
  function selectAll() {
    const e = editor();
    if (e && (document.activeElement === e || e.contains(document.activeElement))) { document.execCommand('selectAll'); return; }
    const t = thread(); if (!t) return;
    const r = document.createRange(); r.selectNodeContents(t);
    const s = getSelection(); s.removeAllRanges(); s.addRange(r);
  }

  // ---- document actions
  const docTitle = () => { const t = document.title.trim(); return !t || t === 'ChatGPT' ? 'Untitled chat' : t; };
  function documentText() {
    const t = thread(); if (!t) return '';
    return $$('[data-user-message-bubble], [data-markdown-text-style=assistant-message]', t).map(el =>
      el.matches('[data-user-message-bubble]') ? 'Prompt:\n' + el.innerText.trim() : el.innerText.trim()).join('\n\n');
  }
  function download() {
    const text = documentText(); if (!text) return toast('There is no conversation on this page yet.');
    const blob = new Blob([docTitle() + '\n\n' + text + '\n'], { type: 'text/plain' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = docTitle().replace(/[\\/:*?"<>|]+/g, '-').slice(0, 80) + '.txt';
    document.body.append(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 2000);
  }
  addEventListener('beforeprint', () => {
    if (prefs.original) return;
    const t = thread(); if (!t) return;
    const d = document.createElement('div'); d.id = 'gd-print'; d.style.display = 'none';
    const h = document.createElement('h1'); h.className = 'gd-print-title'; h.textContent = docTitle();
    d.append(h, t.cloneNode(true)); document.body.append(d);
    root.setAttribute('data-gd-printing', '');
  });
  addEventListener('afterprint', () => { $('#gd-print')?.remove(); root.removeAttribute('data-gd-printing'); });
  function wordCount() {
    const t = thread();
    const count = s => (s.match(/\S+/g) || []).length;
    const ans = t ? $$('[data-markdown-text-style=assistant-message]', t).map(e => e.innerText) : [];
    const pr = t ? $$('[data-user-message-bubble]', t).map(e => e.innerText) : [];
    const all = ans.concat(pr).join(' ');
    dialog('Word count', [
      ['Words in answers', count(ans.join(' '))], ['Words in prompts', count(pr.join(' '))],
      ['Total words', count(all)], ['Characters (no spaces)', all.replace(/\s/g, '').length],
      ['Prompts', pr.length], ['Answers', ans.length],
    ]);
  }
  // ChatGPT's own sidebar stays folded away in the workspace (chats and projects are in the tabs and
  // menus) unless switched on here. Hiding it never changes ChatGPT's saved sidebar setting.
  async function toggleSidebar() {
    prefs.sidebar = !prefs.sidebar; savePrefs();
    if (prefs.sidebar && $('[data-app-shell-sidebar-open=false]')) { await harvest(); press(N.toggleSidebar()) || toast('The ChatGPT sidebar control is not available.'); }
  }
  function toggleFullscreen() { document.fullscreenElement ? document.exitFullscreen() : root.requestFullscreen().catch(() => toast('Full screen is not available.')); }
  function setZoom(z) { prefs.zoom = Math.max(50, Math.min(200, z)); savePrefs(); }

  // ---- chat history and projects (read from ChatGPT's own navigation panel)
  let chats = [], projects = [], harvesting = false, harvestTries = 0, lastHarvest = 0;
  // ChatGPT's in-page chat list can lag behind a rename (it may come from an older cache). A title
  // confirmed here only replaces names that list showed before the rename; once it shows the new name,
  // or a name it never showed before (renamed in ChatGPT or on another device), ChatGPT's list wins.
  // The open chat always shows its live page title.
  const renamedTitles = new Map();   // conversation id -> { title, stale: names the list showed before }
  const navSeen = new Map();         // conversation id -> names ChatGPT's list has shown in this window
  const idOf = href => (href.match(/\/c\/([0-9a-f-]{36})(?:\/|$)/) || [])[1] || '';
  function knownTitle(href, navTitle) {
    const id = idOf(href);
    if (!id) return navTitle;
    const r = renamedTitles.get(id);
    if (r && (navTitle === r.title || !r.stale.has(navTitle))) renamedTitles.delete(id);
    if (!navSeen.has(id)) navSeen.set(id, new Set());
    navSeen.get(id).add(navTitle);
    if (id === convId() && !renaming && pageTitle() && pageTitle() !== 'ChatGPT') return pageTitle();
    return renamedTitles.get(id)?.title || navTitle;
  }
  function readNav() {
    const n = homeNav(); if (!n) return false;
    const links = $$('a[href^="/c/"]', n);
    const seen = new Set();
    chats = links.map(a => ({ href: a.getAttribute('href'), title: knownTitle(a.getAttribute('href'), (label(a) || a.textContent).trim() || 'Untitled chat'), a }))
      .filter(c => !seen.has(c.href) && seen.add(c.href));
    projects = $$('button[aria-label^="New chat in "]', n).map(btn => {
      const name = label(btn).slice('New chat in '.length);
      let group = btn;
      while (group.parentElement && group.parentElement !== n && $$('button[aria-label^="New chat in "]', group.parentElement).length === 1) group = group.parentElement;
      const items = $$('a[href*="/g/g-p-"]', group).map(a => ({ href: a.getAttribute('href'), title: knownTitle(a.getAttribute('href'), (label(a) || a.textContent).trim() || 'Untitled chat') }));
      return { name, btn, items };
    });
    return links.length > 0 || projects.length > 0;
  }
  async function harvest() {
    if (harvesting) return;
    if (readNav() && chats.length) return;
    harvestTries++; lastHarvest = Date.now();
    const b = N.homeRail(); if (!b) return;
    harvesting = true; root.setAttribute('data-gd-harvest', '');
    const o = { bubbles: true, pointerType: 'mouse' };
    b.dispatchEvent(new PointerEvent('pointerover', o)); b.dispatchEvent(new PointerEvent('pointerenter', o));
    b.dispatchEvent(new MouseEvent('mouseover', o)); b.dispatchEvent(new MouseEvent('mouseenter', o));
    for (let i = 0; i < 20 && !readNav(); i++) await sleep(100);
    b.dispatchEvent(new PointerEvent('pointerleave', o)); b.dispatchEvent(new PointerEvent('pointerout', o));
    b.dispatchEvent(new MouseEvent('mouseout', o)); b.dispatchEvent(new MouseEvent('mouseleave', o));
    await sleep(350);
    root.removeAttribute('data-gd-harvest'); harvesting = false;
    renderTabs();
  }
  const currentHref = () => location.pathname;

  // ---- icons (original line icons)
  const P = {
    undo: '<path d="M9 14 4 9l5-5"/><path d="M4 9h10.5a5.5 5.5 0 0 1 0 11H11"/>',
    redo: '<path d="m15 14 5-5-5-5"/><path d="M20 9H9.5a5.5 5.5 0 0 0 0 11H13"/>',
    print: '<path d="M7 8V3h10v5"/><rect x="3" y="8" width="18" height="9" rx="2"/><path d="M7 14h10v7H7z"/>',
    code: '<path d="m9 7-5 5 5 5M15 7l5 5-5 5"/>',
    bullets: '<path d="M9 6h11M9 12h11M9 18h11"/><circle cx="4.5" cy="6" r=".9" fill="currentColor"/><circle cx="4.5" cy="12" r=".9" fill="currentColor"/><circle cx="4.5" cy="18" r=".9" fill="currentColor"/>',
    numbers: '<path d="M10 6h10M10 12h10M10 18h10"/><path d="M4 4.5 5.5 4v4M4 11h2.2L4 14h2.4M4 16.5h2.2l-1.2 1.6a1.1 1.1 0 1 1-1 1.5"/>',
    quote: '<path d="M10 11H6.5a.5.5 0 0 1-.5-.5V8a1 1 0 0 1 1-1h2a1 1 0 0 1 1 1v4c0 2.5-1.2 4-3.5 5M19 11h-3.5a.5.5 0 0 1-.5-.5V8a1 1 0 0 1 1-1h2a1 1 0 0 1 1 1v4c0 2.5-1.2 4-3.5 5"/>',
    link: '<path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1"/><path d="M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1"/>',
    attach: '<path d="M20 11.5 12.4 19a5 5 0 0 1-7-7L13 4.4a3.4 3.4 0 0 1 4.8 4.8L10.3 16.7a1.8 1.8 0 0 1-2.6-2.6L14.5 7.4"/>',
    plus: '<path d="M12 5v14M5 12h14"/>',
    find: '<circle cx="11" cy="11" r="6"/><path d="m20 20-4.5-4.5"/>',
    copy: '<rect x="8" y="8" width="12" height="12" rx="2"/><path d="M16 8V5.5A1.5 1.5 0 0 0 14.5 4h-9A1.5 1.5 0 0 0 4 5.5v9A1.5 1.5 0 0 0 5.5 16H8"/>',
    regen: '<path d="M20 12a8 8 0 1 1-2.6-5.9"/><path d="M20 4v5h-5"/>',
    speak: '<path d="M4 10v4h4l5 4V6l-5 4z"/><path d="M16.5 9a4 4 0 0 1 0 6M19 6.5a7.5 7.5 0 0 1 0 11"/>',
    mic: '<rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21"/>',
    newchat: '<path d="M12 4H6a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-6"/><path d="M17.5 3.5a2.1 2.1 0 0 1 3 3L13 14l-4 1 1-4z"/>',
    share: '<path d="M12 15V3.5M7.5 8 12 3.5 16.5 8"/><path d="M5 13v5.5A2.5 2.5 0 0 0 7.5 21h9a2.5 2.5 0 0 0 2.5-2.5V13"/>',
    more: '<circle cx="5.5" cy="12" r="1.3" fill="currentColor"/><circle cx="12" cy="12" r="1.3" fill="currentColor"/><circle cx="18.5" cy="12" r="1.3" fill="currentColor"/>',
    menu: '<path d="M4 7h16M4 12h16M4 17h16"/>',
    chev: '<path d="m7 10 5 5 5-5"/>',
    check: '<path d="m5 12.5 4.5 4.5L19 7.5"/>',
    back: '<path d="m14.5 6-6 6 6 6"/>',
    next: '<path d="m9.5 6 6 6-6 6"/>',
    up: '<path d="m6 14.5 6-6 6 6"/>',
    down: '<path d="m6 9.5 6 6 6-6"/>',
    close: '<path d="M6 6l12 12M18 6 6 18"/>',
    tools: '<path d="M4 7h10M18 7h2M4 17h4M12 17h8"/><circle cx="16" cy="7" r="2"/><circle cx="10" cy="17" r="2"/>',
    model: '<path d="M12 3 4 7.5v9L12 21l8-4.5v-9z"/><path d="M4 7.5 12 12l8-4.5M12 12v9"/>',
    clock: '<circle cx="12" cy="12" r="8"/><path d="M12 8v4.5l3 2"/>',
    pen: '<path d="M4.5 19.5 5.5 15 15.8 4.7a2 2 0 0 1 2.9 0l.6.6a2 2 0 0 1 0 2.9L9 18.5z"/><path d="m14 6.5 3.5 3.5"/>',
  };
  const icon = (name, size = 18) => `<svg viewBox="0 0 24 24" width="${size}" height="${size}" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${P[name] || ''}</svg>`;
  // Original app icon: a plain page in the Soft Light accent with two text lines.
  const APP_ICON = `<svg viewBox="0 0 32 32" width="30" height="30" aria-hidden="true">
    <path d="M9.5 3h10L25 8.5v18a2.5 2.5 0 0 1-2.5 2.5h-13A2.5 2.5 0 0 1 7 26.5v-21A2.5 2.5 0 0 1 9.5 3z" fill="#4B77BE" stroke="#4B77BE" stroke-width="1" stroke-linejoin="round"/>
    <path d="M11 14h9M11 18.5h6" stroke="#fff" stroke-width="2.2" stroke-linecap="round"/></svg>`;
  const esc = s => String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

  // ---- menus: each item runs a real action; items whose ChatGPT control is absent are disabled
  const SEP = { sep: true };
  const MENUS = () => [
    { id: 'file', label: 'File', items: [
      { label: 'New chat', icon: 'newchat', run: newChat },
      { label: 'New temporary chat', run: () => location.assign('/?temporary-chat=true') },
      { label: 'Open chat…', kbd: 'Search', run: async () => { await harvest(); press(N.search()) || openMenu('chats'); } },
      SEP,
      { label: 'Share…', icon: 'share', run: () => press(N.share()), enabled: () => !!N.share() },
      { label: 'Save temporary chat', run: () => press(N.saveTemp()), enabled: () => !!N.saveTemp() },
      SEP,
      { label: 'Download as text (.txt)', run: download, enabled: () => !!thread() },
      { label: 'Print…', icon: 'print', kbd: 'Ctrl+P', run: () => print(), enabled: () => !!thread() },
      SEP,
      { label: 'Original ChatGPT layout', run: () => { prefs.original = true; savePrefs(); } },
    ] },
    { id: 'edit', label: 'Edit', items: [
      { label: 'Undo', icon: 'undo', kbd: 'Ctrl+Z', run: () => editorKey('z') },
      { label: 'Redo', icon: 'redo', kbd: 'Ctrl+Y', run: () => editorKey('z', true) },
      SEP,
      { label: 'Cut', kbd: 'Ctrl+X', run: () => document.execCommand('cut') },
      { label: 'Copy', kbd: 'Ctrl+C', run: () => document.execCommand('copy') },
      { label: 'Paste', kbd: 'Ctrl+V', run: paste },
      { label: 'Select all', kbd: 'Ctrl+A', run: selectAll },
      SEP,
      { label: 'Find in document…', icon: 'find', run: openFind, enabled: () => !!thread() },
      SEP,
      { label: 'Edit last prompt', run: () => press(N.editPrompt()), enabled: () => !!N.editPrompt() },
      { label: 'Copy last answer', icon: 'copy', run: () => press(N.copyAnswer()) && toast('Answer copied'), enabled: () => !!N.copyAnswer() },
    ] },
    { id: 'view', label: 'View', items: [
      { label: 'Zoom in', run: () => setZoom(prefs.zoom + 10) },
      { label: 'Zoom out', run: () => setZoom(prefs.zoom - 10) },
      { label: 'Actual size (100%)', run: () => setZoom(100), checked: () => prefs.zoom === 100 },
      SEP,
      { label: 'Fit page to window', run: () => { prefs.pageW = 'fit'; savePrefs(); }, checked: () => prefs.pageW === 'fit' },
      { label: 'Narrow page', run: () => { prefs.pageW = 640; savePrefs(); }, checked: () => prefs.pageW === 640 },
      { label: 'Standard page', run: () => { prefs.pageW = 816; savePrefs(); }, checked: () => prefs.pageW === 816 },
      { label: 'Wide page', run: () => { prefs.pageW = 1040; savePrefs(); }, checked: () => prefs.pageW === 1040 },
      { label: 'Serif page font', run: () => { prefs.serif = !prefs.serif; savePrefs(); }, checked: () => prefs.serif },
      SEP,
      { label: 'Toolbar', run: () => { prefs.toolbar = !prefs.toolbar; savePrefs(); }, checked: () => prefs.toolbar },
      { label: 'Chat tabs', run: () => { prefs.tabs = !prefs.tabs; savePrefs(); }, checked: () => prefs.tabs },
      { label: 'Ruler', run: () => { prefs.ruler = !prefs.ruler; savePrefs(); }, checked: () => prefs.ruler },
      { label: 'Compact header', run: () => { prefs.compact = prefs.compact === 'on' ? 'auto' : 'on'; savePrefs(); }, checked: () => prefs.compact === 'on' || isCompact() },
      SEP,
      { label: 'ChatGPT sidebar', run: toggleSidebar, checked: () => prefs.sidebar },
      { label: 'ChatGPT navigation rail', run: () => { prefs.rail = !prefs.rail; savePrefs(); }, checked: () => prefs.rail },
      { label: 'ChatGPT title bar', run: () => { prefs.header = !prefs.header; savePrefs(); }, checked: () => prefs.header },
      { label: 'Full screen', kbd: 'F11', run: toggleFullscreen, checked: () => !!document.fullscreenElement },
    ] },
    { id: 'insert', label: 'Insert', items: [
      { label: 'Files…', icon: 'attach', run: () => N.fileAny().click(), enabled: () => !!N.fileAny() },
      { label: 'Photos…', run: () => N.filePhotos().click(), enabled: () => !!N.filePhotos() },
      { label: 'ChatGPT tools…', icon: 'tools', run: () => press(N.tools()), enabled: () => !!N.tools() },
      SEP,
      { label: 'Link…', icon: 'link', run: insertLink },
      { label: 'Code block', icon: 'code', run: () => wrap('\n```\n', '\n```\n') },
      { label: 'Table', run: () => insert('\n| Column 1 | Column 2 | Column 3 |\n| --- | --- | --- |\n|  |  |  |\n') },
      { label: 'Equation', run: () => wrap('$$', '$$') },
      { label: 'Horizontal line', run: () => insert('\n---\n') },
      { label: 'Date and time', icon: 'clock', run: () => insert(new Date().toLocaleString()) },
    ] },
    { id: 'format', label: 'Format', items: [
      { label: 'Bold', kbd: '**text**', run: () => wrap('**') },
      { label: 'Italic', kbd: '*text*', run: () => wrap('*') },
      { label: 'Strikethrough', kbd: '~~text~~', run: () => wrap('~~') },
      { label: 'Inline code', icon: 'code', run: () => wrap('`') },
      SEP,
      { label: 'Heading 1', run: () => linePrefix('# ') },
      { label: 'Heading 2', run: () => linePrefix('## ') },
      { label: 'Heading 3', run: () => linePrefix('### ') },
      SEP,
      { label: 'Bulleted list', icon: 'bullets', run: () => linePrefix('- ') },
      { label: 'Numbered list', icon: 'numbers', run: () => linePrefix('1. ') },
      { label: 'Checklist', run: () => linePrefix('- [ ] ') },
      { label: 'Quote', icon: 'quote', run: () => linePrefix('> ') },
    ] },
    { id: 'tools', label: 'Tools', items: [
      { label: 'Model…', icon: 'model', run: () => press(N.model()), enabled: () => !!N.model() },
      { label: 'Dictate', icon: 'mic', run: () => press(N.dictate()), enabled: () => !!N.dictate() },
      { label: 'Stop generating', run: () => press(N.stop()), enabled: () => !!N.stop() },
      SEP,
      { label: 'Regenerate last answer', icon: 'regen', run: () => press(N.regenerate()), enabled: () => !!N.regenerate() },
      { label: 'Read last answer aloud', icon: 'speak', run: () => press(N.readAloud()), enabled: () => !!N.readAloud() },
      { label: 'Word count', run: wordCount, enabled: () => !!thread() },
      SEP,
      { label: 'Temporary chat on/off', run: () => press(N.tempToggle()), enabled: () => !!N.tempToggle() },
      { label: 'Personalization…', run: () => revealPress('header', N.personal), enabled: () => !!N.personal() },
      { label: 'Account and settings…', run: () => revealPress('rail', N.profile), enabled: () => !!N.profile() },
    ] },
    { id: 'chats', label: 'Chats', items: () => [
      { label: 'New chat', icon: 'newchat', run: newChat },
      { label: 'Search chats…', icon: 'find', run: async () => { await harvest(); press(N.search()) || toast('Search is not available.'); } },
      { label: 'Show ChatGPT sidebar', run: toggleSidebar, checked: () => prefs.sidebar },
      SEP,
      ...(chats.length ? chats.slice(0, 25).map(c => ({ priv: true, label: c.title, run: () => navigate(c.href), checked: () => currentHref() === c.href }))
        : [{ label: harvesting ? 'Loading chats…' : 'No chats found', enabled: () => false }]),
    ] },
    { id: 'projects', label: 'Projects', items: () => [
      { label: 'All projects…', run: () => revealPress('rail', N.projectsPage), enabled: () => !!N.projectsPage() },
      { label: 'New project…', run: async () => { await harvest(); press(N.newProject()) || toast('New project is not available.'); } },
      SEP,
      ...(projects.length ? projects.map(p => ({
        priv: true, label: p.name, sub: () => [
          { label: 'New chat in this project', icon: 'newchat', run: () => { readNav(); const fresh = projects.find(x => x.name === p.name); press((fresh || p).btn); } },
          ...(p.items.length ? [SEP, ...p.items.map(c => ({ priv: true, label: c.title, run: () => navigate(c.href), checked: () => currentHref() === c.href }))] : []),
        ],
      })) : [{ label: harvesting ? 'Loading projects…' : 'No projects found', enabled: () => false }]),
    ] },
    { id: 'help', label: 'Help', items: [
      { label: 'Keyboard shortcuts', run: shortcutsDialog },
      { label: 'ChatGPT Help Center', run: () => open('https://help.openai.com/', '_blank', 'noopener') },
      { label: 'About Document Workspace', run: aboutDialog },
    ] },
  ];
  const menuItems = m => typeof m.items === 'function' ? m.items() : m.items;

  // ---- build the shell (in a shadow root, so ChatGPT's styles and ours never mix)
  const host = document.createElement('div');
  host.id = 'ghost-doc-workspace';
  const shadow = host.attachShadow({ mode: 'open' });
  shadow.innerHTML = `<style>${SHELL_CSS()}</style>
  <div class="shell" part="shell">
    <div class="rowA">
      <span class="logo" title="ChatGPT Document Workspace">${APP_ICON}</span>
      <button class="menuBtn ib" data-act="allmenus" aria-label="Menus" aria-haspopup="menu">${icon('menu')}</button>
      <div class="names"><span class="app">ChatGPT</span>
        <span class="tline" tabindex="0"><span class="title" role="heading" aria-level="1"></span><span class="pen" aria-hidden="true">${icon('pen', 14)}</span></span>
        <input class="tin" type="text" aria-label="Chat title" spellcheck="false" autocomplete="off" hidden></div>
      <span class="badge" hidden>Temporary</span>
      <span class="spacer"></span>
      <button class="abtn share" data-act="share" hidden>${icon('share', 16)}<span>Share</span></button>
      <button class="abtn primary" data-act="newchat" aria-label="New chat">${icon('newchat', 16)}<span>New chat</span></button>
    </div>
    <div class="rowB" role="menubar" aria-label="Document menus"></div>
    <div class="rowC" role="toolbar" aria-label="Formatting and ChatGPT tools"></div>
    <div class="rowD" role="tablist" aria-label="Chats"></div>
    <div class="rowE" aria-hidden="true"><div class="rbar"><div class="rml"></div><div class="rtext"></div><div class="rmr"></div>
      <span class="rh left" title="Drag to change the page width"></span><span class="rh right" title="Drag to change the page width"></span></div></div>
  </div>
  <button class="returnPill" hidden>${APP_ICON}<span>Document view</span></button>
  <div class="menu" role="menu" hidden></div>
  <div class="findbar" hidden><input type="search" placeholder="Find in document" aria-label="Find in document">
    <span class="fcount"></span><button class="ib" data-f="prev" aria-label="Previous match">${icon('up', 16)}</button>
    <button class="ib" data-f="next" aria-label="Next match">${icon('down', 16)}</button><button class="ib" data-f="close" aria-label="Close find">${icon('close', 16)}</button></div>
  <div class="dlg" hidden><div class="dbox" role="dialog" aria-modal="true"><h2></h2><div class="dbody"></div><div class="dbtns"></div></div></div>
  <div class="toast" role="status" aria-live="polite"></div>`;
  const S = s => shadow.querySelector(s);
  const shell = S('.shell'), menuEl = S('.menu'), rowB = S('.rowB'), rowC = S('.rowC'), rowD = S('.rowD'), rowE = S('.rowE');

  // menubar
  MENUS().forEach(m => {
    const b = document.createElement('button');
    b.className = 'mb'; b.textContent = m.label; b.dataset.menu = m.id;
    b.setAttribute('role', 'menuitem'); b.setAttribute('aria-haspopup', 'menu'); b.setAttribute('aria-expanded', 'false');
    rowB.append(b);
  });

  // toolbar: [id, icon or text, label, action, enabled?]
  const TB = [
    ['undo', 'undo', 'Undo', () => editorKey('z')],
    ['redo', 'redo', 'Redo', () => editorKey('z', true)],
    ['print', 'print', 'Print', () => print(), () => !!thread()],
    '|',
    ['zoom', 'text:zoom', 'Zoom', el => popup(zoomItems(), el.getBoundingClientRect())],
    ['styles', 'text:Styles', 'Paragraph styles', el => popup(styleItems(), el.getBoundingClientRect())],
    '|',
    ['bold', 'text:B', 'Bold', () => wrap('**')],
    ['italic', 'text:I', 'Italic', () => wrap('*')],
    ['strike', 'text:S', 'Strikethrough', () => wrap('~~')],
    ['code', 'code', 'Inline code', () => wrap('`')],
    ['link', 'link', 'Insert link', insertLink],
    '|',
    ['bullets', 'bullets', 'Bulleted list', () => linePrefix('- ')],
    ['numbers', 'numbers', 'Numbered list', () => linePrefix('1. ')],
    ['quote', 'quote', 'Quote', () => linePrefix('> ')],
    '|',
    ['attach', 'attach', 'Attach files', () => N.fileAny()?.click(), () => !!N.fileAny()],
    ['tools', 'tools', 'ChatGPT tools', () => press(N.tools()), () => !!N.tools()],
    ['model', 'text:model', 'Choose model', () => press(N.model()), () => !!N.model()],
    ['dictate', 'mic', 'Dictate', () => press(N.dictate()), () => !!N.dictate()],
    '|',
    ['find', 'find', 'Find in document', openFind, () => !!thread()],
    ['copyans', 'copy', 'Copy last answer', () => press(N.copyAnswer()) && toast('Answer copied'), () => !!N.copyAnswer()],
    ['regen', 'regen', 'Regenerate last answer', () => press(N.regenerate()), () => !!N.regenerate()],
    ['speak', 'speak', 'Read last answer aloud', () => press(N.readAloud()), () => !!N.readAloud()],
  ];
  const tbButtons = [];
  TB.forEach(t => {
    if (t === '|') { const s = document.createElement('span'); s.className = 'sep'; rowC.append(s); tbButtons.push({ sep: s }); return; }
    const [id, ic, lab, run, en] = t;
    const b = document.createElement('button');
    b.className = 'tb ' + id; b.dataset.tb = id; b.setAttribute('aria-label', lab); b.title = lab;
    if (ic.startsWith('text:')) { b.classList.add('txt'); b.innerHTML = `<span class="tl">${esc(ic.slice(5))}</span>${id === 'zoom' || id === 'styles' || id === 'model' ? icon('chev', 14) : ''}`; }
    else b.innerHTML = icon(ic);
    b.addEventListener('mousedown', e => e.preventDefault());
    b.addEventListener('click', () => { if (en && !en()) return; run(b); });
    rowC.append(b); tbButtons.push({ el: b, en, lab, run, id });
  });
  const more = document.createElement('button');
  more.className = 'tb more'; more.title = 'More tools'; more.setAttribute('aria-label', 'More tools'); more.innerHTML = icon('more');
  more.addEventListener('mousedown', e => e.preventDefault());
  more.addEventListener('click', () => popup(tbButtons.filter(t => t.el && t.el.hidden).map(t => ({ label: t.lab, run: () => t.run(more), enabled: t.en })), more.getBoundingClientRect()));
  rowC.append(more);

  const zoomItems = () => [50, 75, 90, 100, 110, 125, 150, 200].map(z => ({ label: z + '%', run: () => setZoom(z), checked: () => prefs.zoom === z }));
  const styleItems = () => [
    { label: 'Normal text', run: () => linePrefix('') },
    { label: 'Heading 1', run: () => linePrefix('# ') },
    { label: 'Heading 2', run: () => linePrefix('## ') },
    { label: 'Heading 3', run: () => linePrefix('### ') },
    { label: 'Quote', run: () => linePrefix('> ') },
    { label: 'Code block', run: () => wrap('\n```\n', '\n```\n') },
  ];

  // ---- popup menu (used by the menubar, toolbar dropdowns, tabs and the compact menu)
  let menuState = null;
  function popup(items, rect, opts = {}) {
    menuEl.innerHTML = '';
    menuState = { items, rect, opts };
    if (opts.back) {
      const b = document.createElement('button');
      b.className = 'mi head' + (opts.priv ? ' priv' : ''); b.setAttribute('role', 'menuitem');
      b.innerHTML = `<span class="ck">${icon('back', 16)}</span><span class="ml">${esc(opts.title || 'Back')}</span><span></span>`;
      b.addEventListener('mousedown', e => e.preventDefault());
      b.addEventListener('click', opts.back);
      menuEl.append(b, Object.assign(document.createElement('div'), { className: 'msep' }));
    }
    items.forEach(it => {
      if (it.sep) { menuEl.append(Object.assign(document.createElement('div'), { className: 'msep', role: 'separator' })); return; }
      const b = document.createElement('button');
      const enabled = !it.enabled || it.enabled();
      const checked = it.checked ? it.checked() : null;
      b.className = 'mi' + (it.priv ? ' priv' : ''); b.setAttribute('role', checked === null ? 'menuitem' : 'menuitemcheckbox');
      if (checked !== null) b.setAttribute('aria-checked', String(!!checked));
      if (!enabled) { b.setAttribute('aria-disabled', 'true'); b.classList.add('off'); }
      b.innerHTML = `<span class="ck">${checked ? icon('check', 16) : it.icon ? icon(it.icon, 16) : ''}</span><span class="ml">${esc(it.label)}</span><span class="kb">${it.sub || it.arrow ? icon('next', 15) : esc(it.kbd || '')}</span>`;
      b.addEventListener('mousedown', e => e.preventDefault());
      b.addEventListener('click', () => {
        if (!enabled) return;
        if (it.sub) { popup(it.sub(), rect, { back: () => popup(items, rect, opts), title: it.label, priv: it.priv }); focusFirst(); return; }
        if (it.keep) return it.run();
        closeMenu(); it.run();
      });
      menuEl.append(b);
    });
    menuEl.hidden = false;
    const vw = innerWidth, vh = innerHeight;
    const w = Math.min(Math.max(menuEl.offsetWidth, 230), vw - 16);
    menuEl.style.left = Math.max(8, Math.min(rect.left, vw - w - 8)) + 'px';
    menuEl.style.top = Math.round(rect.bottom + 4) + 'px';
    menuEl.style.maxHeight = Math.max(160, vh - rect.bottom - 14) + 'px';
  }
  function focusFirst() { const f = menuEl.querySelector('.mi:not(.off):not(.head)') || menuEl.querySelector('.mi'); f && f.focus(); }
  let openMenuId = null;
  function openMenu(id, focus = false) {
    const m = MENUS().find(x => x.id === id); if (!m) return;
    if (id === 'chats' || id === 'projects') { readNav(); if (!chats.length && !projects.length) harvest().then(() => { if (openMenuId === id) openMenu(id, focus); }); }
    const btn = rowB.querySelector(`[data-menu="${id}"]`);
    const compact = isCompact();
    const anchor = compact || !btn ? S('.menuBtn').getBoundingClientRect() : btn.getBoundingClientRect();
    rowB.querySelectorAll('.mb').forEach(b => { b.classList.toggle('open', b === btn); b.setAttribute('aria-expanded', String(b === btn)); });
    openMenuId = id;
    popup(menuItems(m), anchor, compact ? { back: allMenus, title: m.label } : {});
    if (focus) focusFirst();
  }
  function allMenus(focus) {
    openMenuId = 'all';
    const anchor = S('.menuBtn').getBoundingClientRect();
    // compact menu: choosing a top-level entry shows its items with a Back row
    popup(MENUS().map(m => ({ label: m.label, arrow: true, keep: true, run: () => openMenu(m.id, true) })), anchor);
    if (focus === true) focusFirst();
  }
  function closeMenu() {
    menuEl.hidden = true; menuState = null; openMenuId = null;
    rowB.querySelectorAll('.mb').forEach(b => { b.classList.remove('open'); b.setAttribute('aria-expanded', 'false'); });
  }
  rowB.addEventListener('mousedown', e => e.preventDefault());
  rowB.addEventListener('click', e => {
    const b = e.target.closest('.mb'); if (!b) return;
    openMenuId === b.dataset.menu ? closeMenu() : openMenu(b.dataset.menu);
  });
  rowB.addEventListener('mouseover', e => {
    const b = e.target.closest('.mb');
    if (b && openMenuId && openMenuId !== 'all' && openMenuId !== b.dataset.menu && !menuEl.hidden) openMenu(b.dataset.menu);
  });
  rowB.addEventListener('keydown', e => {
    const bs = [...rowB.querySelectorAll('.mb')]; const i = bs.indexOf(shadow.activeElement); if (i < 0) return;
    if (e.key === 'ArrowRight' || e.key === 'ArrowLeft') { e.preventDefault(); const n = bs[(i + (e.key === 'ArrowRight' ? 1 : bs.length - 1)) % bs.length]; n.focus(); if (!menuEl.hidden) openMenu(n.dataset.menu); }
    else if (e.key === 'ArrowDown' || e.key === 'Enter' || e.key === ' ') { e.preventDefault(); openMenu(bs[i].dataset.menu, true); }
    else if (e.key === 'Escape') closeMenu();
  });
  menuEl.addEventListener('keydown', e => {
    const items = [...menuEl.querySelectorAll('.mi')]; const i = items.indexOf(shadow.activeElement);
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault(); const d = e.key === 'ArrowDown' ? 1 : -1;
      for (let k = 1; k <= items.length; k++) { const n = items[(i + d * k + items.length * 2) % items.length]; if (!n.classList.contains('off')) { n.focus(); break; } }
    } else if (e.key === 'Escape') {
      e.preventDefault(); const id = openMenuId; closeMenu();
      (rowB.querySelector(`[data-menu="${id}"]`) || S('.menuBtn')).focus?.();
    } else if ((e.key === 'ArrowRight' || e.key === 'ArrowLeft') && openMenuId && openMenuId !== 'all' && !isCompact()) {
      e.preventDefault(); const bs = [...rowB.querySelectorAll('.mb')]; const j = bs.findIndex(b => b.dataset.menu === openMenuId);
      const n = bs[(j + (e.key === 'ArrowRight' ? 1 : bs.length - 1)) % bs.length]; n.focus(); openMenu(n.dataset.menu, true);
    }
  });
  addEventListener('pointerdown', e => { if (!menuEl.hidden && !e.composedPath().includes(menuEl) && !e.composedPath().includes(rowB) && !e.composedPath().includes(S('.menuBtn'))) closeMenu(); }, true);
  addEventListener('resize', () => { closeMenu(); applyPrefs(); });
  addEventListener('keydown', e => {
    if (e.altKey && e.shiftKey && (e.key === 'M' || e.key === 'm')) { e.preventDefault(); prefs.original ? null : (isCompact() ? (S('.menuBtn').focus(), allMenus(true)) : rowB.querySelector('.mb').focus()); }
  }, true);

  // header buttons
  S('.menuBtn').addEventListener('mousedown', e => e.preventDefault());
  S('.menuBtn').addEventListener('click', () => menuEl.hidden ? allMenus() : closeMenu());
  S('[data-act=newchat]').addEventListener('click', newChat);
  S('[data-act=share]').addEventListener('click', () => press(N.share()));
  S('.returnPill').addEventListener('click', () => { prefs.original = false; savePrefs(); });

  // ---- rename the open chat from its title
  // The new name is saved by ChatGPT itself: its "Chat actions > Rename" dialog for the conversation in
  // the address bar (never one picked by title), filled in unseen. Success is only reported once ChatGPT
  // shows the new title; if it doesn't confirm, its own dialog is shown or the real title comes back.
  const convId = () => (location.pathname.match(/\/c\/([0-9a-f-]{36})(?:\/|$)/) || [])[1] || '';
  const titleLine = S('.tline'), titleInput = S('.tin');
  let editing = null, renaming = false;   // editing = { id, original } while the title field is open
  const canRename = () => !!convId() && !isTemporary();
  const pageTitle = () => document.title.trim();
  const until = async (fn, ms) => { for (let t = 0; t < ms; t += 100) { const v = fn(); if (v) return v; await sleep(100); } return fn(); };
  const setValue = (input, v) => {   // as typing would, so ChatGPT's form sees the change
    Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(input, v);
    input.dispatchEvent(new Event('input', { bubbles: true }));
  };
  function beginRename() {
    if (editing || renaming || prefs.original) return;
    if (isTemporary()) return toast('Temporary chats can\'t be renamed: they aren\'t saved to your chat history.');
    if (!convId()) return toast('This chat isn\'t saved yet. Send a message first, then rename it.');
    editing = { id: convId(), original: docTitle() };
    titleInput.value = editing.original;
    S('.names').classList.add('editing'); titleLine.hidden = true; titleInput.hidden = false;
    titleInput.focus(); titleInput.select();
  }
  // how: 'enter', 'blur' (clicked elsewhere) or 'cancel' (Escape, or the chat changed)
  function endRename(how) {
    if (!editing) return;
    const { id, original } = editing, val = titleInput.value.replace(/\s+/g, ' ').trim();
    if (how === 'enter' && !val) { toast('A chat title can\'t be empty.'); titleInput.focus(); return; }
    editing = null;
    titleInput.hidden = true; titleLine.hidden = false; S('.names').classList.remove('editing');
    if (how === 'cancel' || !val || val === original) return;
    if (convId() !== id) return toast('The chat changed while you were typing, so nothing was renamed.');
    renameChat(id, val, original);
  }
  async function renameChat(id, val, original) {
    renaming = true;
    const te = S('.title');
    te.textContent = val; te.title = 'Saving the new title…'; te.classList.add('pending');
    const reveal = !prefs.header;
    root.setAttribute('data-gd-renaming', '');   // ChatGPT's menu and dialog do the work unseen (docmode.css)
    if (reveal) { root.setAttribute('data-gd-reveal-header', ''); await frame(); await sleep(150); }
    let result = 'failed', field = null;
    try {
      if (convId() !== id || !press(N.chatActions())) throw 0;
      const item = await until(() => $$('[role=menu] [role^=menuitem]').find(m => m.textContent.trim() === 'Rename'), 3000);
      if (!item) throw 0;
      item.click();
      field = await until(() => $('[role=dialog] input[aria-label="Chat title"]'), 3000);
      if (!field || convId() !== id) throw 0;   // the chat changed meanwhile: don't save anything
      setValue(field, val);
      const save = $$('button', field.form || field.closest('[role=dialog]')).find(b => b.textContent.trim() === 'Save');
      if (!save || save.disabled) throw 0;
      save.click();
      // ChatGPT closes its dialog and retitles the page once the new name has been saved
      if (await until(() => !field.isConnected && pageTitle() === val, 10000)) result = 'ok';
      else if (field.isConnected) result = 'dialog';
    } catch {}
    if (result === 'failed') {
      if (field && field.isConnected) $$('button', field.form || document).find(b => b.textContent.trim() === 'Cancel')?.click();
      const menu = $('[role=menu]'); if (menu) menu.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
      await sleep(200);
    }
    root.removeAttribute('data-gd-renaming');
    if (reveal) root.removeAttribute('data-gd-reveal-header');
    if (result === 'ok') {
      await sleep(1500);   // ChatGPT puts the old title back if the save is rejected
      if (convId() === id && pageTitle() !== val) result = 'failed';
    }
    te.classList.remove('pending');
    renaming = false;
    if (result === 'ok') {
      // tabs and menus follow at once, even if ChatGPT's own chat list hasn't caught up yet
      renamedTitles.set(id, { title: val, stale: new Set([...(navSeen.get(id) || []), original]) });
      for (const c of [...chats, ...projects.flatMap(p => p.items)]) if (c.href.endsWith('/c/' + id)) c.title = val;
      toast('Chat renamed');
    } else if (result === 'dialog') {
      toast('ChatGPT hasn\'t confirmed the new title. Its Rename dialog is open: finish or cancel there.');
    } else {
      toast('Couldn\'t rename this chat. Its title is unchanged.');
    }
    rowD.dataset.sig = ''; tick();
  }
  titleLine.addEventListener('click', beginRename);
  titleLine.addEventListener('keydown', e => { if (e.key === 'Enter' || e.key === 'F2') { e.preventDefault(); beginRename(); } });
  titleInput.addEventListener('keydown', e => {
    e.stopPropagation();
    if (e.key === 'Enter') { e.preventDefault(); endRename('enter'); }
    else if (e.key === 'Escape') { e.preventDefault(); endRename('cancel'); }
  });
  titleInput.addEventListener('blur', () => setTimeout(() => {
    if (document.hasFocus()) endRename('blur');   // switching to another app keeps the edit open
  }, 0));
  addEventListener('popstate', () => { if (editing && convId() !== editing.id) endRename('cancel'); });

  // ---- chat tabs
  function renderTabs() {
    if (!prefs.tabs || isCompact() || prefs.original) return;
    readNav();
    const cur = currentHref();
    // the open chat's tab follows the live page title (a fresh rename shows before the chat list updates)
    const live = !renaming && pageTitle() !== 'ChatGPT' ? pageTitle() : '';
    const list = chats.slice(0, 12).map(c => ({ ...c, cur: c.href === cur, title: c.href === cur && live ? live : c.title }));
    if (!list.some(c => c.cur)) list.unshift({ href: cur, title: cur === '/' ? (isTemporary() ? 'Temporary chat' : 'New chat') : docTitle(), cur: true, local: true });
    const sig = list.map(c => c.href + c.title + c.cur).join('|');
    if (rowD.dataset.sig === sig && rowD.offsetWidth === +rowD.dataset.w) return;
    rowD.dataset.sig = sig; rowD.dataset.w = rowD.offsetWidth;
    rowD.innerHTML = '';
    list.forEach(c => {
      const t = document.createElement('button');
      t.className = 'tab' + (c.cur ? ' cur' : ''); t.setAttribute('role', 'tab'); t.setAttribute('aria-selected', String(c.cur));
      t.title = c.title; t.textContent = c.title;
      if (!c.cur) t.addEventListener('click', () => navigate(c.href));
      rowD.append(t);
    });
    const all = document.createElement('button');
    all.className = 'tab all'; all.innerHTML = `<span>All chats</span>${icon('chev', 14)}`; all.setAttribute('aria-haspopup', 'menu');
    all.addEventListener('mousedown', e => e.preventDefault());
    all.addEventListener('click', () => { readNav(); popup(menuItems(MENUS().find(m => m.id === 'chats')), all.getBoundingClientRect()); });
    rowD.append(all);
    // drop tabs that do not fit (the current tab and "All chats" always stay)
    const tabs = [...rowD.querySelectorAll('.tab:not(.all)')];
    for (let i = tabs.length - 1; i >= 0 && rowD.scrollWidth > rowD.clientWidth; i--) if (!tabs[i].classList.contains('cur')) tabs[i].remove();
  }

  // ---- ruler: follows the page; dragging its handles changes the page width
  function placeRuler() {
    if (!prefs.ruler || isCompact() || prefs.original) return;
    const p = page(); const bar = S('.rbar');
    let r, pl, pr;
    if (p) {
      r = p.getBoundingClientRect(); const cs = getComputedStyle(p);
      pl = parseFloat(cs.paddingLeft) || 0; pr = parseFloat(cs.paddingRight) || 0;
    } else {
      // start page: the blank page drawn behind the home composer
      const a = shown('[data-app-shell-focus-area=main]'); if (!a) { bar.style.visibility = 'hidden'; return; }
      const ar = a.getBoundingClientRect(); const w = Math.min(prefs.pageW === 'fit' ? FIT_MAX : prefs.pageW, ar.width - (isCompact() ? 12 : 32));
      r = { left: ar.left + (ar.width - w) / 2, width: w };
      pl = pr = marginPx(ar.width);
    }
    bar.style.visibility = 'visible';
    bar.style.left = r.left + 'px'; bar.style.width = r.width + 'px';
    S('.rml').style.width = pl + 'px'; S('.rmr').style.width = pr + 'px';
    const t = S('.rtext'); t.style.left = pl + 'px'; t.style.right = pr + 'px';
    S('.rh.left').style.left = (pl - 5) + 'px'; S('.rh.right').style.left = (r.width - pr - 5) + 'px';
    const inch = 96 * prefs.zoom / 100, w = r.width - pl - pr, key = Math.round(w) + ':' + inch;
    if (t.dataset.key !== key) {
      t.dataset.key = key; t.innerHTML = '';
      for (let i = 1; i * inch < w - 6; i++) { const n = document.createElement('span'); n.className = 'rn'; n.textContent = i; n.style.left = (i * inch) + 'px'; t.append(n); }
      t.style.backgroundSize = `${inch / 8}px 4px, ${inch / 2}px 7px`;
    }
  }
  shadow.querySelectorAll('.rh').forEach(h => h.addEventListener('pointerdown', e => {
    e.preventDefault(); h.setPointerCapture(e.pointerId);
    const x0 = e.clientX, w0 = prefs.pageW === 'fit' ? Math.round(S('.rbar').getBoundingClientRect().width) : prefs.pageW, dir = h.classList.contains('right') ? 1 : -1;
    const move = ev => { prefs.pageW = Math.round(Math.max(480, Math.min(1600, w0 + dir * 2 * (ev.clientX - x0)))); applyPrefs(); };
    const up = () => { h.removeEventListener('pointermove', move); savePrefs(); };
    h.addEventListener('pointermove', move); h.addEventListener('pointerup', up, { once: true });
  }));

  // ---- find bar
  const findbar = S('.findbar'), finput = findbar.querySelector('input');
  function openFind() { findbar.hidden = false; positionFloating(); finput.focus(); finput.select(); }
  function findStep(back) {
    const q = finput.value; if (!q) return;
    const t = thread(); const text = t ? t.innerText.toLowerCase() : '';
    let n = 0, i = -1; while ((i = text.indexOf(q.toLowerCase(), i + 1)) >= 0) n++;
    S('.fcount').textContent = n ? n + (n === 1 ? ' match' : ' matches') : 'No matches';
    if (n) { window.find(q, false, back, true, false, false, false); finput.focus(); }
  }
  finput.addEventListener('keydown', e => { if (e.key === 'Enter') { e.preventDefault(); findStep(e.shiftKey); } else if (e.key === 'Escape') { findbar.hidden = true; } });
  findbar.addEventListener('click', e => { const f = e.target.closest('[data-f]')?.dataset.f; if (f === 'close') findbar.hidden = true; else if (f) findStep(f === 'prev'); });

  // ---- dialogs and notices
  function dialog(title, body, buttons = [['Close', null]]) {
    const d = S('.dlg'); d.querySelector('h2').textContent = title;
    const db = d.querySelector('.dbody'); db.innerHTML = '';
    if (Array.isArray(body)) {
      const tbl = document.createElement('table');
      body.forEach(([k, v]) => { const tr = tbl.insertRow(); tr.insertCell().textContent = k; const c = tr.insertCell(); c.textContent = v; c.className = 'num'; });
      db.append(tbl);
    } else if (body instanceof Node) db.append(body); else db.textContent = body;
    const bb = d.querySelector('.dbtns'); bb.innerHTML = '';
    buttons.forEach(([lab, fn], i) => {
      const b = document.createElement('button'); b.className = 'abtn' + (i === buttons.length - 1 ? ' primary' : ''); b.textContent = lab;
      b.addEventListener('click', () => { if (fn && fn() === false) return; d.hidden = true; });
      bb.append(b);
    });
    d.hidden = false; (d.querySelector('input') || bb.lastChild).focus();
  }
  S('.dlg').addEventListener('keydown', e => { if (e.key === 'Escape') S('.dlg').hidden = true; });
  S('.dlg').addEventListener('mousedown', e => { if (e.target === S('.dlg')) S('.dlg').hidden = true; });
  function insertLink() {
    const sel = getSelection().toString();
    const f = document.createElement('div'); f.className = 'form';
    f.innerHTML = '<label>Text<input name="t"></label><label>Address<input name="u" placeholder="https://"></label>';
    f.querySelector('[name=t]').value = sel;
    dialog('Insert link', f, [['Cancel', null], ['Insert', () => {
      const t = f.querySelector('[name=t]').value.trim(), u = f.querySelector('[name=u]').value.trim();
      if (!u) return false;
      setTimeout(() => insert(`[${t || u}](${u})`), 0);
    }]]);
  }
  function shortcutsDialog() {
    dialog('Keyboard shortcuts', [
      ['Open the menus', 'Alt+Shift+M'], ['Move between menus', 'Left / Right'], ['Move within a menu', 'Up / Down'],
      ['Close a menu or dialog', 'Esc'], ['Print the document', 'Ctrl+P'], ['Undo / redo in the message box', 'Ctrl+Z / Ctrl+Y'],
      ['Show or hide the overlay', 'Ctrl+Alt+G'], ['Overlay opacity', 'Ctrl+Alt+Up / Down'],
      ['Overlay always on top', 'Ctrl+Alt+T'], ['Overlay emergency reset', 'Ctrl+Alt+Shift+R'],
    ]);
  }
  function aboutDialog() {
    dialog('About Document Workspace', 'This is ChatGPT (chatgpt.com) shown in a document-style workspace by the local "Ghost Overlay Document Mode" extension. ' +
      'Every menu and toolbar control drives ChatGPT\'s own controls. Use File > Original ChatGPT layout to return to the standard ChatGPT interface at any time.');
  }
  let toastTimer;
  function toast(msg) { const t = S('.toast'); t.textContent = msg; t.classList.add('on'); clearTimeout(toastTimer); toastTimer = setTimeout(() => t.classList.remove('on'), 2400); return false; }
  function positionFloating() { findbar.style.top = (shell.offsetHeight + 8) + 'px'; }

  // ---- layout and live state
  // "Fit page to window": the page fills the window (with a slim desk border) up to a readable width
  const FIT_MAX = 880;   // page ~920 px wide incl. its frame: readable line length
  const marginPx = w => isCompact() ? 16 : Math.round(Math.max(28, Math.min(72, w * 0.06)));
  // ChatGPT reuses the width in its own centring math, so it must be plain pixels (no percentages).
  function setPageWidth() {
    const reg = shown('[data-app-action-timeline-scroll]') || shown('[data-app-shell-focus-area=main]') || shown('main');
    const avail = reg ? reg.clientWidth : innerWidth;
    const w = isCompact() ? avail - 12 : Math.min(prefs.pageW === 'fit' ? FIT_MAX : prefs.pageW, avail - 32);
    const v = Math.max(280, Math.round(w)) + 'px';
    if (root.style.getPropertyValue('--gd-page-w') !== v) root.style.setProperty('--gd-page-w', v);
  }
  const isCompact = () => prefs.compact === 'on' || (prefs.compact === 'auto' && (innerWidth < 720 || innerHeight < 480));
  function applyPrefs() {
    root.style.setProperty('--gd-zoom', String(prefs.zoom / 100));
    setPageWidth();
    setAttr('data-gd-serif', prefs.serif); setAttr('data-gd-rail', prefs.rail); setAttr('data-gd-sidebar', prefs.sidebar);
    setAttr('data-gd-header', prefs.header); setAttr('data-gd-original', prefs.original);
    layout();
  }
  function fitToolbar() {
    if (!prefs.toolbar || prefs.original) return;
    tbButtons.forEach(t => { (t.el || t.sep).hidden = false; });
    more.hidden = true;
    if (rowC.scrollWidth <= rowC.clientWidth) return;
    more.hidden = false;
    for (let i = tbButtons.length - 1; i >= 0 && rowC.scrollWidth > rowC.clientWidth; i--) (tbButtons[i].el || tbButtons[i].sep).hidden = true;
    // no separator left dangling at the end
    for (let i = tbButtons.length - 1; i >= 0; i--) { const t = tbButtons[i]; if ((t.el || t.sep).hidden) continue; if (t.sep) t.sep.hidden = true; else break; }
  }
  function layout() {
    const compact = isCompact();
    shell.classList.toggle('compact', compact);
    setAttr('data-gd-compact', compact);
    shell.hidden = prefs.original; S('.returnPill').hidden = !prefs.original;
    rowB.hidden = compact; rowC.hidden = !prefs.toolbar;
    rowD.hidden = compact || !prefs.tabs; rowE.hidden = compact || !prefs.ruler;
    root.style.setProperty('--gd-top', (prefs.original ? 0 : shell.offsetHeight) + 'px');
    fitToolbar(); rowD.dataset.sig = ''; renderTabs(); placeRuler(); positionFloating();
  }
  function tick() {
    if (prefs.original) return;
    setPageWidth();
    const tt = docTitle(); const te = S('.title');
    if (editing && convId() !== editing.id) endRename('cancel');   // left the chat while typing
    if (!editing && !renaming) {   // never overwrite the title while it is being typed or saved
      if (te.textContent !== tt) te.textContent = tt;
      const can = canRename(), tip = can ? tt + ' (click to rename)' : tt;
      if (te.title !== tip) te.title = tip;
      titleLine.classList.toggle('can', can);
    }
    S('.badge').hidden = !isTemporary();
    S('[data-act=share]').hidden = !N.share();
    const m = N.model(); const ml = rowC.querySelector('.model .tl'); const mt = (m && m.innerText.trim().split(/\n/).pop().trim()) || 'Model';
    if (ml.textContent !== mt) { ml.textContent = mt; fitToolbar(); }
    const zl = rowC.querySelector('.zoom .tl'); if (zl.textContent !== prefs.zoom + '%') zl.textContent = prefs.zoom + '%';
    tbButtons.forEach(t => { if (t.el && t.en) t.el.classList.toggle('off', !t.en()); });
    // the chat list may not exist yet right after the window opens; try again a few times
    if (!chats.length && !harvesting && Date.now() - lastHarvest > (harvestTries < 6 ? 4000 : 60000)) harvest();
    renderTabs(); placeRuler();
  }

  function mount() {
    if (!document.body) return void document.addEventListener('DOMContentLoaded', mount, { once: true });
    document.body.append(host);
    applyPrefs(); tick();
    setInterval(tick, 700);
    new ResizeObserver(() => { const h = prefs.original ? 0 : shell.offsetHeight; if (root.style.getPropertyValue('--gd-top') !== h + 'px') root.style.setProperty('--gd-top', h + 'px'); }).observe(shell);
    addEventListener('scroll', e => { if (e.target.matches?.('[data-app-action-timeline-scroll]')) placeRuler(); }, { capture: true, passive: true });
    setTimeout(harvest, 2500);
  }
  mount();

  function SHELL_CSS() { return `
  :host { all: initial; }
  * { box-sizing: border-box; }
  .shell, .menu, .findbar, .dlg, .toast, .returnPill {
    --ui: "Segoe UI Variable Text", "Segoe UI", system-ui, sans-serif;
    /* Soft Light tokens */ --ink: #202124; --muted: #5F6368; --icon: #444746; --line: #DFE3EA; --soft: #E8F0FE; --accent: #4B77BE; --accent-ink: #3D66A8; --chrome: #F8FAFD; --bar: #EDF2FA; --paper: #FFFFFF;
    font: 13px/1.3 var(--ui); color: var(--ink);
  }
  button { font: inherit; color: inherit; background: none; border: 0; margin: 0; padding: 0; cursor: pointer; }
  button:focus-visible, input:focus-visible { outline: 2px solid var(--accent); outline-offset: -1px; }
  [hidden] { display: none !important; }
  .shell { position: fixed; top: 0; left: 0; right: 0; z-index: 2147483000; background: var(--chrome); border-bottom: 1px solid var(--line); user-select: none; }
  .rowA { display: flex; align-items: center; gap: 10px; height: 46px; padding: 0 12px; }
  .logo { display: flex; flex: none; }
  .names { display: flex; flex-direction: column; min-width: 0; line-height: 1.2; }
  .app { font-size: 11px; font-weight: 600; letter-spacing: .03em; color: var(--accent-ink); }
  .title { font-size: 16px; color: var(--ink); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  /* click-to-rename: same place and type as the title; a pencil appears on hover */
  .names.editing { flex: 1 1 auto; max-width: 640px; }
  .tline { display: flex; align-items: center; gap: 6px; min-width: 0; margin: 0 -4px; padding: 0 4px; border-radius: 4px; }
  .tline.can { cursor: text; }
  .tline.can:hover { background: var(--bar); }
  .tline:focus-visible { outline: 2px solid var(--accent); outline-offset: -1px; }
  .pen { display: inline-flex; flex: none; color: var(--muted); opacity: 0; transition: opacity .12s; }
  .tline.can:hover .pen, .tline.can:focus-visible .pen { opacity: 1; }
  .title.pending { color: var(--muted); }
  .tin { display: block; width: calc(100% + 10px); min-width: 0; height: 21px; margin: 0 -5px; padding: 0 4px; font: 16px/1.2 var(--ui); color: var(--ink);
    background: var(--paper); border: 1px solid var(--accent); border-radius: 4px; box-shadow: 0 0 0 2px var(--soft); outline: none; user-select: text; }
  .badge { flex: none; font-size: 11px; padding: 2px 8px; border-radius: 10px; background: var(--soft); color: var(--accent-ink); border: 0; }
  .spacer { flex: 1; }
  .abtn { display: inline-flex; align-items: center; gap: 6px; height: 30px; padding: 0 12px; border-radius: 6px; border: 1px solid var(--line); background: var(--paper); font-size: 13px; white-space: nowrap; flex: none; }
  .abtn:hover { background: var(--soft); }
  .abtn.primary { background: var(--accent); border-color: var(--accent); color: #fff; }
  .abtn.primary:hover { background: var(--accent-ink); }
  .ib { display: inline-flex; align-items: center; justify-content: center; width: 30px; height: 30px; border-radius: 6px; flex: none; }
  .ib:hover { background: var(--soft); }
  .menuBtn { display: none; }
  .rowB { display: flex; align-items: center; height: 28px; padding: 0 12px 2px 3px; gap: 1px; }
  .mb { height: 24px; padding: 0 9px; border-radius: 4px; font-size: 13px; }
  .mb:hover, .mb.open { background: var(--soft); }
  .mb.open { background: var(--soft); }
  .rowC { display: flex; align-items: center; gap: 1px; height: 38px; margin: 0 12px 6px; padding: 0 4px; background: var(--bar); border: 0; border-radius: 6px; overflow: hidden; }
  .tb { display: inline-flex; align-items: center; justify-content: center; height: 28px; min-width: 28px; border-radius: 4px; color: var(--icon); flex: none; }
  .tb:hover { background: var(--line); }
  .tb.off { opacity: .38; cursor: default; }
  .tb.off:hover { background: none; }
  .tb.txt { padding: 0 6px; gap: 2px; font-size: 13px; }
  .tb.bold .tl { font-weight: 700; font-size: 15px; } .tb.italic .tl { font-style: italic; font-family: Georgia, serif; font-size: 15px; }
  .tb.strike .tl { text-decoration: line-through; font-size: 15px; }
  .tb.bold, .tb.italic, .tb.strike { width: 28px; padding: 0; }
  .tb.zoom { min-width: 62px; } .tb.styles { min-width: 76px; }
  .tb.model { max-width: 150px; } .tb.model .tl { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .tb.more { margin-left: auto; }
  .sep { width: 1px; height: 20px; background: var(--line); margin: 0 5px; flex: none; }
  .rowD { display: flex; align-items: flex-end; gap: 2px; height: 30px; padding: 0 12px; overflow: hidden; }
  .tab { height: 27px; max-width: 200px; padding: 0 12px; border: 1px solid transparent; border-bottom: 0; border-radius: 6px 6px 0 0; font-size: 12.5px; color: var(--muted); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; flex: none; }
  .tab:hover { background: var(--soft); color: var(--ink); }
  .tab.cur { background: #fff; color: var(--ink); border-color: var(--line); box-shadow: inset 0 2px 0 var(--accent); cursor: default; }
  .tab.all { display: inline-flex; align-items: center; gap: 2px; color: var(--accent-ink); margin-left: 4px; }
  .rowE { position: relative; height: 22px; border-top: 1px solid var(--line); background: var(--chrome); }
  .rbar { position: absolute; top: 3px; height: 15px; background: var(--paper); box-shadow: 0 0 0 1px var(--line); }
  .rml, .rmr { position: absolute; top: 0; bottom: 0; background: var(--bar); }
  .rml { left: 0; } .rmr { right: 0; }
  .rtext { position: absolute; top: 0; bottom: 0;
    background-image: linear-gradient(90deg, #BDC3CB 1px, transparent 1px), linear-gradient(90deg, var(--muted) 1px, transparent 1px);
    background-repeat: repeat-x; background-position: 0 100%, 0 100%; background-size: 12px 4px, 48px 7px; }
  .rn { position: absolute; top: 0; transform: translateX(-50%); font-size: 9.5px; line-height: 11px; color: var(--muted); background: var(--paper); padding: 0 1px; }
  .rh { position: absolute; top: -3px; width: 10px; height: 9px; cursor: ew-resize; touch-action: none;
    background: var(--accent); clip-path: polygon(0 0, 100% 0, 50% 100%); }
  .shell.compact .rowA { height: 38px; gap: 6px; padding: 0 8px; }
  .shell.compact .logo svg { width: 24px; height: 24px; }
  .shell.compact .menuBtn { display: inline-flex; width: 28px; height: 28px; }
  .shell.compact .app { display: none; }
  .shell.compact .title { font-size: 14px; }
  .shell.compact .tin { font-size: 14px; height: 19px; }
  .shell.compact .pen svg { width: 13px; height: 13px; }
  .shell.compact .abtn { height: 28px; padding: 0 8px; }
  .shell.compact .abtn span { display: none; }
  .shell.compact .rowC { height: 34px; margin: 0 8px 6px; }
  .shell.compact .tb.styles, .shell.compact .tb.zoom { min-width: 0; }
  .menu { position: fixed; z-index: 2147483001; min-width: 230px; max-width: min(360px, calc(100vw - 16px)); overflow-y: auto; padding: 5px 0;
    background: var(--paper); border: 1px solid var(--line); border-radius: 6px; box-shadow: 0 2px 6px rgba(60, 64, 67, .15), 0 1px 2px rgba(60, 64, 67, .10); }
  .mi { display: grid; grid-template-columns: 26px 1fr auto; align-items: center; width: 100%; min-height: 30px; padding: 0 14px 0 8px; text-align: left; font-size: 13px; }
  .mi:hover, .mi:focus { background: var(--soft); outline: none; }
  .mi.off { color: rgba(95, 99, 104, .5); cursor: default; } .mi.off:hover { background: none; }
  .mi.head { font-weight: 600; }
  .ck { display: inline-flex; color: var(--accent-ink); } .mi.off .ck { color: inherit; }
  .ml { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; padding-right: 14px; }
  .kb { color: var(--muted); font-size: 12px; display: inline-flex; }
  .msep { height: 1px; margin: 5px 0; background: var(--line); }
  .findbar { position: fixed; right: 16px; z-index: 2147483001; display: flex; align-items: center; gap: 4px; padding: 5px 6px 5px 10px;
    background: var(--paper); border: 1px solid var(--line); border-radius: 6px; box-shadow: 0 2px 6px rgba(60, 64, 67, .15); }
  .findbar input { width: min(220px, 50vw); height: 28px; border: 1px solid var(--line); border-radius: 4px; padding: 0 8px; font: inherit; background: var(--paper); color: var(--ink); }
  .fcount { font-size: 12px; color: var(--muted); min-width: 64px; text-align: right; }
  .dlg { position: fixed; inset: 0; z-index: 2147483002; background: rgba(32, 33, 36, .32); display: flex; align-items: center; justify-content: center; padding: 12px; }
  .dbox { width: min(420px, 100%); max-height: calc(100vh - 24px); overflow: auto; background: var(--paper); border-radius: 8px; padding: 18px 20px 14px; box-shadow: 0 8px 24px rgba(60, 64, 67, .2); }
  .dbox h2 { margin: 0 0 12px; font-size: 16px; font-weight: 600; }
  .dbody { font-size: 13px; line-height: 1.5; color: var(--ink); }
  .dbody table { width: 100%; border-collapse: collapse; } .dbody td { padding: 5px 0; border-bottom: 1px solid var(--line); } .dbody td.num { text-align: right; color: var(--ink); font-weight: 600; }
  .form label { display: block; margin-bottom: 10px; font-size: 12px; color: var(--muted); }
  .form input { display: block; width: 100%; margin-top: 3px; height: 32px; border: 1px solid var(--line); border-radius: 4px; padding: 0 8px; font: 13px var(--ui); color: var(--ink); }
  .dbtns { display: flex; justify-content: flex-end; gap: 8px; margin-top: 14px; }
  .toast { position: fixed; left: 50%; bottom: 22px; transform: translate(-50%, 20px); z-index: 2147483003; background: #202124; color: #fff; padding: 8px 14px; border-radius: 6px; font-size: 13px; opacity: 0; pointer-events: none; transition: opacity .15s, transform .15s; }
  .toast.on { opacity: 1; transform: translate(-50%, 0); }
  .returnPill { position: fixed; left: 64px; bottom: 14px; z-index: 2147483000; display: flex; align-items: center; gap: 6px; height: 34px; padding: 0 12px 0 6px;
    background: var(--paper); border: 1px solid var(--line); border-radius: 17px; box-shadow: 0 1px 3px rgba(60, 64, 67, .15); font-size: 13px; }
  .returnPill svg { width: 22px; height: 22px; }
  `; }
})();
