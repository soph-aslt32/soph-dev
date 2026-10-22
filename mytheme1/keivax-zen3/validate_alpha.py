"""keivax-zen3-alpha-theme.json の検証レポート。

- 元 JSON とのキー構成一致（順序込み）
- 背景の厳密一致 / 枠線の透明
- 文字色のコントラスト（背景に対する実効色）
- 役割ごとの色の近さ（OKLab 距離 x100。小さいほど似ている）

使い方: python validate_alpha.py [alpha.json] [original.json]
"""

from __future__ import annotations

import itertools
import json
import math
import re
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")  # パイプ経由でも日本語・記号を文字化けさせない

ROOT = Path(__file__).parent
ALPHA =Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "themes" / "keivax-zen3-alpha-theme.json"
ORIG = Path(sys.argv[2]) if len(sys.argv) > 2 else ROOT / "themes" / "keivax-zen3-theme.json"

alpha = json.loads(ALPHA.read_text(encoding="utf-8-sig"))
orig = json.loads(ORIG.read_text(encoding="utf-8-sig"))
colors = alpha["colors"]
BG = colors["editor.background"]

problems = 0


def section(title: str) -> None:
    print(f"\n== {title} ==")


def fail(msg: str) -> None:
    global problems
    problems += 1
    print("  NG:", msg)


# --- 色ユーティリティ ---------------------------------------------------------
def parse(hexv: str) -> tuple[int, int, int, float]:
    r, g, b = (int(hexv[i : i + 2], 16) for i in (1, 3, 5))
    al = int(hexv[7:9], 16) / 255 if len(hexv) == 9 else 1.0
    return r, g, b, al


def blend(hexv: str, over: str = BG) -> str:
    r, g, b, al = parse(hexv)
    br, bg_, bb, _ = parse(over)
    mix = [round(c * al + o * (1 - al)) for c, o in ((r, br), (g, bg_), (b, bb))]
    return "#{:02x}{:02x}{:02x}".format(*mix)


def lin(v: float) -> float:
    v /= 255
    return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4


def lum(h: str) -> float:
    r, g, b, _ = parse(h)
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)


