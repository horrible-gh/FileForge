"""Exercise the compiled Flutter app/iframe boundary, including the watchdog.

Build client/test/browser/mail_html_app.dart with Flutter --release and
--no-web-resources-cdn into client/build/mail-html-app before running this.
Unlike test_mail_html_browser.py, this executes the production Dart receiver.
"""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import base64
import json
import os
import re
import threading
import unittest

from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'client/build/mail-html-app'
ARTIFACTS = ROOT / 'artifacts/mail-html-app'
SELECTOR = 'iframe[title="HTML email"]'
IMAGE_GATE = threading.Event()
PNG = base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAACgAAAAUCAIAAABwJOjsAAAAJElEQVR4nO3NMQ0AAAACIPuX1hg+bPykycVnFYvFYrFYLO4jHn36HQ4oCLQGAAAAAElFTkSuQmCC')


class AppHandler(SimpleHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def do_GET(self):
        path = self.path.split('?')[0]
        if path in ('/', '/index.html'):
            # Avoid unrelated PDF CDN scripts in the production index. Flutter's
            # actual generated loader/CanvasKit/compiled app are served locally.
            body = b'<!doctype html><html><head><base href="/"><meta charset="utf-8"></head><body><script src="flutter_bootstrap.js" async></script></body></html>'
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if path == '/late.png':
            IMAGE_GATE.wait(timeout=10)
            self.send_response(200)
            self.send_header('Content-Type', 'image/png')
            self.send_header('Content-Length', str(len(PNG)))
            self.end_headers()
            self.wfile.write(PNG)
            return
        super().do_GET()


class FlutterMailBrowserTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not (BUILD / 'main.dart.js').is_file():
            raise RuntimeError('Build the Flutter browser integration entry point first')
        ARTIFACTS.mkdir(parents=True, exist_ok=True)
        cls.server = ThreadingHTTPServer(('127.0.0.1', 0), partial(AppHandler, directory=str(BUILD)))
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.origin = f'http://127.0.0.1:{cls.server.server_port}'
        cls.pw = sync_playwright().start()
        options = {'headless': True}
        if os.getenv('CHROMIUM_PATH'):
            options['executable_path'] = os.environ['CHROMIUM_PATH']
        cls.browser = cls.pw.chromium.launch(**options)
        print('Compiled Flutter browser:', cls.browser.version, flush=True)

    @classmethod
    def tearDownClass(cls):
        cls.browser.close()
        cls.pw.stop()
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join(timeout=5)

    def setUp(self):
        self.context = self.browser.new_context(viewport={'width': 1280, 'height': 1000}, color_scheme='dark')
        self.page = self.context.new_page()
        self.errors = []
        self.page.on('pageerror', lambda error: self.errors.append(str(error)))
        self.page.goto(self.origin)
        self.page.wait_for_function('typeof ffSetMailFixture === "function"')
        self.iframe = self.page.locator(SELECTOR)
        self.iframe.wait_for(state='attached')
        self.frame = self.iframe.element_handle().content_frame()
        self.frame.wait_for_selector('#greeting')

    def tearDown(self):
        IMAGE_GATE.set()
        name = self._testMethodName
        try:
            self.page.screenshot(path=str(ARTIFACTS / f'{name}.png'), full_page=True)
            (ARTIFACTS / f'{name}.json').write_text(json.dumps({'page_errors': self.errors, 'iframe_count': self.iframe.count()}, ensure_ascii=False, indent=2), encoding='utf-8')
        finally:
            self.context.close()

    def assert_no_errors(self):
        self.assertEqual(self.errors, [], '\n'.join(self.errors))

    def wait_for_height(self, minimum):
        self.iframe.evaluate('(el,min)=>new Promise((resolve,reject)=>{const start=Date.now();const check=()=>{if(el.getBoundingClientRect().height>min){resolve(true);return;}if(Date.now()-start>5000){reject(new Error("Flutter iframe height stayed at "+el.getBoundingClientRect().height));return;}setTimeout(check,50);};check();})', minimum)

    def token(self):
        return re.search(r'<script nonce="([^"]+)"', self.iframe.get_attribute('srcdoc')).group(1)

    def replace_html(self, html, marker):
        self.page.evaluate('html=>ffSetMailFixture(html)', html)
        self.page.wait_for_timeout(200)
        self.iframe.wait_for(state='attached')
        self.frame = self.iframe.element_handle().content_frame()
        self.frame.wait_for_selector(marker)

    def test_browser_survives_watchdog_without_switching_to_fallback(self):
        self.page.wait_for_timeout(13500)
        self.assertEqual(self.iframe.count(), 1, 'The browser was replaced by the legacy table-flattening fallback. Errors: ' + repr(self.errors))
        self.assertGreater(self.iframe.bounding_box()['height'], 320)
        self.assertEqual(self.frame.locator('#step').evaluate('el=>getComputedStyle(el).display'), 'table-cell')
        self.assert_no_errors()

    def test_height_and_table_columns_reach_flutter(self):
        self.wait_for_height(400)
        step = self.frame.locator('#step').bounding_box()
        text = self.frame.locator('#instructions').bounding_box()
        self.assertGreaterEqual(text['x'], step['x'] + step['width'] - 1)
        self.assertAlmostEqual(step['y'], text['y'], delta=1)
        self.assert_no_errors()

    def test_viewport_resize_keeps_the_same_browser_document(self):
        self.wait_for_height(400)
        self.frame.evaluate('window.fixtureIdentity = "keep-this-document"')
        self.page.set_viewport_size({'width': 600, 'height': 900})
        self.page.wait_for_timeout(600)
        self.assertEqual(self.frame.evaluate('window.fixtureIdentity'), 'keep-this-document')
        self.assertEqual(self.frame.locator('#step').evaluate('el=>getComputedStyle(el).display'), 'table-cell')
        self.assertGreater(self.frame.evaluate('document.documentElement.scrollWidth'), self.frame.evaluate('innerWidth'))
        self.assert_no_errors()

    def test_switching_mail_replaces_the_document_and_ignores_old_channel(self):
        self.wait_for_height(400)
        old_html, old_token = self.iframe.get_attribute('srcdoc'), self.token()
        self.replace_html('<p id="second">Second message</p>', '#second')
        self.assertNotEqual(self.iframe.get_attribute('srcdoc'), old_html)
        before = self.iframe.bounding_box()['height']
        self.frame.evaluate('token=>parent.postMessage({channel:"fileforge-mail",token,kind:"height",value:4000},"*")', old_token)
        self.page.wait_for_timeout(200)
        self.assertEqual(self.iframe.count(), 1)
        self.assertAlmostEqual(self.iframe.bounding_box()['height'], before, delta=1)
        self.assert_no_errors()

    def test_foreign_source_bad_origin_and_bad_token_are_ignored(self):
        self.wait_for_height(400)
        token = self.token()
        before = self.iframe.bounding_box()['height']
        self.assertEqual(self.iframe.get_attribute('sandbox'), 'allow-scripts')
        self.page.evaluate('''token=>{
          const sibling=document.createElement('iframe');
          sibling.id='foreign-mail'; sibling.sandbox='allow-scripts';
          sibling.srcdoc='<script>parent.postMessage('+JSON.stringify({channel:'fileforge-mail',token,kind:'error',value:'forged'})+',"*")<'+ '/script>';
          document.body.appendChild(sibling);
        }''', token)
        self.iframe.evaluate('''(el,token)=>{
          window.dispatchEvent(new MessageEvent('message',{source:el.contentWindow,origin:'https://wrong.example',data:{channel:'fileforge-mail',token,kind:'height',value:4000}}));
        }''', token)
        self.frame.evaluate('''()=>{
          parent.postMessage({channel:'fileforge-mail',token:'wrong',kind:'error'},'*');
          parent.postMessage({channel:'fileforge-mail',token:'wrong',kind:'height',value:4000},'*');
        }''')
        self.page.wait_for_timeout(400)
        self.assertEqual(self.iframe.count(), 1)
        self.assertAlmostEqual(self.iframe.bounding_box()['height'], before, delta=1)
        self.page.locator('#foreign-mail').evaluate('el=>el.remove()')
        self.assert_no_errors()

    def test_delayed_image_updates_height_without_replacing_browser(self):
        IMAGE_GATE.clear()
        self.replace_html(f'<p id="image-start">Before image</p><img id="late" style="width:600px" src="{self.origin}/late.png"><p id="after-image">After image</p>', '#after-image')
        self.page.wait_for_timeout(200)
        before = self.iframe.bounding_box()['height']
        self.frame.evaluate('window.fixtureIdentity="same-after-image"')
        IMAGE_GATE.set()
        self.frame.wait_for_function('document.querySelector("#late").naturalWidth===40')
        self.wait_for_height(before + 200)
        self.assertEqual(self.frame.evaluate('window.fixtureIdentity'), 'same-after-image')
        self.assertEqual(self.iframe.count(), 1)
        self.assert_no_errors()

    def open_link_dialog(self):
        self.wait_for_height(400)
        self.frame.locator('#application').click()
        self.page.get_by_role('button', name='Cancel', exact=True).wait_for()
        self.assertEqual(self.iframe.evaluate('el=>el.style.pointerEvents'), 'none')
        self.assertEqual(len(self.context.pages), 1)

    def assert_browser_restored(self):
        self.page.wait_for_timeout(400)
        self.assertEqual(self.iframe.evaluate('el=>el.style.pointerEvents'), '')
        self.assertEqual(self.iframe.count(), 1)
        self.assertEqual(self.frame.locator('#step').evaluate('el=>getComputedStyle(el).display'), 'table-cell')
        self.assert_no_errors()

    def test_real_link_opens_confirmation_and_cancel_keeps_browser(self):
        self.open_link_dialog()
        self.page.get_by_role('button', name='Cancel', exact=True).click()
        self.assert_browser_restored()

    def test_link_dialog_escape_reaches_flutter_not_the_focused_iframe(self):
        self.open_link_dialog()
        # Do not focus/click the parent page from the test. The production link
        # handler must transfer focus itself after a genuine iframe click.
        self.page.keyboard.press('Escape')
        self.assert_browser_restored()


if __name__ == '__main__':
    unittest.main(verbosity=2)
