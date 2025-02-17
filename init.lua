local warnings, allowed_big_upvalues, stack, handle_primitive, cache_packages, mark_as_const

-- API --

local ldump_mt = {}

--- Serialization library, can be called directly.
--- Serialize the given value to a string, that can be deserialized via `load`.
--- @overload fun(value: any): string
local ldump = setmetatable({}, ldump_mt)

--- @alias deserializer string | fun(): any

-- no fun overload, lua ls bugs out here

--- Function, encapsulating custom serialization logic.
---
--- Defined by default to work with `__serialize` and `.handlers`, can be reassigned. Accepts the
--- serialized value, returns a deserializer in the form of a string with a valid lua expression, a
--- function or nil if the value should be serialized normally. Also may return a second optional
--- result -- a string to be displayed in the error message.
ldump.serializer = setmetatable({
  --- Custom serialization functions for the exact objects. 
  ---
  --- Key is the value that can be serialized, value is a deserializer in the form of a string with a
  --- valid lua expression or a function. Takes priority over `__serialize`.
  --- @type table<any, deserializer>
  handlers = {},
}, {
  __call = function(self, x)
    local handler = self.handlers[x]
    if handler then
      return handler, "`ldump.serializer.handlers`"
    end

    local mt = getmetatable(x)
    handler = mt and mt.__serialize and mt.__serialize(x)
    if handler then
      return handler, "`getmetatable(x).__serialize(x)`"
    end
  end,
})

--- Get the environment for safe `load`ing.
---
--- Intended to be passed as `env` argument when `load`ing untrusted data to prevent malicious code
--- execution. Contains only functions, required by ldump itself -- if serialization is overridden,
--- may need to be updated with the environment used there.
ldump.get_safe_env = function()
  return {
    load = load,
    loadstring = loadstring,
    debug = {
      setupvalue = debug.setupvalue,
      upvaluejoin = debug.upvaluejoin,
    },
    setmetatable = setmetatable,
  }
end

--- Get the list of warnings from the last ldump call.
---
--- See `ldump.strict_mode`.
--- @return string[]
ldump.get_warnings = function() return {unpack(warnings)} end

--- Mark function, causing dump to stop producing upvalue size warnings.
---
--- Upvalues can cause large modules to be serialized implicitly. Warnings allow tracking that.
--- @generic T: function
--- @param f T
--- @return T # returns the same function
ldump.ignore_upvalue_size = function(f)
  allowed_big_upvalues[f] = true
  return f
end

--- If true (by default), `ldump` treats unserializable data as an error, if false produces a
--- warning and replaces data with nil.
--- @type boolean
ldump.strict_mode = true

--- If true (false by default), `ldump` will serialize modules through `require`.
---
--- Allows to avoid serializing the modules, captured as upvalues in functions. Works only on the
--- modules themselves, not on the values within. Is overall safe, as Lua itself caches modules the
--- same way.
--- @type boolean
ldump.preserve_modules = false

--- `require`-style path to the ldump module, used in deserialization.
---
--- Inferred from requiring the ldump itself, can be changed.
--- @type string
ldump.require_path = select(1, ...)

--- @generic T
--- @param module T
--- @param schema table | "const"
--- @param modname string
--- @return T
ldump.mark = function(module, schema, modname)
  mark_as_const(module, schema, modname)
  return module
end


-- internal implementation --

-- NOTICE: lua5.1-compatible; does not support goto
unpack = unpack or table.unpack
if _VERSION == "Lua 5.1" then
  load = loadstring
end

ldump_mt.__call = function(self, x)
  assert(
    self.require_path,
    "Put the lua path to ldump libary into ldump.require_path before calling ldump itself"
  )

  stack = {}
  warnings = {}
  if ldump.preserve_modules then
    cache_packages()
  end
  local ok, result = pcall(handle_primitive, x, {size = 0}, {})

  if not ok then
    error(result, 2)
  end

  local base_code = [[
local cache = {}
local ldump
if require then
  ldump = require("%s")
else
  ldump = {
    ignore_upvalue_size = function() end
  }
end
return %s
  ]]

  return base_code:format(self.require_path, result)
end

allowed_big_upvalues = {}

local to_expression = function(statement)
  return ("(function()\n%s\nend)()"):format(statement)
end

local build_table = function(x, cache, upvalue_id_cache)
  local mt = getmetatable(x)

  cache.size = cache.size + 1
  cache[x] = cache.size

  local result = {}
  result[1] = "local _ = {}"
  result[2] = ("cache[%s] = _"):format(cache.size)

  for k, v in pairs(x) do
    table.insert(stack, tostring(k))
    table.insert(result, ("_[%s] = %s"):format(
      handle_primitive(k, cache, upvalue_id_cache),
      handle_primitive(v, cache, upvalue_id_cache)
    ))
    table.remove(stack)
  end

  if not mt then
    table.insert(result, "return _")
  else
    table.insert(result, ("return setmetatable(_, %s)")
      :format(handle_primitive(mt, cache, upvalue_id_cache)))
  end

  return table.concat(result, "\n")
