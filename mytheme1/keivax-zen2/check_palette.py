"""カラーパレット外の色がテーマファイルに使われていないかチェックする。"""

import re
from pathlib import Path

PALETTE = {
    "#dae5e4", "#5e4f3b", "#3a3738", "#b50191", "#c619b2",
    "#64af77", "#2d560b", "#647f6b", "#91825e", "#e5e3d7",
    "#a38a96", "#ba9593", "#8c6089", "#3d6303", "#3630e5",
    "#07040f", "#0a0411", "#efd39b", "#766e7a", "#9ba9c6",
    "#dd06dd", "#56f725", "#13a37c", "#ef52f2", "#ac17d6",
    "#3b76bf", "#f15dfc", "#aff92f", "#4ecace", "#d360e5",
    "#7fa01b", "#0ccc82", "#f4f116", "#a4f96b", "#39d3c4",
    "#e21bc1", "#e8e85c", "#31ea91", "#bc0db9", "#c6117b",
}

# 6桁または8桁(透明度付き)の hex カラーコードを検出
HEX_RE = re.compile(r'"(#[0-9a-fA-F]{6,8})"')

theme_path = Path(__file__).parent / "themes" / "keivax-zen2-theme.json"
lines = theme_path.read_text(encoding="utf-8").splitlines()

# { ベース色: [(行番号, 出現形式), ...] }
violations: dict[str, list[tuple[int, str]]] = {}

for lineno, line in enumerate(lines, start=1):
    for m in HEX_RE.finditer(line):
        raw = m.group(1).lower()
        base = raw[:7]  # '#' + 6桁 (透明度の2桁を除く)
        if base not in PALETTE:
            violations.setdefault(base, []).append((lineno, raw))

if not violations:
    print("✓ 全ての色がカラーパレット内です。")
else:
    print(f"⚠ パレット外の色が {len(violations)} 種類見つかりました:\n")
    for base in sorted(violations):
        entries = violations[base]
        forms = sorted({form for _, form in entries})
        lines_used = sorted({ln for ln, _ in entries})
        print(f"  {base}")
        print(f"    使用形式 : {', '.join(forms)}")
        print(f"    行番号   : {lines_used}\n")
