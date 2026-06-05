# GridCodec Schema Language — VS Code / Cursor Extension

Syntax highlighting for `.grid` schema definition files used by [GridCodec](https://github.com/the-gridai/grid_codec).

## Features

- Syntax highlighting for all `.grid` constructs: `@syntax`, `schema`, `struct`, `enum`, `type`, `group`, `batch`
- Import statement highlighting with string paths
- Field declarations with type references and options (`wire_format`, `since`, `default`, `presence`, `value`)
- Built-in type recognition (u8–u64, i8–i64, f32/f64, uuid, string8/16/32, decimal, timestamp, etc.)
- User-defined type references (enums, composites)
- Comment highlighting (`#` line comments)
- Auto-closing brackets, auto-indent, and folding

## Installation

### From the repo (symlink)

```bash
ln -sf /path/to/grid_codec/editors/vscode-grid \
  ~/.cursor/extensions/the-gridai.vscode-grid-0.1.0
```

Restart Cursor / VS Code after linking.

### Manual copy

Copy the `editors/vscode-grid/` directory to your extensions folder:

```bash
cp -r editors/vscode-grid ~/.cursor/extensions/the-gridai.vscode-grid-0.1.0
# or for VS Code:
cp -r editors/vscode-grid ~/.vscode/extensions/the-gridai.vscode-grid-0.1.0
```
