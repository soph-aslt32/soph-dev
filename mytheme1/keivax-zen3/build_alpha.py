"""keivax-zen3-theme.json のキー構成を引き継ぎ、NewColorPalette から色を割り当て直して
keivax-zen3-alpha-theme.json を生成する。

- 色は README の NewColorPalette のみ（透明度の付加は可）。
- colors は「キー名  色の式」の表(COLORS_SPEC)で全キーを明示的に割り当てる。
  元 JSON にあって表に無いキー、表にあって元 JSON に無いキーはエラーにする。
- tokenColors は scope[0] で、semanticTokenColors は元のキーで割り当てる。
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")  # パイプ経由でも日本語・記号を文字化けさせない

ROOT = Path(__file__).parent
SRC = ROOT / "themes" / "keivax-zen3-theme.json"
DST = ROOT / "themes" / "keivax-zen3-alpha-theme.json"

# ---------------------------------------------------------------------------
# 役割 → パレット色
# ---------------------------------------------------------------------------
BG = "#1e2323"  # 全セクション共通の背景
FG = "#e8f7f0"  # 通常テキスト
FG2 = "#979ac4"  # 二次テキスト・アイコン・キーワード
DIM = "#7a6a64"  # 非活性・コメント・句読点
SOFT = "#a08e96"  # Docstring・演算子・プレースホルダ
GRAY = "#323233"  # 中立の暗灰

BLUE = "#4470ff"  # 鮮やかな青: アクセント・クラス/型・変更
BLUE_M = "#1761aa"  # 中間の青: 選択背景・ボタン
INDIGO = "#4a4d91"  # ホバー・淡い強調背景
VIOLET_B = "#5f47cc"  # 青紫: デバッグ・マージ
LAV = "#9b7dc6"  # 藤色: 検索一致・各種マッチ強調
EXTERN = "#b075d8"  # 明るい紫: 外部ライブラリ・ビルトイン・モジュール
PURP = "#ae47d1"  # 紫: 引数・削除
MAG = "#f411e1"  # マゼンタ: グローバル/定数・変数ハイライト
ROSE = "#dd949e"  # バラ色: 関数
GREEN = "#7ea033"  # オリーブ緑: 文字列/数値・追加
PALEGREEN = "#c4e5ac"  # 淡緑: 正規表現・未追跡・書込ハイライト
KHAKI = "#d6d595"  # カーキ: ローカル変数

ERR = "#dd2a57"  # エラー専有
WARN = "#fcb346"  # 警告専有
SHADOW = "#070606"  # 影

T = BG + "00"  # 透明（枠線など）


def a(color: str, alpha: int) -> str:
    return f"{color}{alpha:02x}"


NAMESPACE = {k: v for k, v in globals().items() if k.isupper() and isinstance(v, str)}
NAMESPACE.update({"a": a, "T": T})

BRACKETS = [BLUE, GREEN, MAG, KHAKI, FG2, ROSE]

# ---------------------------------------------------------------------------
# colors: キー  色の式
# ---------------------------------------------------------------------------
COLORS_SPEC = """
# --- 基本 ---
foreground                      FG
descriptionForeground           FG2
disabledForeground              DIM
errorForeground                 ERR
focusBorder                     BLUE
selection.background            a(BLUE_M, 0x90)
icon.foreground                 FG2
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
editor.lineHighlightBackground          a(INDIGO, 0x20)
editor.lineHighlightBorder              T
editor.selectionBackground              a(BLUE_M, 0x90)
editor.selectionForeground              FG
editor.inactiveSelectionBackground      a(BLUE_M, 0x50)
editor.selectionHighlightBackground     a(FG, 0x20)
editor.selectionHighlightBorder         a(FG, 0x60)
editor.wordHighlightBackground          a(MAG, 0x38)
editor.wordHighlightBorder              MAG
editor.wordHighlightStrongBackground    a(PALEGREEN, 0x40)
editor.wordHighlightStrongBorder        PALEGREEN
editor.wordHighlightTextBackground      a(MAG, 0x24)
editor.wordHighlightTextBorder          a(MAG, 0x70)
editor.findMatchBackground              a(LAV, 0x70)
editor.findMatchBorder                  LAV
editor.findMatchHighlightBackground     a(LAV, 0x40)
editor.findMatchHighlightBorder         T
editor.findRangeHighlightBackground     a(INDIGO, 0x30)
editor.findRangeHighlightBorder         T
editor.hoverHighlightBackground         a(INDIGO, 0x50)
editor.rangeHighlightBackground         a(INDIGO, 0x30)
editor.rangeHighlightBorder             T
editor.symbolHighlightBackground        a(INDIGO, 0x50)
editor.symbolHighlightBorder            T
editor.inlineValuesBackground           a(BG, 0xcc)
editor.inlineValuesForeground           DIM
editor.linkedEditingBackground          a(PURP, 0x30)
editor.foldBackground                   a(INDIGO, 0x30)
editor.foldPlaceholderForeground        DIM
editor.placeholder.foreground           DIM
editor.snippetTabstopHighlightBackground        a(FG2, 0x30)
editor.snippetTabstopHighlightBorder            a(FG2, 0x60)
editor.snippetFinalTabstopHighlightBackground   a(LAV, 0x30)
editor.snippetFinalTabstopHighlightBorder       LAV
editor.stackFrameHighlightBackground            a(INDIGO, 0x50)
editor.focusedStackFrameHighlightBackground     a(BLUE, 0x40)
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
editorLineNumber.activeForeground       FG2
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
editorBracketMatch.background                       a(FG2, 0x30)
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
editorHint.foreground           a(SOFT, 0xc8)
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
editorSuggestWidget.selectedBackground          a(BLUE_M, 0x60)
editorSuggestWidget.selectedForeground          FG
editorSuggestWidget.selectedIconForeground      FG2
editorSuggestWidgetStatus.foreground            DIM
editorActionList.background             BG
editorActionList.foreground             FG
editorActionList.focusBackground        a(BLUE_M, 0x60)
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
editorInlayHint.parameterForeground     SOFT
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
tab.inactiveForeground                  SOFT
tab.inactiveModifiedBorder              a(PALEGREEN, 0x70)
tab.hoverBackground                     a(INDIGO, 0x50)
tab.hoverForeground                     FG
tab.hoverBorder                         T
tab.unfocusedActiveBackground           BG
tab.unfocusedActiveForeground           FG2
tab.unfocusedActiveBorder               T
tab.unfocusedActiveBorderTop            a(BLUE, 0x60)
tab.unfocusedActiveModifiedBorder       a(PALEGREEN, 0x50)
tab.unfocusedInactiveBackground         BG
tab.unfocusedInactiveForeground         DIM
tab.unfocusedInactiveModifiedBorder     a(PALEGREEN, 0x30)
tab.unfocusedHoverBackground            a(INDIGO, 0x30)
tab.unfocusedHoverForeground            FG2
tab.unfocusedHoverBorder                T
tab.selectedBackground                  BG
tab.selectedForeground                  FG
tab.selectedBorderTop                   BLUE
tab.lastPinnedBorder                    T
tab.dragAndDropBorder                   BLUE
modernTab.activeBackground              a(BLUE_M, 0x60)
modernTab.activeForeground              FG
modernTab.hoverBackground               a(INDIGO, 0x70)
modernTab.hoverForeground               FG
modernEditorTab.activeBackground        a(BLUE_M, 0x80)
modernEditorTab.activeForeground        FG
modernEditorTab.inactiveBackground      BG
modernEditorTab.hoverBackground         a(INDIGO, 0x90)
modernEditorTab.hoverForeground         FG
modernEditorTab.activeHoverBackground   a(BLUE_M, 0xa0)

