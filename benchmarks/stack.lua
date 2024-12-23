local dump = require("dump")


print("-- Stacktracing --")

local serialized = {}
for i = 1, 10 do
  local last = {}
  serialized[i] = last
  for j = 1, 1000 do
    last[j] = {}
  end
end

for _, enabled in ipairs({true, false}) do
  print("enabled: ", enabled)
  dump.is_stacktracing_enabled = enabled

  local N = 10
  local sum = 0
  local size

  for _ = 1, N do
    local t = os.clock()
    size = #dump(serialized)
    sum = sum + os.clock() - t
  end

  print(("%.3f s"):format(sum / N))
  print(("%.3f MB"):format(size / 1024 ^ 2))
end
