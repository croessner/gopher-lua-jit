-- Small complete programs combining several language features. They avoid
-- library functions beyond the basic ones and check exact results.
local T = tostring

-- ## sieve of Eratosthenes
do
local function sieve(n)
  local is = {}
  for i = 2, n do is[i] = true end
  for i = 2, n do
    if is[i] then
      for j = i * i, n, i do is[j] = false end
    end
  end
  local primes = {}
  for i = 2, n do if is[i] then primes[#primes + 1] = i end end
  return primes
end
local p = sieve(100)
assert(#p == 25)
assert(p[1] == 2 and p[25] == 97)
assert(#sieve(10000) == 1229)
end

-- ## n queens
do
local function queens(n)
  local count = 0
  local cols, d1, d2 = {}, {}, {}
  local function place(r)
    if r > n then count = count + 1; return end
    for c = 1, n do
      if not cols[c] and not d1[r + c] and not d2[r - c + n] then
        cols[c], d1[r + c], d2[r - c + n] = true, true, true
        place(r + 1)
        cols[c], d1[r + c], d2[r - c + n] = false, false, false
      end
    end
  end
  place(1)
  return count
end
assert(queens(6) == 4)
assert(queens(8) == 92)
end

-- ## quicksort with table swaps
do
local function qsort(t, lo, hi)
  lo, hi = lo or 1, hi or #t
  if lo < hi then
    local pivot = t[hi]
    local i = lo - 1
    for j = lo, hi - 1 do
      if t[j] <= pivot then
        i = i + 1
        t[i], t[j] = t[j], t[i]
      end
    end
    t[i + 1], t[hi] = t[hi], t[i + 1]
    qsort(t, lo, i)
    qsort(t, i + 2, hi)
  end
  return t
end
local data = {}
local seed = 12345
for i = 1, 500 do
  seed = (seed * 1103515245 + 12345) % 2147483648
  data[i] = seed % 1000
end
qsort(data)
for i = 2, #data do assert(data[i - 1] <= data[i], "sorted") end
assert(#data == 500)
end

-- ## binary search
do
local function bsearch(t, x)
  local lo, hi = 1, #t
  while lo <= hi do
    local mid = (lo + hi) // 2
    if t[mid] == x then return mid
    elseif t[mid] < x then lo = mid + 1
    else hi = mid - 1 end
  end
  return nil
end
local sorted = {}
for i = 1, 100 do sorted[i] = i * 3 end
assert(bsearch(sorted, 3) == 1)
assert(bsearch(sorted, 150) == 50)
assert(bsearch(sorted, 300) == 100)
assert(bsearch(sorted, 151) == nil)
assert(T(bsearch(sorted, 150)) == "50")
end

-- ## 64-bit FNV-1a hash relies on wrap-around multiplication
do
local function fnv1a(s)
  local h = 0xcbf29ce484222325
  for i = 1, #s do
    h = h ~ s:byte(i)
    h = h * 0x100000001b3
  end
  return h
end
assert(fnv1a("") == -3750763034362895579)
assert(fnv1a("a") == -5808556873153909620)
assert(fnv1a("hello") == -6615550055289275125)
assert(string.format("%d", fnv1a("foobar")) == "-8821353812377114648")
end

-- ## xorshift pseudo random numbers
do
local function xorshift(state)
  state = state ~ (state << 13)
  state = state ~ (state >> 7)
  state = state ~ (state << 17)
  return state
end
local s = 88172645463325252
s = xorshift(s)
assert(s == 8748534153485358512)
s = xorshift(s)
assert(s == 3040900993826735515)
s = xorshift(s)
assert(s == 3453997556048239312)
end

-- ## population count and bit reversal
do
local function popcount(x)
  local n = 0
  while x ~= 0 do
    n = n + (x & 1)
    x = x >> 1
  end
  return n
end
assert(popcount(0) == 0)
assert(popcount(255) == 8)
assert(popcount(-1) == 64)
assert(popcount(0x5555555555555555) == 32)
assert(popcount(1 << 63) == 1)
local function reverse_bits(x)
  local r = 0
  for _ = 1, 64 do
    r = (r << 1) | (x & 1)
    x = x >> 1
  end
  return r
end
assert(reverse_bits(1) == 1 << 63)
assert(reverse_bits(1 << 63) == 1)
assert(reverse_bits(-1) == -1)
assert(reverse_bits(0xF0) == 0x0F00000000000000)
end

-- ## base conversion with floor division and modulo
do
local function to_base(n, b)
  local digits = "0123456789abcdef"
  if n == 0 then return "0" end
  local neg = n < 0
  if neg then n = -n end
  local out = ""
  while n > 0 do
    local d = n % b
    out = digits:sub(d + 1, d + 1) .. out
    n = n // b
  end
  return (neg and "-" or "") .. out
end
assert(to_base(255, 16) == "ff")
assert(to_base(255, 2) == "11111111")
assert(to_base(-10, 2) == "-1010")
assert(to_base(9223372036854775807, 16) == "7fffffffffffffff")
assert(to_base(1000000, 10) == "1000000")
end

-- ## greatest common divisor and least common multiple
do
local function gcd(a, b)
  while b ~= 0 do
    local r = a % b
    a = b
    b = r
  end
  return a
end
assert(gcd(48, 18) == 6)
assert(gcd(17, 5) == 1)
assert(gcd(0, 9) == 9)
assert(gcd(1071, 462) == 21)
assert(gcd(2^40 // 1, 2^20 // 1) == 1048576)
local function lcm(a, b) return a // gcd(a, b) * b end
assert(lcm(4, 6) == 12)
assert(T(lcm(21, 6)) == "42")
end

-- ## collatz with integer arithmetic
do
local function collatz(n)
  local steps = 0
  while n ~= 1 do
    if n % 2 == 0 then n = n // 2 else n = 3 * n + 1 end
    steps = steps + 1
  end
  return steps
end
assert(collatz(1) == 0)
assert(collatz(27) == 111)
assert(collatz(97) == 118)
end

-- ## exact integer factorials and their float counterparts
do
local function fact(n) local r = 1; for i = 2, n do r = r * i end; return r end
assert(fact(20) == 2432902008176640000)
assert(T(fact(20)) == "2432902008176640000")
assert(fact(21) == -4249290049419214848)
local function ffact(n) local r = 1.0; for i = 2, n do r = r * i end; return r end
assert(T(ffact(20)) == "2.43290200817664e+18")
assert(T(ffact(25)) == "1.5511210043330986e+25")
assert(ffact(20) == fact(20))
end

-- ## matrix multiplication
do
local function matmul(a, b)
  local n, m, p = #a, #b, #b[1]
  local c = {}
  for i = 1, n do
    c[i] = {}
    for j = 1, p do
      local s = 0
      for k = 1, m do s = s + a[i][k] * b[k][j] end
      c[i][j] = s
    end
  end
  return c
end
local m = matmul({{1, 2}, {3, 4}}, {{5, 6}, {7, 8}})
assert(m[1][1] == 19 and m[1][2] == 22 and m[2][1] == 43 and m[2][2] == 50)
local id = matmul({{1, 0}, {0, 1}}, {{2.5, 0}, {0, 2.5}})
assert(T(id[1][1]) == "2.5" and T(id[1][2]) == "0.0")
local function matpow(a, n)
  local r = {{1, 0}, {0, 1}}
  while n > 0 do
    if n % 2 == 1 then r = matmul(r, a) end
    a = matmul(a, a)
    n = n // 2
  end
  return r
end
assert(matpow({{1, 1}, {1, 0}}, 90)[1][2] == 2880067194370816120)
end

-- ## memoisation with closures
do
local function memoize(f)
  local cache = {}
  return function(n)
    local v = cache[n]
    if v == nil then v = f(n); cache[n] = v end
    return v
  end
end
local calls = 0
local fib
fib = memoize(function(n)
  calls = calls + 1
  if n < 2 then return n end
  return fib(n - 1) + fib(n - 2)
end)
assert(fib(80) == 23416728348467685)
assert(calls == 81)
assert(fib(80) == 23416728348467685)
assert(calls == 81)
end

-- ## linked list and stack
do
local list
for i = 1, 5 do list = {value = i, next = list} end
local sum, len = 0, 0
local node = list
while node do sum = sum + node.value; len = len + 1; node = node.next end
assert(sum == 15 and len == 5 and list.value == 5)
local function reverse(l)
  local prev
  while l do
    local nxt = l.next
    l.next = prev
    prev = l
    l = nxt
  end
  return prev
end
list = reverse(list)
assert(list.value == 1 and list.next.value == 2)
local Stack = {}
Stack.__index = Stack
function Stack.new() return setmetatable({n = 0}, Stack) end
function Stack:push(v) self.n = self.n + 1; self[self.n] = v end
function Stack:pop() local v = self[self.n]; self[self.n] = nil; self.n = self.n - 1; return v end
local st = Stack.new()
for i = 1, 10 do st:push(i * i) end
assert(st:pop() == 100 and st:pop() == 81 and st.n == 8)
end

-- ## class hierarchy with three levels
do
local Animal = {}
Animal.__index = Animal
function Animal.new(name) local o = setmetatable({}, Animal); o.name = name; return o end
function Animal:speak() return self.name .. " makes a sound" end
function Animal:kind() return "animal" end
local Dog = setmetatable({}, {__index = Animal})
Dog.__index = Dog
function Dog.new(name) local o = Animal.new(name); return setmetatable(o, Dog) end
function Dog:speak() return self.name .. " barks" end
function Dog:kind() return "dog" end
local Puppy = setmetatable({}, {__index = Dog})
Puppy.__index = Puppy
function Puppy.new(name) local o = Dog.new(name); return setmetatable(o, Puppy) end
function Puppy:speak() return Dog.speak(self) .. " softly" end
local a, d, pup = Animal.new("Generic"), Dog.new("Rex"), Puppy.new("Bit")
assert(a:speak() == "Generic makes a sound")
assert(d:speak() == "Rex barks")
assert(pup:speak() == "Bit barks softly")
assert(pup:kind() == "dog" and a:kind() == "animal")
assert(getmetatable(pup) == Puppy and getmetatable(d) == Dog)
end

-- ## permutations with coroutines
do
local function permgen(a, n)
  n = n or #a
  if n <= 1 then
    coroutine.yield(a)
  else
    for i = 1, n do
      a[n], a[i] = a[i], a[n]
      permgen(a, n - 1)
      a[n], a[i] = a[i], a[n]
    end
  end
end
local function permutations(a)
  return coroutine.wrap(function() permgen(a) end)
end
local seen, count = {}, 0
for perm in permutations({"a", "b", "c", "d"}) do
  count = count + 1
  seen[table.concat(perm)] = true
end
assert(count == 24)
local distinct = 0
for _ in pairs(seen) do distinct = distinct + 1 end
assert(distinct == 24)
assert(seen.abcd and seen.dcba and seen.bdac)
end

-- ## a tokenizer state machine with string operations
do
local function tokenize(src)
  local tokens, i, n = {}, 1, #src
  while i <= n do
    local c = src:sub(i, i)
    if c == " " then
      i = i + 1
    elseif c >= "0" and c <= "9" then
      local j = i
      while j <= n and src:sub(j, j) >= "0" and src:sub(j, j) <= "9" do j = j + 1 end
      tokens[#tokens + 1] = "num:" .. src:sub(i, j - 1)
      i = j
    elseif (c >= "a" and c <= "z") or c == "_" then
      local j = i
      while j <= n and ((src:sub(j, j) >= "a" and src:sub(j, j) <= "z") or src:sub(j, j) == "_") do j = j + 1 end
      tokens[#tokens + 1] = "id:" .. src:sub(i, j - 1)
      i = j
    else
      tokens[#tokens + 1] = "op:" .. c
      i = i + 1
    end
  end
  return tokens
end
local toks = tokenize("foo = bar_baz + 42 * (x - 7)")
assert(#toks == 11)
assert(table.concat(toks, " ") == "id:foo op:= id:bar_baz op:+ num:42 op:* op:( id:x op:- num:7 op:)")
end

-- ## a recursive descent calculator
do
local function calc(src)
  local pos = 1
  local function peek() return src:sub(pos, pos) end
  local function skip() while peek() == " " do pos = pos + 1 end end
  local expr
  local function atom()
    skip()
    if peek() == "(" then
      pos = pos + 1
      local v = expr()
      skip()
      pos = pos + 1
      return v
    elseif peek() == "-" then
      pos = pos + 1
      return -atom()
    end
    local start = pos
    while peek() >= "0" and peek() <= "9" and peek() ~= "" do pos = pos + 1 end
    return tonumber(src:sub(start, pos - 1)) // 1
  end
  local function term()
    local v = atom()
    while true do
      skip()
      local op = peek()
      if op == "*" then pos = pos + 1; v = v * atom()
      elseif op == "/" then pos = pos + 1; v = v // atom()
      elseif op == "%" then pos = pos + 1; v = v % atom()
      else return v end
    end
  end
  function expr()
    local v = term()
    while true do
      skip()
      local op = peek()
      if op == "+" then pos = pos + 1; v = v + term()
      elseif op == "-" then pos = pos + 1; v = v - term()
      else return v end
    end
  end
  return expr()
end
assert(calc("1 + 2 * 3") == 7)
assert(calc("(1 + 2) * 3") == 9)
assert(calc("100 / 7 % 5 - -3") == 7)
assert(calc("2 * (3 + (4 - 1)) * 5") == 60)
assert(calc("-(7 - 10) * 2") == 6)
end

-- ## event queue with closures and varargs
do
local queue = {}
local function schedule(fn, ...)
  local args = {...}
  local n = select("#", ...)
  queue[#queue + 1] = function()
    local a, b, c = args[1], args[2], args[3]
    return fn(a, b, c, n)
  end
end
local log = {}
schedule(function(a, b, c, n) log[#log + 1] = a .. b .. string.format("%d", n) end, "x", "y")
schedule(function(a, b, c, n) log[#log + 1] = tostring(a) .. string.format("%d", n) end)
schedule(function(a, b, c, n) log[#log + 1] = c end, 1, 2, "three")
for i = 1, #queue do queue[i]() end
assert(table.concat(log, ",") == "xy2,nil0,three")
end

-- ## numeric integration and float accumulation
do
local function integrate(f, a, b, n)
  local h = (b - a) / n
  local s = 0.5 * (f(a) + f(b))
  for i = 1, n - 1 do s = s + f(a + i * h) end
  return s * h
end
local area = integrate(function(x) return x * x end, 0, 3, 1000)
assert(area > 8.9999 and area < 9.0001)
local harmonic = 0
for i = 1, 1000 do harmonic = harmonic + 1 / i end
assert(T(harmonic) == "7.4854708605503433")
local kahan_sum, comp = 0.0, 0.0
for i = 1, 10 do
  local y = 0.1 - comp
  local t = kahan_sum + y
  comp = (t - kahan_sum) - y
  kahan_sum = t
end
assert(kahan_sum == 1.0)
end
