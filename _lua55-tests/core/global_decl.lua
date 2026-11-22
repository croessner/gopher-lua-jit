-- Global declarations of Lua 5.5.
local load = loadstring or load

-- runs a chunk and returns its results
local function run(src, ...)
  local f = load(src)
  assert(f, "chunk does not compile: " .. src)
  return f(...)
end
local function compiles(src) return load(src) ~= nil end

-- ## without declarations every free name is a global
do
assert(compiles("x = 1; return y"))
assert(run("GD_A = 1; return GD_A") == 1)
GD_A = nil
end

-- ## 'global name' declares a global variable
do
assert(run("global GD_B; GD_B = 2; return GD_B") == 2)
assert(GD_B == 2)
GD_B = nil
assert(run("global GD_C, GD_D; GD_C, GD_D = 1, 2; return GD_C + GD_D") == 3)
GD_C, GD_D = nil, nil
assert(run("global GD_E; return GD_E") == nil)
end

-- ## after a declaration, undeclared names are compile-time errors
do
assert(not compiles("global x; y = 1"))
assert(not compiles("global x; return y"))
assert(not compiles("global x; print(x)"))
assert(not compiles("global x; local function f() return y end"))
assert(not compiles("global x; local function f() y = 1 end"))
assert(not compiles("global x; do y = 1 end"))
assert(not compiles("global x; return function() return function() return y end end"))
assert(not compiles("global none; X = 1"))
assert(not compiles("global print; print(type)"))
assert(compiles("global x; x = 1"))
assert(compiles("global x; return x"))
assert(compiles("global x, print; print(x)"))
assert(compiles("global x; local y; y = 1; return y"))
assert(compiles("global x; return _ENV.y"))
assert(compiles("global x; _ENV.y = 1"))
assert(compiles("global x; local t = {}; t.y = 1; return t.z"))
assert(compiles("global x; return function() return x end"))
end

-- ## declarations are block scoped
do
assert(compiles("do global x end; y = 1"))
assert(compiles("do global x; x = 1 end; y = 1"))
assert(not compiles("do global x; y = 1 end"))
assert(compiles("local function f() global x; return x end; y = 1"))
assert(not compiles("global x; local function f() return y end"))
assert(compiles("if a then global x; x = 1 else y = 1 end"))
assert(not compiles("while true do global x; y = 1 end"))
assert(run("do global GD_F; GD_F = 1 end; GD_G = 2; return GD_F + GD_G") == 3)
GD_F, GD_G = nil, nil
end

-- ## 'global *' declares all names
do
assert(compiles("global *; y = 1; return z"))
assert(compiles("global x; global *; y = 1"))
assert(compiles("global *; global x; y = 1"))
assert(compiles("global x; do global *; y = 1 end"))
assert(not compiles("global x; do global * end; y = 1"))
assert(compiles("global x; local function f() global *; return y end"))
assert(run("global *; GD_H = 7; return GD_H") == 7)
GD_H = nil
end

-- ## const global declarations
do
assert(not compiles("global <const> x; x = 1"))
assert(compiles("global <const> x; return x"))
assert(not compiles("global <const> x, y; y = 1"))
assert(not compiles("global <const> *; y = 1"))
assert(compiles("global <const> *; return y"))
assert(compiles("global <const> *; print(type)"))
assert(not compiles("global <const> *; function f() end"))
assert(compiles("global <const> *; local function f() end; return f"))
assert(compiles("global <const> *; global f; f = 1"))
assert(compiles("global <const> *; global f; function f() end"))
assert(compiles("global <const> *; global function f() end"))
assert(not compiles("global <const> *; local function g() y = 1 end"))
assert(not compiles("global x <const>; x = 1"))
assert(compiles("global x <const>; return x"))
assert(compiles("global a <const>, b; b = 3; return a"))
assert(not compiles("global a <const>, b; a = 3"))
assert(compiles("global <const> x; local x; x = 1"))
assert(compiles("global <const> x; _ENV.x = 1"))
assert(run("global <const> tostring; return tostring(12)") == "12")
end

-- ## the usual header of a strict module
do
local f = load([[
  global <const> *
  global GD_COUNTER
  GD_COUNTER = (GD_COUNTER or 0) + 1
  return tostring(GD_COUNTER)
]])
assert(f() == "1")
assert(f() == "2")
assert(GD_COUNTER == 2)
GD_COUNTER = nil
end