end

local build_function = function(x, cache, upvalue_id_cache)
  cache.size = cache.size + 1
  local x_cache_i = cache.size
  cache[x] = x_cache_i

  local result = {}

  local ok, res = pcall(string.dump, x)

  if not ok then
    local message = (
      "Function .%s is not `string.dump`-compatible; it likely uses coroutines; to serialize " ..
      "it properly, use `ldump.serializer.handlers`"
    ):format(table.concat(stack, "."))

    if ldump.strict_mode then
      error(message, 0)
    else
      table.insert(warnings, message)
      return "nil"
    end
  end

  result[1] = "local _ = " .. ([[load(%q)]]):format(res)
  result[2] = ("cache[%s] = _"):format(x_cache_i)

  if allowed_big_upvalues[x] then
    result[3] = "ldump.ignore_upvalue_size(_)"
  end

  for i = 1, math.huge do
    local k, v = debug.getupvalue(x, i)
    if not k then break end

    table.insert(stack, ("<upvalue %s>"):format(k))
    local upvalue
    if
      k == "_ENV"
      and _ENV ~= nil  -- in versions without _ENV, upvalue _ENV is always just a normal upvalue
      and v._G == _G  -- for some reason, it may be that v ~= _ENV, but v._G == _ENV
    then
      upvalue = "_ENV"
    else
      upvalue = handle_primitive(v, cache, upvalue_id_cache)
    end
    table.remove(stack)

    if not allowed_big_upvalues[x] and #upvalue > 2048 and k ~= "_ENV" then
      table.insert(warnings, ("Big upvalue %s in %s"):format(k, table.concat(stack, ".")))
    end
    table.insert(result, ("debug.setupvalue(_, %s, %s)"):format(i, upvalue))

    if debug.upvalueid then
      local id = debug.upvalueid(x, i)
      local pair = upvalue_id_cache[id]
      if pair then
        local f_i, upvalue_i = unpack(pair)
        table.insert(
          result,
          ("debug.upvaluejoin(_, %s, cache[%s], %s)"):format(i, f_i, upvalue_i)
        )
      else
        upvalue_id_cache[id] = {x_cache_i, i}
      end
    end
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
  ["function"] = function(x, cache, upvalue_id_cache)
    return to_expression(build_function(x, cache, upvalue_id_cache))
  end,
  table = function(x, cache, upvalue_id_cache)
    return to_expression(build_table(x, cache, upvalue_id_cache))
  end,
  ["nil"] = function()
    return "nil"
  end,
  boolean = function(x)
    return tostring(x)
  end,
}

local package_cache = {}

local REFERENCE_TYPES = {
  table = true,
  ["function"] = true,
  userdata = true,
  thread = true,
}

handle_primitive = function(x, cache, upvalue_id_cache)
  local xtype = type(x)
  if REFERENCE_TYPES[xtype] then
    local cache_i = cache[x]
    if cache_i then
      return ("cache[%s]"):format(cache_i)
    end
  end

  do  -- handle custom serialization
    local deserializer, source = ldump.serializer(x)

    if deserializer then
      local deserializer_type = type(deserializer)

      if deserializer_type ~= "string" and deserializer_type ~= "function" then
        error(("%s returned type %s for .%s; it should return string or function")
          :format(source or "ldump.serializer", deserializer_type, table.concat(stack, ".")), 0)
      end

      local expression
      if deserializer_type == "string" then
        expression = deserializer
      else
        allowed_big_upvalues[deserializer] = true
        expression = ("%s()"):format(handle_primitive(deserializer, cache, upvalue_id_cache))
      end

      cache.size = cache.size + 1
      cache[x] = cache.size

      return to_expression(([[
        local _ = %s
        cache[%s] = _
        return _
      ]]):format(expression, cache.size))
    end
  end

  if not primitives[xtype] then
    local message = (
      "ldump does not support serializing type %q of .%s; use `__serialize` metamethod or " ..
      "`ldump.serializer.handlers` to define serialization"
    ):format(xtype, table.concat(stack, "."))

    if ldump.strict_mode then
      error(message, 0)
    end

    table.insert(warnings, message)
    return "nil"
  end

  if ldump.preserve_modules then
    local path = package_cache[x]
    if path then
      return ("require(%q)"):format(path)
    end
  end

  return primitives[xtype](x, cache, upvalue_id_cache)
