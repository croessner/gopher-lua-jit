-- The package library and require.

local function checkerr(expected, f, ...)
  local ok, msg = pcall(f, ...)
  assert(not ok, "expected an error containing: " .. expected)
  assert(type(msg) == "string" and msg:find(expected, 1, true), "unexpected message: " .. tostring(msg))
end

local function pack(...)
  return {n = select("#", ...), ...}
end

-- directory holding the fixture modules of this test
local dir = debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") .. "/modules/"

-- fields of the package table
assert(type(package.path) == "string" and type(package.cpath) == "string")
assert(type(package.loaded) == "table" and type(package.preload) == "table")
assert(type(package.searchers) == "table" and type(package.searchpath) == "function")
assert(type(package.loadlib) == "function")
assert(#package.searchers == 4)
for i = 1, 4 do assert(type(package.searchers[i]) == "function") end
assert(package.loaders == nil)

-- package.config: directory separator, path separator, mark, executable directory, ignore mark
local dirsep, pathsep, mark, execdir, igmark = package.config:match("^(.-)\n(.-)\n(.-)\n(.-)\n(.-)\n$")
assert((dirsep == "/" or dirsep == "\\") and pathsep == ";" and mark == "?" and execdir == "!" and igmark == "-")

-- package.loaded holds the standard libraries; require returns them
assert(package.loaded._G == _G and package.loaded.package == package)
assert(package.loaded.coroutine == coroutine and package.loaded.debug == debug)
assert(package.loaded.string == string and package.loaded.table == table)
assert(require("string") == string and require("_G") == _G and require("package") == package)
assert(select("#", require("string")) == 1)   -- no loader data for loaded modules
assert(require == package.loaded._G.require)

local default_path = package.path
package.path = dir .. "?.lua;" .. dir .. "?/init.lua"
package.cpath = ""

-- loading a module from a file: the loader gets the name and the file name
local r = pack(require("mod_simple"))
assert(r.n == 2 and type(r[1]) == "table" and r[2] == dir .. "mod_simple.lua")
local mod = r[1]
assert(mod.name == "mod_simple" and mod.file == dir .. "mod_simple.lua" and mod.nargs == 2)
assert(package.loaded.mod_simple == mod)
-- the second require returns the cached value only
r = pack(require("mod_simple"))
assert(r.n == 1 and r[1] == mod)
-- a module is loaded once ...
require("mod_counter") require("mod_counter")
assert(mod_counter_loads == 1)
-- ... until it is removed from package.loaded
package.loaded.mod_counter = nil
require("mod_counter")
assert(mod_counter_loads == 2)
mod_counter_loads = nil

-- submodules and init files
r = pack(require("sub.inner"))
assert(r.n == 2 and r[1] == "sub.inner:sub.inner" and r[2] == dir .. "sub/inner.lua")
assert(package.loaded["sub.inner"] == "sub.inner:sub.inner")
r = pack(require("mod_init"))
assert(r[1] == "init:mod_init" and r[2] == dir .. "mod_init/init.lua")

-- module results: nil becomes true, false is kept (and not cached as loaded)
r = pack(require("mod_nil"))
assert(r.n == 2 and r[1] == true and r[2] == dir .. "mod_nil.lua" and package.loaded.mod_nil == true)
assert(require("mod_nil") == true)
r = pack(require("mod_false"))
assert(r.n == 2 and r[1] == false and package.loaded.mod_false == false)
-- a module may register itself in package.loaded
assert(require("mod_setloaded") == "set by module" and package.loaded.mod_setloaded == "set by module")
-- values put into package.loaded by hand are returned
package.loaded.manual = 42
assert(require("manual") == 42)
package.loaded.manual = nil

-- package.preload
package.preload.pre = function(...) return {args = pack(...)} end
r = pack(require("pre"))
assert(r.n == 2 and r[2] == ":preload:")
assert(r[1].args.n == 2 and r[1].args[1] == "pre" and r[1].args[2] == ":preload:")
assert(select("#", require("pre")) == 1 and require("pre") == r[1])
package.preload.selfset = function(name) package.loaded[name] = "set by loader" return "returned" end
assert(require("selfset") == "returned" and package.loaded.selfset == "returned")
package.preload.selfset2 = function(name) package.loaded[name] = "set by loader" end
assert(require("selfset2") == "set by loader")
-- preload wins over files
package.preload.mod_error = function() return "preloaded instead" end
assert(require("mod_error") == "preloaded instead")
package.preload.mod_error = nil
package.loaded.mod_error = nil

-- failures
local ok, msg = pcall(require, "nonexistent.mod")
assert(not ok)
local expected = "module 'nonexistent.mod' not found:" ..
  "\n\tno field package.preload['nonexistent.mod']" ..
  "\n\tno file '" .. dir .. "nonexistent/mod.lua'" ..
  "\n\tno file '" .. dir .. "nonexistent/mod/init.lua'" ..
  "\n\tno file ''" ..
  "\n\tno file ''"
assert(msg == expected, msg)
ok, msg = pcall(require, "mod_syntax")
assert(not ok)
assert(msg == "error loading module 'mod_syntax' from file '" .. dir .. "mod_syntax.lua':\n\t" ..
              dir .. "mod_syntax.lua:1: unexpected symbol near '='", msg)
ok, msg = pcall(require, "mod_error")
assert(not ok and msg == dir .. "mod_error.lua:1: load failure", msg)
assert(package.loaded.mod_error == nil)
checkerr("string expected", require)
checkerr("string expected", require, {})

-- package.searchpath
assert(package.searchpath("mod_simple", package.path) == dir .. "mod_simple.lua")
assert(package.searchpath("sub.inner", package.path) == dir .. "sub/inner.lua")
assert(package.searchpath("mod_init", package.path) == dir .. "mod_init/init.lua")
r = pack(package.searchpath("zz", package.path))
assert(r.n == 2 and r[1] == nil)
assert(r[2] == "no file '" .. dir .. "zz.lua'\n\tno file '" .. dir .. "zz/init.lua'")
r = pack(package.searchpath("a.b", "x/?.lua;y/?", ".", "/"))
assert(r[1] == nil and r[2] == "no file 'x/a/b.lua'\n\tno file 'y/a/b'")
r = pack(package.searchpath("a.b", "x/?.lua", "", "/"))
assert(r[2] == "no file 'x/a.b.lua'")
r = pack(package.searchpath("a-b", "x/?.lua;y/?", "-", "+"))
assert(r[2] == "no file 'x/a+b.lua'\n\tno file 'y/a+b'")
r = pack(package.searchpath("m", ""))
assert(r[1] == nil and r[2] == "no file ''")
assert(package.searchpath("sub/inner", dir .. "?.lua", ".", "/") == dir .. "sub/inner.lua")
checkerr("string expected", package.searchpath)
checkerr("string expected", package.searchpath, "x")

-- the standard searchers
local searchers = package.searchers
assert(searchers[1]("zzz") == "no field package.preload['zzz']")
r = pack(searchers[1]("pre"))
assert(r.n == 2 and r[1] == package.preload.pre and r[2] == ":preload:")
assert(searchers[2]("zzz") == "no file '" .. dir .. "zzz.lua'\n\tno file '" .. dir .. "zzz/init.lua'")
r = pack(searchers[2]("mod_simple"))
assert(r.n == 2 and type(r[1]) == "function" and r[2] == dir .. "mod_simple.lua")
checkerr("error loading module 'mod_syntax' from file", searchers[2], "mod_syntax")
assert(searchers[3]("zzz") == "no file ''")
assert(searchers[4]("zzz") == nil)             -- not a submodule name
assert(searchers[4]("zzz.sub") == "no file ''")

-- custom searchers: loader data is passed to the loader and returned by require
table.insert(package.searchers, 2, function(name)
  if name == "custom" then
    return function(n, extra) return n .. "|" .. tostring(extra) end, "EXTRA"
  end
  return "no custom '" .. name .. "'"
end)
r = pack(require("custom"))
assert(r.n == 2 and r[1] == "custom|EXTRA" and r[2] == "EXTRA")
ok, msg = pcall(require, "zzz2")
assert(not ok and msg:find("\n\tno field package.preload['zzz2']\n\tno custom 'zzz2'\n\tno file '", 1, true), msg)
table.remove(package.searchers, 2)
-- searchers returning neither a function nor a string are skipped; numbers count as strings
table.insert(package.searchers, 1, function() return nil end)
table.insert(package.searchers, 1, function() return 42 end)
ok, msg = pcall(require, "zzz3")
assert(not ok and msg:find("module 'zzz3' not found:\n\t42\n\tno field package.preload['zzz3']", 1, true), msg)
table.remove(package.searchers, 1)
table.remove(package.searchers, 1)
assert(#package.searchers == 4)

-- require follows the current package.searchers and package.path
local saved = package.searchers
package.searchers = nil
checkerr("'package.searchers' must be a table", require, "zzz")
package.searchers = saved
local saved_path = package.path
package.path = nil
checkerr("'package.path' must be a string", require, "zzz")
package.path = saved_path

-- package.loadlib reports a failure with nil, a message and a failure kind
r = pack(package.loadlib("no_such_library_xyz", "luaopen_x"))
assert(r.n == 3 and r[1] == nil and type(r[2]) == "string")
assert(r[3] == "open" or r[3] == "init" or r[3] == "absent")
checkerr("string expected", package.loadlib)

package.path = default_path
