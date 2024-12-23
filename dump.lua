local warnings, allowed_big_upvalues, stack, build_table, handle_primitive

-- API --

local dump_mt = {}
--- @overload fun(value: any): string
local dump = setmetatable({}, dump_mt)

--- @return string[]
dump.get_warnings = function() return {unpack(warnings)} end

--- @generic T: function
--- @param f T
--- @return T
dump.ignore_upvalue_size = function(f)
  allowed_big_upvalues[f] = true
  return f
end

--- @type string
dump.require_path = select(1, ...)

--- @alias serialize_function fun(any): (string | fun(): any)

--- Custom serialization functions for the exact objects. 
--- Takes priority over `getmetatable(x).__serialize`
--- @type table<any, serialize_function>
dump.custom_serializers = {}

--- @type boolean
dump.is_stacktracing_enabled = false

dump_mt.__call = function(self, x)
  assert(
    self.require_path,
    "Put the lua path to dump libary into dump.require_path before calling dump itself"
  )

  stack = {}
  warnings = {}
  local cache = {size = 0}
  local result = "return " .. handle_primitive(x, cache)

  return ("local cache = {}\nlocal dump = require(\"%s\")\n"):format(self.require_path) .. result
end


-- internal implementation --

allowed_big_upvalues = {}

local to_expression = function(statement)
  return ("(function()\n%s\nend)()"):format(statement)
end

local stack_render = function()
  return dump.is_stacktracing_enabled
    and table.concat(stack, ".")
    or "<stacktracing is disabled>"
end

local stack_push = function(value)
  if not dump.is_stacktracing_enabled then return end
  table.insert(stack, value)
end

local stack_pop = function(value)
  if not dump.is_stacktracing_enabled then return end
  table.remove(stack)
end

build_table = function(x, cache)
  local mt = getmetatable(x)

  cache.size = cache.size + 1
  cache[x] = cache.size

  local result = {}
  result[1] = "local _ = {}"
  result[2] = ("cache[%s] = _"):format(cache.size)

  for k, v in pairs(x) do
    stack_push(tostring(k))
    table.insert(result, ("_[%s] = %s"):format(
      handle_primitive(k, cache),
      handle_primitive(v, cache)
    ))
    stack_pop()
  end

  if not mt then
    table.insert(result, "return _")
  else
    table.insert(result, ("return setmetatable(_, %s)"):format(handle_primitive(mt, cache)))
  end

  return table.concat(result, "\n")
end

local build_function = function(x, cache)
  cache.size = cache.size + 1
  cache[x] = cache.size

  local result = {}

  local ok, res = pcall(string.dump, x)

  if not ok then
    error("Unable to dump function " .. stack_render())
  end

  result[1] = "local _ = " .. ([[load(%q)]]):format(res)
  result[2] = ("cache[%s] = _"):format(cache.size)

  if allowed_big_upvalues[x] then
    result[3] = "dump.ignore_upvalue_size(_)"
  end

  for i = 1, math.huge do
    local k, v = debug.getupvalue(x, i)
    if not k then break end

    stack_push(("<upvalue %s>"):format(k))
    local upvalue = handle_primitive(v, cache)
    stack_pop()

    if not allowed_big_upvalues[x] and #upvalue > 2048 then
      table.insert(warnings, ("Big upvalue %s in %s"):format(k, stack_render()))
    end
    table.insert(result, ("debug.setupvalue(_, %s, %s)"):format(i, upvalue))
  end
  table.insert(result, "return _")
  return table.concat(result, "\n")
end

local primitives = {
  number = function(x)
    return tostring(x)
  end,
  string = function(x)
    return string.format("%q", x)
  end,
  ["function"] = function(x, cache)
    return to_expression(build_function(x, cache))
  end,
  table = function(x, cache)
    return to_expression(build_table(x, cache))
  end,
  ["nil"] = function()
    return "nil"
  end,
  boolean = function(x)
    return tostring(x)
  end,
}

handle_primitive = function(x, cache)
  do  -- handle custom serializers
    local mt = getmetatable(x)
    local custom_serialize = dump.custom_serializers[x] or mt and mt.__serialize

    if custom_serialize then
      local serialized = custom_serialize(x)
      local serialized_type = type(serialized)

      if serialized_type == "string" then
        return serialized
      end

      if serialized_type == "function" then
        allowed_big_upvalues[serialized] = true
        return ("%s()"):format(handle_primitive(serialized, cache))
      end

      table.insert(warnings,
        ("Serializer returned type %s for %s, falling back to default serialization"):format(
          serialized_type, stack_render()
        )
      )
    end
  end

  local xtype = type(x)
  if not primitives[xtype] then
    table.insert(warnings, ("dump does not support type %q of %s"):format(
      xtype, stack_render()
    ))
    return "nil"
  end

  if xtype == "table" or xtype == "function" then
    local cache_i = cache[x]
    if cache_i then
      return ("cache[%s]"):format(cache_i)
    end
  end

  return primitives[xtype](x, cache)
end


return dump
