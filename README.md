# lusoup

A lightweight HTML parser and scraping library for Lua, inspired by Python's BeautifulSoup. Written in 100% pure Lua with zero external dependencies, it runs on Lua 5.1 to 5.4 and LuaJIT.

Its parser implements the [WHATWG HTML parsing algorithm](https://html.spec.whatwg.org/multipage/parsing.html), so it builds the same trees as browsers do, even from broken HTML: it passes all of the [html5lib tree-construction tests](#testing).

---

## Features

- Standards-compliant parsing: unclosed and misnested tags, tables, forms, `<template>`, SVG and MathML are handled as browsers handle them. Whole documents or fragments, in any context element.
- CSS Selectors: Classes (.btn), IDs (#main), nested chains (ul > li), comma lists (h1, h2), pseudo-classes (:first-child, :last-child), and attribute matchers ([href^=https], [src$=.png], [data*=val]).
- Syntactic Sugar: Direct dot-notation node access (soup.head.title, soup.body.div.h1).
- DOM Navigation: Flexible tree traversal with :parent_node(), :next_sibling(), :prev_sibling(), :closest(), and :children_nodes().
- Entity Decoding: All of HTML5's named character references (&amp;, &eacute;, &NotEqualTilde;, ...) and numeric ones, decoded while parsing, and available on their own as `lusoup.entities.decode()`.
- Tree Mutation: Clean tag removal using :decompose().
- Serialization: Clean HTML reconstruction via :inner_html() and :outer_html().

---

## Installation

Install via LuaRocks:

```bash
luarocks install lusoup
```

Or build locally:

```bash
sudo luarocks make

```

---

## Quickstart

```lua
local lusoup = require("lusoup")

local html = [[
<div class="product-card" id="card-1">
    <h2 class="title">Scraping with <span class="highlight">Lusoup</span></h2>
    <a href="https://example.com/item" class="btn primary" target="_blank">Order Now</a>
</div>
]]

local soup = lusoup.parse(html)

-- Direct Property Access
print(soup.div.h2:text()) --> Scraping with Lusoup

-- CSS Selectors
local link = soup:select_one("a[href^=https]")
print(link:attr("href"))  --> https://example.com/item
print(link:text())        --> Order Now

-- Closest Parent Matching
local card = link:closest("div")
print(card:attr("id"))    --> card-1

```

---

## Parsing

`lusoup.parse(html, options)` parses a fragment, as if setting `innerHTML`
on an element: by default a `<body>`. The result is a `document` node whose
children are the fragment's top-level nodes.

`lusoup.parse_document(html, options)` parses a whole document: the result
holds the doctype, if any, and an `<html>` element with its `<head>` and
`<body>`, whether or not they were written out.

Both take an optional table of options:

| Option | Default | Meaning |
|---|---|---|
| `comments` | `false` | Keep comments as `#comment` nodes. |
| `scripting` | `true` | Parse as if scripting is enabled, as browsers do; this makes `<noscript>`'s content text. |
| `context` | `"body"` | `parse()` only: the element the fragment is parsed in, e.g. `"td"`, `"title"` or `"svg path"`. |

Nodes have a `tag`: an element's name (lowercase, except for some SVG
names such as `foreignObject`), or `"#text"`, `"#comment"`, `"#doctype"`,
`"#processing-instruction"` or `"document"`. Text and comments keep their
content in `text_content`, already decoded; a processing instruction has a
`target`, and its data in `text_content`. SVG and MathML elements have `namespace` set to `"svg"` or
`"math"`. A `<template>`'s children are in its `content`.

As in browsers, a boolean attribute such as `<input disabled>` has the value
`""`, so test it with `node:attr("disabled") ~= nil`.

---

## Scraping with lureq

```lua
local lureq = require("lureq")
local lusoup = require("lusoup")

local res = lureq.get("https://news.ycombinator.com/")
if res and res.ok then
    local soup = lusoup.parse(res.text)
    local items = soup:select("span.titleline > a")

    for i = 1, math.min(#items, 5) do
        print(string.format("%d. %s (%s)", i, items[i]:text(), items[i]:attr("href")))
    end
end

```

---

## Testing

The tests use [busted](https://lunarmodules.github.io/busted/):

```bash
luarocks test             # or just: busted
```

Anything after `--` goes to `busted` (check `busted --help` for options).

For example, to list each test by name instead of just by dot:

```bash
luarocks test -- -o TAP
```

or to test under a particular Lua version:

```bash
luarocks test -- --lua=lua5.4
```


or to run only the tests whose names match a Lua pattern, such as the
tests of querying nodes (attributes, text, selectors and navigation):

```bash
luarocks test -- --filter="^Node"
```


### Parser Conformance

To test the parser's conformance with the HTML5 spec, fetch the HTML
parser tests from [web-platform-tests](https://github.com/web-platform-tests/wpt/tree/master/html/syntax/parsing),
then run the tests as usual:

```bash
spec/conformance/fetch.sh
luarocks test             # or just: busted
```

These are the html5lib tree-construction tests, the de facto conformance
suite for HTML parsers, used by browsers and parser authors; they're now
maintained in web-platform-tests. The script fetches them into
`spec/conformance/cases/`, at the commit pinned in
`spec/conformance/wpt-commit`. To move to WPT's latest tests, which picks up
new tests and drops removed ones:

```bash
spec/conformance/fetch.sh -u
```

The parser tests include some limited fuzzing, but with a fixed seed. For real extensive fuzzing:

```bash
lua spec/fuzz.lua -n 100000 [-s seed]
```

---

## License
```
MIT License © 2026
```
