"""keivax-zen3-theme.json のキー構成を引き継ぎ、NewColorPalette から色を割り当て直して
keivax-zen3-alpha-theme.json（と背景違いの比較版 VARIANTS）を生成する。

- 色は README の NewColorPalette のみ（透明度の付加は可）。
- colors は「キー名  色の式」の表(COLORS_SPEC)で全キーを明示的に割り当てる。
  元 JSON にあって表に無いキー、表にあって元 JSON に無いキーはエラーにする。
- tokenColors は scope[0] で、semanticTokenColors は元のキーで割り当てる。
"""

from __future__ import annotations

import json
import sys
from dataclasses import dataclass, fields, replace
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")  # パイプ経由でも日本語・記号を文字化けさせない

ROOT = Path(__file__).parent
SRC = ROOT / "themes" / "keivax-zen3-theme.json"
# ---------------------------------------------------------------------------
# 役割 → パレット色
# ---------------------------------------------------------------------------
class Tone(str):
    """パレット色に透明度を掛けた色。a() で更に透明度を重ねられる。"""

    base: str
    alpha: int

    def __new__(cls, base: str, alpha: int) -> "Tone":
        obj = super().__new__(cls, f"{base}{alpha:02x}")
        obj.base, obj.alpha = base, alpha
        return obj


BG = "#1e2323"  # 全セクション共通の背景
FG = "#e8f7f0"  # 通常テキスト
FG2 = "#979ac4"  # 二次テキスト・アイコン・キーワード
DIM = Tone(FG2, 0xB0)  # 寒色の静かな文字・線・コメント・行番号（FG2 の透明度違い）
MUTED = Tone(FG2, 0xD8)  # DIM より明るい寒色（非アクティブのアイコン・ラベル）
CHROME = FG2  # UI の文字（エクスプローラー・サイドバー・ステータスバー・非アクティブタブなど）．明るくしたい場合は FG に差し替える
DOC = "#a08e96"  # ターミナルの ANSI 白にだけ使う暖灰
GRAY = "#323233"  # 中立の暗灰

BLUE = "#4470ff"  # 鮮やかな青: クラス/型・アクセント
BLUE_M = "#1761aa"  # 中間の青: 選択背景・ボタン
INDIGO = "#4a4d91"  # ホバー・淡い強調背景
VIOLET_B = "#5f47cc"  # 青紫: デバッグ・マージ
LAV = "#9b7dc6"  # 藤色: 検索一致・各種マッチ強調
EXTERN = "#b075d8"  # 明るい紫: 外部ライブラリ・ビルトイン・モジュール
PURP = "#ae47d1"  # 紫: Git の削除・差分（トークンには使わない）
PLUM = "#6c1d91"  # 中紫: 選択・ホバーに色味を足す（比較用）
MAG = "#f411e1"  # マゼンタ: 注意色（グローバル/定数など希少で重要なもの）・変数ハイライト
ROSE = "#dd949e"  # バラ色: 関数・Git の変更・エラー文字
GREEN = "#7ea033"  # オリーブ緑: 文字列・数値・正規表現・None/True/False・未追跡
PALEGREEN = "#c4e5ac"  # 淡緑: Git の追加・ステージ済み・書込ハイライトの縁
KHAKI = "#d6d595"  # カーキ: 変数（ローカル・引数・プロパティ）

# 背景用の濃い色。明るさが背景並みなので，どのトークン色の上でもコントラストを保てる（彩度で目立たせる）
DEEP_BLUE = "#0d00a3"  # 濃い青: 選択・ホバー・アクティブタブ
DEEP_WINE = "#4f122f"  # 暗いワイン色: 単語ハイライト（読取・書込に共通の塗り．区別は縁取りだけで行う）
DEEP_GREEN = "#002319"  # 暗い緑: 差分の追加
DEEP_VIOLET = "#231663"  # 暗い青紫: 検索一致
DEEP_PURPLE = "#421949"  # 暗い紫: 差分の削除
NIGHT = "#0f0514"  # 背景より暗い青紫: 沈み込み型の選択・ホバー（比較用）
NAVY = "#081a56"  # 濃紺: 選択（比較用）
TEAL = "#113f56"  # 暗い青緑がかった青: ホバー（比較用）

ERR = "#dd2a57"  # エラー専有
WARN = "#fcb346"  # 警告専有
SHADOW = "#070606"  # 影

def a(color: str, alpha: int) -> str:
    if isinstance(color, Tone):  # 透明度つきの色には透明度を掛け合わせる
        return f"{color.base}{round(color.alpha * alpha / 255):02x}"
    return f"{color}{alpha:02x}"


@dataclass(frozen=True)
class Roles:
    """コードのトークン色の役割。色=種類，斜体=外部由来，で表すので外部ライブラリ専用の色は持たない。"""

    keyword: str  # キーワード・self・デコレータ・HTML タグ
    operator: str  # 演算子・句読点
    variable: str  # 変数（ローカル・引数・プロパティ）・属性・モジュール
    function: str  # 関数・メソッド・マクロ
    type: str  # クラス・型・列挙型メンバー
    value: str  # 文字列・数値・正規表現・None/True/False
    comment: str  # コメント・Docstring
    accent: str  # 注意色（グローバル/定数など希少で重要なもの）


ROLES_MAIN = Roles(
    keyword=BLUE, operator=MUTED, variable=FG2, function=ROSE,
    type=PURP, value=GREEN, comment=DIM, accent=MAG,
)  # fmt: skip
@dataclass(frozen=True)
class Surfaces:
    """選択・ホバーなど「面」の色の役割。None は透明。強さの段階は hover < mark < sel_sub < sel_focus < sel < sel_strong。"""

    sel: str  # 選択（エディタ・リスト・メニュー・サジェスト・ターミナル）のアクティブ時
    sel_sub: str  # 非アクティブな選択・括弧の一致・スタックフレーム
    sel_focus: str  # リストのフォーカス行（選択はされていない）
    sel_strong: str  # アクティブなタブ・フォーカス中のスタックフレーム
    mark: str  # 選択範囲と同じ文字列の強調・スニペットのタブ位置
    hover: str  # リストのホバー・シンボルの強調
    tab_hover: str  # タブのホバー
    tab_active_hover: str  # アクティブなタブのホバー
    hover_editor: str  # エディタ上でホバー表示が出ている語の強調
    find: str  # 検索一致の塗り（他の一致はこの色の透明度違い）
    line: str  # カーソルがある行の背景
    toolbar_hover: str  # ツールバーのボタン（アクティビティバー・タイトルバー・エディタ右上など）のホバー
    menubar_hover: str | None  # タイトルバーのメニュー（ファイル・編集…）のホバー
    command_active: str | None  # コマンドセンターのホバー
    status_hover: str | None  # ステータスバーの項目のホバー
    status_compact_hover: str | None  # ステータスバーの小さい項目のホバー
    title_fg: str  # タイトルバー・メニューの普段の文字
    title_fg_inactive: str  # ウィンドウが非アクティブなときのタイトルバーの文字


