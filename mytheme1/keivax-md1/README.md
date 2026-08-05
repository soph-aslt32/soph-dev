# Keivax-md1

## ColorPallete

- #9a6ce2
- #825132
- #c9ae78
- #84b5ff
- #74931f
- #687c69
- #bab094
- #fffce5
- #68ba4a
- #b7c9c7
- #bc053f
- #ffca3a
- #ef40ac
- #24c955
- #7ce21d
- #60b6d6
- #3b51a0
- #5ee0e0
- #5bd8c1
- #30cca2
- #190615

```md
## 要件

UI部分について

- ダークテーマである．
- どちらかというと寒色を基調としたい．
- エディタ部分，サイドパネル，ターミナル等，各部分を隔てる境界線は無く，それぞれの背景は同じ色で配色されていて，全体が一色で統一されている．
- スクロールバーやミニマップの現在地は視認性を良くしたい（透明度が高すぎると困る）

tokenColors, semanticTokenColorsについて

- 現状はおそらくそうなっていない部分として，変数，型，モジュールの区別が文字色でつくようにしたい
- 変数，型，モジュール，関数等プログラム中頻出すると思われるものに関しては，それぞれの区別がつきやすい配色にしたい
- UI部分の配色と多少調和を考えたい（UI部分が寒色基調であるのに，文字色は暖色基調だと困る）
- コメントは主張の弱い色にしたい
```

---

## Color Usage

透明度付き（例：`#60b6d655`）も同色として記載しています。
UI は `colors` セクション、Token は `tokenColors` / `semanticTokenColors` セクションの使用箇所です。

---

### #190615
>
> 非常に暗い紫黒。UI 全体の統一背景色。

| カテゴリ | 使用箇所 |
|---|---|
| **UI** | `activityBar.background`, `button.secondaryBackground`, `debugToolBar.background`, `editor.background`, `editorGroupHeader.tabsBackground`, `notificationCenterHeader.background`, `panel.background`, `peekViewEditor.background`, `sideBar.background`, `sideBarSectionHeader.background`, `statusBar.background`, `statusBar.noFolderBackground`, `tab.inactiveBackground`, `titleBar.activeBackground`, `titleBar.inactiveBackground` |
| **Token** | — |

---

### #3b51a0
>
> ダークネイビー。アクセント・境界・バッジ・インタラクション状態の基色。

| カテゴリ | 使用箇所 |
|---|---|
| **UI** | `activityBarBadge.background`, `badge.background`, `button.background`, `button.secondaryHoverBackground`, `checkbox.border`, `dropdown.border`, `editor.inactiveSelectionBackground`, `editorInlayHint.background/parameterBackground/typeBackground`, `input.border`, `menu.border/separatorBackground`, `notifications.border`, `pickerGroup.border`, `settings.dropdownBorder`, `statusBar.debuggingBackground`, `statusBarItem.remoteBackground`, `tab.unfocusedActiveBorderTop`, `terminal.inactiveSelectionBackground`, `textSeparator.foreground`, `widget.border` |
| **Token** | — |

---

### #60b6d6
>
> スカイブルー。フォーカス・アクティブ状態・スクロールバー・ミニマップのメインアクセント色。

| カテゴリ | 使用箇所 |
|---|---|
| **UI** | `activityBar.activeBorder`, `button.border/hoverBackground`, `editorBracketHighlight.foreground2`, `editorBracketPairGuide.activeBackground2/background2`, `editorGutter.modifiedBackground`, `editorIndentGuide.activeBackground2/background2`, `editorInlayHint.foreground`, `focusBorder`, `inputOption.activeBackground/activeBorder`, `menu.selectionBackground`, `minimapSlider.*`, `panelTitle.activeBorder`, `progressBar.background`, `scrollbarSlider.*`, `statusBar.focusBorder`, `statusBarItem.focusBorder/hoverBackground`, `tab.activeBorderTop/lastPinnedBorder/selectedBorderTop`, `terminal.tab.activeBorder`, `textBlockQuote.border`, `textLink.foreground`, `welcomePage.progress.foreground` |
| **Token** | `markup.changed`, `meta.diff.header`, `storage.modifier.import.java` / `variable.language.wildcard.java` / `storage.modifier.package.java` ／ semantic: `namespace`, `module` |

---

### #b7c9c7
>
> 青みがかったライトグレー。エディタ・UI 全体のデフォルト文字色。

