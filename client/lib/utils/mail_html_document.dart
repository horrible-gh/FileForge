import 'dart:convert';
import 'dart:math';

/// Isolated, script-restricted document shared by the web iframe and native
/// WebViews. Mail HTML is DATA, never interpolated as executable markup. Only
/// our randomly nonced bootstrap can execute; the sender's active content is
/// removed from an inert template before insertion as a second defence.
class MailHtmlDocument {
  MailHtmlDocument(String mailHtml) : token = _newToken() {
    final script = _mailBootstrap
        .replaceAll('__FF_TOKEN__', token)
        .replaceAll('__FF_PAYLOAD__', base64Encode(utf8.encode(mailHtml)));
    html = _mailTemplate
        .replaceAll('__FF_TOKEN__', token)
        .replaceAll('__FF_SCRIPT__', script);
  }

  final String token;
  late final String html;

  static String _newToken() {
    final random = Random.secure();
    return base64UrlEncode(List<int>.generate(
      24, (_) => random.nextInt(256), growable: false,
    ));
  }
}

/// Bounds native surface allocation. Longer messages remain scrollable INSIDE
/// the document; they are not clipped or truncated.
const double mailHtmlMaxHeight = 4096;

const _mailTemplate = r'''<!doctype html>
<html><head>
<meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'nonce-__FF_TOKEN__'; script-src-attr 'none'; style-src 'unsafe-inline'; img-src https: http: data:; font-src data:; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'">
<meta name="referrer" content="no-referrer">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light">
<style>
html { color-scheme: light; background: #fff; color: #111; }
body { margin: 0; padding: 12px; box-sizing: border-box;
       font: 14px/1.5 Arial, sans-serif; overflow-wrap: break-word; }
img { max-width: 100%; height: auto; }
a { color: #0655b4; text-decoration: underline; cursor: pointer; }
</style>
</head><body>
<script nonce="__FF_TOKEN__">__FF_SCRIPT__</script>
</body></html>''';