# --- アクティビティバー ---
activityBar.background              BG
activityBar.foreground              FG
activityBar.inactiveForeground      DIM
activityBar.border                  T
activityBar.activeBorder            BLUE
activityBar.activeFocusBorder       BLUE
activityBar.activeBackground        T
activityBar.dropBorder              BLUE
activityBarBadge.background         BLUE_M
activityBarBadge.foreground         FG
activityBarTop.background           BG
activityBarTop.foreground           FG
activityBarTop.inactiveForeground   DIM
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
sideBar.foreground                  FG
sideBar.border                      T
sideBar.dropBackground              a(BLUE_M, 0x30)
sideBarTitle.foreground             FG
sideBarTitle.background             BG
sideBarTitle.border                 T
sideBarSectionHeader.background     BG
sideBarSectionHeader.foreground     FG2
sideBarSectionHeader.border         T
sideBarActivityBarTop.border        T
sideBarStickyScroll.background      BG
sideBarStickyScroll.border          T
sideBarStickyScroll.shadow          a(SHADOW, 0x80)

# --- ステータスバー ---
statusBar.background                BG
statusBar.foreground                FG2
statusBar.border                    T
statusBar.focusBorder               BLUE
statusBar.debuggingBackground       VIOLET_B
statusBar.debuggingForeground       FG
statusBar.debuggingBorder           T
statusBar.noFolderBackground        BG
statusBar.noFolderForeground        FG2
statusBar.noFolderBorder            T
statusBarItem.hoverBackground       a(BLUE_M, 0x50)
statusBarItem.hoverForeground       FG
statusBarItem.activeBackground      a(BLUE_M, 0x80)
statusBarItem.focusBorder           BLUE
statusBarItem.compactHoverBackground    a(BLUE_M, 0x60)
statusBarItem.remoteBackground      BLUE_M
statusBarItem.remoteForeground      FG
statusBarItem.remoteHoverBackground BLUE
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
titleBar.activeForeground       FG
titleBar.inactiveBackground     BG
titleBar.inactiveForeground     DIM
titleBar.border                 T
menubar.selectionBackground     a(BLUE_M, 0x50)
menubar.selectionForeground     FG
menubar.selectionBorder         T
menu.background                 BG
menu.foreground                 FG
menu.selectionBackground        a(BLUE_M, 0x70)
menu.selectionForeground        FG
menu.selectionBorder            T
menu.separatorBackground        a(DIM, 0x50)
menu.border                     T
commandCenter.background        BG
commandCenter.foreground        FG2
commandCenter.border            a(DIM, 0x50)
commandCenter.activeBackground  a(BLUE_M, 0x30)
commandCenter.activeBorder      BLUE
commandCenter.activeForeground  FG
commandCenter.inactiveBorder    a(DIM, 0x30)
commandCenter.inactiveForeground    DIM