| カテゴリ | 使用箇所 |
|---|---|
| **UI** | `activityBar.foreground`, `badge.foreground`, `button.secondaryForeground`, `dropdown.foreground`, `editor.foreground`, `editorLineNumber.activeForeground`, `foreground`, `icon.foreground`, `input.foreground`, `keybindingLabel.foreground`, `menu.foreground`, `notificationCenterHeader.foreground`, `notifications.foreground`, `panelTitle.activeForeground`, `quickInput.foreground`, `sideBar/sideBarSectionHeader/sideBarTitle.foreground`, `statusBar.foreground`, `tab.selectedForeground`, `terminal.foreground`, `textPreformat.foreground`, `titleBar.activeForeground` |
| **Token** | `meta.embedded` / `source.groovy.embedded` / `string meta.image.inline.markdown` / `variable.legacy.builtin.python` |

---

### #687c69
>
> セージグリーン。コメント・非アクティブ・補助テキストの文字色。

| カテゴリ | 使用箇所 |
|---|---|
| **UI** | `activityBar.inactiveForeground`, `descriptionForeground`, `editorLineNumber.foreground`, `input.placeholderForeground`, `panelTitle.inactiveForeground`, `tab.inactiveForeground`, `titleBar.inactiveForeground` |
| **Token** | `comment`, `punctuation.definition.quote.begin.markdown`, `punctuation.definition.tag` |

---

### #fffce5
>
> クリームホワイト。強調・選択状態のテキスト色。

| カテゴリ | 使用箇所 |
|---|---|
| **UI** | `activityBarBadge.foreground`, `button.foreground`, `list.activeSelectionIconForeground`, `settings.headerForeground`, `statusBar.debuggingForeground`, `statusBarItem.hoverForeground/remoteForeground`, `tab.activeForeground` |
| **Token** | `header`, `markup.heading`, `entity.name.label` |

---

### #9a6ce2
>
> 紫。キーワード・ストレージ修飾子・ブラケット第1レイヤー。

| カテゴリ | 使用箇所 |
|---|---|
| **UI** | `editorBracketHighlight.foreground1`, `editorBracketPairGuide.activeBackground1/background1`, `editorIndentGuide.activeBackground1/background1` |
| **Token** | `meta.preprocessor` / `entity.name.function.preprocessor`, `storage`, `storage.type`, `storage.modifier` / `keyword.operator.noexcept`, `keyword`, `keyword.control`（単体）, `keyword.operator.new/.expression/.cast/.sizeof/.alignof/.typeid/.alignas/.instanceof/.logical.python/.wordlike`, `punctuation.definition.template-expression.*`, `punctuation.section.embedded.*`, `token.debug-token` ／ semantic: `keyword` |

---

### #ef40ac
>
> ホットピンク。制御フロー演算子・マクロ・ブラケット第4レイヤー。

| カテゴリ | 使用箇所 |
|---|---|
| **UI** | `editorBracketHighlight.foreground4`, `editorBracketPairGuide.activeBackground4/background4`, `editorIndentGuide.activeBackground4/background4` |
| **Token** | `keyword.control`（配列）/ `source.cpp keyword.operator.new` / `keyword.operator.delete` / `keyword.other.using/.directive.using/.operator` / `entity.name.operator` ／ semantic: `newOperator`, `macro` |

---

### #84b5ff
>
> 淡青。変数・リンク・インレイパラメータ・ミニマップ選択。

| カテゴリ | 使用箇所 |
|---|---|
| **UI** | `chat.slashCommandForeground`, `editor.selectionHighlightBackground`, `editorInlayHint.parameterForeground`, `minimap.selectionHighlight`, `textLink.activeForeground` |
| **Token** | `entity.name.tag`, `markup.bold`, `punctuation.definition.list.begin.markdown`, `meta.structure.dictionary.key.python`, `support.function.git-rebase`, `variable.language`, `variable` / `meta.definition.variable.name` / `support.variable` / `entity.name.variable` / `constant.other.placeholder`, `token.info-token` ／ semantic: `variable`, `selfParameter`, `clsParameter` |

---

### #5ee0e0
>
> シアン。型・クラス・インターフェース・ブラケット第6レイヤー。

| カテゴリ | 使用箇所 |
|---|---|
| **UI** | `editorBracketHighlight.foreground6`, `editorBracketPairGuide.activeBackground6/background6`, `editorIndentGuide.activeBackground6/background6`, `editorInlayHint.typeForeground` |
| **Token** | `support.class` / `support.type` / `entity.name.type` / `entity.name.namespace` / `entity.name.class` / `storage.type.*`（Go/C#/Java/Groovy）/ `entity.name.scope-resolution` / `entity.other.attribute` ／ semantic: `type`, `class`, `interface`, `enum` |

---

### #5bd8c1
>
> ティール。言語組み込み定数・型キャスト・継承クラス・const変数。

| カテゴリ | 使用箇所 |
|---|---|
| **UI** | — |
| **Token** | `constant.language`, `meta.type.cast.expr` / `meta.type.new.expr` / `support.constant.math/.dom/.json` / `entity.other.inherited-class` / `punctuation.separator.namespace.ruby`, `constant.character` / `constant.other.option` ／ semantic: `variable.readonly`, `typeParameter` |

