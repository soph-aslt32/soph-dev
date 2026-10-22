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


def closest(
    label: str, items: dict[str, str], limit: float, show: int = 6, same_ok: tuple = ()
) -> None:
    """same_ok: 同色にする意図がある組。距離の比較から除外する。"""
    section(label)
    ok = {frozenset(pair) for pair in same_ok}
    pairs = sorted(
        (dist(blend(items[x]), blend(items[y])), x, y)
        for x, y in itertools.combinations(items, 2)
        if frozenset((x, y)) not in ok
    )
    for d, x, y in pairs[:show]:
        flag = "  <-- 近い" if d < limit else ""
        print(f"  {d:5.1f}  {x} ({blend(items[x])}) <-> {y} ({blend(items[y])}){flag}")
    print(f"  最小距離: {pairs[0][0]:.1f} / 閾値 {limit}")
    if same_ok:
        print("  同色にする意図のため除外: " + ", ".join(f"{x}={y}" for x, y in same_ok))


# --- 1. キー構成 -------------------------------------------------------------
section("キー構成（元JSONとの一致）")
if list(alpha) != list(orig):
    fail(f"トップレベルキーが不一致: {list(alpha)} vs {list(orig)}")
for k in ("schema", "name", "type", "semanticHighlighting"):
    if alpha.get(k) != orig.get(k):
        fail(f"{k} が元と異なる")
if list(colors) != list(orig["colors"]):
    fail("colors のキー/順序が不一致")
orig_tc = [(t["name"], t["scope"]) for t in orig["tokenColors"]]
alpha_tc = [(t["name"], t["scope"]) for t in alpha["tokenColors"]]
if alpha_tc[: len(orig_tc)] != orig_tc:
    fail("tokenColors の元の name/scope が不一致（追加は末尾のみ可）")
orig_sem = list(orig["semanticTokenColors"])
if list(alpha["semanticTokenColors"])[: len(orig_sem)] != orig_sem:
    fail("semanticTokenColors の元のキー/順序が不一致（追加は末尾のみ可）")
extra_tc = len(alpha_tc) - len(orig_tc)
extra_sem = len(alpha["semanticTokenColors"]) - len(orig_sem)
if extra_tc or extra_sem:
    print(f"  追加項目: tokenColors +{extra_tc} / semanticTokenColors +{extra_sem}")
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
closest(
    "トークン役割どうしの色の近さ（OKLab x100）",
    ROLES,
    8.0,
    show=8,
    same_ok=(
        ("function", "external lib"),  # 外部由来は斜体で区別する
        ("string/number", "regexp"),
        ("local variable", "parameter"),  # 引数は下線で区別する
        ("comment", "docstring"),
    ),
)

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
closest(
    "ファイル名の色の近さ（Add1/Add6）",
    FILES,
    10.0,
    show=8,
    same_ok=(
        ("added", "renamed"),
        ("added", "staged modified"),
        ("renamed", "staged modified"),
    ),
)