# --- クイック入力・入力部品 ---
quickInput.background               BG
quickInput.foreground               FG
quickInputList.focusBackground      a(BLUE_M, 0x70)
quickInputList.focusForeground      FG
quickInputList.focusIconForeground  FG2
quickInputTitle.background          BG
pickerGroup.border                  a(DIM, 0x40)
pickerGroup.foreground              FG2
input.background                    BG
input.foreground                    FG
input.border                        a(DIM, 0x90)
input.placeholderForeground         DIM
inputOption.activeBackground        a(BLUE_M, 0x60)
inputOption.activeBorder            BLUE
inputOption.activeForeground        FG
inputOption.hoverBackground         a(INDIGO, 0x50)
inputValidation.errorBackground     BG
inputValidation.errorBorder         ERR
inputValidation.errorForeground     ERR
inputValidation.warningBackground   BG
inputValidation.warningBorder       WARN
inputValidation.warningForeground   WARN
inputValidation.infoBackground      BG
inputValidation.infoBorder          FG2
inputValidation.infoForeground      FG2
dropdown.background                 BG
dropdown.foreground                 FG
dropdown.border                     a(DIM, 0x90)
dropdown.listBackground             BG
button.background                   BLUE_M
button.foreground                   FG
button.hoverBackground              BLUE
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
list.activeSelectionBackground          a(BLUE_M, 0x70)
list.activeSelectionForeground          FG
list.activeSelectionIconForeground      FG
list.inactiveSelectionBackground        a(BLUE_M, 0x40)
list.inactiveSelectionForeground        FG2
list.inactiveSelectionIconForeground    DIM
list.inactiveFocusBackground            a(INDIGO, 0x40)
list.inactiveFocusOutline               T
list.hoverBackground                    a(INDIGO, 0x50)
list.hoverForeground                    FG
list.focusBackground                    a(BLUE_M, 0x60)
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
panelTitle.inactiveForeground       DIM
panelTitle.border                   T
panelTitleBadge.background          BLUE_M
panelTitleBadge.foreground          FG
panelSection.border                 T
panelSection.dropBackground         a(BLUE_M, 0x30)
panelSectionHeader.background       BG
panelSectionHeader.foreground       FG2
panelSectionHeader.border           T
panelStickyScroll.background        BG
panelStickyScroll.border            T
panelStickyScroll.shadow            a(SHADOW, 0x80)
outputView.background               BG
outputViewStickyScroll.background   BG
terminal.background                 BG
terminal.foreground                 FG
terminal.border                     T
terminal.selectionBackground        a(BLUE_M, 0x70)
terminal.selectionForeground        FG
terminal.inactiveSelectionBackground    a(BLUE_M, 0x40)
terminal.ansiBlack                  GRAY
terminal.ansiRed                    ERR
terminal.ansiGreen                  GREEN
terminal.ansiYellow                 WARN
terminal.ansiBlue                   BLUE
terminal.ansiMagenta                PURP
terminal.ansiCyan                   FG2
terminal.ansiWhite                  SOFT
terminal.ansiBrightBlack            DIM
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
breadcrumb.foreground               DIM
breadcrumb.focusForeground          FG
breadcrumb.activeSelectionForeground    FG2
breadcrumb.background               BG
breadcrumbPicker.background         BG

