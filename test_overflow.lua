local ldump = require("init")
loadstring = loadstring or load

local t = {}
for i = 1, 100000 do
  t[i] = 1000000 + i
end

local f, msg = loadstring(ldump(t))
if f then
  f()
else
  print(msg)
end
