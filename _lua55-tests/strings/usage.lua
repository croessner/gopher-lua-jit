-- Typical string processing idioms combining several library functions.
-- Hand written; must pass unmodified under the reference interpreter.

local function split(s, sep)
  local out = {}
  for field in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do
    out[#out + 1] = field
  end
  return out
end

local parts = split("a,b,,c", ",")
assert(#parts == 4 and parts[1] == "a" and parts[3] == "" and parts[4] == "c")
parts = split("1.2.3", ".")
assert(#parts == 3 and parts[2] == "2")

-- trimming
local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
assert(trim("  \t hello world \n") == "hello world")
assert(trim("") == "" and trim("   ") == "" and trim("x") == "x")
assert(("  x  "):match("^%s*(.-)%s*$") == "x")

-- template expansion with a table and with a function
local vars = {name = "Lua", version = 5.5, int = 7}
assert(("$name $version ($int) $missing"):gsub("%$(%w+)", vars) == "Lua 5.5 (7) $missing")
local expanded, n = ("${a}+${b}"):gsub("%${(%w+)}", function(k) return k:upper():rep(2) end)
assert(expanded == "AA+BB" and n == 2)

-- URL encoding and decoding
local function urlencode(s)
  return (s:gsub("[^%w%-_%.~]", function(c) return string.format("%%%02X", c:byte()) end))
end
local function urldecode(s)
  return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end
local raw = "a b&c=d/\u{E4}"
assert(urlencode(raw) == "a%20b%26c%3Dd%2F%C3%A4")
assert(urldecode(urlencode(raw)) == raw)

-- hex dump and back
local function tohex(s) return (s:gsub(".", function(c) return ("%02x"):format(c:byte()) end)) end
local function fromhex(h) return (h:gsub("%x%x", function(b) return string.char(tonumber(b, 16)) end)) end
assert(tohex("\0\1\255Az") == "0001ff417a")
assert(fromhex(tohex("binary\0data\200")) == "binary\0data\200")

-- key/value parsing with captures and position captures
local conf = {}
for k, v in ("host = example.org\nport=8080\n# comment\n  debug = true  \n"):gmatch("%s*([%w_]+)%s*=%s*([^\n]-)%s*\n") do
  conf[k] = v
end
assert(conf.host == "example.org" and conf.port == "8080" and conf.debug == "true")
local starts = {}
for pos in ("one two  three"):gmatch("()%a+") do starts[#starts + 1] = pos end
assert(#starts == 3 and starts[1] == 1 and starts[2] == 5 and starts[3] == 10)
assert(math == nil or math.type == nil or math.type(starts[1]) == "integer")

-- numbers embedded in text keep their subtype when converted back
local sum = 0
for num in ("10 20 30.5"):gmatch("[%d.]+") do sum = sum + tonumber(num) end
assert(sum == 60.5)
assert(string.format("%d items, %5.1f%%, %s", 3, 99.5, true) == "3 items,  99.5%, true")
assert(string.format("%-6s|%6s|%06.2f|%+d|%x", "ab", "cd", 3.14159, 5, 255) == "ab    |    cd|003.14|+5|ff")
assert(string.format("%q", "line1\nline2\0end") == '"line1\\\nline2\\0end"')

-- binary records with string.pack / string.unpack
local rec = string.pack("<I2 i4 s1 z d", 513, -2, "name", "tail", 0.5)
assert(#rec == 2 + 4 + 5 + 5 + 8)
local id, delta, name, tail, ratio, nextpos = string.unpack("<I2 i4 s1 z d", rec)
assert(id == 513 and delta == -2 and name == "name" and tail == "tail" and ratio == 0.5 and nextpos == #rec + 1)
assert(string.packsize("<I2 i4") == 6 and string.packsize("!4 I2 i4") == 8)
local items = {}
local pos = 1
local stream = string.pack(">I1I1I1", 7, 8, 9)
while pos <= #stream do
  items[#items + 1], pos = string.unpack(">I1", stream, pos)
end
assert(#items == 3 and items[3] == 9)

-- utf8 helpers
local text = "na\u{EF}ve \u{20AC}5 \u{1D11E}"
assert(utf8.len(text) == 10 and #text == 16)
local cps = {}
for _, cp in utf8.codes(text) do cps[#cps + 1] = cp end
assert(#cps == 10 and cps[3] == 0xEF and cps[10] == 0x1D11E)
local rebuilt = {}
for i = 1, #cps do rebuilt[i] = utf8.char(cps[i]) end
assert(table.concat(rebuilt) == text)
assert(utf8.char(72, 228, 8364) == "H\u{E4}\u{20AC}")
-- substring by character positions
local function usub(s, i, j) return s:sub(utf8.offset(s, i), utf8.offset(s, j + 1) - 1) end
assert(usub(text, 3, 5) == "\u{EF}ve")
-- reverse by characters
local chars = {}
for ch in text:gmatch(utf8.charpattern) do table.insert(chars, 1, ch) end
assert(table.concat(chars) == "\u{1D11E} 5\u{20AC} ev\u{EF}an")
assert(utf8.len("\xff") == nil and select("#", utf8.len("\xff")) == 2)

-- methods through the string metatable
local s = "Hello"
assert(s:len() == 5 and s:lower() == "hello" and s:upper() == "HELLO" and s:reverse() == "olleH")
assert(s:byte(1) == 72 and s:sub(2, -2) == "ell" and s:rep(2, "-") == "Hello-Hello")
assert(s:find("l", 1, true) == 3 and s:match("^(H)(.*)$") == "H")
assert(("%d-%s"):format(1, "x") == "1-x")
assert(#s == 5 and s .. 1 == "Hello1")
