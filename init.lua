unpack = unpack or table.unpack
local warnings, allowed_big_upvalues, stack, build_table, handle_primitive,
  mark_as_static_recursively, validate_keys, reset_serializers_recursively

-- API --

local ldump_mt = {}

--- Serialization library, can be called directly.
--- Serialize given value to a string, that can be deserialized via `load`.
--- @overload fun(value: any): string
local ldump = setmetatable({}, ldump_mt)

--- @alias deserializer string | fun(): any

--- Custom serialization functions for the exact objects. 
---
--- Key is the value that can be serialized, value is a deserializer in form of `load`-compatible
--- string or function. Takes priority over `__serialize`.
--- @type table<any, deserializer>
ldump.custom_serializers = {}

--- Loads the given module, returns any value returned by the given module (`true` when `nil`).
--- 
--- Additionally, marks all data inside to be deserialized by requiring the module.
--- @param modname string
--- @return any
ldump.require = function(modname)
  local is_currently_loaded = package.loaded[modname]
  local result = require(modname)

  if is_currently_loaded then return result end

  local potential_unserializable_keys = {}
  mark_as_static_recursively(result, modname, potential_unserializable_keys)
  validate_keys(result, modname, potential_unserializable_keys)

  return result
end

--- Disables `ldump.require` erroring on reference-type keys for the module path.
--- @type table<string, true>
ldump.modules_with_reference_keys = {}

-- --- Resets `package.loaded` & `ldump.custom_serializers` for the given module.
-- ---
-- --- Reseting only the `package.loaded` may cause a memory leak.
-- --- @param modname string
-- --- @return any
-- ldump.reset_require_cache = function(modname)
--   reset_serializers_recursively(package.loaded[modname])
--   package.loaded[modname] = nil
-- end

--- Get the list of warnings from the last ldump call.
---
--- See `ldump.strict_mode`.
--- @return string[]
ldump.get_warnings = function() return {unpack(warnings)} end

--- Mark function, causing dump to stop producing upvalue size warnings.
---
--- Upvalues can cause large modules to be serialized implicitly. Warnings allow to track that.
--- @generic T: function
--- @param f T
--- @return T # returns the same function
ldump.ignore_upvalue_size = function(f)
  allowed_big_upvalues[f] = true
  return f
end

--- If true (by default), `ldump` treats unserializable data as an error, if false produces a
--- warning.
--- @type boolean
ldump.strict_mode = true

--- `require`-style path to the ldump module, used in deserialization.
---
--- Inferred from requiring the ldump itself, can be changed.
--- @type string
ldump.require_path = select(1, ...)


-- internal implementation --

ldump_mt.__call = function(self, x)
  assert(
    self.require_path,
    "Put the lua path to ldump libary into ldump.require_path before calling ldump itself"
  )

  stack = {}
  warnings = {}
  local cache = {size = 0}
  local ok, result = pcall(handle_primitive, x, cache)

  if not ok then
    error(result, 2)
  end

  return ("local cache = {}\nlocal ldump = require(\"%s\")\nreturn %s")
    :format(self.require_path, result)
end

allowed_big_upvalues = {}

local to_expression = function(statement)
  return ("(function()\n%s\nend)()"):format(statement)
end