---

### #30cca2
>
> ミント。数値リテラル・単位・Git SHA。

| カテゴリ | 使用箇所 |
|---|---|
| **UI** | — |
| **Token** | `constant.numeric` / `keyword.operator.plus.exponent` / `.minus.exponent`, `meta.preprocessor.numeric`, `keyword.other.unit`, `constant.sha.git-rebase` ／ semantic: `numberLiteral` |

---

### #68ba4a
>
> 緑。文字列リテラル・差分追加・Gutterの追加行。

| カテゴリ | 使用箇所 |
|---|---|
| **UI** | `editorBracketHighlight.foreground3`, `editorBracketPairGuide.activeBackground3/background3`, `editorGutter.addedBackground`, `editorIndentGuide.activeBackground3/background3`, `ports.iconRunningProcessForeground` |
| **Token** | `markup.inserted`, `meta.preprocessor.string`, `string` / `meta.embedded.assembly`, `string.tag`, `string.value`, `markup.inline.raw`, `support.constant.property-value/.font-name/.media-type/.media` / `constant.other.color.rgb-value` / `support.constant.color` ／ semantic: `stringLiteral` |

---

### #24c955
>
> 鮮緑。enum メンバー・定数変数。

| カテゴリ | 使用箇所 |
|---|---|
| **UI** | — |
| **Token** | `variable.other.enummember`（単体）, `variable.other.constant` / `variable.other.enummember`（配列）／ semantic: `enumMember` |

---

### #7ce21d
>
> ライムグリーン。エスケープシーケンス。

| カテゴリ | 使用箇所 |
|---|---|
| **UI** | — |
| **Token** | `constant.character.escape` |

---

### #ffca3a
>
> 黄。関数・メソッド名・検索ハイライト・ブラケット第5レイヤー。

| カテゴリ | 使用箇所 |
|---|---|
| **UI** | `editor.findMatchBackground`, `editorBracketHighlight.foreground5`, `editorBracketPairGuide.activeBackground5/background5`, `editorIndentGuide.activeBackground5/background5`, `minimap.findMatchHighlight`, `peekViewEditor/peekViewResult.matchHighlightBackground`, `settings.modifiedItemIndicator` |
| **Token** | `entity.name.function` / `support.function` / `support.constant.handlebars` / `source.powershell variable.other.member` / `entity.name.operator.custom-literal`, `keyword.operator.or.regexp` / `keyword.control.anchor.regexp`, `token.warn-token` ／ semantic: `customLiteral`, `function`, `method` |

---

### #bc053f
>
> ダークレッド。エラー・削除・正規表現。

| カテゴリ | 使用箇所 |
|---|---|
| **UI** | `editorGutter.deletedBackground`, `errorForeground`, `minimap.errorHighlight` |
| **Token** | `constant.regexp`, `invalid`, `markup.deleted`, `string.regexp`, `punctuation.definition.group.regexp` / `.assertion.regexp` / `.character-class.regexp` / `punctuation.character.set.begin/.end.regexp` / `keyword.operator.negation.regexp` / `support.other.parenthesis.regexp`, `constant.character.character-class.regexp` / `constant.other.character-class.set/.regexp` / `constant.character.set.regexp`, `token.error-token` |

---

### #c9ae78
>
> ゴールデン。オブジェクトキー・属性名・プロパティ・デコレータ。

| カテゴリ | 使用箇所 |
|---|---|
| **UI** | `chat.editedFileForeground` |
| **Token** | `entity.name.tag.css` / `.less`, `entity.other.attribute-name`, `keyword.operator.quantifier.regexp`, `meta.object-literal.key` ／ semantic: `property`, `decorator` |

---

### #74931f
>
> オリーブ。CSS 属性名（クラス・ID・疑似クラス等）・CSS カスタムプロパティ。

| カテゴリ | 使用箇所 |
|---|---|
| **UI** | — |
| **Token** | `entity.other.attribute-name.class.css` / `.id.css` / `.parent-selector.css` / `.parent.less` / `.pseudo-class` / `.pseudo-element.css` / `.scss`, `support.type.vendored.property-name` / `support.type.property-name` / `source.css variable` / `source.coffee.embedded` |

---

### #825132
>
> ブラウン。テンプレートリテラル式の内部テキスト。

| カテゴリ | 使用箇所 |
|---|---|
| **UI** | — |
| **Token** | `meta.template.expression` |

---

### #bab094
>
> ウォームグレー。演算子・関数パラメータ名。

| カテゴリ | 使用箇所 |
|---|---|
| **UI** | — |
| **Token** | `keyword.operator` ／ semantic: `parameter` |