# --- 7. 文字と背景の組 -------------------------------------------------------
PAIRS = [
    ("button", "button.foreground", "button.background"),
    ("button hover", "button.foreground", "button.hoverBackground"),
    ("button secondary", "button.secondaryForeground", "button.secondaryBackground"),
    ("button secondary hover", "button.secondaryForeground", "button.secondaryHoverBackground"),
    ("extensionButton", "extensionButton.foreground", "extensionButton.background"),
    ("extensionButton hover", "extensionButton.foreground", "extensionButton.hoverBackground"),
    ("badge", "badge.foreground", "badge.background"),
    ("activityBarBadge", "activityBarBadge.foreground", "activityBarBadge.background"),
    ("panelTitleBadge", "panelTitleBadge.foreground", "panelTitleBadge.background"),
    ("profileBadge", "profileBadge.foreground", "profileBadge.background"),
    ("extensionBadge.remote", "extensionBadge.remoteForeground", "extensionBadge.remoteBackground"),
    ("activityErrorBadge", "activityErrorBadge.foreground", "activityErrorBadge.background"),
    ("activityWarningBadge", "activityWarningBadge.foreground", "activityWarningBadge.background"),
    ("statusBar debugging", "statusBar.debuggingForeground", "statusBar.debuggingBackground"),
    ("statusBarItem hover", "statusBarItem.hoverForeground", "statusBarItem.hoverBackground"),
    ("statusBarItem active", "statusBarItem.hoverForeground", "statusBarItem.activeBackground"),
    ("statusBarItem remote", "statusBarItem.remoteForeground", "statusBarItem.remoteBackground"),
    ("statusBarItem remote hover", "statusBarItem.remoteHoverForeground", "statusBarItem.remoteHoverBackground"),
    ("statusBarItem error", "statusBarItem.errorForeground", "statusBarItem.errorBackground"),
    ("statusBarItem error hover", "statusBarItem.errorHoverForeground", "statusBarItem.errorHoverBackground"),
    ("statusBarItem warning", "statusBarItem.warningForeground", "statusBarItem.warningBackground"),
    ("statusBarItem warning hover", "statusBarItem.warningHoverForeground", "statusBarItem.warningHoverBackground"),
    ("statusBarItem offline", "statusBarItem.offlineForeground", "statusBarItem.offlineBackground"),
    ("statusBarItem offline hover", "statusBarItem.offlineHoverForeground", "statusBarItem.offlineHoverBackground"),
    ("statusBarItem prominent", "statusBarItem.prominentForeground", "statusBarItem.prominentBackground"),
    ("statusBarItem prominent hover", "statusBarItem.prominentHoverForeground", "statusBarItem.prominentHoverBackground"),
    ("list active selection", "list.activeSelectionForeground", "list.activeSelectionBackground"),
    ("list inactive selection", "list.inactiveSelectionForeground", "list.inactiveSelectionBackground"),
    ("list hover", "list.hoverForeground", "list.hoverBackground"),
    ("list focus", "list.focusForeground", "list.focusBackground"),
    ("menu selection", "menu.selectionForeground", "menu.selectionBackground"),
    ("menubar selection", "menubar.selectionForeground", "menubar.selectionBackground"),
    ("quickInput focus", "quickInputList.focusForeground", "quickInputList.focusBackground"),
    ("suggest selected", "editorSuggestWidget.selectedForeground", "editorSuggestWidget.selectedBackground"),
    ("actionList focus", "editorActionList.focusForeground", "editorActionList.focusBackground"),
    ("peek selection", "peekViewResult.selectionForeground", "peekViewResult.selectionBackground"),
    ("tab active (modern)", "modernEditorTab.activeForeground", "modernEditorTab.activeBackground"),
    ("tab active hover (modern)", "modernEditorTab.activeForeground", "modernEditorTab.activeHoverBackground"),
    ("tab hover (modern)", "modernEditorTab.hoverForeground", "modernEditorTab.hoverBackground"),
    ("tab active (modernTab)", "modernTab.activeForeground", "modernTab.activeBackground"),
    ("tab hover (modernTab)", "modernTab.hoverForeground", "modernTab.hoverBackground"),
    ("tab inactive", "tab.inactiveForeground", "tab.inactiveBackground"),
    ("terminal selection", "terminal.selectionForeground", "terminal.selectionBackground"),
    ("debug exception label", "debugView.exceptionLabelForeground", "debugView.exceptionLabelBackground"),
    ("debug state label", "debugView.stateLabelForeground", "debugView.stateLabelBackground"),
    ("input", "input.foreground", "input.background"),
    ("input placeholder", "input.placeholderForeground", "input.background"),
    ("keybindingLabel", "keybindingLabel.foreground", "keybindingLabel.background"),
    ("scmGraph hover label", "scmGraph.historyItemHoverDefaultLabelForeground", "scmGraph.historyItemHoverDefaultLabelBackground"),
]
section("文字と背景の組のコントラスト（4.5 未満を表示。背景は BG と合成した実効色）")
low_pairs = []
for label, fk, bk in PAIRS:
    if fk not in colors or bk not in colors:
        fail(f"PAIRS のキーが存在しない: {fk} / {bk}")
        continue
    bgc = blend(colors[bk])
    cr = contrast(blend(colors[fk], bgc), bgc)
    if cr < 4.5:
        low_pairs.append((cr, label, colors[fk], colors[bk]))
for cr, label, fv, bv in sorted(low_pairs):
    print(f"  {cr:4.2f}  {label:30s} fg {fv} / bg {bv}")
