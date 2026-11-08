# HTML mail rendering

## Runtime paths

`MailDetailScreen` still calls `MailHtmlBody`; no mail API, stored EML, account,
attachment download, reply/forward or plain-text code is changed.

- **Web:** an `HtmlElementView` iframe with `sandbox="allow-scripts"`. There is
  **no** `allow-same-origin`, popup, form, download or top-navigation permission.
- **Windows / Android / iOS / macOS:** `flutter_inappwebview` 6.1.5, using the OS
  browser engine. Windows checks for WebView2 first and uses an application
  support directory, not the executable directory, for its dedicated profile.
- **Linux / Fuchsia / unavailable native engine / failed bootstrap:** the
  previous Flutter widget renderer remains as a compatibility fallback, inside
  a light theme/white canvas. Its old image-stability and table workarounds are
  intentionally retained ONLY here. It is not equivalent to browser rendering.

`mail_html_document.dart` supplies the same document/bootstrap to both browser
paths. Browser paths preserve real table rows, columns, spans, nested tables,
inline images, inline styles and `<style>` rules; they do not apply the old
blanket `display:block` rewrite. A light document default prevents black mail
text inheriting the dark app background, without overriding sender colours.
Wide tables scroll horizontally. Height follows content/image/viewport changes;
a 4096px surface ceiling avoids excessive native allocation, with internal
scrolling beyond that ceiling. Boundary wheel/touch scrolling is forwarded to
the outer Flutter list so the embedded view does not trap scrolling.

HTML text selection uses the browser. The existing whole-body copy menu is
unchanged. Links, including image maps, use the existing real-URL confirmation
and external-launch flow; the renderer does not navigate to them itself.

## Trust boundary

The original message is UTF-8 base64 **data**, not HTML interpolated into an
executable template. A fresh 192-bit nonce identifies the document and the only
script allowed by its CSP: FileForge's bootstrap. Mail scripts are not enabled.

The bootstrap parses the message into an inert template, reconstructs an
allow-listed static DOM and drops scripts, event attributes, frames, objects,
SVG/MathML, forms/inputs, external stylesheets, meta refresh, base tags, active
URLs and relative links to the app's APIs. Sender CSS and normal table
presentation survive. CSP is an independent second boundary: no arbitrary
scripts, connections, frames, objects, forms or local-file resources. The native
engine also denies file/content access, permissions, popups and navigation.

Messages from the web iframe require the exact frame source, opaque `null`
origin, channel name and per-document token. Native bridge messages require the
channel/token. Links additionally require an actual user click and the existing
Dart scheme allow-list. The app's tokens are never placed in this document.

Raster data images and HTTP(S) images remain supported, including the server's
existing signed image-proxy URLs. This preserves the pre-existing remote-image
policy; it is NOT a new tracking-image blocker. Referrers are suppressed.

## Build / operation

A new native plugin requires a **full client rebuild**, not just hot reload:

```sh
cd client
flutter pub get
# Then use the existing run/build script for the intended platform.
```

Windows builds require NuGet on PATH and runtime use requires Microsoft Edge
WebView2. Other native setup requirements are those of the selected plugin:
https://inappwebview.dev/docs/intro/
https://inappwebview.dev/docs/webview/in-app-webview/

The existing pubspec.lock is retained. `flutter pub get` must resolve the new
pinned plugin and regenerate it; a successful SDK resolution must precede
committing a newly generated lockfile. Do not hand-invent lockfile hashes.

A deployment CSP which blocks the iframe's nonced bootstrap will cause the
compatibility fallback, not a permanently blank message. Very large native
HTML documents can also hit engine-specific limits and use the fallback.

Server MIME-selection policy is unchanged: this change renders the HTML the
mail API supplies. It does not recover HTML for messages the server returns as
plain text, and does not modify stored mail or force a re-sync.

## Verification

The authoring environment had Chromium/Playwright but no Flutter/Dart SDK.
**17 production-bootstrap browser tests passed** in that environment. These
exercise the actual raw constants embedded in `mail_html_document.dart`, not a
separately implemented sanitizer. They cover table/spans/style preservation,
dark-app readability, author colours, nested security-notice tables, narrow
viewports, image aspect/inline layout, text selection/Unicode, link/image-map
routing, resize/long-message/wheel handling and active-content/CSP isolation.

```sh
python -m pip install playwright
python -m playwright install chromium
python tools/test_mail_html_browser.py
# Or set CHROMIUM_PATH to an existing Chromium installation.
```

Flutter analysis, widget tests and native builds were **not run locally**.
The checked-in mail-rendering workflow runs targeted Flutter tests plus web and
Windows compilation on pushes that affect this renderer. A workflow definition
is not evidence of a successful run; inspect its actual result before treating
those checks as passed. No exact reproduction with the reporter's original EML
was possible because only screenshots were supplied.
