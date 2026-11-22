-- Control flow: goto and labels.
local load = loadstring or load

-- ## a label visible from an enclosing block cannot be redeclared
do
assert(load("::x:: do ::x:: end") == nil)
assert(load("::x:: while true do ::x:: end") == nil)
assert(load("::x:: if a then ::x:: end") == nil)
assert(load("do ::x:: do do ::x:: end end end") == nil)
end
