-- lusoup's API. How HTML is parsed into trees is covered by the html5lib
-- tests (spec/html5lib_spec.lua); these cover what's lusoup's own: the
-- parsing entry points and their options, the Node API, serialization and
-- entity decoding.
local lusoup = require("lusoup")
local entities = require("lusoup.entities")

-- Serialize a node's subtree compactly, to compare tree shapes:
-- elements as tag(child,child), text nodes as their text in quotes.
local function shape(node)
    if node.tag == "#text" then
        return string.format("%q", node.text_content)
    elseif node.tag == "#comment" then
        return "<!--" .. node.text_content .. "-->"
    end
    local parts = {}
    for _, child in ipairs(node.children) do
        parts[#parts + 1] = shape(child)
    end
    return node.tag .. "(" .. table.concat(parts, ",") .. ")"
end

describe("parse()", function()
    it("returns a document node whose children are the fragment's top-level nodes", function()
        local soup = lusoup.parse("<p>Hello <b>world</b></p>text")
        assert.are.equal("document", soup.tag)
        assert.are.equal('document(p("Hello ",b("world")),"text")', shape(soup))
        assert.are.equal(soup, soup.children[1].parent)
    end)

    it("drops comments unless asked to keep them", function()
        assert.are.equal('document(p("ab"))', shape(lusoup.parse("<p>a<!-- c -->b")))
        assert.are.equal('document(p("a",<!-- c -->,"b"))',
            shape(lusoup.parse("<p>a<!-- c -->b", { comments = true })))
    end)

    it("parses in the context of another element", function()
        -- in a <tr>, a <td> needs no table around it
        assert.are.equal('document(td("x"))', shape(lusoup.parse("<td>x", { context = "tr" })))
        -- in a <title>, markup is text
        assert.are.equal('document("<b>x</b>")', shape(lusoup.parse("<b>x</b>", { context = "title" })))
        -- in SVG, elements are SVG elements
        local soup = lusoup.parse("<path/>", { context = "svg svg" })
        assert.are.equal("svg", soup.children[1].namespace)
    end)

    it("parses <noscript> as text with scripting on, and as markup with it off", function()
        assert.are.equal('document(noscript("<b>x</b>"))', shape(lusoup.parse("<noscript><b>x</b></noscript>")))
        assert.are.equal('document(noscript(b("x")))',
            shape(lusoup.parse("<noscript><b>x</b></noscript>", { scripting = false })))
    end)

    it("handles empty and missing input", function()
        assert.are.equal("document()", shape(lusoup.parse("")))
        assert.are.equal("document()", shape(lusoup.parse(nil)))
    end)
end)

describe("parse_document()", function()
    it("builds the <html>, <head> and <body> a document implies", function()
        local soup = lusoup.parse_document("<title>t</title><p>a")
        assert.are.equal('document(html(head(title("t")),body(p("a"))))', shape(soup))
    end)

    it("keeps the doctype as a node", function()
        local doctype = lusoup.parse_document("<!DOCTYPE html><p>a").children[1]
        assert.are.equal("#doctype", doctype.tag)
        assert.are.equal("html", doctype.name)
    end)
end)

describe("Node", function()
    it("reads attributes, case-insensitively and decoded", function()
        local a = lusoup.parse('<a HREF="?a=1&amp;b=2" class=btn hidden>x</a>'):select_one("a")
        assert.are.equal("?a=1&b=2", a:attr("href"))
        assert.are.equal("?a=1&b=2", a:attr("HREF"))
        assert.are.equal("btn", a:attr("class"))
        -- boolean attributes have an empty value, as in browsers
        assert.are.equal("", a:attr("hidden"))
        assert.is_nil(a:attr("title"))
    end)

    it("text() joins and collapses whitespace", function()
        local soup = lusoup.parse("<h2>Scraping  with\n<span>lusoup</span></h2>")
        assert.are.equal("Scraping with lusoup", soup:select_one("h2"):text())
    end)

    it("text() returns only the text", function()
        assert.are.equal(1, select("#", lusoup.parse("<p>a</p>"):select_one("p"):text()))
    end)

    it("text() doesn't decode text twice", function()
        assert.are.equal("&amp;", lusoup.parse("<p>&amp;amp;</p>"):select_one("p"):text())
    end)

    it("gives access to descendants by tag name", function()
        local soup = lusoup.parse("<div><h1>a</h1></div>")
        assert.are.equal("a", soup.div.h1:text())
    end)

    it("never looks up node fields as descendant tags", function()
        -- the root has no parent and elements have no text_content; reading
        -- those must not search the tree for a <parent> or <text_content> tag
        local soup = lusoup.parse("<div><parent></parent><text_content></text_content></div>")
        assert.is_nil(soup.parent)
        assert.is_nil(soup.div.text_content)
        assert.are.equal(soup, soup.div.parent)
        assert.are.equal("div", soup.div.tag)
    end)

    it("doesn't hang walking up to the root of a document with a <parent>", function()
        -- the parser climbs to the root for a stray end tag, and next_element()
        -- climbs to the root to start its search; both used to loop forever
        lusoup.parse("<parent></parent></x>")
        local soup = lusoup.parse("<div><parent></parent><p>a</p></div>")
        assert.is_nil(soup:select_one("p"):next_element())
    end)

    it("skips text and comments when listing child elements", function()
        local ul = lusoup.parse("<ul> <li>a</li> <!-- c --> <li>b</li> </ul>", { comments = true }).ul
        local children = ul:children_nodes()
        assert.are.equal(2, #children)
        assert.are.equal("li", children[1].tag)
        assert.are.equal(children[2], children[1]:next_sibling())
    end)

    it("selects with CSS selectors", function()
        local soup = lusoup.parse('<div id=card><a class="btn primary" href="https://x">go</a></div>')
        local a = soup:select_one("a[href^=https]")
        assert.are.equal("go", a:text())
        assert.are.equal(a, soup:select_one("#card > .btn"))
        assert.are.equal("card", a:closest("div"):attr("id"))
    end)
end)

describe("outer_html()", function()
    it("escapes text and attribute values", function()
        local p = lusoup.parse([[<p title='say "hi" &amp; go'>1 &lt; 2 &amp; 3&nbsp;4</p>]]):select_one("p")
        assert.are.equal('<p title="say &quot;hi&quot; &amp; go">1 &lt; 2 &amp; 3&nbsp;4</p>', p:outer_html())
    end)

    it("doesn't escape the text of script and style", function()
        local soup = lusoup.parse("<script>if (a < b && c) {}</script>")
        assert.are.equal("<script>if (a < b && c) {}</script>", soup:outer_html())
    end)

    it("writes void elements, comments and template contents", function()
        local soup = lusoup.parse("<br><!--c--><template><b>t</b></template>", { comments = true })
        assert.are.equal("<br /><!--c--><template><b>t</b></template>", soup:outer_html())
    end)

    it("writes processing instructions", function()
        local soup = lusoup.parse("<p><?php echo 1 ?></p>")
        local pi = soup.p.children[1]
        assert.are.equal("#processing-instruction", pi.tag)
        assert.are.equal("php", pi.target)
        assert.are.equal("<p><?php echo 1 ?></p>", soup:outer_html())
        assert.are.equal("", soup.p:text())
    end)

    it("round-trips well-formed HTML", function()
        local html = '<div class="a"><p>x <em>y</em></p><ul><li>1</li><li>2</li></ul></div>'
        assert.are.equal(html, lusoup.parse(html):outer_html())
    end)
end)

describe("entities.decode()", function()
    it("decodes named and numeric references", function()
        assert.are.equal('<a> & "b" AB', entities.decode("&lt;a&gt; &amp; &quot;b&quot; &#65;&#x42;"))
        assert.are.equal("caf\195\169 \226\128\148 \226\137\130\204\184",
            entities.decode("caf&eacute; &mdash; &NotEqualTilde;"))
    end)

    it("encodes numeric references as UTF-8, replacing invalid ones", function()
        assert.are.equal("\240\159\152\128", entities.decode("&#X1F600;"))
        assert.are.equal("\239\191\189\239\191\189\239\191\189", entities.decode("&#xD800;&#x110000;&#0;"))
        -- C1 control codes mean their windows-1252 characters
        assert.are.equal("\226\130\172", entities.decode("&#x80;"))
    end)

    it("decodes &nbsp; as a no-break space", function()
        assert.are.equal("a\194\160b", entities.decode("a&nbsp;b"))
    end)

    it("decodes legacy references without a semicolon, longest match first", function()
        assert.are.equal("\194\169 2024 & co", entities.decode("&copy 2024 &amp co"))
        assert.are.equal("\194\172it", entities.decode("&notit"))
        assert.are.equal("&mdash x &unknown;", entities.decode("&mdash x &unknown;"))
    end)

    it("leaves legacy references before = or alphanumerics alone in attribute mode", function()
        assert.are.equal("?a=1&copy=2&ampx&", entities.decode("?a=1&copy=2&ampx&amp", true))
    end)
end)
