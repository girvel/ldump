# Overloading serialization

There are two ways to customize serialization in `ldump`: by defining serializers for certain values or all the values with a certain metatable, or by reassigning a global preprocessing function that may choose to override or not override serialization for any data. Any serialization override would work recursively, so the serialization inside of the composite data (s. a. tables and closures) would use the override.

## 0. Method

Any serialization function should return a deserializer. It may come in two forms:

1. (The main way) a function, that rebuilds the value back

```lua
local produce_userdata = function() end  -- placeholder for external function

local userdata_container_mt
userdata_container_mt = {
  __serialize = function(self)
    -- capture normal, serializable data as an upvalue
    local normal_data_copy = self.normal_data

    -- return the deserializer
    return function()
      return setmetatable({
        normal_data = normal_data_copy,
        userdata = produce_userdata()
      }, userdata_container_mt)
    end
  end
}

local value = setmetatable({
  userdata = produce_userdata(),
  normal_data = 42,
}, userdata_container_mt)

local serialized_data = ldump(value)
local value_copy = load(serialized_data)()
```

Here the deserializer function is:

```lua
function()
  return setmetatable({
    normal_data = normal_data_copy,
    userdata = produce_userdata()
  }, userdata_container_mt)
end
```

It captures the serializable data from the original using upvalues and recreates non-serializable data manually.

See as a test at [/tests/test_use_case.lua:124](/tests/test_use_case.lua#L124)

2. The form of the string containing a valid lua expression (or a chunk), that when passed to `load` would produce the desired value, such as `"42"`, `"2 + 2"`, `"require('utf8')"` or any other valid expression.

## 1. Custom serializers

Custom serializers can be defined in two ways: through the `__serialize` metamethod or `ldump.serializer.handlers`.

### `__serialize`

Allows to redefine serialization for all values with the given metatable. The serialize metamethod should accept one argument — the object itself — and return the deserializer. See examples in [Method](#0-method).

### `ldump.serializer.handlers`

Allows to redefine serialization for certain values. To do so, assign the handler with the value as a key and the deserializer as the value. See [API#`ldump.serializer.handlers`](/docs/api.md#ldumpserializerhandlers).

## 2. Custom preprocess

You can reassign the `ldump.serializer` itself. It would be called before serializing each value and allow customizing serialization in the most flexible way. See signature at [API#`ldump.serializer`](/docs/api.md#ldumpserializer).