# --- Diff・マージ ---
diffEditor.insertedLineBackground   a(GREEN, 0x20)
diffEditor.insertedTextBackground   a(GREEN, 0x38)
diffEditor.insertedTextBorder       T
diffEditor.removedLineBackground    a(PURP, 0x20)
diffEditor.removedTextBackground    a(PURP, 0x38)
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
gitDecoration.addedResourceForeground           GREEN
gitDecoration.modifiedResourceForeground        BLUE
gitDecoration.deletedResourceForeground         PURP
gitDecoration.renamedResourceForeground         EXTERN
gitDecoration.untrackedResourceForeground       PALEGREEN
gitDecoration.ignoredResourceForeground         DIM
gitDecoration.conflictingResourceForeground     MAG
gitDecoration.stageModifiedResourceForeground   FG2
gitDecoration.stageDeletedResourceForeground    PURP
gitDecoration.submoduleResourceForeground       SOFT
git.blame.editorDecorationForeground            a(SOFT, 0xb0)

# --- 通知・問題 ---
notificationLink.foreground         FG2
notifications.background            BG
notifications.foreground            FG
notifications.border                T
notificationCenter.border           T
notificationCenterHeader.background BG
notificationCenterHeader.foreground FG2
notificationToast.border            T
notificationsErrorIcon.foreground   ERR
notificationsWarningIcon.foreground WARN
notificationsInfoIcon.foreground    FG2
problemsErrorIcon.foreground        ERR
problemsWarningIcon.foreground      WARN
problemsInfoIcon.foreground         FG2
sash.hoverBorder                    BLUE
toolbar.hoverBackground             a(INDIGO, 0x50)
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
peekViewResult.selectionBackground      a(BLUE_M, 0x70)
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
debugConsole.errorForeground        ERR
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
debugTokenExpression.name           KHAKI
debugTokenExpression.value          FG
debugTokenExpression.string         GREEN
debugTokenExpression.boolean        MAG
debugTokenExpression.number         GREEN
debugTokenExpression.error          ERR
debugTokenExpression.type           BLUE

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
symbolIcon.classForeground              BLUE
symbolIcon.interfaceForeground          BLUE
symbolIcon.structForeground             BLUE
symbolIcon.enumForeground               BLUE
symbolIcon.enumeratorForeground         BLUE
symbolIcon.enumeratorMemberForeground   MAG
symbolIcon.functionForeground           ROSE
symbolIcon.methodForeground             ROSE
symbolIcon.constructorForeground        ROSE
symbolIcon.variableForeground           KHAKI
symbolIcon.fieldForeground              KHAKI
symbolIcon.propertyForeground           KHAKI
symbolIcon.keyForeground                KHAKI
symbolIcon.keywordForeground            FG2
symbolIcon.moduleForeground             EXTERN
symbolIcon.namespaceForeground          EXTERN
symbolIcon.packageForeground            EXTERN
symbolIcon.constantForeground           MAG
symbolIcon.numberForeground             GREEN
symbolIcon.stringForeground             GREEN
symbolIcon.booleanForeground            MAG
symbolIcon.nullForeground               MAG
symbolIcon.arrayForeground              SOFT
symbolIcon.objectForeground             SOFT
symbolIcon.operatorForeground           FG2
symbolIcon.typeForeground               BLUE
symbolIcon.typeParameterForeground      BLUE
symbolIcon.colorForeground              ROSE
symbolIcon.eventForeground              PURP
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
extensionButton.prominentHoverBackground    BLUE
extensionButton.background          BLUE_M
extensionButton.foreground          FG
extensionButton.hoverBackground     BLUE
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