def contrast(a: str, b: str) -> float:
    la, lb = sorted((lum(a), lum(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


def oklab(h: str) -> tuple[float, float, float]:
    r, g, b, _ = parse(h)
    r, g, b = lin(r), lin(g), lin(b)
    l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ** (1 / 3)
    m = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ** (1 / 3)
    s = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ** (1 / 3)
    return (
        0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
        1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
        0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
    )


def dist(a: str, b: str) -> float:
    return 100 * math.dist(oklab(a), oklab(b))


def closest(label: str, items: dict[str, str], limit: float, show: int = 6) -> None:
    section(label)
    pairs = sorted(
        (dist(blend(items[x]), blend(items[y])), x, y) for x, y in itertools.combinations(items, 2)
    )
    for d, x, y in pairs[:show]:
        flag = "  <-- 近い" if d < limit else ""
        print(f"  {d:5.1f}  {x} ({blend(items[x])}) <-> {y} ({blend(items[y])}){flag}")
    print(f"  最小距離: {pairs[0][0]:.1f} / 閾値 {limit}")


# --- 1. キー構成 -------------------------------------------------------------
section("キー構成（元JSONとの一致）")
if list(alpha) != list(orig):
    fail(f"トップレベルキーが不一致: {list(alpha)} vs {list(orig)}")
for k in ("schema", "name", "type", "semanticHighlighting"):
    if alpha.get(k) != orig.get(k):
        fail(f"{k} が元と異なる")
if list(colors) != list(orig["colors"]):
    fail("colors のキー/順序が不一致")
if [(t["name"], t["scope"]) for t in alpha["tokenColors"]] != [
    (t["name"], t["scope"]) for t in orig["tokenColors"]
]:
    fail("tokenColors の name/scope が不一致")
if list(alpha["semanticTokenColors"]) != list(orig["semanticTokenColors"]):
    fail("semanticTokenColors のキー/順序が不一致")
print(
    f"  colors={len(colors)} tokenColors={len(alpha['tokenColors'])} "
    f"semantic={len(alpha['semanticTokenColors'])}"
)

# --- 2. 値の形式 -------------------------------------------------------------
section("値の形式")
HEX = re.compile(r"^#[0-9a-f]{6}([0-9a-f]{2})?$")
bad = [(k, v) for k, v in colors.items() if not (isinstance(v, str) and HEX.match(v))]
for k, v in bad:
    fail(f"colors[{k}] = {v!r} は #rrggbb(aa) 小文字ではない")
print("  OK" if not bad else f"  {len(bad)} 件")

# --- 3. 背景の厳密一致 -------------------------------------------------------
section("背景: 不透明の *background* で BG と異なるもの（意図したアクセント以外は NG）")
opaque_non_bg = [
    (k, v)
    for k, v in colors.items()
    if re.search(r"background$", k, re.I) and len(v) == 7 and v != BG
]
for k, v in opaque_non_bg:
    print(f"  {k:55s} {v}")

SECTIONS = [
    "editor.background", "editorGutter.background", "editorPane.background",
    "editorGroup.emptyBackground", "editorGroupHeader.tabsBackground",
    "editorGroupHeader.noTabsBackground", "tab.activeBackground", "tab.inactiveBackground",
    "tab.unfocusedActiveBackground", "tab.unfocusedInactiveBackground", "tab.selectedBackground",
    "modernEditorTab.inactiveBackground", "activityBar.background", "activityBarTop.background",
    "sideBar.background", "sideBarTitle.background", "sideBarSectionHeader.background",
    "statusBar.background", "statusBar.noFolderBackground", "titleBar.activeBackground",
    "titleBar.inactiveBackground", "panel.background", "panelSectionHeader.background",
    "terminal.background", "outputView.background", "breadcrumb.background",
    "welcomePage.background", "minimap.background", "editorOverviewRuler.background",
    "editorWidget.background", "editorSuggestWidget.background", "editorHoverWidget.background",
    "menu.background", "quickInput.background", "notifications.background",
    "peekViewEditor.background", "peekViewResult.background", "input.background",
    "dropdown.background", "commandCenter.background", "editorStickyScroll.background",
    "terminalStickyScroll.background", "panelStickyScroll.background", "sideBarStickyScroll.background",
]
off = [(k, colors[k]) for k in SECTIONS if colors[k] != BG]
for k, v in off:
    fail(f"セクション背景が BG と不一致: {k} = {v}")
print(f"  セクション背景 {len(SECTIONS)} キーを BG({BG}) と照合: " + ("全て一致" if not off else "不一致あり"))

# --- 4. 枠線 -----------------------------------------------------------------
section("枠線: 透明でない *border / outline*（機能的な強調として許容するか要レビュー）")
visible_borders = [
    (k, v)
    for k, v in colors.items()
    if re.search(r"(border|outline)$", k, re.I) and not v.endswith("00")
]
for k, v in visible_borders:
    print(f"  {k:55s} {v}")
print(f"  合計 {len(visible_borders)} 件")

# --- 5. コントラスト ---------------------------------------------------------
section("文字色: BG 上の実効コントラストが 3.0 未満の *foreground")
low = []
for k, v in colors.items():
    if re.search(r"foreground\d?$", k, re.I) and "opacity" not in k.lower():
        cr = contrast(blend(v), BG)
        if cr < 3.0:
            low.append((cr, k, v))
for cr, k, v in sorted(low):
    print(f"  {cr:4.2f}  {k:55s} {v}")
print(f"  合計 {len(low)} 件")

section("トークン色のコントラスト（BG 上）")
sem = alpha["semanticTokenColors"]


def sem_fg(key: str) -> str:
    v = sem[key]
    return v if isinstance(v, str) else v["foreground"]


doc = next(t for t in alpha["tokenColors"] if t["scope"][0].startswith("string.quoted.docstring"))
ROLES = {
    "class/type": sem_fg("class"),
    "function": sem_fg("function"),
    "parameter": sem_fg("parameter"),
    "local variable": sem_fg("variable"),
    "global/constant": sem_fg("variable.readonly"),
    "external lib": sem_fg("function.defaultLibrary"),
    "keyword": sem_fg("keyword"),
    "string/number": sem_fg("string"),
    "regexp": sem_fg("regexp"),
    "comment": sem_fg("comment"),
    "docstring": doc["settings"]["foreground"],
    "operator": sem_fg("operator"),
}
ROLES = {name: blend(hv) for name, hv in ROLES.items()}  # 透明度つきは BG と合成した実効色
for name, hv in ROLES.items():
    print(f"  {name:16s} {hv}  {contrast(hv, BG):5.2f}")

# --- 6. 色の近さ -------------------------------------------------------------
closest("トークン役割どうしの色の近さ（OKLab x100）", ROLES, 8.0, show=8)

MARKERS = {
    "git added": colors["editorGutter.addedBackground"],
    "git modified": colors["editorGutter.modifiedBackground"],
    "git deleted": colors["editorGutter.deletedBackground"],
    "error": colors["editorError.foreground"],
    "warning": colors["editorWarning.foreground"],
    "info": colors["editorInfo.foreground"],
    "find match": colors["editorOverviewRuler.findMatchForeground"],
    "selection hl": colors["editorOverviewRuler.selectionHighlightForeground"],
    "word hl (read)": colors["editorOverviewRuler.wordHighlightForeground"],
    "word hl (write)": colors["editorOverviewRuler.wordHighlightStrongForeground"],
    "bracket match": colors["editorOverviewRuler.bracketMatchForeground"],
}
closest("ルーラー/ガター/ハイライトの色の近さ（Add6）", MARKERS, 10.0, show=8)

FILES = {
    "modified": colors["gitDecoration.modifiedResourceForeground"],
    "added": colors["gitDecoration.addedResourceForeground"],
    "untracked": colors["gitDecoration.untrackedResourceForeground"],
    "ignored": colors["gitDecoration.ignoredResourceForeground"],
    "deleted": colors["gitDecoration.deletedResourceForeground"],
    "renamed": colors["gitDecoration.renamedResourceForeground"],
    "conflicting": colors["gitDecoration.conflictingResourceForeground"],
    "staged modified": colors["gitDecoration.stageModifiedResourceForeground"],
    "error file": colors["list.errorForeground"],
    "warning file": colors["list.warningForeground"],
    "default text": colors["sideBar.foreground"],
}
closest("ファイル名の色の近さ（Add1/Add6）", FILES, 10.0, show=8)

print(f"\n結果: {'問題なし' if problems == 0 else f'NG {problems} 件'}")
sys.exit(1 if problems else 0)
