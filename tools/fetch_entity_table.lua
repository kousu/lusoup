-- usage: lua tools/fetch_entity_table.lua > lusoup/entity_table.lua

-- (not lusoup's: it needs the table this generates)
local function utf8_char(code)
    if code < 0x80 then
        return string.char(code)
    elseif code < 0x800 then
        return string.char(0xC0 + math.floor(code / 0x40), 0x80 + code % 0x40)
    elseif code < 0x10000 then
        return string.char(0xE0 + math.floor(code / 0x1000),
            0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
    end
    return string.char(0xF0 + math.floor(code / 0x40000), 0x80 + math.floor(code / 0x1000) % 0x40,
        0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
end

local URL = "https://html.spec.whatwg.org/entities.json"

local curl = assert(io.popen("curl -fsSL " .. URL))
local json = curl:read("*a")
assert(curl:close(), "couldn't download " .. URL)

local entities, names = {}, {}
for name, codepoints in json:gmatch('"&([%w;]+)":%s*{%s*"codepoints":%s*%[([%d,%s]*)%]') do
    local chars = {}
    for code in codepoints:gmatch("%d+") do
        chars[#chars + 1] = utf8_char(tonumber(code))
    end
    entities[name] = table.concat(chars)
    names[#names + 1] = name
end
assert(#names > 2000, "expected over 2000 entities in " .. URL .. ", found " .. #names)
table.sort(names)

local function lua_str(s)
    return '"' .. s:gsub('[%c"\\\128-\255]', function(c)
        if c == '"' or c == "\\" then
            return "\\" .. c
        end
        return "\\" .. c:byte()
    end) .. '"'
end

print([[
-- HTML5 named character references, generated from the WHATWG list
-- (]] .. URL .. [[) by tools/fetch_entity_table.lua.
-- Names ending in ";" need the semicolon; the others are the legacy ones
-- that may also be written without it. Do not edit by hand.]])
print("return {")
for _, name in ipairs(names) do
    print(("    [%s] = %s,"):format(lua_str(name), lua_str(entities[name])))
end
print("}")
