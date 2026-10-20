"""カラーパレット外の色がテーマファイルに使われていないかチェックする。"""

import re
from pathlib import Path

PALETTE = {
    "#7a6a64",
    "#002319",
    "#4a4d91",
    "#1c161a",
    "#0f0f0e",
    "#b67eb7",
    "#38600f",
    "#0c040b",
    "#6c1d91",
    "#0c1904",
    "#070606",
    "#0f0514",
    "#fcb346",
    "#272828",
    "#447c03",
    "#274242",
    "#0d00a3",
    "#f411e1",
    "#5f47cc",
    "#d6d595",
    "#9b7dc6",
    "#c4e5ac",
    "#7ea033",
    "#ae47d1",
    "#081a56",
    "#231663",
    "#070001",
    "#4470ff",
    "#e8f7f0",
    "#1761aa",
    "#421949",
    "#3f120e",
    "#031912",
    "#113f56",
    "#0c0000",
    "#b075d8",
    "#a976c1",
    "#63873a",
    "#4f122f",
    "#323233",
    "#dd2a57",
    "#979ac4",
    "#a08e96",
    "#1e2323",
    "#dd949e",
    "#201d33",
    "#f9f2f2",
    "#847f66",
    "#5e2102",
}

# 6桁または8桁(透明度付き)の hex カラーコードを検出
HEX_RE = re.compile(r'"(#[0-9a-fA-F]{6,8})"')

theme_path = Path(__file__).parent / "themes" / "keivax-zen3-theme.json"
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
