# Argwrap.nvim

A simple Neovim plugin written in Lua that toggles wrapping and unwrapping of function or list arguments.

Inspired by [argwrap.vim](https://github.com/vim-scripts/argwrap.vim) by Alex Yatskov.

---

## Installation (with [lazy.nvim](https://github.com/folke/lazy.nvim))

Add this to your Lazy plugin list:

```lua
{
  "exdis/argwrap.nvim",
  keys = {
    { "<leader>a", function() require("argwrap").toggle() end, desc = "Toggle argument wrap" },
  },
  opts = {
    tail_comma = true,
    wrap_closing_brace = true,
    padded_braces = "",
    line_prefix = "",
  },
  config = function(_, opts)
    require("argwrap").setup(opts)
  end,
}
```

## Usage

Place the cursor inside a function call or container (like (), [], {}) and press <leader>a.

Example:

```
myfunc(foo, bar, baz)
```

After pressing <leader>a:

```
myfunc(
  foo,
  bar,
  baz
)

```

Press <leader>a again to unwrap:

```
myfunc(foo, bar, baz)
```

You can also run the command manually:

```vim
:ArgWrapToggle
```

## Configuration

You can control behavior with these options:

| Option               | Type      | Default | Description                                        |
| -------------------- | --------- | ------- | -------------------------------------------------- |
| `tail_comma`         | `boolean` | `false` | Add a trailing comma when wrapping.                |
| `wrap_closing_brace` | `boolean` | `true`  | Put the closing brace on a new line.               |
| `padded_braces`      | `string`  | `""`    | Add space padding for listed braces (e.g. `"()"`). |
| `line_prefix`        | `string`  | `""`    | Optional text prefix for each wrapped line.        |

Example custom setup:

```lua
require("argwrap").setup({
  tail_comma = false,
  wrap_closing_brace = false,
  padded_braces = "(){}",
  line_prefix = "  ",
})
```

## Requirements

* Neovim 0.8.0 or newer
* No external dependencies

## License

MIT