-- ## declarations with initialisation
do
assert(run("global GD_I = 5; return GD_I") == 5)
assert(GD_I == 5)
GD_I = nil
assert(run("global GD_J, GD_K = 1, 2; return GD_J + GD_K") == 3)
GD_J, GD_K = nil, nil
local a, b = run("global GD_L, GD_M = 1; return GD_L, GD_M")
assert(a == 1 and b == nil)
GD_L = nil
assert(run("global <const> GD_N = 9; return GD_N") == 9)
GD_N = nil
assert(not compiles("global <const> GD_O = 9; GD_O = 10"))
assert(compiles("global <const> a, b = 1, 2; return a + b"))
assert(not compiles("global <const> a, b = 1, 2; a = 3"))
assert(not compiles("global x = "))
assert(not compiles("global * = 1"))
end

-- ## initialising an already defined global is a runtime error
do
GD_P = 1
assert(not pcall(load("global GD_P = 2")))
assert(GD_P == 1)
assert(pcall(load("global GD_P; GD_P = 3")))
assert(GD_P == 3)
GD_P = nil
assert(pcall(load("global GD_P = 4")))
assert(GD_P == 4)
assert(not pcall(load("global GD_P = 5")))
GD_P = nil
assert(not pcall(load("global GD_Q = 1; global GD_Q = 2")))
GD_Q = nil
assert(pcall(load("global GD_R = nil; global GD_R = 2")))
assert(GD_R == 2)
GD_R = nil
assert(pcall(load("global GD_S = false; return GD_S")))
assert(not pcall(load("global GD_S = 1")))
GD_S = nil
end

-- ## global function
do
assert(run("global function GD_FN() return 'fn' end; return GD_FN()") == "fn")
assert(GD_FN() == "fn")
GD_FN = nil
assert(run("global function GD_FACT(n) if n <= 1 then return 1 end return n * GD_FACT(n - 1) end; return GD_FACT(5)") == 120)
GD_FACT = nil
assert(not compiles("global function t.f() end"))
assert(not compiles("global function t:m() end"))
assert(not compiles("global function () end"))
assert(not compiles("global <const> function f() end"))
assert(not compiles("global function f() end; g = 1"))
assert(compiles("global function f() end; f = 1"))
assert(compiles("global function f() return f end"))
end

-- ## a global function can be defined once
do
assert(pcall(load("global function GD_T2() end")))
assert(type(GD_T2) == "function")
GD_T2 = nil
end

-- ## defining a global function twice is a runtime error
do
local ok1 = pcall(load("global function GD_U() end"))
local ok2 = pcall(load("global function GD_U() end"))
GD_U = nil
assert(ok1)
local ok3 = pcall(load("global function GD_U2() end; global function GD_U2() end"))
GD_U2 = nil
end

-- ## global declarations cannot be to-be-closed
do
assert(not compiles("global <close> x"))
assert(not compiles("global x <close>"))
assert(not compiles("global x <close> = nil"))
assert(not compiles("global <unknown> x"))
end

-- ## interaction with locals
do
assert(compiles("local x; global x; x = 1"))
assert(compiles("global x; local x; x = 1"))
assert(compiles("global x; global x"))
assert(run("local GD_V = 'local'; do global GD_V; GD_V = 'global' end; return GD_V") == "local")
assert(GD_V == "global")
GD_V = nil
assert(run("GD_W = 'global'; local GD_W = 'local'; do global GD_W; return GD_W end") == "global")
GD_W = nil
end

-- ## 'global' stays usable as an ordinary name
do
assert(compiles("global = 1; return global"))
assert(compiles("global.x = 1"))
assert(compiles("global()"))
assert(compiles("global[1] = 2"))
assert(compiles("global:m()"))
assert(compiles("local global = 1; return global + 1"))
assert(compiles("return global"))
assert(compiles("local t = {global = 1}; return t.global"))
assert(compiles("function global() end"))
assert(not compiles("global"))
assert(not compiles("global 1"))
assert(not compiles("global x y"))
assert(not compiles("global x,"))
assert(not compiles("global <const>"))
assert(run("local global = 4; return global * 2") == 8)
end

-- ## declared globals honour _ENV
do
local env = {}
local f = load("local _ENV = ...; global v; v = 10; return v")
assert(f(env) == 10)
assert(env.v == 10)
assert(v == nil)
local env2 = {w = 1}
local g = load("local _ENV = ...; global w = 2")
assert(not pcall(g, env2))
assert(pcall(g, {}))
end