SURFACES_MAIN = Surfaces(
    sel=a(DEEP_BLUE, 0xC0), sel_sub=a(DEEP_BLUE, 0x80), sel_focus=a(DEEP_BLUE, 0xA0), sel_strong=a(DEEP_BLUE, 0xE0),
    mark=a(DEEP_BLUE, 0x70), hover=a(DEEP_BLUE, 0x60), tab_hover=a(DEEP_BLUE, 0x80), tab_active_hover=DEEP_BLUE,
    hover_editor=a(DEEP_BLUE, 0x60), find=DEEP_VIOLET, line=a(INDIGO, 0x40),
    toolbar_hover=a(INDIGO, 0x50), menubar_hover=a(DEEP_BLUE, 0x90), command_active=a(BLUE_M, 0x30),
    status_hover=a(BLUE_M, 0x50), status_compact_hover=a(BLUE_M, 0x60),
    title_fg=FG, title_fg_inactive=FG2,
)  # fmt: skip
# --- 比較用（Prompt zen3 16: 選択・ホバーの純青が強い）。3案とも上のバーは塗りをなくし，文字の明暗で示す ---
SURFACES_QUIET_BARS = replace(
    SURFACES_MAIN,
    menubar_hover=None, command_active=None, status_hover=None, status_compact_hover=None,
    title_fg=CHROME, title_fg_inactive=DIM,
)  # fmt: skip
# Soft1: 彩度を落とした青紫（背景と同じ色相）で選択を示す．ホバーは INDIGO を薄く重ねて明るさで示す．
# 検索一致の塗りが選択と被るので DEEP_PURPLE に移す
SURFACES_SOFT1 = replace(
    SURFACES_QUIET_BARS,
    sel=a(DEEP_VIOLET, 0xE0), sel_sub=a(DEEP_VIOLET, 0xB2), sel_focus=a(DEEP_VIOLET, 0xC7), sel_strong=DEEP_VIOLET,
    mark=a(DEEP_VIOLET, 0xA0), hover=a(INDIGO, 0x29), tab_hover=a(INDIGO, 0x29), tab_active_hover=DEEP_VIOLET,
    hover_editor=a(INDIGO, 0x24), find=DEEP_PURPLE, toolbar_hover=a(INDIGO, 0x20),
)  # fmt: skip
# Soft2: INDIGO の透明度だけで示す（明るさ重視）．選択・ホバー・現在行が同じ系統になるので，現在行を弱める
SURFACES_SOFT2 = replace(
    SURFACES_QUIET_BARS,
    sel=a(INDIGO, 0x3C), sel_sub=a(INDIGO, 0x2A), sel_focus=a(INDIGO, 0x34), sel_strong=a(INDIGO, 0x3C),
    mark=a(INDIGO, 0x26), hover=a(INDIGO, 0x1C), tab_hover=a(INDIGO, 0x1C), tab_active_hover=a(INDIGO, 0x44),
    hover_editor=a(INDIGO, 0x24), line=a(INDIGO, 0x1C), toolbar_hover=a(INDIGO, 0x20),
)  # fmt: skip
# Soft2b: Soft2 の基底を INDIGO → VIOLET_B（色味を少し足す）にし，同じ読みやすさ（コード色・ファイル名 3.0 以上）で
# 選択を ΔE 5.4 → 6.8 に強める．ホバーは 2.5 → 3.7 に上げ，各段の差を約1ずつ取る．現在行は Soft2 のまま
SURFACES_SOFT2B = replace(
    SURFACES_SOFT2,
    sel=a(VIOLET_B, 0x35), sel_sub=a(VIOLET_B, 0x26), sel_focus=a(VIOLET_B, 0x30), sel_strong=a(VIOLET_B, 0x35),
    mark=a(VIOLET_B, 0x22), hover=a(VIOLET_B, 0x1C), tab_hover=a(VIOLET_B, 0x1C), tab_active_hover=a(VIOLET_B, 0x35),
    hover_editor=a(VIOLET_B, 0x19), toolbar_hover=a(VIOLET_B, 0x20),
)  # fmt: skip
# Soft2c: Soft2b の基底を VIOLET_B → PLUM（#6c1d91）にして色味をさらに足す．選択 ΔE 6.8 → 8.8，色相は 288 → 307（紫寄り）．
# 各段は ΔE が ホバー3.9 / 非アクティブ5.5 / フォーカス7.3 / アクティブ8.8 になる透明度
SURFACES_SOFT2C = replace(
    SURFACES_SOFT2B,
    sel=a(PLUM, 0x5F), sel_sub=a(PLUM, 0x3B), sel_focus=a(PLUM, 0x4F), sel_strong=a(PLUM, 0x5F),
    mark=a(PLUM, 0x35), hover=a(PLUM, 0x2A), tab_hover=a(PLUM, 0x2A), tab_active_hover=a(PLUM, 0x5F),
    hover_editor=a(PLUM, 0x22), toolbar_hover=a(PLUM, 0x2A),
)  # fmt: skip
# Soft2d: 基底を MAG（マゼンタ）の薄い重ねにする．選択 ΔE 8.8，色相は 317（赤紫寄り）．Soft2c と同じ階段
SURFACES_SOFT2D = replace(
    SURFACES_SOFT2B,
    sel=a(MAG, 0x29), sel_sub=a(MAG, 0x19), sel_focus=a(MAG, 0x22), sel_strong=a(MAG, 0x29),
    mark=a(MAG, 0x17), hover=a(MAG, 0x12), tab_hover=a(MAG, 0x12), tab_active_hover=a(MAG, 0x29),
    hover_editor=a(MAG, 0x0E), toolbar_hover=a(MAG, 0x12),
)  # fmt: skip
# --- Prompt zen3 20: 「落ち着いた青」「青紫・藍」のグループの色を選択・ホバーに使う比較 ---
# Soft2e: 選択は Soft2b（VIOLET_B）のまま，ホバーだけ TEAL（青緑がかった青）にして，選択↔ホバーの間を ΔE 2.7 → 5.0 に広げる
SURFACES_SOFT2E = replace(
    SURFACES_SOFT2B,
    hover=a(TEAL, 0x57), tab_hover=a(TEAL, 0x57), hover_editor=a(TEAL, 0x46), toolbar_hover=a(TEAL, 0x57),
)  # fmt: skip
# Soft2f: 選択を NAVY（濃紺．ΔE 7.5，明るさの差は +0.6 と小さい），ホバーを INDIGO の薄い重ね（明るさで示す）にする
SURFACES_SOFT2F = replace(
    SURFACES_SOFT2B,
    sel=NAVY, sel_sub=a(NAVY, 0x9D), sel_focus=a(NAVY, 0xD0), sel_strong=NAVY,
    mark=a(NAVY, 0x96), hover=a(INDIGO, 0x2D), tab_hover=a(INDIGO, 0x2D), tab_active_hover=NAVY,
    hover_editor=a(INDIGO, 0x23), toolbar_hover=a(INDIGO, 0x2D),
)  # fmt: skip
# Soft2g: アクティブなタブだけ DEEP_VIOLET（ΔE 9.2）にする．リスト・エディタの選択は Soft2b のまま
SURFACES_SOFT2G = replace(SURFACES_SOFT2B, sel_strong=DEEP_VIOLET, tab_active_hover=DEEP_VIOLET)
# Soft3: 背景より暗い NIGHT を重ねて「沈み込み」で示す（ほぼ無彩色．文字のコントラストは上がる）
SURFACES_SOFT3 = replace(
    SURFACES_QUIET_BARS,
    sel=a(NIGHT, 0xD9), sel_sub=a(NIGHT, 0xA6), sel_focus=a(NIGHT, 0xC0), sel_strong=a(NIGHT, 0xE6),
    mark=a(NIGHT, 0x99), hover=a(NIGHT, 0x66), tab_hover=a(NIGHT, 0x66), tab_active_hover=NIGHT,
    hover_editor=a(NIGHT, 0x54), toolbar_hover=a(NIGHT, 0x4C),
)  # fmt: skip
# 出力ファイル -> (背景色, 役割の色, 面の色)。見比べたいときは dataclasses.replace(ROLES_MAIN, ...) /
# dataclasses.replace(SURFACES_MAIN, ...) でエントリを足す
# （package.json にも登録する．決まったら採用案を ROLES_MAIN / SURFACES_MAIN にして比較用を削除する）。
VARIANTS = {
    ROOT / "themes" / "keivax-zen3-alpha-theme.json": ("#201d33", ROLES_MAIN, SURFACES_MAIN),
    ROOT / "themes" / "keivax-zen3-soft1-theme.json": ("#201d33", ROLES_MAIN, SURFACES_SOFT1),
    ROOT / "themes" / "keivax-zen3-soft2-theme.json": ("#201d33", ROLES_MAIN, SURFACES_SOFT2),
    ROOT / "themes" / "keivax-zen3-soft2b-theme.json": ("#201d33", ROLES_MAIN, SURFACES_SOFT2B),
    ROOT / "themes" / "keivax-zen3-soft2c-theme.json": ("#201d33", ROLES_MAIN, SURFACES_SOFT2C),
    ROOT / "themes" / "keivax-zen3-soft2d-theme.json": ("#201d33", ROLES_MAIN, SURFACES_SOFT2D),
    ROOT / "themes" / "keivax-zen3-soft2e-theme.json": ("#201d33", ROLES_MAIN, SURFACES_SOFT2E),
    ROOT / "themes" / "keivax-zen3-soft2f-theme.json": ("#201d33", ROLES_MAIN, SURFACES_SOFT2F),
    ROOT / "themes" / "keivax-zen3-soft2g-theme.json": ("#201d33", ROLES_MAIN, SURFACES_SOFT2G),
    ROOT / "themes" / "keivax-zen3-soft3-theme.json": ("#201d33", ROLES_MAIN, SURFACES_SOFT3),
}


