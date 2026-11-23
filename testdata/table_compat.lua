-- Random table operations whose results must be the same on upstream
-- GopherLua and on this runtime in the Lua 5.1 profile, with and without
-- the JIT. The file returns run(seed), which returns a trace of every
-- result as a string. The expected traces in table_compat_upstream.txt
-- were produced by upstream GopherLua (see table_compat_test.go).
--
-- Not exercised, because this runtime differs from upstream on purpose
-- (docs/migration.md): table.sort on arrays that contain nil, and the
-- order in which pairs visits keys that are not array indexes.

local function run(seed)
  -- minimal standard generator: exact in double precision
  local state = seed * 7919 % 2147483647 + 1
  local function rnd(n)
    state = state * 16807 % 2147483647
    return state % n + 1
  end

  local trace = {}
  local function note(...)
    local n = select("#", ...)
    local parts = {}
    for i = 1, n do
      local v = select(i, ...)
      parts[i] = type(v) == "string" and ("'" .. v .. "'") or tostring(v)
    end
    trace[#trace + 1] = "[" .. table.concat(parts, ",") .. "]"
  end
  local function try(f, ...)
    local res = {pcall(f, ...)}
    if not res[1] then
      note("error", (tostring(res[2]):gsub("^.-:%d+: ", "")))
    else
      note(unpack(res, 2, table.maxn(res)))
    end
  end

  local strings = {"a", "bb", "ccc", "d"}
  local function value()
    local k = rnd(10)
    if k <= 5 then return rnd(20) end
    if k <= 7 then return rnd(20) + 0.5 end
    if k <= 9 then return strings[rnd(4)] end
    return true
  end

  -- dump describes everything that can be observed of a table
  local function dump(t)
    local seq = {}
    for i, v in ipairs(t) do seq[i] = tostring(v) end
    local rest = {}
    for k, v in pairs(t) do
      rest[#rest + 1] = tostring(k) .. "=" .. tostring(v)
    end
    table.sort(rest)
    -- the number keys in the order of the traversal: the array part in
    -- ascending order, then the other number keys as they were added
    local order = {}
    for k in pairs(t) do
      if type(k) == "number" then order[#order + 1] = tostring(k) end
    end
    note("len", #t, "maxn", table.maxn(t), "ipairs", table.concat(seq, "|"), "pairs", table.concat(rest, "|"),
      "order", table.concat(order, "|"))
  end

  for round = 1, 3 do
    local t = {}
    -- most tables start as a sequence of one kind of value
    local kind = rnd(4)
    for i = 1, rnd(12) - 1 do
      if kind == 1 then t[i] = i * 3
      elseif kind == 2 then t[i] = i + 0.25
      elseif kind == 3 then t[i] = i % 2 == 0
      else t[i] = value() end
    end
    local sorting = rnd(3)
    if sorting == 1 then
      try(table.sort, t)
      try(table.sort, t, function(a, b) return tostring(a) > tostring(b) end)
      dump(t)
    elseif sorting == 2 then
      -- holes, but no nil behind the last element: the array part ends
      -- at the border, which is where this runtime stops sorting too
      for i = 1, rnd(4) do t[#t + rnd(300)] = value() end
      try(table.sort, t, function(a, b) return tostring(a) > tostring(b) end)
      dump(t)
      try(table.sort, t)
      dump(t)
    end
    for step = 1, 25 do
      local op = rnd(26)
      local n = #t
      if op <= 3 then
        t[n + 1] = value()
      elseif op <= 5 then
        t[rnd(n + 3)] = value()
      elseif op == 6 then
        t[rnd(n + 3)] = nil
      elseif op == 7 then
        if n > 0 then t[n] = nil end
      elseif op == 8 then
        t[n + rnd(40)] = value()
      elseif op == 9 then
        local keys = {0, -1, 2.5, n + 0.5, "x", "y", 1e9, 2 ^ 27}
        local k = keys[rnd(#keys)]
        if rnd(3) == 1 then t[k] = nil else t[k] = value() end
      elseif op <= 11 then
        try(table.insert, t, value())
      elseif op == 12 then
        try(table.insert, t, rnd(n + 2), value())
      elseif op == 13 then
        try(table.insert, t, rnd(n + 12) - 4, value())
      elseif op <= 15 then
        try(table.remove, t)
      elseif op == 16 then
        try(table.remove, t, rnd(n + 2))
      elseif op == 17 then
        try(table.remove, t, rnd(n + 12) - 4)
      elseif op == 18 then
        try(table.concat, t, ",")
      elseif op == 19 then
        if n <= 200 then
          try(function() return select("#", unpack(t)), unpack(t) end)
        end
      elseif op == 22 then
        -- far behind the end
        t[n + rnd(3000)] = value()
      elseif op == 23 then
        t[rnd(5000)] = value()
      elseif op == 24 then
        t[n + rnd(2000)] = nil
      elseif op == 25 then
        -- next to an element that lies far behind the end
        local k = table.maxn(t)
        if rnd(2) == 1 then t[k + 1] = value() else t[k] = nil end
      elseif op == 26 then
        try(table.remove, t, rnd(math.max(n, 1)))
        try(table.insert, t, rnd(math.max(n, 1)), value())
      elseif op == 20 then
        -- a stack: elements are popped by assigning nil and pushed
        -- again in a loop that compiled code can run
        for i = 1, rnd(6) do
          if #t > 0 then t[#t] = nil end
        end
        for i = 1, rnd(30) do t[#t + 1] = i * round end
        try(table.remove, t)
      else
        local sum = 0
        for i = 1, #t do
          if type(t[i]) == "number" then sum = sum + t[i] end
        end
        note("sum", sum)
      end
      note(#t, table.maxn(t))
    end
    dump(t)
    -- taking the table apart from both ends
    for i = 1, 6 do
      try(table.remove, t)
      try(table.remove, t, 1)
      note(#t, table.maxn(t))
    end
    dump(t)
  end
  return table.concat(trace, " ")
end

return run