def parse_colors_spec() -> dict[str, str]:
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
        value = expr if expr.startswith("#") else eval(expr, {}, NAMESPACE)  # noqa: S307
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


TOKEN_SETTINGS: dict[str, dict[str, str]] = {
    "comment": S(DIM, "italic"),
    "string": S(GREEN),
    "string.quoted.docstring.multi.python": S(a(SOFT, 0xE0), "italic"),
    "constant.character.escape": S(KHAKI),
    "punctuation.definition.template-expression": S(FG2),
    "string.regexp": S(GREEN, "italic"),
    "constant.numeric": S(GREEN),
    "constant.language": S(MAG),
    "keyword.control": S(FG2, "bold"),
    "keyword.operator": S(FG2),
    "storage.type": S(FG2),
    "entity.name.type": S(BLUE),
    "entity.other.inherited-class": S(BLUE, "italic"),
    "entity.name.function": S(ROSE),
    "variable.parameter": S(PURP, "italic underline"),
    "variable.other.local": S(KHAKI),
    "variable": S(KHAKI),
    "variable.language.special.self.python": S(FG2, "italic"),
    "variable.other.property": S(KHAKI, "italic"),
    "support.function": S(EXTERN, "italic"),
    "support.class": S(EXTERN, "italic"),
    "support.variable": S(EXTERN, "italic"),
    "meta.tag": S(BLUE),
    "entity.other.attribute-name": S(KHAKI, "italic"),
    "meta.decorator": S(FG2, "italic"),
    "variable.other.enummember": S(MAG, "italic"),
    "entity.name.function.macro": S(ROSE, "bold"),
    "meta.import": S(EXTERN),
    "punctuation": S(DIM),
    "support.type.property-name": S(FG2),
    "support.constant.property-value": S(GREEN),
    "entity.name.tag.css": S(BLUE),
    "markup.heading": S(BLUE, "bold"),
    "markup.bold": S(None, "bold"),
    "markup.italic": S(None, "italic"),
    "markup.inline.raw": S(GREEN),
    "markup.underline.link": S(FG2),
    "markup.quote": S(DIM, "italic"),
    "invalid": S(ERR, "underline"),
    "invalid.deprecated": S(SOFT, "strikethrough"),
}

