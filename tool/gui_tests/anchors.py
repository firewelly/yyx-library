"""GUI 测试锚点表（canvas 坐标，按视口标定）。

约束：Flutter Web 为 canvas 渲染，页内按钮需按坐标点击。
UI 布局变更后：python3 run_suite.py --calibrate 生成标注截图，重新标定本文件。
导航一律用 hash 路由（/#/xxx），不依赖坐标；文本输入用 DOM input。
"""

# 桌面 1440×900
DESKTOP = {
    "sidebar.library": (45, 93),
    "sidebar.import": (45, 130),
    "sidebar.crawler": (45, 168),
    "sidebar.stats": (45, 205),
    "sidebar.tags": (45, 243),
    "sidebar.authors": (45, 280),
    "sidebar.settings": (125, 867),
    "shelf.first_book": (860, 155),
    "shelf.row2": (860, 222),
    "fab.import": (1395, 855),
    "import.choose_file": (1340, 236),
    "import.start": (850, 373),
    "import.manual_add": (1347, 117),
    "detail.read_btn": (347, 338),
    "detail.continue_btn": (390, 450),
    "reader.next": (1371, 74),
    "reader.prev": (1322, 74),
}

# 手机 390×844
MOBILE = {
    "nav.library": (28, 806),
    "nav.import": (84, 806),
    "nav.crawler": (139, 806),
    "nav.stats": (195, 806),
    "nav.tags": (251, 806),
    "nav.authors": (306, 806),
    "nav.settings": (362, 806),
    "shelf.first_book": (195, 185),
    "shelf.search_input": (118, 28),
    "detail.continue_btn": (100, 444),
    "reader.next": (315, 74),
    "reader.prev": (230, 74),
}

MAPS = {"desktop": DESKTOP, "mobile": MOBILE}

DESKTOP["shelf.search_input"] = (1160, 30)
DESKTOP["manual.save"] = (916, 646)
