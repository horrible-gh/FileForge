#!/usr/bin/env python3
"""Run the actual embedded mail bootstrap in a sandboxed Chromium iframe.

No server/account or real mail is needed. Install playwright and its Chromium,
or set CHROMIUM_PATH to an existing browser. This does not compile Flutter.
"""
from __future__ import annotations

import base64
import os
from pathlib import Path
import re
import unittest
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'client/lib/utils/mail_html_document.dart'
TOKEN = 'mail-test-nonce-0123456789abcdef'


def build_document(raw: str) -> str:
    dart = SOURCE.read_text(encoding='utf-8')
    def constant(name: str) -> str:
        match = re.search(r"const " + name + r" = r'''(.*?)''';", dart, re.S)
        if not match:
            raise AssertionError(f'Missing production constant: {name}')
        return match.group(1)
    script = constant('_mailBootstrap').replace('__FF_TOKEN__', TOKEN).replace(
        '__FF_PAYLOAD__', base64.b64encode(raw.encode()).decode())
    return constant('_mailTemplate').replace('__FF_TOKEN__', TOKEN).replace('__FF_SCRIPT__', script)


TABLE = '''<!doctype html><html lang="ja"><head><style>
.schedule { border-collapse:collapse; width:760px; font-size:14px; }
.schedule th,.schedule td { border:1px solid #456; padding:12px; }
.schedule th { background:#d9eaf7; }
</style></head><body style="color:#000;background-color:#fff">
<p>開発者向けのご案内</p>
<table class="schedule"><thead><tr><th>日程</th><th>内容</th><th>場所</th></tr></thead>
<tbody><tr><td rowspan="2">11月8日</td><td>サービス開発</td><td>オンライン</td></tr>
<tr><td colspan="2">詳細はリンクをご確認ください。</td></tr></tbody></table>
<p><a href="https://example.org/details?x=1&amp;y=2" target="_blank">詳細を確認</a></p>
</body></html>'''


class MailBrowserTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pw = sync_playwright().start()
        # Use the exact browser installed for this Playwright version in CI.
        # A random system Chrome can be protocol-incompatible or a snap wrapper.
        path = os.environ.get('CHROMIUM_PATH')
        cls.browser = cls.pw.chromium.launch(executable_path=path, headless=True, args=['--no-sandbox'])
        print(f'Browser: {cls.browser.version}; executable: {path or "Playwright-managed"}', flush=True)

    @classmethod
    def tearDownClass(cls):
        cls.browser.close()
        cls.pw.stop()

    def setUp(self):
        self.context = self.browser.new_context(viewport={'width': 1100, 'height': 900}, color_scheme='dark')
        # Tests never depend on external images, fonts, CSS, DNS or real mail.
        self.context.route('**/*', lambda route: route.abort())
        self.page = self.context.new_page()
        self.errors = []
        self.page.on('pageerror', lambda error: self.errors.append(str(error)))

    def tearDown(self):
        self.context.close()

    def render(self, raw: str, width=900, sandbox='allow-scripts'):
        self.page.set_content('''<html><body style="background:#14171e"><script>
window.mailMessages=[];window.compromised=false;
window.addEventListener('message',e=>{
 const f=document.querySelector('iframe');
 if(e.source===f.contentWindow && e.data.token==="__TEST_TOKEN__" && e.data.channel==='fileforge-mail') {
   window.mailMessages.push(e.data);
   if(e.data.kind==='height') f.style.height=Math.max(48,Math.min(4096,e.data.value))+'px';
 }
});</script><iframe title="mail" style="border:0;height:320px;background:white;color-scheme:light"></iframe></body></html>'''.replace('__TEST_TOKEN__', TOKEN))
        self.page.locator('iframe').evaluate('''(frame,args)=>{
 frame.setAttribute('sandbox',args.sandbox);frame.setAttribute('referrerpolicy','no-referrer');
 frame.style.width=args.width+'px';frame.srcdoc=args.html;
}''', {'html': build_document(raw), 'width': width, 'sandbox': sandbox})
        self.page.wait_for_function("window.mailMessages.some(m=>m.kind==='ready')", timeout=5000)
        self.frame = next(f for f in self.page.frames if f != self.page.main_frame)
        self.page.wait_for_timeout(80)
        self.assertEqual(self.errors, [])
        return self.frame

    def test_table_columns_spans_css_and_dark_app(self):
        frame = self.render(TABLE)
        info = frame.evaluate('''()=>{
 const t=document.querySelector('table'),cells=t.rows[0].cells;
 return {display:getComputedStyle(t).display,x:[...cells].map(c=>c.getBoundingClientRect().x),
 color:getComputedStyle(t).color,bg:getComputedStyle(document.body).backgroundColor,
 header:getComputedStyle(cells[0]).backgroundColor,span:t.rows[1].cells[0].rowSpan,
 colspan:t.rows[2].cells[0].colSpan,lang:document.documentElement.lang};
}''')
        self.assertEqual(info['display'], 'table')
        self.assertTrue(info['x'][0] < info['x'][1] < info['x'][2])
        self.assertEqual(info['color'], 'rgb(0, 0, 0)')
        self.assertEqual(info['bg'], 'rgb(255, 255, 255)')
        self.assertEqual(info['header'], 'rgb(217, 234, 247)')
        self.assertEqual(info['span'], 2)
        self.assertEqual(info['colspan'], 2)
        self.assertEqual(info['lang'], 'ja')

    def test_light_defaults_without_overwriting_author_colours(self):
        frame = self.render('<p style="color:black">Readable</p>')
        self.assertEqual(frame.evaluate('getComputedStyle(document.documentElement).backgroundColor'), 'rgb(255, 255, 255)')
        self.assertEqual(frame.locator('p').evaluate('(e)=>getComputedStyle(e).color'), 'rgb(0, 0, 0)')
        frame = self.render('<body style="background:#123456;color:#abcdef"><p>Custom</p></body>')
        self.assertEqual(frame.evaluate('getComputedStyle(document.body).backgroundColor'), 'rgb(18, 52, 86)')
        self.assertEqual(frame.locator('p').evaluate('(e)=>getComputedStyle(e).color'), 'rgb(171, 205, 239)')

    def test_legacy_body_bgcolor_and_quoted_greater_than(self):
        frame = self.render('<body title="a > b" bgcolor="#ffccaa" text="#123456"><p>text</p></body>')
        self.assertEqual(frame.evaluate('getComputedStyle(document.body).backgroundColor'), 'rgb(255, 204, 170)')
        self.assertEqual(frame.locator('p').evaluate('(e)=>getComputedStyle(e).color'), 'rgb(18, 52, 86)')
        self.assertEqual(frame.evaluate('document.body.title'), 'a > b')

    def test_narrow_data_table_scrolls_instead_of_stacking(self):
        frame = self.render(TABLE, 360)
        self.assertGreater(frame.locator('table').evaluate('(e)=>e.getBoundingClientRect().width'), 700)
        self.assertGreater(frame.evaluate('document.documentElement.scrollWidth'), 360)
        self.assertEqual(frame.locator('td').first.evaluate('(e)=>getComputedStyle(e).display'), 'table-cell')

    def test_google_nested_table_does_not_collapse_to_one_glyph(self):
        frame = self.render('''<table style="min-width:600px;width:100%"><tr><td>
<table style="min-width:220px"><tr><td style="width:8px;font-size:1px">&nbsp;</td>
<td><div id="message" style="padding:40px 20px">보안 알림 새로운 기기에서 로그인했습니다 이것은 충분히 긴 본문 문장입니다</div></td>
<td style="width:8px;font-size:1px">&nbsp;</td></tr></table></td></tr></table>''', 800)
        self.assertGreater(frame.locator('#message').evaluate('(e)=>e.getBoundingClientRect().width'), 200)

    def test_active_content_and_unsafe_links_are_removed(self):
        frame = self.render('''<body onload="parent.compromised=true">
<script>parent.compromised=true</script><iframe srcdoc="<script>parent.compromised=true</script>"></iframe>
<svg onload="parent.compromised=true"></svg><math><mtext>x</mtext></math>
<meta http-equiv="refresh" content="0;url=https://evil.example"><base href="https://evil.example">
<form action="https://evil.example"><input value="secret"><button>Visible label</button></form>
<img src="x" onerror="parent.compromised=true"><a href="javascript:alert(1)">JS</a>
<a href="file:///etc/passwd">File</a><a href="/fileforge/logout">Relative</a>
<img src="file:///etc/passwd"><img src="data:image/svg+xml,xxx"><p>Safe tail</p></body>''')
        self.assertFalse(self.page.evaluate('window.compromised'))
        self.assertEqual(frame.locator('iframe,svg,math,form,input,button,base,object,embed').count(), 0)
        self.assertEqual(frame.locator('[onload],[onerror],[onclick]').count(), 0)
        self.assertEqual(frame.locator('a[href]').count(), 0)
        self.assertEqual(frame.locator('img[src]').count(), 0)
        self.assertIn('Visible label', frame.locator('body').inner_text())
        self.assertIn('Safe tail', frame.locator('body').inner_text())
        self.assertEqual(frame.locator('script').count(), 1)  # trusted bootstrap only
        self.assertTrue(self.page.evaluate("document.querySelector('iframe').contentDocument === null"))

    def test_links_send_destination_without_navigating(self):
        frame = self.render(TABLE)
        initial_url = frame.url
        frame.get_by_text('詳細を確認').click()
        self.page.wait_for_function("window.mailMessages.some(m=>m.kind==='link')")
        messages = self.page.evaluate('window.mailMessages.filter(m=>m.kind==="link")')
        self.assertEqual(messages[0]['value'], 'https://example.org/details?x=1&y=2')
        self.assertEqual(frame.url, initial_url)
        self.assertEqual(frame.locator('a').get_attribute('href'), '#fileforge-link')
        self.assertIsNone(frame.locator('a').get_attribute('target'))
        # Synthetic page-authored clicks must not open the app's confirmation UI.
        frame.locator('a').evaluate('(a)=>a.click()')
        self.page.wait_for_timeout(50)
        self.assertEqual(self.page.evaluate('window.mailMessages.filter(m=>m.kind==="link").length'), 1)

    def test_plain_selection_and_unicode(self):
        frame = self.render('<p id="text">한국어 日本語 café &amp; &lt;body&gt;</p>')
        selected = frame.evaluate('''()=>{const r=document.createRange();r.selectNodeContents(document.querySelector('#text'));const s=getSelection();s.removeAllRanges();s.addRange(r);return s.toString()}''')
        self.assertEqual(selected, '한국어 日本語 café & <body>')

    def test_height_resize_and_long_message_remain_accessible(self):
        frame = self.render('<div style="height:6000px">top</div><p>bottom</p>')
        self.assertEqual(self.page.locator('iframe').evaluate('(e)=>e.getBoundingClientRect().height'), 4096)
        self.assertGreater(frame.evaluate('document.documentElement.scrollHeight'), 6000)
        frame.get_by_text('bottom', exact=True).scroll_into_view_if_needed()
        self.assertGreater(frame.evaluate('window.scrollY'), 1000)
        self.assertLess(len(self.page.evaluate('window.mailMessages')), 10)

    def test_injected_closing_script_is_inert(self):
        frame = self.render('</script><script>parent.compromised=true</script><p>still here</p>')
        self.assertFalse(self.page.evaluate('window.compromised'))
        self.assertEqual(frame.locator('p').inner_text(), 'still here')

    def test_images_keep_inline_flow_aspect_and_fit(self):
        png = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACgAAAAUCAIAAABwJOjsAAAAJElEQVR4nO3NMQ0AAAACIPuX1hg+bPykycVnFYvFYrFYLO4jHn36HQ4oCLQGAAAAAElFTkSuQmCC'
        frame = self.render(f'<p>before <img id="small" src="{png}" width="40" height="20"> after</p><img id="big" src="{png}" width="1600" height="800">', 800)
        small = frame.locator('#small').bounding_box()
        big = frame.locator('#big').bounding_box()
        self.assertEqual((small['width'], small['height']), (40, 20))
        self.assertEqual(frame.locator('#small').evaluate('(e)=>getComputedStyle(e).display'), 'inline')
        self.assertLessEqual(big['width'], 800)
        self.assertAlmostEqual(big['width'] / big['height'], 2)
        self.assertTrue(frame.locator('#big').evaluate('(e)=>e.complete && e.naturalWidth===40'))

    def test_csp_blocks_a_script_even_if_sanitizer_were_bypassed(self):
        frame = self.render('<p>safe</p>')
        frame.evaluate("""()=>{
 window.senderRan=false;
 const s=document.createElement('script');s.textContent='window.senderRan=true';document.body.appendChild(s);
 const img=document.createElement('img');img.setAttribute('onerror','window.senderRan=true');
 document.body.appendChild(img);img.dispatchEvent(new Event('error'));
}""")
        self.assertFalse(frame.evaluate('window.senderRan'))

    def test_sender_nonce_does_not_bypass_sanitizer(self):
        frame = self.render(f'<script nonce="{TOKEN}">window.senderRan=true</script><p>safe</p>')
        self.assertFalse(frame.evaluate('Boolean(window.senderRan)'))
        self.assertEqual(frame.locator('script').count(), 1)

    def test_wheel_at_document_boundary_hands_back_to_flutter(self):
        frame = self.render('<p>short message</p>')
        frame.locator('p').hover()
        self.page.mouse.wheel(0, 220)
        self.page.wait_for_function("window.mailMessages.some(m=>m.kind==='scroll')")
        message = self.page.evaluate("window.mailMessages.filter(m=>m.kind==='scroll').pop()")
        self.assertEqual(message['value'], 220)

    def test_wheel_inside_long_document_scrolls_without_forwarding(self):
        frame = self.render('<div style="height:6000px">long message</div>')
        frame.get_by_text('long message').hover()
        self.page.mouse.wheel(0, 220)
        self.page.wait_for_timeout(150)
        self.assertGreater(frame.evaluate('window.scrollY'), 0)
        self.assertEqual(self.page.evaluate("window.mailMessages.filter(m=>m.kind==='scroll').length"), 0)

    def test_resize_updates_height_without_viewport_feedback_loop(self):
        frame = self.render('<body style="height:100vh;min-height:100vh"><p>' + 'long readable mail text ' * 100 + '</p></body>', 900)
        before = self.page.locator('iframe').bounding_box()['height']
        self.page.locator('iframe').evaluate("e=>e.style.width='360px'")
        self.page.wait_for_timeout(150)
        after = self.page.locator('iframe').bounding_box()['height']
        self.assertGreater(after, before)
        self.assertLess(self.page.evaluate('window.mailMessages.length'), 10)
        self.assertNotEqual(frame.evaluate('getComputedStyle(document.body).height'), '100vh')

    def test_image_map_uses_same_confirmation_channel(self):
        png = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACgAAAAUCAIAAABwJOjsAAAAJElEQVR4nO3NMQ0AAAACIPuX1hg+bPykycVnFYvFYrFYLO4jHn36HQ4oCLQGAAAAAElFTkSuQmCC'
        frame = self.render(f'<img src="{png}" width="40" height="20" usemap="#nav"><map name="nav"><area shape="rect" coords="0,0,40,20" href="https://example.org/map" alt="map"></map>')
        frame.locator('img').click(position={'x': 10, 'y': 10})
        self.page.wait_for_function("window.mailMessages.some(m=>m.kind==='link')")
        self.assertEqual(self.page.evaluate("window.mailMessages.filter(m=>m.kind==='link')[0].value"), 'https://example.org/map')


if __name__ == '__main__':
    unittest.main(verbosity=2)
