-- floating point kernel with data dependent branches
return function(n)
  local inside = 0
  for y = 0, n - 1 do
    local ci = 2.0 * y / n - 1.0
    for x = 0, n - 1 do
      local cr = 2.0 * x / n - 1.5
      local zr, zi, it = 0.0, 0.0, 0
      while it < 50 and zr * zr + zi * zi < 4.0 do
        zr, zi = zr * zr - zi * zi + cr, 2.0 * zr * zi + ci
        it = it + 1
      end
      if it == 50 then inside = inside + 1 end
    end
  end
  return inside
end
