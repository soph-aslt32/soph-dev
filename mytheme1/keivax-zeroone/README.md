# keivax-Z1

A minimal, dark color theme for Visual Studio Code built around a tight five-color palette.

## Color Palette

| Color | Hex | Role |
|-------|-----|------|
| <img src="https://placehold.co/16x16/0c110f/0c110f" alt=""> | `#0c110f` | **Background** — Main editor and all docked UI surfaces |
| <img src="https://placehold.co/16x16/1d1721/1d1721" alt=""> | `#1d1721` | **Float Background** — Menus, hover widgets, notifications, peek views, and other floating elements |
| <img src="https://placehold.co/16x16/d135fc/d135fc" alt=""> | `#d135fc` | **Primary Accent** — Selections, highlights, scrollbar, badges, active borders, control-flow keywords |
| <img src="https://placehold.co/16x16/54a5d3/54a5d3" alt=""> | `#54a5d3` | **Secondary Accent** — Links, info indicators, keywords, storage types, constants |
| <img src="https://placehold.co/16x16/d84187/d84187" alt=""> | `#d84187` | **Tertiary Accent** — Errors, find-match highlights, invalid tokens, delete markers |

## Design Principles

- **Borderless by default** — Nearly all borders are fully transparent. Panel boundaries appear only on hover via the resize sash (`sash.hoverBorder`).
- **Two-tier backgrounds** — Docked elements share the deep dark `#0c110f`; floating elements use the slightly warmer `#1d1721` to create subtle depth.
- **Transparency over color** — UI states (selection, hover, focus) are expressed through varying alpha levels of the accent colors rather than introducing new hues.
- **Standalone token colors** — All syntax highlighting rules are self-contained (no `include`), combining the full set from `dark_vs` and `dark_plus` with palette-aligned overrides.

## Syntax Highlighting

Token colors are tuned for **Rust**, **Python**, **Java**, and **C++**:

| Element | Color | Style |
|---------|-------|-------|
| Control flow (`if`, `for`, `match`, `return`) | `#d135fc` | *italic* |
| Keywords & storage (`fn`, `let`, `struct`, `class`) | `#54a5d3` | *italic* |
| Storage modifiers (`pub`, `mut`, `static`, `async`) | `#54a5d3` | *italic* |
| `self` / `this` / `super` | `#54a5d3` | *italic* |
| Types & classes | `#4EC9B0` | |
| Functions | `#DCDCAA` | |
| Variables & parameters | `#9CDCFE` | |
| Constants & enums | `#4FC1FF` | |
| Strings | `#ce9178` | |
| Numbers | `#b5cea8` | |
| Comments | `#6A9955` | |
| Invalid | `#d84187` | **bold** |
| Preprocessor directives | `#54a5d3` | **bold** |

## Recommended Settings

For the best experience with the borderless design, increase the sash (resize handle) width in your `settings.json`:

```json
"workbench.sash.size": 6
```

## License

MIT
