local ldump = require("init")


local utils = {}

if os.getenv("LDUMP_TEST_SAFETY") then
  local old_load
  if loadstring and type(jit) ~= "table" then
    old_load = loadstring
  else
    old_load = load
  end

  local env = ldump.get_safe_env()
  env.coroutine = coroutine

  utils.load = function(x)
    return old_load(x, nil, nil, env)
  end
else
  utils.load = load
end

--- Serialize and deserialize
--- @generic T
--- @param value T
--- @return T
utils.pass = function(value)
  return load(ldump(value))()
end

return utils