def make_namespace(bg: str, roles: Roles, surfaces: Surfaces) -> dict[str, object]:
    """割り当て表の式を評価する名前空間。BG・T と R_*（役割の色）・S_*（面の色）は variant ごとに差し替える。"""
    ns: dict[str, object] = {
        k: v for k, v in globals().items() if k.isupper() and isinstance(v, str)
    }
    ns.update({"a": a, "BG": bg, "T": bg + "00"})
    ns.update({f"R_{f.name.upper()}": getattr(roles, f.name) for f in fields(roles)})
    for f in fields(surfaces):
        value = getattr(surfaces, f.name)
        ns[f"S_{f.name.upper()}"] = bg + "00" if value is None else value
    return ns

BRACKETS = [BLUE, GREEN, MAG, KHAKI, FG2, ROSE]

# ---------------------------------------------------------------------------
# colors: キー  色の式
# ---------------------------------------------------------------------------
COLORS_SPEC = """
# --- 基本 ---
foreground                      FG
descriptionForeground           CHROME
disabledForeground              DIM
errorForeground                 ROSE
focusBorder                     BLUE
selection.background            S_SEL
icon.foreground                 CHROME
progressBar.background          BLUE
textBlockQuote.background       a(INDIGO, 0x30)
textBlockQuote.border           INDIGO
textCodeBlock.background        BG
textLink.foreground             FG2
textLink.activeForeground       FG
textPreformat.foreground        GREEN
textPreformat.background        BG
textPreformat.border            T
textSeparator.foreground        a(DIM, 0x70)

# --- エディタ本体 ---
editor.background                       BG
editor.foreground                       FG
editor.lineHighlightBackground          S_LINE
editor.lineHighlightBorder              T
editor.selectionBackground              S_SEL
editor.selectionForeground              FG
editor.inactiveSelectionBackground      S_SEL_SUB
editor.selectionHighlightBackground     S_MARK
editor.selectionHighlightBorder         a(FG, 0x60)
editor.wordHighlightBackground          DEEP_WINE
editor.wordHighlightBorder              MAG
editor.wordHighlightStrongBackground    DEEP_WINE
editor.wordHighlightStrongBorder        PALEGREEN
editor.wordHighlightTextBackground      a(DEEP_WINE, 0xb0)
editor.wordHighlightTextBorder          a(MAG, 0x70)
editor.findMatchBackground              S_FIND
editor.findMatchBorder                  LAV
editor.findMatchHighlightBackground     a(S_FIND, 0xc0)
editor.findMatchHighlightBorder         T
editor.findRangeHighlightBackground     a(INDIGO, 0x30)
editor.findRangeHighlightBorder         T
editor.hoverHighlightBackground         S_HOVER_EDITOR
editor.rangeHighlightBackground         a(INDIGO, 0x30)
editor.rangeHighlightBorder             T
editor.symbolHighlightBackground        S_HOVER
editor.symbolHighlightBorder            T
editor.inlineValuesBackground           a(BG, 0xcc)
editor.inlineValuesForeground           DIM
editor.linkedEditingBackground          a(PURP, 0x30)
editor.foldBackground                   a(INDIGO, 0x30)
editor.foldPlaceholderForeground        DIM
editor.placeholder.foreground           DIM
editor.snippetTabstopHighlightBackground        S_MARK
editor.snippetTabstopHighlightBorder            a(FG2, 0x60)
editor.snippetFinalTabstopHighlightBackground   a(LAV, 0x30)
editor.snippetFinalTabstopHighlightBorder       LAV
editor.stackFrameHighlightBackground            S_SEL_SUB
editor.focusedStackFrameHighlightBackground     S_SEL_STRONG
editor.compositionBorder                BLUE

# --- カーソル ---
editorCursor.foreground                     FG2
editorCursor.background                     BG
editorMultiCursor.primary.foreground        FG2
editorMultiCursor.primary.background        BG
editorMultiCursor.secondary.foreground      LAV
editorMultiCursor.secondary.background      BG

# --- 行番号・インデント ---
editorLineNumber.foreground             DIM
editorLineNumber.activeForeground       FG
editorLineNumber.dimmedForeground       a(DIM, 0x80)
editorIndentGuide.background1           a(DIM, 0x40)
editorIndentGuide.background2           a(DIM, 0x30)
editorIndentGuide.background3           a(DIM, 0x30)
editorIndentGuide.background4           a(DIM, 0x30)
editorIndentGuide.background5           a(DIM, 0x30)
editorIndentGuide.background6           a(DIM, 0x30)
editorIndentGuide.activeBackground1     DIM
editorIndentGuide.activeBackground2     a(DIM, 0xb0)
editorIndentGuide.activeBackground3     a(DIM, 0xb0)
editorIndentGuide.activeBackground4     a(DIM, 0xb0)
editorIndentGuide.activeBackground5     a(DIM, 0xb0)
editorIndentGuide.activeBackground6     a(DIM, 0xb0)

# --- 括弧 (1〜6 は BRACKETS から生成) ---
editorBracketMatch.background                       S_SEL_SUB
editorBracketMatch.border                           FG2
editorBracketHighlight.unexpectedBracket.foreground ERR

# --- ガター (追加=緑 / 変更=青 / 削除=紫) ---
editorGutter.background                     BG
editorGutter.addedBackground                GREEN
editorGutter.modifiedBackground             BLUE
editorGutter.deletedBackground              PURP
editorGutter.foldingControlForeground       DIM
editorGutter.addedSecondaryBackground       a(GREEN, 0x80)
editorGutter.deletedSecondaryBackground     a(PURP, 0x80)
editorGutter.modifiedSecondaryBackground    a(BLUE, 0x80)

# --- 診断 (エラー=赤 / 警告=黄 / 情報=中立) ---
editorError.foreground          ERR
editorError.border              T
editorError.background          a(ERR, 0x10)
editorWarning.foreground        WARN
editorWarning.border            T
editorWarning.background        a(WARN, 0x10)
editorInfo.foreground           FG2
editorInfo.border               T
editorInfo.background           a(FG2, 0x10)
editorHint.foreground           MUTED
editorHint.border               T
editorUnnecessaryCode.opacity   a(FG, 0x70)
editorUnnecessaryCode.border    T
editorUnicodeHighlight.background   a(WARN, 0x20)
editorUnicodeHighlight.border       WARN

# --- オーバービューライラー ---
editorOverviewRuler.background                      BG
editorOverviewRuler.border                          T
editorOverviewRuler.addedForeground                 GREEN
editorOverviewRuler.modifiedForeground              BLUE
editorOverviewRuler.deletedForeground               PURP
editorOverviewRuler.errorForeground                 ERR
editorOverviewRuler.warningForeground               WARN
editorOverviewRuler.infoForeground                  FG2
editorOverviewRuler.findMatchForeground             LAV
editorOverviewRuler.selectionHighlightForeground    a(FG, 0xa0)
editorOverviewRuler.wordHighlightForeground         MAG
editorOverviewRuler.wordHighlightStrongForeground   PALEGREEN
editorOverviewRuler.wordHighlightTextForeground     a(MAG, 0xb0)
editorOverviewRuler.bracketMatchForeground          T

# --- ウィジェット (サジェスト・ホバー等。背景は BG、影のみで分離) ---
editorSuggestWidget.background                  BG
editorSuggestWidget.border                      T
editorSuggestWidget.foreground                  FG
editorSuggestWidget.highlightForeground         LAV
editorSuggestWidget.focusHighlightForeground    LAV
editorSuggestWidget.selectedBackground          S_SEL
editorSuggestWidget.selectedForeground          FG
editorSuggestWidget.selectedIconForeground      FG2
editorSuggestWidgetStatus.foreground            DIM
editorActionList.background             BG
editorActionList.foreground             FG
editorActionList.focusBackground        S_SEL
editorActionList.focusForeground        FG
editorHoverWidget.background            BG
editorHoverWidget.border                T
editorHoverWidget.foreground            FG
editorHoverWidget.highlightForeground   LAV
editorHoverWidget.statusBarBackground   BG
editorWidget.background                 BG
editorWidget.border                     T
editorWidget.foreground                 FG
editorWidget.resizeBorder               BLUE
widget.border                           T
widget.shadow                           a(SHADOW, 0xc0)
editorGhostText.foreground              DIM
editorGhostText.background              T
editorGhostText.border                  T
editorCodeLens.foreground               DIM
editorInlayHint.background              T
editorInlayHint.foreground              DIM
editorInlayHint.parameterBackground     T
editorInlayHint.parameterForeground     MUTED
editorInlayHint.typeBackground          T
editorInlayHint.typeForeground          DIM
editorLightBulb.foreground              WARN
editorLightBulbAutoFix.foreground       GREEN
editorLightBulbAi.foreground            LAV
editorWhitespace.foreground             a(DIM, 0x40)
editorRuler.foreground                  a(DIM, 0x50)
editorLink.activeForeground             FG2
editorStickyScroll.background           BG
editorStickyScrollHover.background      a(INDIGO, 0x30)
editorStickyScroll.border               T
editorStickyScroll.shadow               a(SHADOW, 0x80)
editorStickyScrollGutter.background     BG

# --- エディタグループ・タブ ---
editorPane.background                   BG
editorGroup.border                      T
editorGroup.dropBackground              a(BLUE_M, 0x30)
editorGroup.emptyBackground             BG
editorGroup.focusedEmptyBorder          T
editorGroupHeader.border                T
editorGroupHeader.tabsBackground        BG
editorGroupHeader.tabsBorder            T
editorGroupHeader.noTabsBackground      BG
tab.border                              T
tab.activeBackground                    BG
tab.activeForeground                    FG
tab.activeBorder                        T
tab.activeBorderTop                     BLUE
tab.activeModifiedBorder                PALEGREEN
tab.inactiveBackground                  BG
tab.inactiveForeground                  CHROME
tab.inactiveModifiedBorder              a(PALEGREEN, 0x70)
tab.hoverBackground                     S_TAB_HOVER
tab.hoverForeground                     FG
tab.hoverBorder                         T
tab.unfocusedActiveBackground           BG
tab.unfocusedActiveForeground           FG2
tab.unfocusedActiveBorder               T
tab.unfocusedActiveBorderTop            a(BLUE, 0x60)
tab.unfocusedActiveModifiedBorder       a(PALEGREEN, 0x50)
tab.unfocusedInactiveBackground         BG
tab.unfocusedInactiveForeground         FG2
tab.unfocusedInactiveModifiedBorder     a(PALEGREEN, 0x30)
tab.unfocusedHoverBackground            a(INDIGO, 0x30)
tab.unfocusedHoverForeground            FG2
tab.unfocusedHoverBorder                T
tab.selectedBackground                  BG
tab.selectedForeground                  FG
tab.selectedBorderTop                   BLUE
tab.lastPinnedBorder                    T
tab.dragAndDropBorder                   BLUE
modernTab.activeBackground              S_SEL_STRONG
modernTab.activeForeground              FG
modernTab.hoverBackground               S_TAB_HOVER
modernTab.hoverForeground               FG
modernEditorTab.activeBackground        S_SEL_STRONG
modernEditorTab.activeForeground        FG
modernEditorTab.inactiveBackground      BG
modernEditorTab.hoverBackground         S_TAB_HOVER
modernEditorTab.hoverForeground         FG
modernEditorTab.activeHoverBackground   S_TAB_ACTIVE_HOVER

# --- アクティビティバー ---
activityBar.background              BG
activityBar.foreground              FG
activityBar.inactiveForeground      FG2
activityBar.border                  T
activityBar.activeBorder            BLUE
activityBar.activeFocusBorder       BLUE
activityBar.activeBackground        T
activityBar.dropBorder              BLUE
activityBarBadge.background         BLUE_M
activityBarBadge.foreground         FG
activityBarTop.background           BG
activityBarTop.foreground           FG
activityBarTop.inactiveForeground   FG2
activityBarTop.activeBorder         BLUE
activityBarTop.activeBackground     T
activityBarTop.dropBorder           BLUE
activityErrorBadge.background       ERR
activityErrorBadge.foreground       FG
activityWarningBadge.background     WARN
activityWarningBadge.foreground     BG
actionBar.toggledBackground         a(BLUE_M, 0x60)

# --- サイドバー ---
sideBar.background                  BG
sideBar.foreground                  CHROME
sideBar.border                    T
sideBar.dropBackground              a(BLUE_M, 0x30)
sideBarTitle.foreground             FG
sideBarTitle.background             BG
sideBarTitle.border                 T
sideBarSectionHeader.background     BG
sideBarSectionHeader.foreground     CHROME
sideBarSectionHeader.border         T
sideBarActivityBarTop.border        T
sideBarStickyScroll.background      BG
sideBarStickyScroll.border          T
sideBarStickyScroll.shadow          a(SHADOW, 0x80)

# --- ステータスバー ---
statusBar.background                BG
statusBar.foreground                CHROME
statusBar.border                    T
statusBar.focusBorder               BLUE
statusBar.debuggingBackground       VIOLET_B
statusBar.debuggingForeground       FG
statusBar.debuggingBorder           T
statusBar.noFolderBackground        BG
statusBar.noFolderForeground        CHROME
statusBar.noFolderBorder            T
statusBarItem.hoverBackground       S_STATUS_HOVER
statusBarItem.hoverForeground       FG
statusBarItem.activeBackground      a(BLUE_M, 0x80)
statusBarItem.focusBorder           BLUE
statusBarItem.compactHoverBackground    S_STATUS_COMPACT_HOVER
statusBarItem.remoteBackground      BLUE_M
statusBarItem.remoteForeground      FG
statusBarItem.remoteHoverBackground VIOLET_B
statusBarItem.remoteHoverForeground FG
statusBarItem.errorBackground       ERR
statusBarItem.errorForeground       FG
statusBarItem.errorHoverBackground  ROSE
statusBarItem.errorHoverForeground  BG
statusBarItem.warningBackground     WARN
statusBarItem.warningForeground     BG
statusBarItem.warningHoverBackground    KHAKI
statusBarItem.warningHoverForeground    BG
statusBarItem.offlineBackground     #5e2102
statusBarItem.offlineForeground     FG
statusBarItem.offlineHoverBackground    DIM
statusBarItem.offlineHoverForeground    FG
statusBarItem.prominentBackground   VIOLET_B
statusBarItem.prominentForeground   FG
statusBarItem.prominentHoverBackground  LAV
statusBarItem.prominentHoverForeground  BG

# --- タイトルバー・メニュー・コマンドセンター ---
titleBar.activeBackground       BG
titleBar.activeForeground       S_TITLE_FG
titleBar.inactiveBackground     BG
titleBar.inactiveForeground     S_TITLE_FG_INACTIVE
titleBar.border                 T
menubar.selectionBackground     S_MENUBAR_HOVER
menubar.selectionForeground     FG
menubar.selectionBorder         T
menu.background                 BG
menu.foreground                 FG
menu.selectionBackground        S_SEL
menu.selectionForeground        FG
menu.selectionBorder            T
menu.separatorBackground        a(DIM, 0x50)
menu.border                     T
commandCenter.background        BG
commandCenter.foreground        CHROME
commandCenter.border            a(DIM, 0xe8)
commandCenter.activeBackground  S_COMMAND_ACTIVE
commandCenter.activeBorder      BLUE
commandCenter.activeForeground  FG
commandCenter.inactiveBorder    a(DIM, 0x30)
commandCenter.inactiveForeground    FG2

# --- クイック入力・入力部品 ---
quickInput.background               BG
quickInput.foreground               FG
quickInputList.focusBackground      S_SEL
quickInputList.focusForeground      FG
quickInputList.focusIconForeground  FG2
quickInputTitle.background          BG
pickerGroup.border                  a(DIM, 0x40)
pickerGroup.foreground              FG2
input.background                    BG
input.foreground                    FG
input.border                        a(DIM, 0xe8)
input.placeholderForeground         DIM
inputOption.activeBackground        a(BLUE_M, 0x60)
inputOption.activeBorder            BLUE
inputOption.activeForeground        FG
inputOption.hoverBackground         a(INDIGO, 0x50)
inputValidation.errorBackground     BG
inputValidation.errorBorder         ERR
inputValidation.errorForeground     ROSE
inputValidation.warningBackground   BG
inputValidation.warningBorder       WARN
inputValidation.warningForeground   WARN
inputValidation.infoBackground      BG
inputValidation.infoBorder          FG2
inputValidation.infoForeground      FG2
dropdown.background                 BG
dropdown.foreground                 FG
dropdown.border                     a(DIM, 0xe8)
dropdown.listBackground             BG
button.background                   BLUE_M
button.foreground                   FG
button.hoverBackground              VIOLET_B
button.border                       T
button.separator                    a(FG, 0x40)
button.secondaryBackground          GRAY
button.secondaryForeground          FG
button.secondaryHoverBackground     INDIGO
button.secondaryBorder              T
checkbox.background                 BG
checkbox.foreground                 FG
checkbox.border                     DIM
checkbox.selectBackground           a(BLUE_M, 0x60)
checkbox.selectBorder               BLUE
checkbox.disabled.background        BG
checkbox.disabled.foreground        DIM
radio.activeBackground              a(BLUE_M, 0x60)
radio.activeBorder                  BLUE
radio.activeForeground              FG
radio.inactiveBackground            BG
radio.inactiveBorder                DIM
radio.inactiveForeground            DIM
radio.inactiveHoverBackground       a(INDIGO, 0x50)
badge.background                    BLUE_M
badge.foreground                    FG

# --- リスト・ツリー ---
list.activeSelectionBackground          S_SEL
list.activeSelectionForeground          FG
list.activeSelectionIconForeground      FG
list.inactiveSelectionBackground        S_SEL_SUB
list.inactiveSelectionForeground        FG
list.inactiveSelectionIconForeground    FG2
list.inactiveFocusBackground            S_HOVER
list.inactiveFocusOutline               T
list.hoverBackground                    S_HOVER
list.hoverForeground                    FG
list.focusBackground                    S_SEL_FOCUS
list.focusForeground                    FG
list.focusOutline                       T
list.focusAndSelectionOutline           T
list.focusHighlightForeground           LAV
list.highlightForeground                LAV
list.dropBackground                     a(BLUE_M, 0x40)
list.dropBetweenBackground              BLUE
list.errorForeground                    ERR
list.warningForeground                  WARN
list.deemphasizedForeground             DIM
list.invalidItemForeground              ERR
list.filterMatchBackground              a(LAV, 0x40)
list.filterMatchBorder                  LAV
listFilterWidget.background             BG
listFilterWidget.outline                BLUE
listFilterWidget.noMatchesOutline       ERR
listFilterWidget.shadow                 a(SHADOW, 0xb0)
tree.indentGuidesStroke                 a(DIM, 0x60)
tree.inactiveIndentGuidesStroke         a(DIM, 0x30)
tree.tableColumnsBorder                 a(DIM, 0x30)
tree.tableOddRowsBackground             a(INDIGO, 0x10)

# --- パネル・出力・ターミナル ---
panel.background                    BG
panel.border                        T
panel.dropBorder                    BLUE
panelInput.border                   a(DIM, 0x60)
panelTitle.activeForeground         FG
panelTitle.activeBorder             BLUE
panelTitle.inactiveForeground       FG2
panelTitle.border                   T
panelTitleBadge.background          BLUE_M
panelTitleBadge.foreground          FG
panelSection.border                 T
panelSection.dropBackground         a(BLUE_M, 0x30)
panelSectionHeader.background       BG
panelSectionHeader.foreground       CHROME
panelSectionHeader.border           T
panelStickyScroll.background        BG
panelStickyScroll.border            T
panelStickyScroll.shadow            a(SHADOW, 0x80)
outputView.background               BG
outputViewStickyScroll.background   BG
terminal.background                 BG
terminal.foreground                 FG
terminal.border                     T
terminal.selectionBackground        S_SEL
terminal.selectionForeground        FG
terminal.inactiveSelectionBackground    S_SEL_SUB
terminal.ansiBlack                  INDIGO
terminal.ansiRed                    ERR
terminal.ansiGreen                  GREEN
terminal.ansiYellow                 WARN
terminal.ansiBlue                   BLUE
terminal.ansiMagenta                PURP
terminal.ansiCyan                   FG2
terminal.ansiWhite                  DOC
terminal.ansiBrightBlack            FG2
terminal.ansiBrightRed              ROSE
terminal.ansiBrightGreen            PALEGREEN
terminal.ansiBrightYellow           KHAKI
terminal.ansiBrightBlue             LAV
terminal.ansiBrightMagenta          MAG
terminal.ansiBrightCyan             FG
terminal.ansiBrightWhite            #f9f2f2
terminalCursor.foreground           FG2
terminalCursor.background           BG
terminal.findMatchBackground        a(LAV, 0x70)
terminal.findMatchBorder            LAV
terminal.findMatchHighlightBackground   a(LAV, 0x40)
terminal.findMatchHighlightBorder   T
terminal.hoverHighlightBackground   a(INDIGO, 0x50)
terminal.dropBackground             a(BLUE_M, 0x30)
terminal.tab.activeBorder           BLUE
terminal.initialHintForeground      DIM
terminalStickyScroll.background     BG
terminalStickyScrollHover.background    a(INDIGO, 0x30)
terminalStickyScroll.border         T
terminalCommandDecoration.successBackground GREEN
terminalCommandDecoration.errorBackground   ERR
terminalCommandDecoration.defaultBackground DIM
terminalCommandGuide.foreground     a(DIM, 0x40)
terminalOverviewRuler.cursorForeground  FG2
terminalOverviewRuler.findMatchForeground   LAV
terminalOverviewRuler.border        T

# --- ミニマップ・スクロールバー・パンくず ---
minimap.background                  BG
minimap.selectionHighlight          a(FG, 0x60)
minimap.findMatchHighlight          a(LAV, 0x80)
minimap.errorHighlight              ERR
minimap.warningHighlight            WARN
minimap.infoHighlight               FG2
minimap.selectionOccurrenceHighlight    a(MAG, 0x80)
minimap.foregroundOpacity           BG
minimapSlider.background            a(INDIGO, 0x90)
minimapSlider.hoverBackground       a(INDIGO, 0x70)
minimapSlider.activeBackground      a(INDIGO, 0x80)
minimapGutter.addedBackground       GREEN
minimapGutter.modifiedBackground    BLUE
minimapGutter.deletedBackground     PURP
scrollbar.shadow                    a(SHADOW, 0x80)
scrollbarSlider.background          a(INDIGO, 0x90)
scrollbarSlider.hoverBackground     a(INDIGO, 0x70)
scrollbarSlider.activeBackground    a(INDIGO, 0x80)
breadcrumb.foreground               MUTED
breadcrumb.focusForeground          FG
breadcrumb.activeSelectionForeground    FG2
breadcrumb.background               BG
breadcrumbPicker.background         BG

# --- Diff・マージ ---
diffEditor.insertedLineBackground   a(DEEP_GREEN, 0xc0)
diffEditor.insertedTextBackground   DEEP_GREEN
diffEditor.insertedTextBorder       T
diffEditor.removedLineBackground    a(DEEP_PURPLE, 0xc0)
diffEditor.removedTextBackground    DEEP_PURPLE
diffEditor.removedTextBorder        T
diffEditor.border                   T
diffEditor.diagonalFill             a(DIM, 0x40)
diffEditor.move.border              VIOLET_B
diffEditor.moveActive.border        MAG
diffEditor.unchangedCodeBackground  a(INDIGO, 0x18)
diffEditor.unchangedRegionBackground    BG
diffEditor.unchangedRegionForeground    DIM
diffEditorGutter.insertedLineBackground a(GREEN, 0x28)
diffEditorGutter.removedLineBackground  a(PURP, 0x28)
diffEditorOverview.insertedForeground   GREEN
diffEditorOverview.removedForeground    PURP
merge.currentHeaderBackground       a(BLUE_M, 0x60)
merge.currentContentBackground      a(BLUE_M, 0x28)
merge.incomingHeaderBackground      a(VIOLET_B, 0x70)
merge.incomingContentBackground     a(VIOLET_B, 0x28)
merge.commonHeaderBackground        a(DIM, 0x50)
merge.commonContentBackground       a(DIM, 0x20)
merge.border                        T

# --- Git 装飾 (ファイル名の色) ---
gitDecoration.addedResourceForeground           PALEGREEN
gitDecoration.modifiedResourceForeground        ROSE
gitDecoration.deletedResourceForeground         PURP
gitDecoration.renamedResourceForeground         PALEGREEN
gitDecoration.untrackedResourceForeground       GREEN
gitDecoration.ignoredResourceForeground         DIM
gitDecoration.conflictingResourceForeground     MAG
gitDecoration.stageModifiedResourceForeground   PALEGREEN
gitDecoration.stageDeletedResourceForeground    PURP
gitDecoration.submoduleResourceForeground       BLUE
git.blame.editorDecorationForeground            DIM

# --- 通知・問題 ---
notificationLink.foreground         FG2
notifications.background            BG
notifications.foreground            FG
notifications.border                T
notificationCenter.border           T
notificationCenterHeader.background BG
notificationCenterHeader.foreground CHROME
notificationToast.border            T
notificationsErrorIcon.foreground   ERR
notificationsWarningIcon.foreground WARN
notificationsInfoIcon.foreground    FG2
problemsErrorIcon.foreground        ERR
problemsWarningIcon.foreground      WARN
problemsInfoIcon.foreground         FG2
sash.hoverBorder                    BLUE
toolbar.hoverBackground             S_TOOLBAR_HOVER
toolbar.hoverOutline                T
toolbar.activeBackground            a(BLUE_M, 0x60)
keybindingLabel.background          a(INDIGO, 0x40)
keybindingLabel.foreground          FG
keybindingLabel.border              a(DIM, 0x80)
keybindingLabel.bottomBorder        a(DIM, 0xb0)
keybindingTable.headerBackground    BG
keybindingTable.rowsBackground      BG

# --- ピークビュー・マーカーナビ ---
peekView.border                         BLUE
peekViewEditor.background               BG
peekViewEditorGutter.background         BG
peekViewEditorStickyScroll.background  BG
peekViewResult.background               BG
peekViewResult.fileForeground           FG
peekViewResult.lineForeground           FG2
peekViewResult.matchHighlightBackground a(LAV, 0x50)
peekViewResult.selectionBackground      S_SEL
peekViewResult.selectionForeground      FG
peekViewTitle.background                BG
peekViewTitleDescription.foreground     FG2
peekViewTitleLabel.foreground           FG
peekViewEditor.matchHighlightBackground a(LAV, 0x40)
peekViewEditor.matchHighlightBorder     T
editorMarkerNavigation.background               BG
editorMarkerNavigationError.background          a(ERR, 0x20)
editorMarkerNavigationError.headerBackground    a(ERR, 0x35)
editorMarkerNavigationWarning.background        a(WARN, 0x20)
editorMarkerNavigationWarning.headerBackground  a(WARN, 0x35)
editorMarkerNavigationInfo.background           a(FG2, 0x20)
editorMarkerNavigationInfo.headerBackground     a(FG2, 0x35)

# --- デバッグ ---
debugToolBar.background             BG
debugToolBar.border                 T
debugView.exceptionLabelBackground  a(ERR, 0x40)
debugView.exceptionLabelForeground  FG
debugView.stateLabelBackground      a(BLUE_M, 0x60)
debugView.stateLabelForeground      FG
debugView.valueChangedHighlight     a(PALEGREEN, 0x50)
debugConsole.errorForeground        ROSE
debugConsole.warningForeground      WARN
debugConsole.infoForeground         FG2
debugConsole.sourceForeground       FG2
debugConsoleInputIcon.foreground    FG2
debugExceptionWidget.background     BG
debugExceptionWidget.border         ERR
debugIcon.breakpointForeground          ERR
debugIcon.breakpointDisabledForeground  DIM
debugIcon.breakpointUnverifiedForeground    ROSE
debugIcon.breakpointCurrentStackframeForeground LAV
debugIcon.breakpointStackframeForeground    FG2
debugIcon.startForeground           GREEN
debugIcon.stopForeground            ERR
debugIcon.disconnectForeground      WARN
debugIcon.pauseForeground           WARN
debugIcon.continueForeground        GREEN
debugIcon.stepOverForeground        BLUE
debugIcon.stepIntoForeground        BLUE
debugIcon.stepOutForeground         BLUE
debugIcon.stepBackForeground        FG2
debugIcon.restartForeground         GREEN
debugTokenExpression.name           R_VARIABLE
debugTokenExpression.value          FG
debugTokenExpression.string         R_VALUE
debugTokenExpression.boolean        R_VALUE
debugTokenExpression.number         R_VALUE
debugTokenExpression.error          ROSE
debugTokenExpression.type           R_TYPE

# --- 設定画面 ---
settings.headerForeground               FG
settings.headerBorder                   T
settings.settingsHeaderHoverForeground  FG2
settings.focusedRowBackground           a(INDIGO, 0x30)
settings.focusedRowBorder               a(BLUE, 0x60)
settings.rowHoverBackground             a(INDIGO, 0x20)
settings.modifiedItemIndicator          BLUE
settings.dropdownBackground             BG
settings.dropdownForeground             FG
settings.dropdownBorder                 a(DIM, 0x80)
settings.dropdownListBorder             a(DIM, 0x80)
settings.checkboxBackground             BG
settings.checkboxForeground             FG
settings.checkboxBorder                 DIM
settings.textInputBackground            BG
settings.textInputForeground            FG
settings.textInputBorder                a(DIM, 0x80)
settings.numberInputBackground          BG
settings.numberInputForeground          FG
settings.numberInputBorder              a(DIM, 0x80)
settings.sashBorder                     BLUE

# --- シンボルアイコン (トークン色と対応) ---
symbolIcon.classForeground              R_TYPE
symbolIcon.interfaceForeground          R_TYPE
symbolIcon.structForeground             R_TYPE
symbolIcon.enumForeground               R_TYPE
symbolIcon.enumeratorForeground         R_TYPE
symbolIcon.enumeratorMemberForeground   R_TYPE
symbolIcon.functionForeground           R_FUNCTION
symbolIcon.methodForeground             R_FUNCTION
symbolIcon.constructorForeground        R_FUNCTION
symbolIcon.variableForeground           R_VARIABLE
symbolIcon.fieldForeground              R_VARIABLE
symbolIcon.propertyForeground           R_VARIABLE
symbolIcon.keyForeground                R_VARIABLE
symbolIcon.keywordForeground            R_KEYWORD
symbolIcon.moduleForeground             R_VARIABLE
symbolIcon.namespaceForeground          R_VARIABLE
symbolIcon.packageForeground            R_VARIABLE
symbolIcon.constantForeground           R_ACCENT
symbolIcon.numberForeground             R_VALUE
symbolIcon.stringForeground             R_VALUE
symbolIcon.booleanForeground            R_VALUE
symbolIcon.nullForeground               R_VALUE
symbolIcon.arrayForeground              MUTED
symbolIcon.objectForeground             MUTED
symbolIcon.operatorForeground           R_OPERATOR
symbolIcon.typeForeground               R_TYPE
symbolIcon.typeParameterForeground      R_TYPE
symbolIcon.colorForeground              ROSE
symbolIcon.eventForeground              R_FUNCTION
symbolIcon.fileForeground               FG2
symbolIcon.folderForeground             FG2
symbolIcon.referenceForeground          FG2
symbolIcon.snippetForeground            FG2
symbolIcon.textForeground               FG2
symbolIcon.unitForeground               FG2
symbolIcon.labelForeground              FG2

# --- チャート・拡張機能・その他 ---
charts.foreground                   FG
charts.lines                        DIM
charts.red                          ERR
charts.blue                         BLUE
charts.yellow                       WARN
charts.orange                       ROSE
charts.green                        GREEN
charts.purple                       PURP
extensionIcon.starForeground        WARN
extensionIcon.verifiedForeground    BLUE
extensionIcon.preReleaseForeground  LAV
extensionIcon.sponsorForeground     ROSE
extensionBadge.remoteBackground     BLUE_M
extensionBadge.remoteForeground     FG
extensionButton.prominentBackground BLUE_M
extensionButton.prominentForeground FG
extensionButton.prominentHoverBackground    VIOLET_B
extensionButton.background          BLUE_M
extensionButton.foreground          FG
extensionButton.hoverBackground     VIOLET_B
extensionButton.separator           a(FG, 0x40)
extensionButton.border              T
ports.iconRunningProcessForeground  GREEN
profileBadge.background             BLUE_M
profileBadge.foreground             FG
profiles.sashBorder                 BLUE
welcomePage.background              BG
welcomePage.tileBackground          BG
welcomePage.tileHoverBackground     a(INDIGO, 0x40)
welcomePage.tileBorder              T
welcomePage.progress.background     GRAY
welcomePage.progress.foreground     BLUE
walkThrough.embeddedEditorBackground    BG
walkthrough.stepTitle.foreground    FG
search.resultsInfoForeground        DIM
searchEditor.findMatchBackground    a(LAV, 0x40)
searchEditor.findMatchBorder        LAV
searchEditor.textInputBorder        a(DIM, 0x80)
commentsView.resolvedIcon           DIM
commentsView.unresolvedIcon         FG2
interactive.activeCodeBorder        BLUE
interactive.inactiveCodeBorder      a(DIM, 0x50)
scmGraph.foreground1                BLUE
scmGraph.foreground2                GREEN
scmGraph.foreground3                MAG
scmGraph.foreground4                FG2
scmGraph.foreground5                PURP
scmGraph.historyItemRefColor        BLUE
scmGraph.historyItemRemoteRefColor  LAV
scmGraph.historyItemBaseRefColor    FG2
scmGraph.historyItemHoverLabelForeground    FG
scmGraph.historyItemHoverDefaultLabelBackground a(DIM, 0x70)
scmGraph.historyItemHoverDefaultLabelForeground FG
scmGraph.historyItemHoverAdditionsForeground    GREEN
scmGraph.historyItemHoverDeletionsForeground    PURP
surface.border                      T
modernSash.gripForeground           BLUE
mcpIcon.starForeground              WARN
agentsPanel.border                  T
"""


