local ldump = require("init")

local t = {}
for i = 1, 100000 do
  t[i] = 1000000 + i
end

local ok, f = loadstring(ldump(t))
if not ok then
  print(f)
else
  assert(f)()
end
