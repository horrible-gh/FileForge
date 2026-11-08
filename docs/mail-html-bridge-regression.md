# Delayed HTML-mail fallback and duplicate subject — 2026-11-08

## Symptom and proven cause

The reported web screen initially showed a readable, correctly structured mail
inside a roughly 320px-high browser frame. It later expanded into a different,
broken table layout. The original interpretation that expansion itself was
corrupting the table was incorrect: the browser was being replaced.

The compiled Flutter web regression harness reproduced this on the unchanged
runtime at `aac860c75c7e8555465c867b6068cafc884d3722`:

1. `MailHtmlView` starts its 12-second bootstrap watchdog.
2. The iframe renders HTML and sends `ready` and `height` messages.
3. Reading/comparing `MessageEvent.source` and `iframe.contentWindow` through
   the ordinary Dart interop path probes a Dart dispatch property on the
   cross-origin WindowProxy and throws `SecurityError`.
4. Neither message is acknowledged; the frame stays at its initial 320px.
5. The watchdog expires and replaces that working browser with the legacy
   Flutter fallback, which still stacks table elements as blocks.

The captured exception included:

```text
Failed to read a named property '___dart_dispatch_record_ZxYxX_0_' from 'Window':
Blocked a frame ... from accessing a cross-origin frame.
```

Baseline reproduction run (4 failing compiled-app tests):
https://github.com/horrible-gh/FileForge/actions/runs/42447459388

The previous 17 standalone HTML tests exercised the production JavaScript
bootstrap but not the compiled Dart receiver, so they could not catch this
integration failure. They remain useful but are no longer the only browser
verification layer.

## Runtime changes

`client/lib/widgets/mail_html_web.dart` now obtains the iframe through
`contentWindowCrossOrigin`, reads the event source as opaque `JSAny?` and uses
JavaScript strict identity comparison. It does not inspect the cross-origin
window's properties. Origin, exact source window, channel and per-document
nonce validation all remain mandatory; sandbox permissions are not relaxed.

A valid positive finite height message also acknowledges bootstrap readiness.
A successfully rendering browser therefore cannot be replaced just because an
earlier readiness message was missed. Genuine initialization failure retains
the compatibility fallback. No table or sender-CSS rewriting was added.

The integration tests also exposed keyboard focus remaining inside the iframe
when a link confirmation dialog opened. The parent-owned iframe is now blurred
before Flutter requests dialog focus. Both the actual Cancel button and Escape
are exercised, including restoration of mail input after dismissal.

`client/lib/screens/mail/mail_detail_screen.dart` displays the subject once,
in the AppBar. The loaded message is authoritative, the route subject is only
a loading placeholder, and an empty subject uses localized no-subject text.
A previous message's detail cannot supply the new message's title or actions.
The full subject remains available through the existing copy menu. The body
starts with sender/recipient metadata rather than a second subject heading.

## Verification

Runtime fix: `d4581487ff9dd1754c8e40baa598f3861a791734`.
Final runtime code including keyboard focus:
`0e888fec139c6e39904cc6bd31e5c74e9039535b`.

- Targeted Flutter analysis passed (one pre-existing informational native lint).
- **36 Flutter regression tests passed**, including five title and two Bcc tests.
- **17 production-bootstrap browser tests passed**.
- **8 compiled Flutter web integration tests passed**.
- `flutter build web --release` passed.

Rendering checks:
https://github.com/horrible-gh/FileForge/actions/runs/42448219182
Compiled-app browser checks:
https://github.com/horrible-gh/FileForge/actions/runs/42448219198

The compiled-app suite verifies survival beyond the 12-second watchdog,
measured height, non-overlapping table columns, viewport resizing without
replacing the document, delayed-image sizing, message replacement/stale-token
rejection, foreign-source/bad-origin/bad-token rejection, and real link-dialog
cancellation by both button and keyboard. Each final evidence JSON reports
zero page errors and one retained iframe. Screenshots and JSON are stored in
the `mail-html-app-evidence` workflow artifact.

The fixture uses the production detail screen and renderer in a release-built
Flutter app, with synthetic mail and a local HTTP server. It does not use real
mail, credentials, or accounts. The test-only index avoids unrelated PDF CDN
scripts while retaining the actual Flutter loader, CanvasKit and compiled app.

## Scope and application

No server, mail synchronization, stored EML, account data, dependencies or native
renderer were changed for this incident. The user's live deployment was not
replaced. Apply the latest main and rebuild/redeploy the web client with the
existing production configuration, then reload the browser to load that bundle.
No mail re-sync or data migration is required.

The reporter's original EML was not supplied, so the evidence establishes the
reproduced bridge failure and synthetic-table regression, not a pixel-identical
comparison of that private message. No physical-device native GUI testing or
Android/iOS/macOS build was performed for this follow-up.