// Keep the bootstrap self-contained. tools/test_mail_html_browser.py runs this
// EXACT source in Chromium, not an imitation of the renderer/sanitizer.
const _mailBootstrap = r'''
(() => {
  'use strict';
  const token = '__FF_TOKEN__';
  const raw = new TextDecoder().decode(Uint8Array.from(atob('__FF_PAYLOAD__'), c => c.charCodeAt(0)));
  const destinations = new WeakMap();
  const allowedTags = new Set(('a area map abbr address article b bdi bdo big blockquote br caption center cite code col colgroup dd del details dfn div dl dt em figcaption figure font footer h1 h2 h3 h4 h5 h6 header hr i img ins kbd li main mark ol p pre q rp rt ruby s samp section small span strike strong style sub summary sup table tbody td tfoot th thead time tr tt u ul var wbr').split(' '));
  const dropTags = new Set(('script iframe frame frameset object embed applet base link meta noscript template svg math audio video source track canvas input select textarea option').split(' '));
  const attrs = new Set(('id class style title lang dir align valign width height bgcolor color face size border cellpadding cellspacing colspan rowspan scope headers start type value reversed span nowrap alt role text coords shape').split(' '));
  const raster = /^data:image\/(?:png|gif|jpe?g|webp|avif|bmp|x-icon);base64,[a-z0-9+/=\s]+$/i;

  function send(kind, value) {
    const message = { channel: 'fileforge-mail', token, kind, value };
    if (window.parent !== window) {
      window.parent.postMessage(message, '*');
    } else if (window.flutter_inappwebview && typeof window.flutter_inappwebview.callHandler === 'function') {
      window.flutter_inappwebview.callHandler('fileforgeMail', message).catch(() => {});
    }
  }

  function safeUrl(value, image = false) {
    const text = String(value || '').trim();
    if (!text || /[\u0000-\u001f\u007f]/.test(text)) return null;
    if (!image && text.startsWith('#')) return text;
    if (image && raster.test(text)) return text;
    const absolute = text.startsWith('//') ? 'https:' + text : text;
    try {
      const u = new URL(absolute); // NO base: relative URLs must not reach the app's API.
      if (u.protocol === 'https:' || u.protocol === 'http:') {
        return u.hostname && !u.username && !u.password ? u.href : null;
      }
      if (!image && u.protocol === 'mailto:') return u.href;
    } catch (_) {}
    return null;
  }

  function cleanAttributes(source, target) {
    for (const attr of Array.from(source.attributes)) {
      const name = attr.name.toLowerCase();
      // Explicit allow-list: no events, nonce, srcdoc, formaction, ping, target,
      // download, srcset, namespaced URLs, custom elements or access keys.
      if (attrs.has(name) || name.startsWith('aria-')) {
        target.setAttribute(name, attr.value);
      } else if (name === 'background') {
        const url = safeUrl(attr.value, true);
        if (url) target.setAttribute(name, url);
      }
    }
  }

  function cleanNode(source) {
    if (source.nodeType === Node.TEXT_NODE) return document.createTextNode(source.data);
    if (source.nodeType !== Node.ELEMENT_NODE) return null;
    const tag = source.localName.toLowerCase();
    if (dropTags.has(tag) || source.namespaceURI !== 'http://www.w3.org/1999/xhtml') return null;
    // Unknown wrappers (including form/button) lose their behaviour but retain
    // readable contents. New nodes are created; untrusted DOM is never adopted.
    const node = allowedTags.has(tag) ? document.createElement(tag) : document.createDocumentFragment();
    if (node.nodeType === Node.ELEMENT_NODE) {
      cleanAttributes(source, node);
      if (tag === 'map' && source.hasAttribute('name')) node.setAttribute('name', source.getAttribute('name'));
      if (tag === 'img') {
        const map = source.getAttribute('usemap');
        if (map && /^#[^\s]+$/.test(map)) node.setAttribute('usemap', map);
        const src = safeUrl(source.getAttribute('src'), true);
        if (src) node.setAttribute('src', src);
        node.setAttribute('referrerpolicy', 'no-referrer');
        node.setAttribute('loading', 'eager');
      }
      if (tag === 'a' || tag === 'area') {
        const href = safeUrl(source.getAttribute('href'));
        if (href) {
          // Keep a harmless href for keyboard focus / a[href] styles. The real
          // destination lives ONLY in a WeakMap, so native context menus and
          // drag/drop cannot bypass the existing Flutter confirmation flow.
          node.setAttribute('href', '#fileforge-link');
          node.setAttribute('title', href);
          destinations.set(node, href);
        }
      }
      if (tag === 'style') {
        node.textContent = source.textContent;
        return node;
      }
    }
    for (const child of Array.from(source.childNodes)) {
      const clean = cleanNode(child);
      if (clean) node.appendChild(clean);
    }
    return node;
  }

  // Parse as a template: unlike a live document/DOMParser document, template
  // contents cannot fetch images, create frames, submit forms or run scripts.
  // HTML/body attributes need a separate inert parse because the fragment
  // parser deliberately ignores document wrappers.
  const inert = document.createElement('template');
  inert.innerHTML = raw;
  const content = document.createElement('div');
  content.style.setProperty('display', 'flow-root', 'important');
  content.style.setProperty('height', 'auto', 'important');
  content.style.setProperty('min-height', '0', 'important');

  function rootAttributes(tag) {
    // Extract ONLY a start-tag into an inert template. No body/content is
    // parsed in a live document. Quoted '>' is supported; regex does not parse
    // or sanitize the message, only recovers presentation on ignored wrappers.
    const match = raw.match(new RegExp('<' + tag + '\\b(?:[^>"\\\']|"[^"]*"|\\\'[^\\\']*\\\')*>', 'i'));
    if (!match) return null;
    const t = document.createElement('template');
    t.innerHTML = match[0].replace(new RegExp('^<' + tag, 'i'), '<div') + '</div>';
    return t.content.firstElementChild;
  }

  let raf = 0;
  let lastHeight = -1;
  function measure() {
    raf = 0;
    const body = getComputedStyle(document.body);
    const num = v => Number.parseFloat(v) || 0;
    const height = Math.ceil(Math.max(content.scrollHeight, content.getBoundingClientRect().height)
      + num(body.paddingTop) + num(body.paddingBottom)
      + num(body.marginTop) + num(body.marginBottom) + 2);
    if (height !== lastHeight) {
      lastHeight = height;
      send('height', height);
    }
  }
  function queueMeasure() { if (!raf) raf = requestAnimationFrame(measure); }
  function announce() { lastHeight = -1; send('ready', true); queueMeasure(); }

  try {
    for (const tag of ['html', 'body']) {
      const source = rootAttributes(tag);
      const target = tag === 'html' ? document.documentElement : document.body;
      if (source) cleanAttributes(source, target);
      // A 100vh / height:100% mail must not cause an iframe-resize feedback loop.
      target.style.setProperty('height', 'auto', 'important');
      target.style.setProperty('min-height', '0', 'important');
    }
    document.documentElement.style.setProperty('color-scheme', 'light', 'important');
    for (const child of Array.from(inert.content.childNodes)) {
      const clean = cleanNode(child);
      if (clean) content.appendChild(clean);
    }
    document.body.appendChild(content);
    // Sender CSS cannot animate the frame forever. This is appended after
    // their styles but deliberately does NOT alter table/row/cell display.
    const stable = document.createElement('style');
    stable.textContent = '*,*::before,*::after{animation:none!important;transition:none!important}';
    document.head.appendChild(stable);

    document.addEventListener('click', event => {
      const a = event.target.closest && event.target.closest('a,area');
      if (!a) return;
      event.preventDefault();
      const href = destinations.get(a);
      if (!href || !event.isTrusted) return;
      if (href.startsWith('#')) {
        let id = href.slice(1);
        try { id = decodeURIComponent(id); } catch (_) {}
        const target = document.getElementById(id);
        if (target) target.scrollIntoView();
      } else {
        send('link', href);
      }
    }, true);
    for (const type of ['auxclick', 'contextmenu', 'dragstart']) {
      document.addEventListener(type, event => {
        if (event.target.closest && event.target.closest('a,area')) event.preventDefault();
      }, true);
    }

    // Platform views consume wheel/touch events before Flutter sees them.
    // Scroll an inner overflow area normally; at its boundary hand the delta
    // to the surrounding Flutter ListView instead of trapping the user here.
    function canScroll(target, delta) {
      for (let el = target instanceof Element ? target : target.parentElement;
           el; el = el.parentElement) {
        const overflow = getComputedStyle(el).overflowY;
        if ((overflow === 'auto' || overflow === 'scroll') && el.scrollHeight > el.clientHeight + 1) {
          if (delta > 0 ? el.scrollTop + el.clientHeight < el.scrollHeight - 1 : el.scrollTop > 0) return true;
        }
      }
      const el = document.scrollingElement;
      return el && (delta > 0 ? el.scrollTop + el.clientHeight < el.scrollHeight - 1 : el.scrollTop > 0);
    }
    document.addEventListener('wheel', event => {
      if (!event.isTrusted || event.ctrlKey || event.metaKey || event.shiftKey ||
          Math.abs(event.deltaX) > Math.abs(event.deltaY)) return;
      const delta = event.deltaY * (event.deltaMode === 1 ? 16 : event.deltaMode === 2 ? innerHeight : 1);
      if (delta && !canScroll(event.target, delta)) {
        event.preventDefault();
        send('scroll', delta);
      }
    }, { passive: false });
    let touch = null;
    document.addEventListener('touchstart', event => {
      touch = event.touches.length === 1 ? { x: event.touches[0].clientX, y: event.touches[0].clientY } : null;
    }, { passive: true });
    document.addEventListener('touchmove', event => {
      if (!touch || event.touches.length !== 1 || !event.isTrusted) return;
      const next = event.touches[0];
      const dy = touch.y - next.clientY, dx = touch.x - next.clientX;
      touch = { x: next.clientX, y: next.clientY };
      // Preserve horizontal table scrolling, pinch zoom and native text selection.
      if (Math.abs(dx) > Math.abs(dy) || String(getSelection()).length) return;
      if (dy && !canScroll(event.target, dy)) {
        event.preventDefault();
        send('scroll', dy);
      }
    }, { passive: false });
    document.addEventListener('touchend', () => { touch = null; });
    document.addEventListener('submit', event => event.preventDefault(), true);
    document.addEventListener('load', queueMeasure, true);
    document.addEventListener('error', queueMeasure, true);
    window.addEventListener('resize', queueMeasure);
    window.addEventListener('flutterInAppWebViewPlatformReady', announce);
    window.addEventListener('fileforge-mail-ready', announce);
    if (window.ResizeObserver) new ResizeObserver(queueMeasure).observe(content);
    announce();
  } catch (_) {
    send('error', 'render_failed');
  }
})();
''';