# ---------------------------------------------------------------------------
# semanticTokenColors: 元のキー -> settings
# ---------------------------------------------------------------------------
SEMANTIC_SETTINGS: dict[str, dict[str, str]] = {
    "variable": S(KHAKI),
    "variable.declaration": S(KHAKI),
    "variable.readonly": S(MAG, "italic"),
    "variable.static": S(MAG, "bold"),
    "variable.modification": S(KHAKI),
    "parameter": S(PURP, "italic underline"),
    "parameter.declaration": S(PURP, "italic underline"),
    "parameter.readonly": S(PURP, "italic"),
    "parameter.modification": S(PURP, "italic underline"),
    "parameter.keywordArgument": S(PURP, "italic"),
    "function": S(ROSE),
    "function.declaration": S(ROSE, "bold"),
    "method": S(ROSE),
    "method.declaration": S(ROSE, "bold"),
    "class": S(BLUE),
    "class.declaration": S(BLUE, "bold"),
    "struct": S(BLUE),
    "struct.declaration": S(BLUE, "bold"),
    "type": S(BLUE),
    "type.declaration": S(BLUE, "bold"),
    "builtinType": S(EXTERN, "italic"),
    "interface": S(BLUE, "italic"),
    "interface.declaration": S(BLUE, "bold italic"),
    "enum": S(BLUE),
    "enum.declaration": S(BLUE, "bold"),
    "enumMember": S(MAG, "italic"),
    "typeParameter": S(BLUE, "italic"),
    "namespace": S(EXTERN),
    "module": S(EXTERN),
    "property": S(KHAKI, "italic"),
    "property.readonly": S(KHAKI, "italic"),
    "property.static": S(MAG, "italic"),
    "modifier": S(FG2),
    "string": S(GREEN),
    "number": S(GREEN),
    "regexp": S(GREEN, "italic"),
    "operator": S(FG2),
    "decorator": S(FG2, "italic"),
    "event": S(PURP, "italic"),
    "comment": S(DIM, "italic"),
    "macro": S(ROSE, "bold"),
    "label": S(DIM),
    "selfKeyword": S(FG2, "italic"),
    "selfKeyword:rust": S(FG2, "italic"),
    "selfKeyword:rust.mutable": S(FG2, "italic underline"),
    "lifetime": S(BLUE, "italic"),
    "variable.defaultLibrary": S(EXTERN, "italic"),
    "function.defaultLibrary": S(EXTERN, "italic"),
    "method.defaultLibrary": S(EXTERN, "italic"),
    "class.defaultLibrary": S(EXTERN, "italic"),
    "type.defaultLibrary": S(EXTERN, "italic"),
    "variable.deprecated": S(SOFT, "strikethrough"),
    "property.deprecated": S(SOFT, "strikethrough"),
    "keyword": S(FG2, "bold"),
}


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


def main() -> None:
    src = json.loads(SRC.read_text(encoding="utf-8-sig"))

    colors_new = parse_colors_spec()
    check_keys("colors", list(src["colors"]), set(colors_new))

    token_keys = [t["scope"][0] for t in src["tokenColors"]]
    check_keys("tokenColors(scope[0])", token_keys, set(TOKEN_SETTINGS))

    check_keys("semanticTokenColors", list(src["semanticTokenColors"]), set(SEMANTIC_SETTINGS))

    out: dict = {}
    for k, v in src.items():
        if k == "colors":
            out[k] = {key: colors_new[key] for key in src["colors"]}
        elif k == "tokenColors":
            out[k] = [
                {"name": t["name"], "scope": t["scope"], "settings": TOKEN_SETTINGS[t["scope"][0]]}
                for t in src["tokenColors"]
            ]
        elif k == "semanticTokenColors":
            sem: dict = {}
            for key, orig in src["semanticTokenColors"].items():
                spec = SEMANTIC_SETTINGS[key]
                if "fontStyle" in spec or isinstance(orig, dict):
                    sem[key] = spec
                else:
                    sem[key] = spec["foreground"]
            out[k] = sem
        else:
            out[k] = v

    DST.write_text(json.dumps(out, ensure_ascii=False, indent=4) + "\n", encoding="utf-8")
    print(f"✓ 生成: {DST.relative_to(ROOT)}")
    print(
        f"  colors={len(out['colors'])} tokenColors={len(out['tokenColors'])} "
        f"semanticTokenColors={len(out['semanticTokenColors'])}"
    )


if __name__ == "__main__":
    main()