end

local reference_types = {
  ["function"] = true,
  userdata = true,
  thread = true,
  table = true,
}

ldump._upvalue_mt = {
  __serialize = function(self)
    local ldump_require_path = ldump.require_path
    local name = self.name
    return function()
      return require(ldump_require_path)._upvalue(name)
    end
  end,
}

ldump._upvalue = function(name)
  return setmetatable({
    name = name,
  }, ldump._upvalue_mt)
end

local mark_as_static = function(value, module_path, key_path)
  local ldump_require_path = ldump.require_path

  ldump.serializer.handlers[value] = function()
    local ldump_local = require(ldump_require_path)
    local result = ldump_local.require(module_path)

    for _, key in ipairs(key_path) do
      if getmetatable(key) == ldump_local._upvalue_mt then
        for i = 1, math.huge do
          local k, v = debug.getupvalue(result, i)
          assert(k)

          if k == key.name then
            result = v
            break
          end
        end
      else
        result = result[key]
      end
    end
    return result
  end
end

local find_keys
find_keys = function(root, keys, key_path, result, seen)
  if seen[root] then return end
  seen[root] = true

  local root_type = type(root)
  if root_type == "table" then
    for k, v in pairs(root) do
      if keys[k] then
        table.insert(result, "." .. table.concat(key_path, "."))
      end

      table.insert(key_path, tostring(k))
      find_keys(v, keys, key_path, result, seen)
      table.remove(key_path)
    end
  elseif root_type == "function" then
    for i = 1, math.huge do
      local k, v = debug.getupvalue(root, i)
      if not k then break end

      -- prevent searching the global table
      -- TODO does this allow for detection in _ENV in lua5.1?
      if k ~= "_ENV" or _ENV == nil or v._G == _G then
        table.insert(key_path, ("<upvalue %s>"):format(k))
        find_keys(v, keys, key_path, result, seen)
        table.remove(key_path)
      end
    end
  end
end

local validate_keys = function(module, modname, potential_unserializable_keys)
  local unserializable_keys = {}
  local unserializable_keys_n = 0
  for key, _ in pairs(potential_unserializable_keys) do
    if not ldump.custom_serializers[key] then
      unserializable_keys[key] = true
      unserializable_keys_n = unserializable_keys_n + 1
    end
  end

  if unserializable_keys_n == 0 then return end

  local key_paths = {}
  find_keys(module, unserializable_keys, {}, key_paths, {})
  local key_paths_rendered = table.concat(key_paths, ", ")
  if #key_paths_rendered > 1000 then
    key_paths_rendered = key_paths_rendered:sub(1, 1000) .. "..."
  end

  error((
    "Encountered reference-type keys (%s) in module %s. Reference-type keys " ..
    "are fundamentally impossible to deserialize using `require`. Save them as a value of " ..
    "the field anywhere in the module, manually overload their serialization or add module " ..
    "path to `ldump.modules_with_reference_keys` to disable the check.\n\nKeys in: %s"
  ):format(unserializable_keys_n, modname, key_paths_rendered), 3)
end

mark_as_const = function(value, modname)
  if not reference_types[type(value)] then return end

  local seen = {[value] = true}
  local queue_values = {value}
  local queue_key_paths = {{}}
  local potential_unserializable_keys = {}

  local i = 0

  while i < #queue_values do
    i = i + 1
    local current = queue_values[i]
    local key_path = queue_key_paths[i]

    mark_as_static(current, modname, key_path)

    local type_current = type(current)
    if type_current == "table" then
      for k, v in pairs(current) do
        if reference_types[type(k)] then
          potential_unserializable_keys[k] = true
        end

        -- duplicated for optimization
        if reference_types[type(v)] and not seen[v] then
          seen[v] = true
          local key_path_copy = {unpack(key_path)}
          table.insert(key_path_copy, k)
          table.insert(queue_values, v)
          table.insert(queue_key_paths, key_path_copy)
        end
      end

    elseif type_current == "function" then
      for j = 1, math.huge do
        local k, v = debug.getupvalue(current, j)
        if not k then break end

        -- duplicated for optimization
        -- seems like any _ENV would be handled by string.dump
        if k ~= "_ENV" and reference_types[type(v)] and not seen[v] then
          seen[v] = true
          local key_path_copy = {unpack(key_path)}
          table.insert(key_path_copy, ldump._upvalue(k))
          table.insert(queue_values, v)
          table.insert(queue_key_paths, key_path_copy)
        end
      end
    end

    validate_keys(value, modname, potential_unserializable_keys)
  end
end

cache_packages = function()
  for k, v in pairs(package.loaded) do
    package_cache[v] = k
  end
end


return ldump