def parse_colors_spec(ns: dict[str, object]) -> dict[str, str]:
    colors: dict[str, str] = {}
    for lineno, raw in enumerate(COLORS_SPEC.splitlines(), start=1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        key, _, expr = line.partition(" ")
        expr = expr.strip()
        if key in colors:
            raise ValueError(f"COLORS_SPEC: キー重複 {key!r} (spec 行 {lineno})")
        # 生の hex は直接指定可
        value = expr if expr.startswith("#") else eval(expr, {}, ns)  # noqa: S307
        colors[key] = value

    # 括弧(1〜6)
    for i, c in enumerate(BRACKETS, start=1):
        colors[f"editorBracketHighlight.foreground{i}"] = c
        colors[f"editorBracketPairGuide.background{i}"] = a(c, 0x1A)
        colors[f"editorBracketPairGuide.activeBackground{i}"] = a(c, 0x60)
    return colors


# ---------------------------------------------------------------------------
# tokenColors: scope[0] -> settings
# ---------------------------------------------------------------------------
def S(fg: str | None = None, style: str | None = None) -> dict[str, str]:
    d: dict[str, str] = {}
    if fg:
        d["foreground"] = fg
    if style:
        d["fontStyle"] = style
    return d


# 方針: 色は 役割（Roles）で決める．色=種類，斜体=外部由来（外部ライブラリ・コメント），太字=宣言，
# 下線=引数（変数と同色なので全使用箇所），取り消し線=非推奨．外部ライブラリ専用の色は持たない．
def token_settings(r: Roles) -> dict[str, dict[str, str]]:
    return {
        "comment": S(r.comment, "italic"),
        "string": S(r.value),
        "string.quoted.docstring.multi.python": S(r.comment, "italic"),
        "constant.character.escape": S(r.variable),
        "punctuation.definition.template-expression": S(r.operator),
        "string.regexp": S(r.value),
        "constant.numeric": S(r.value),
        "constant.language": S(r.value),
        "keyword.control": S(r.keyword),
        "keyword.operator": S(r.operator),
        "storage.type": S(r.keyword),
        "entity.name.type": S(r.type),
        "entity.other.inherited-class": S(r.type),
        "entity.name.function": S(r.function),
        "variable.parameter": S(r.variable, "underline"),
        "variable.other.local": S(r.variable),
        "variable": S(r.variable),
        "variable.language.special.self.python": S(r.keyword),
        "variable.other.property": S(r.variable),
        "support.function": S(r.function, "italic"),
        "support.class": S(r.type, "italic"),
        "support.variable": S(r.variable, "italic"),
        "meta.tag": S(r.keyword),
        "entity.other.attribute-name": S(r.variable),
        "meta.decorator": S(r.keyword),
        "variable.other.enummember": S(r.type),
        "entity.name.function.macro": S(r.function),
        "meta.import": S(r.variable, "italic"),
        "punctuation": S(r.operator),
        "support.type.property-name": S(r.variable),
        "support.constant.property-value": S(r.value),
        "entity.name.tag.css": S(r.keyword),
        "markup.heading": S(r.keyword, "bold"),
        "markup.bold": S(None, "bold"),
        "markup.italic": S(None, "italic"),
        "markup.inline.raw": S(r.value),
        "markup.underline.link": S(r.variable),
        "markup.quote": S(r.comment, "italic"),
        "invalid": S(ERR, "underline"),
        "invalid.deprecated": S(MUTED, "strikethrough"),
    }

# ---------------------------------------------------------------------------
# semanticTokenColors: 元のキー -> settings
# ---------------------------------------------------------------------------
def semantic_settings(r: Roles) -> dict[str, dict[str, str]]:
    return {
        "variable": S(r.variable),
        "variable.declaration": S(r.variable),
        "variable.readonly": S(r.accent),
        "variable.static": S(r.accent),
        "variable.modification": S(r.variable),
        "parameter": S(r.variable, "underline"),
        "parameter.declaration": S(r.variable, "underline"),
        "parameter.readonly": S(r.variable, "underline"),
        "parameter.modification": S(r.variable, "underline"),
        "parameter.keywordArgument": S(r.variable, "underline"),
        "function": S(r.function),
        "function.declaration": S(r.function, "bold"),
        "method": S(r.function),
        "method.declaration": S(r.function, "bold"),
        "class": S(r.type),
        "class.declaration": S(r.type, "bold"),
        "struct": S(r.type),
        "struct.declaration": S(r.type, "bold"),
        "type": S(r.type),
        "type.declaration": S(r.type, "bold"),
        "builtinType": S(r.type, "italic"),
        "interface": S(r.type),
        "interface.declaration": S(r.type, "bold"),
        "enum": S(r.type),
        "enum.declaration": S(r.type, "bold"),
        "enumMember": S(r.type),
        "typeParameter": S(r.type),
        "namespace": S(r.variable, "italic"),
        "module": S(r.variable, "italic"),
        "property": S(r.variable),
        "property.readonly": S(r.variable),
        "property.static": S(r.accent),
        "modifier": S(r.keyword),
        "string": S(r.value),
        "number": S(r.value),
        "regexp": S(r.value),
        "operator": S(r.operator),
        "decorator": S(r.keyword),
        "event": S(r.function),
        "comment": S(r.comment, "italic"),
        "macro": S(r.function),
        "label": S(r.comment),
        "selfKeyword": S(r.keyword),
        "selfKeyword:rust": S(r.keyword),
        "selfKeyword:rust.mutable": S(r.keyword),
        "lifetime": S(r.type),
        "variable.defaultLibrary": S(r.variable, "italic"),
        "function.defaultLibrary": S(r.function, "italic"),
        "method.defaultLibrary": S(r.function, "italic"),
        "class.defaultLibrary": S(r.type, "italic"),
        "type.defaultLibrary": S(r.type, "italic"),
        "variable.deprecated": S(MUTED, "strikethrough"),
        "property.deprecated": S(MUTED, "strikethrough"),
        "keyword": S(r.keyword),
    }


def extra_token_colors(r: Roles) -> list[dict]:
    """元テーマに無い追加項目（末尾に追加．元の項目の name/scope・順序は変えない）。"""
    return [
        {
            "name": "定数 (大文字の名前) ※注意色",
            "scope": ["variable.other.constant"],
            "settings": S(r.accent),
        },
    ]


def check_keys(label: str, expected: list[str], actual: set[str]) -> None:
    missing = [k for k in expected if k not in actual]
    extra = sorted(actual - set(expected))
    if missing or extra:
        msg = [f"{label}: キー不一致"]
        if missing:
            msg.append(f"  割り当て漏れ({len(missing)}): {missing}")
        if extra:
            msg.append(f"  元JSONに無い({len(extra)}): {extra}")
        raise SystemExit("\n".join(msg))


def build(bg: str, roles: Roles, surfaces: Surfaces, dst: Path) -> None:
    src = json.loads(SRC.read_text(encoding="utf-8-sig"))

    colors_new = parse_colors_spec(make_namespace(bg, roles, surfaces))
    check_keys("colors", list(src["colors"]), set(colors_new))

    token_map = token_settings(roles)
    semantic_map = semantic_settings(roles)
    token_keys = [t["scope"][0] for t in src["tokenColors"]]
    check_keys("tokenColors(scope[0])", token_keys, set(token_map))

    check_keys("semanticTokenColors", list(src["semanticTokenColors"]), set(semantic_map))

    out: dict = {}
    for k, v in src.items():
        if k == "colors":
            out[k] = {key: colors_new[key] for key in src["colors"]}
        elif k == "tokenColors":
            out[k] = [
                {"name": t["name"], "scope": t["scope"], "settings": token_map[t["scope"][0]]}
                for t in src["tokenColors"]
            ] + extra_token_colors(roles)
        elif k == "semanticTokenColors":
            sem: dict = {}
            for key, orig in src["semanticTokenColors"].items():
                spec = semantic_map[key]
                if "fontStyle" in spec or isinstance(orig, dict):
                    sem[key] = spec
                else:
                    sem[key] = spec["foreground"]
            out[k] = sem
        else:
            out[k] = v

    dst.write_text(json.dumps(out, ensure_ascii=False, indent=4) + "\n", encoding="utf-8")
    print(f"✓ 生成: {dst.relative_to(ROOT)} (背景 {bg})")
    print(
        f"  colors={len(out['colors'])} tokenColors={len(out['tokenColors'])} "
        f"semanticTokenColors={len(out['semanticTokenColors'])}"
    )


def main() -> None:
    for dst, (bg, roles, surfaces) in VARIANTS.items():
        build(bg, roles, surfaces, dst)


if __name__ == "__main__":
    main()