build_table = function(x, cache)
  local mt = getmetatable(x)

  cache.size = cache.size + 1
  cache[x] = cache.size

  local result = {}
  result[1] = "local _ = {}"
  result[2] = ("cache[%s] = _"):format(cache.size)

  for k, v in pairs(x) do
    table.insert(stack, tostring(k))
    table.insert(result, ("_[%s] = %s"):format(
      handle_primitive(k, cache),
      handle_primitive(v, cache)
    ))
    table.remove(stack)
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
    error((
      "Function %s is not `string.dump`-compatible; if it uses coroutines, use " ..
      "`ldump.custom_serializers`"
    ):format(table.concat(stack, ".")), 0)
  end

  result[1] = "local _ = " .. ([[load(%q)]]):format(res)
  result[2] = ("cache[%s] = _"):format(cache.size)

  if allowed_big_upvalues[x] then
    result[3] = "ldump.ignore_upvalue_size(_)"
  end

  for i = 1, math.huge do
    local k, v = debug.getupvalue(x, i)
    if not k then break end

    table.insert(stack, ("<upvalue %s>"):format(k))
    local upvalue
    if k == "_ENV" then
      upvalue = "_ENV"
    else
      upvalue = handle_primitive(v, cache)
    end
    table.remove(stack)

    if not allowed_big_upvalues[x] and #upvalue > 2048 then
      table.insert(warnings, ("Big upvalue %s in %s"):format(k, table.concat(stack, ".")))
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
    local deserializer = ldump.custom_serializers[x] or mt and mt.__serialize and mt.__serialize(x)

    if deserializer then
      local deserializer_type = type(deserializer)

      if deserializer_type == "string" then
        return deserializer
      end

      if deserializer_type == "function" then
        allowed_big_upvalues[deserializer] = true
        return ("%s()"):format(handle_primitive(deserializer, cache))
      end

      local which_serializer = ldump.custom_serializers[x]
        and "ldump.custom_serializers[x]"
        or "getmetatable(x).__serialize(x)"

      error(("`%s` returned type %s for .%s; it should return string or function")
        :format(which_serializer, deserializer_type, table.concat(stack, ".")), 0)
    end
  end

  local xtype = type(x)
  if not primitives[xtype] then
    local message = (
      "ldump does not support serializing type %q of %s; use `__serialize` metamethod or " ..
      "`ldump.custom_serializers` to define serialization"
    ):format(xtype, table.concat(stack, "."))

    if ldump.strict_mode then
      error(message, 0)
    end

    table.insert(warnings, message)
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
  local key_path_copy = {unpack(key_path)}
  local ldump_require_path = ldump.require_path

  ldump.custom_serializers[value] = function()
    local ldump_local = require(ldump_require_path)
    local result = ldump_local.require(module_path)

    for _, key in ipairs(key_path_copy) do
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

mark_as_static_recursively = function(value, module_path, potential_unserializable_keys)
  if not reference_types[type(value)] then return end

  local seen = {[value] = true}
  local queue = {{{}, value}}
  local i = 0
  -- TODO! handle unserializable keys here, as it is a non-recursive function

  while i < #queue do
    i = i + 1
    local key_path, current = unpack(queue[i])

    mark_as_static(current, module_path, key_path)

    local type_current = type(current)
    if type_current == "table" then
      for k, v in pairs(current) do
        if reference_types[type(k)] then
          potential_unserializable_keys[k] = true
        end

        -- duplicated for optimization
        if not reference_types[type(v)] or seen[v] then goto continue end

        seen[v] = true
        -- TODO! refactor algorithm to prevent allocation here...
        local key_path_copy = {unpack(key_path)}
        table.insert(key_path_copy, k)
        -- TODO! ...and here...
        table.insert(queue, {key_path_copy, v})

        ::continue::
      end
    elseif type_current == "function" then
      for j = 1, math.huge do
        local k, v = debug.getupvalue(current, j)
        if not k then break end
        if k == "_ENV" then goto continue end

        -- duplicated for optimization
        if not reference_types[type(v)] or seen[v] then goto continue end

        seen[v] = true
        --- TODO! ...and here...
        local key_path_copy = {unpack(key_path)}
        table.insert(key_path_copy, ldump._upvalue(k))
        -- TODO! ...and here
        table.insert(queue, {key_path_copy, v})

        ::continue::
      end
    end
  end

  -- local value_type = type(value)
  -- if not reference_types[value_type] or seen[value] then return end
  -- seen[value] = true


  -- if value_type == "table" then
  --   for k, v in pairs(value) do
  --     if reference_types[type(k)] then
  --       potential_unserializable_keys[k] = true
  --     end

  --     table.insert(key_path, k)
  --     mark_as_static(v, module_path, key_path, potential_unserializable_keys, seen)
  --     table.remove(key_path)
  --   end
  -- elseif value_type == "function" then
  --   for i = 1, math.huge do
  --     local k, v = debug.getupvalue(value, i)
  --     if not k then break end
  --     if k == "_ENV" then goto continue end

  --     table.insert(key_path, ldump._upvalue(k))
  --     mark_as_static(v, module_path, key_path, potential_unserializable_keys, seen)
  --     table.remove(key_path)

  --     ::continue::
  --   end
  -- end
end

local find_keys

validate_keys = function(module, modname, potential_unserializable_keys)
  if ldump.modules_with_reference_keys[modname] then return end

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

      table.insert(key_path, ("<upvalue %s>"):format(k))
      find_keys(v, keys, key_path, result, seen)
      table.remove(key_path)
    end
  end
end

-- reset_serializers_recursively = function(value)
--   ldump.custom_serializers[value] = nil
--   if type(value) ~= "table" then return end
-- 
--   for k, v in pairs(value) do
--     reset_serializers_recursively(v)
--   end
-- end


return ldump
