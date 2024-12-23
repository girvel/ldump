print("-- Stacktracing --")

local serialized = {}
for i = 1, 10 do
  local last = {}
  serialized[i] = last
  for j = 1, 100000 do
    last[j] = (i ^ 2 + j ^ 2) % 7
  end
end

for _, enabled in ipairs({true, false}) do
  print("enabled: ", enabled)

  package.loaded = {}
  DUMP_ENABLE_STACKTRACING = enabled
  local dump = require("dump")

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
