"""GUI 测试驱动：Playwright + Flutter Web canvas（坐标点击 + DOM input + /api 断言）。"""
import json
import time
from pathlib import Path

from anchors import MAPS

APP_WAIT_MS = 11000  # Flutter Web 首帧就绪等待（含引擎/字体本地加载）


class Case:
    def __init__(self, cid, name):
        self.cid, self.name = cid, name
        self.status = "PASS"
        self.detail = ""
        self.shot = None

    def fail(self, detail):
        self.status = "FAIL"
        self.detail = detail


class App:
    """被测应用驱动（单视口单会话）。"""

    def __init__(self, page, base, view, evidence: Path):
        self.page = page
        self.base = base.rstrip("/")
        self.view = view
        self.anchors = MAPS[view]
        self.evidence = evidence
        self.evidence.mkdir(parents=True, exist_ok=True)

    # ---- 导航 ----
    async def open(self, route="/", wait_ms=APP_WAIT_MS):
        await self.page.goto(f"{self.base}/#{route}", wait_until="domcontentloaded")
        await self.page.wait_for_timeout(wait_ms)

    async def reload(self, wait_ms=APP_WAIT_MS):
        await self.page.reload(wait_until="domcontentloaded")
        await self.page.wait_for_timeout(wait_ms)

    # ---- 交互 ----
    async def tap(self, anchor):
        x, y = self.anchors[anchor]
        await self.page.mouse.click(x, y)
        await self.page.wait_for_timeout(600)

    async def tap_xy(self, x, y, settle=800):
        await self.page.mouse.click(x, y)
        await self.page.wait_for_timeout(settle)

    async def type(self, index, text, focus_anchor=None, retries=3):
        """向第 index 个可见 DOM 文本框输入（Flutter Web 文本框是真实 <input>；
        DOM 里另有常驻隐藏 input 用于键盘捕获，必须排除）。
        focus_anchor：input 消失/失焦时重点按的锚点（聚焦重建 input）。"""
        last = None
        for _ in range(retries):
            loc = self.page.locator("input:visible:not([type=file])").nth(index)
            try:
                if await loc.count() and await loc.is_visible():
                    await loc.click(timeout=3000)
                    await loc.fill(text, timeout=3000)
                    await self.page.keyboard.press("Enter")
                    await self.page.wait_for_timeout(1200)
                    return
            except Exception as e:
                last = e
            if focus_anchor:
                await self.tap(focus_anchor)
            else:
                await self.page.wait_for_timeout(800)
        raise RuntimeError(f"input[{index}] 不可输入: {last}")

    async def input_count(self):
        return await self.page.locator("input").count()

    async def key(self, key):
        await self.page.keyboard.press(key)
        await self.page.wait_for_timeout(1200)

    async def wheel(self, dy):
        await self.page.mouse.wheel(0, dy)
        await self.page.wait_for_timeout(600)

    # ---- 断言素材 ----
    def api(self, path):
        import urllib.request
        with urllib.request.urlopen(f"{self.base}/api{path}", timeout=20) as r:
            return json.loads(r.read().decode())

    async def shot(self, case: Case, name):
        p = self.evidence / f"{case.cid}-{name}.png"
        await self.page.screenshot(path=str(p))
        case.shot = p.name
        return p

    async def pixel(self, x, y):
        """采样 (x,y) 处像素颜色（主题/字号变化断言用）。"""
        clip = {"x": max(0, x - 2), "y": max(0, y - 2), "width": 4, "height": 4}
        p = self.evidence / "_pixel_tmp.png"
        await self.page.screenshot(path=str(p), clip=clip)
        try:
            from PIL import Image
            im = Image.open(p).convert("RGB")
            px = list(im.getdata())
            return tuple(sum(c[i] for c in px) // len(px) for i in range(3))
        finally:
            p.unlink(missing_ok=True)

    def in_reader(self):
        return "reader" in (self.page.url or "")


class Report:
    def __init__(self, evidence: Path):
        self.cases: list[Case] = []
        self.evidence = evidence

    def case(self, cid, name) -> Case:
        c = Case(cid, name)
        self.cases.append(c)
        return c

    def write(self):
        passed = sum(1 for c in self.cases if c.status == "PASS")
        skipped = [c for c in self.cases if c.status == "SKIP"]
        failed = [c for c in self.cases if c.status == "FAIL"]
        lines = [
            "# GUI 测试报告",
            f"\n- 时间：{time.strftime('%Y-%m-%d %H:%M:%S')}",
            f"- 结果：**{passed}/{len(self.cases)} 通过**，跳过 {len(skipped)}，失败 {len(failed)}",
            "",
            "| # | 用例 | 结果 | 说明 | 截图 |",
            "|---|---|---|---|---|",
        ]
        for c in self.cases:
            shot = f"[{c.shot}]({c.shot})" if c.shot else ""
            if c.status == "SKIP":
                lines.append(f"| {c.cid} | {c.name} | SKIP | {c.detail} | |")
            else:
                lines.append(f"| {c.cid} | {c.name} | {c.status} | {c.detail} | {shot} |")
        (self.evidence / "report.md").write_text("\n".join(lines), encoding="utf-8")
        return passed, len(failed), failed


def check(case: Case, cond, detail_ok="", detail_bad=""):
    if cond:
        case.detail = detail_ok or case.detail
    else:
        case.fail(detail_bad)
    return cond
