# keivax-Z1

A minimal, dark color theme for Visual Studio Code.
Standalone design — no `include`, all token colors are self-contained.
Tuned for **Rust**, **Python**, **Java**, and **C++**.

---

## Main Color Palette

This theme is built on 13 custom-chosen colors:

| Swatch | Hex | Name |
|:------:|------|------|
| <img src="https://placehold.co/16x16/0c1314/0c1314" alt=""> | `#0c1314` | Background |
| <img src="https://placehold.co/16x16/1d1721/1d1721" alt=""> | `#1d1721` | Float |
| <img src="https://placehold.co/16x16/d135fc/d135fc" alt=""> | `#d135fc` | Primary Accent |
| <img src="https://placehold.co/16x16/54a5d3/54a5d3" alt=""> | `#54a5d3` | Secondary Accent |
| <img src="https://placehold.co/16x16/d84187/d84187" alt=""> | `#d84187` | Tertiary Accent |
| <img src="https://placehold.co/16x16/41cc3d/41cc3d" alt=""> | `#41cc3d` | Green |
| <img src="https://placehold.co/16x16/bc094b/bc094b" alt=""> | `#bc094b` | Crimson |
| <img src="https://placehold.co/16x16/26d3d0/26d3d0" alt=""> | `#26d3d0` | Cyan |
| <img src="https://placehold.co/16x16/7758e8/7758e8" alt=""> | `#7758e8` | Purple |
| <img src="https://placehold.co/16x16/c318f7/c318f7" alt=""> | `#c318f7` | Magenta |
| <img src="https://placehold.co/16x16/7456f7/7456f7" alt=""> | `#7456f7` | Blue-Violet |
| <img src="https://placehold.co/16x16/53d6bc/53d6bc" alt=""> | `#53d6bc` | Mint |
| <img src="https://placehold.co/16x16/cbd358/cbd358" alt=""> | `#cbd358` | Yellow-Green |

---

## Design Principles

- **Borderless** — All panel borders are transparent (`#d135fc00`). Boundaries appear only on hover via `sash.hoverBorder`.
- **Two-tier backgrounds** — Docked UI uses `#0c1314`; floating elements (menus, widgets, notifications) use `#1d1721`.
- **Transparency over color** — UI states are expressed through alpha levels of accent colors.

---

## Base Colors

| Swatch | Hex | Role |
|:------:|------|------|
| <img src="https://placehold.co/16x16/0c1314/0c1314" alt=""> | `#0c1314` | **Background** — Editor, sidebar, activity bar, panels |
| <img src="https://placehold.co/16x16/1d1721/1d1721" alt=""> | `#1d1721` | **Float** — Menus, hover widgets, notifications, peek views |
| <img src="https://placehold.co/16x16/cccccc/cccccc" alt=""> | `#cccccc` | **Foreground** — Default UI text |
| <img src="https://placehold.co/16x16/d4d4d4/d4d4d4" alt=""> | `#d4d4d4` | **Editor Foreground** — Source code default text |

## UI Accent Colors

| Swatch | Hex | Role |
|:------:|------|------|
| <img src="https://placehold.co/16x16/d135fc/d135fc" alt=""> | `#d135fc` | **Primary** — Focus, selection, scrollbar, badges, progress bar, highlights |
| <img src="https://placehold.co/16x16/54a5d3/54a5d3" alt=""> | `#54a5d3` | **Secondary** — Links, info indicators, suggest highlight, git modified |
| <img src="https://placehold.co/16x16/d84187/d84187" alt=""> | `#d84187` | **Tertiary** — Errors, find-match, validation errors, list filter mismatch |
| <img src="https://placehold.co/16x16/cca700/cca700" alt=""> | `#cca700` | **Warning** — Validation warnings, editor warnings, marker navigation |

---

## Syntax Highlighting (tokenColors)

8-color palette for syntax tokens:

| Swatch | Hex | Name | Scopes | Style |
|:------:|------|------|--------|-------|
| <img src="https://placehold.co/16x16/41cc3d/41cc3d" alt=""> | `#41cc3d` | Green | Comments, `markup.inserted` | — |
| <img src="https://placehold.co/16x16/bc094b/bc094b" alt=""> | `#bc094b` | Crimson | Strings, regex, invalid, `markup.deleted` | **bold** (invalid) |
| <img src="https://placehold.co/16x16/26d3d0/26d3d0" alt=""> | `#26d3d0` | Cyan | Types, classes, namespaces, `markup.changed` | — |
| <img src="https://placehold.co/16x16/7758e8/7758e8" alt=""> | `#7758e8` | Purple | Keywords, storage, modifiers, `self`/`this`, tags, constants, preprocessor | *italic* / **bold** |
| <img src="https://placehold.co/16x16/c318f7/c318f7" alt=""> | `#c318f7` | Magenta | Control flow (`if`, `for`, `return`), `new`/`delete`, template expressions | *italic* |
| <img src="https://placehold.co/16x16/7456f7/7456f7" alt=""> | `#7456f7` | Blue-Violet | Numbers, enum members, units, constant.sha | — |
| <img src="https://placehold.co/16x16/53d6bc/53d6bc" alt=""> | `#53d6bc` | Mint | Variables, parameters, properties, attributes, dict keys | — |
| <img src="https://placehold.co/16x16/cbd358/cbd358" alt=""> | `#cbd358` | Yellow-Green | Functions, support functions | — |

