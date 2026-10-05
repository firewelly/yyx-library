# 第三方内容声明 / Third-Party Notices

本仓库自有代码以 BSD-3-Clause 授权（见 `LICENSE`）。以下内容不属于自有代码，
按其自身许可分发：

## 示例书库（演示用古籍原文）

发布包（UGOS upk / fnOS fpk）内置的**示例书库** `novelmgt-demo.db` 由
`deploy/ugos/fetch_demo_texts.py` 自[维基文库](https://zh.wikisource.org)抓取、
经繁简转换后生成，包含：

| 作品 | 作者 | 原文页面 |
|---|---|---|
| 西游记 | 吴承恩（明） | https://zh.wikisource.org/wiki/西遊記 |
| 三国演义 | 罗贯中（元末明初） | https://zh.wikisource.org/wiki/三國演義 |
| 红楼梦 | 曹雪芹（清） | https://zh.wikisource.org/wiki/紅樓夢 |

- 上述作品的**原文**属公有领域（作者逝世逾 100 年、初版早于 1931 年）。
- 维基文库的**录入/校勘文本**以 CC BY-SA 4.0 提供，此处按相同许可使用并署名；
  在维基文库页面上再分发该文本或其改编版本时，需保留署名并以相同方式共享。
  正文页链接作为来源标注保留在示例书库每本书的 `sourceUrl` 与每章的 `sourceUrl` 字段。
- 示例书库仅用于让首次安装即可体验书架、阅读与检索；放入用户自己的
  `novelmgt.db` 后即不再使用。

## 其它

- 应用图标、界面文案与代码：本项目自有（BSD-3-Clause）。
- OpenCC 简繁转换词典（如随构建产物分发）遵循其 Apache-2.0 许可。
