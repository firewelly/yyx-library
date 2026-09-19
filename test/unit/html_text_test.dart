import 'package:flutter_test/flutter_test.dart';
import 'package:novelmgt_flutter/utils/html_text.dart';

void main() {
  group('HtmlText.stripHtml', () {
    test('移除标签并保留文本', () {
      expect(HtmlText.stripHtml('<p>你好世界</p>'), '你好世界');
    });

    test('解码命名实体', () {
      expect(HtmlText.stripHtml('A&nbsp;&amp;&lt;B&gt;'), 'A &<B>');
      expect(HtmlText.stripHtml('&ldquo;引号&rdquo;&hellip;'), '“引号”…');
      expect(HtmlText.stripHtml('&mdash;&ndash;'), '—–');
    });

    test('解码数字实体', () {
      expect(HtmlText.stripHtml('&#20320;&#22909;'), '你好');
      expect(HtmlText.stripHtml('&#x4F60;&#x597D;'), '你好');
    });

    test('移除 script/style 内容', () {
      const html = '<p>正文</p><script>var x = 1;</script><style>.a{}</style><p>结尾</p>';
      expect(HtmlText.stripHtml(html), '正文结尾');
    });

    test('preserveParagraphs 保留段落结构', () {
      const html = '<p>第一段</p><p>第二段</p>';
      expect(HtmlText.stripHtml(html, preserveParagraphs: true), '第一段\n\n第二段');
    });

    test('折叠多余空行', () {
      expect(HtmlText.stripHtml('a\n\n\n\nb'), 'a\n\nb');
    });
  });
}