### Supplementary Token Colors

Legacy/specialized scopes that retain their own colors:

| Swatch | Hex | Scopes |
|:------:|------|--------|
| <img src="https://placehold.co/16x16/d7ba7d/d7ba7d" alt=""> | `#d7ba7d` | CSS tag names, character escapes, regex quantifiers |
| <img src="https://placehold.co/16x16/d16969/d16969" alt=""> | `#d16969` | `string.regexp`, character classes |
| <img src="https://placehold.co/16x16/646695/646695" alt=""> | `#646695` | `constant.regexp` |
| <img src="https://placehold.co/16x16/000080/000080" alt=""> | `#000080` | Header |
| <img src="https://placehold.co/16x16/808080/808080" alt=""> | `#808080` | Tag brackets (`punctuation.definition.tag`) |
| <img src="https://placehold.co/16x16/C8C8C8/C8C8C8" alt=""> | `#C8C8C8` | Labels (`entity.name.label`) |
| <img src="https://placehold.co/16x16/D4D4D4/D4D4D4" alt=""> | `#D4D4D4` | Foreground reset (embedded, operators, template expressions) |

### Semantic Token Colors

| Swatch | Hex | Token |
|:------:|------|-------|
| <img src="https://placehold.co/16x16/c318f7/c318f7" alt=""> | `#c318f7` | `newOperator` |
| <img src="https://placehold.co/16x16/bc094b/bc094b" alt=""> | `#bc094b` | `stringLiteral` |
| <img src="https://placehold.co/16x16/cbd358/cbd358" alt=""> | `#cbd358` | `customLiteral` |
| <img src="https://placehold.co/16x16/7456f7/7456f7" alt=""> | `#7456f7` | `numberLiteral` |

---

## Git / Diff Colors

| Swatch | Hex | Where | State |
|:------:|------|-------|-------|
| <img src="https://placehold.co/16x16/54a5d3/54a5d3" alt=""> | `#54a5d3cc` | Gutter / Overview Ruler / Minimap | Modified |
| <img src="https://placehold.co/16x16/41cc3d/41cc3d" alt=""> | `#41cc3dcc` | Gutter / Overview Ruler / Minimap | Added |
| <img src="https://placehold.co/16x16/bc094b/bc094b" alt=""> | `#bc094bcc` | Gutter / Overview Ruler / Minimap | Deleted |

### Git Decoration (File Tree)

| Swatch | Hex | State |
|:------:|------|-------|
| <img src="https://placehold.co/16x16/81b88b/81b88b" alt=""> | `#81b88b` | Added |
| <img src="https://placehold.co/16x16/e2c08d/e2c08d" alt=""> | `#e2c08d` | Modified |
| <img src="https://placehold.co/16x16/c74e39/c74e39" alt=""> | `#c74e39` | Deleted / Stage Deleted |
| <img src="https://placehold.co/16x16/6c6cc4/6c6cc4" alt=""> | `#6c6cc4` | Conflicting |
| <img src="https://placehold.co/16x16/8c8c8c/8c8c8c" alt=""> | `#8c8c8c` | Ignored |
| <img src="https://placehold.co/16x16/73c991/73c991" alt=""> | `#73c991` | Untracked |
| <img src="https://placehold.co/16x16/8db9e2/8db9e2" alt=""> | `#8db9e2` | Submodule |

### Diff Editor

| Swatch | Hex | Role |
|:------:|------|------|
| <img src="https://placehold.co/16x16/587c0c/587c0c" alt=""> | `#587c0c22` | Inserted text background |
| <img src="https://placehold.co/16x16/d84187/d84187" alt=""> | `#d8418722` | Removed text background |

---

## Word Highlight

| Hex | Property |
|------|----------|
| `#d135fc38` | `wordHighlightBackground` |
| `#d135fc66` | `wordHighlightBorder` |
| `#d135fc50` | `wordHighlightStrongBackground` |
| `#d135fc88` | `wordHighlightStrongBorder` |

---

## Borders & Sash

| Hex | Property | Note |
|------|----------|------|
| `#d135fc55` | `sash.hoverBorder` | Resize handle — only visible on hover |
| `#d135fc33` | `focusBorder` | Focus ring |
| `#d135fc00` | `sideBar.border`, `panel.border`, `panelSection.border`, `terminal.border`, `editorGroup.border` | Fully transparent |
| `#00000000` | `tab.border`, `statusBar.border`, `titleBar.border`, `menu.border`, `notifications.border`, `widget.border`, `editorOverviewRuler.border` | Fully transparent |
| `#d135fc33` | `peekView.border`, `editorWidget.resizeBorder` | Subtle accent |

---

## Recommended Settings

For the borderless design, increase the sash width:

```json
"workbench.sash.size": 6
```

## License

MIT