print(f"  検査 {len(PAIRS)} 組中 4.5 未満: {len(low_pairs)} 組")

# --- 8. ハイライト・選択の上でコードの色が読めるか -----------------------------
HIGHLIGHTS = [
    "editor.selectionBackground", "editor.inactiveSelectionBackground",
    "editor.selectionHighlightBackground", "editor.wordHighlightBackground",
    "editor.wordHighlightStrongBackground", "editor.wordHighlightTextBackground",
    "editor.findMatchBackground", "editor.findMatchHighlightBackground",
    "editor.lineHighlightBackground", "editor.hoverHighlightBackground",
    "editor.rangeHighlightBackground", "editor.symbolHighlightBackground",
    "editor.stackFrameHighlightBackground", "editor.focusedStackFrameHighlightBackground",
    "editor.snippetTabstopHighlightBackground", "editorBracketMatch.background",
    "diffEditor.insertedTextBackground", "diffEditor.removedTextBackground",
]
section("ハイライト・選択の上でのコード色（最も低い役割を表示。3.0 未満は要注意）")
for hk in HIGHLIGHTS:
    bgc = blend(colors[hk])
    worst = min(
        ((contrast(blend(hv, bgc), bgc), name) for name, hv in ROLES.items() if name != "comment"),
        key=lambda t: t[0],
    )
    cm = contrast(ROLES["comment"], bgc)
    flag = "  <-- 要注意" if worst[0] < 3.0 or cm < 2.5 else ""
    print(f"  {hk:50s} 最低 {worst[0]:4.2f} ({worst[1]}) / コメント {cm:4.2f}{flag}")

# --- 9. Git 装飾・診断のファイル名色が選択行・タブの上で読めるか ----------------
DECOR = [
    "gitDecoration.addedResourceForeground", "gitDecoration.modifiedResourceForeground",
    "gitDecoration.deletedResourceForeground", "gitDecoration.untrackedResourceForeground",
    "gitDecoration.ignoredResourceForeground", "gitDecoration.conflictingResourceForeground",
    "gitDecoration.submoduleResourceForeground", "list.errorForeground", "list.warningForeground",
    "sideBar.foreground",
]
DECOR_BGS = [
    "list.activeSelectionBackground", "list.inactiveSelectionBackground", "list.hoverBackground",
    "modernEditorTab.activeBackground", "modernEditorTab.hoverBackground",
]
section("ファイル名の色 × 選択行/タブ背景のコントラスト（3.0 未満を表示）")
low_decor = []
for dk in DECOR:
    for bk in DECOR_BGS:
        bgc = blend(colors[bk])
        cr = contrast(blend(colors[dk], bgc), bgc)
        if cr < 3.0:
            low_decor.append((cr, dk, bk))
for cr, dk, bk in sorted(low_decor):
    print(f"  {cr:4.2f}  {dk:46s} on {bk}")
print(f"  合計 {len(low_decor)} 件")

# --- 10. 色相ファミリー別の使用数（青系の採用率の目安） ---------------------------
def hue_family(h: str) -> str:
    r, g, b, _ = parse(h)
    mx, mn = max(r, g, b), min(r, g, b)
    if mx == mn or (mx - mn) / 255 < 0.12:
        return "無彩色寄り"
    import colorsys

    hh = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)[0] * 360
    if 200 <= hh < 270:
        return "青〜青紫"
    if 270 <= hh < 340:
        return "紫〜マゼンタ"
    if hh >= 340 or hh < 15:
        return "赤〜ピンク"
    if 15 <= hh < 70:
        return "橙〜黄"
    if 70 <= hh < 170:
        return "緑"
    return "青緑"


section("色相ファミリー別の使用数（colors の値。背景 BG・透明を除く）")
from collections import Counter

fam = Counter()
for v in colors.values():
    if v[:7] == BG:
        continue
    fam[hue_family(v)] += 1
total = sum(fam.values())
for name, n in fam.most_common():
    print(f"  {name:10s} {n:4d} ({n / total:5.1%})")

print(f"\n結果: {'問題なし' if problems == 0 else f'NG {problems} 件'}")
sys.exit(1 if problems else 0)
