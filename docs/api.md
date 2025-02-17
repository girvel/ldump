# API

## `ldump`

```lua
ldump(value: any) -> string
```

Serialize the given value to a string, that can be deserialized via `load`

### Example

```lua
local upvalue = 42
local world = {
  name = "New world",
  get_answer = function() return upvalue end,
}

local serialized_data = ldump(world)  -- serialize to a string
local loaded_world = load(serialized_data)()  -- deserialize the string
```

See as a test at [/tests/test_use_case:12](/tests/test_use_case#L12)

### Example

```lua
local ldump = require("ldump")

local t = setmetatable({
  creation_time = os.clock(),
  inner = coroutine.create(function()
    coroutine.yield(1)
    coroutine.yield(2)
  end)
}, {
  __serialize = function(self)
    local creation_time = self.creation_time  -- capturing upvalue
    return function()
      return {
        creation_time = creation_time,
        inner = coroutine.create(function()
          coroutine.yield(1)
          coroutine.yield(2)
        end)
      }
    end
  end,
})

local serialized_data = ldump(t)
local t_copy = load(serialized_data)()
```

See as a test at [/tests/test_use_case:71](/tests/test_use_case#L71)

## `ldump.serializer`

```lua
ldump.serializer(x: any) -> (string | fun(): any)?, string?
```

Function, encapsulating custom serialization logic.

Defined by default to work with `__serialize` and `.handlers`, can be reassigned. Accepts the serialized value, returns a deserializer in the form of a string with a valid lua expression, a function or nil if the value should be serialized normally. Also may return a second optional result -- a string to be displayed in the error message.

## `ldump.serializer.handlers`

```lua
ldump.serializer.handlers: table<any, string | fun(): any>
```

Custom serialization functions for the exact objects. 

Key is the value that can be serialized, value is a deserializer in the form of a string with a valid lua expression or a function. Takes priority over `__serialize`.

## `ldump.get_safe_env`

```lua
ldump.get_safe_env() -> table
```

Get the environment for safe `load`ing.

Intended to be passed as `env` argument when `load`ing untrusted data to prevent malicious code execution. Contains only functions, required by ldump itself -- if serialization is overridden, may need to be updated with the environment used there.

## `ldump.get_warnings`

```lua
ldump.get_warnings() -> string[]
```

Get the list of warnings from the last ldump call.

See [`ldump.strict_mode`](#ldumpstrict_mode)

## `ldump.ignore_upvalue_size`

```lua
ldump.ignore_upvalue_size<T: function>(f: T) -> T
```

Mark function, causing dump to stop producing upvalue size warnings.

Upvalues can cause large modules to be serialized implicitly. Warnings allow tracking that. Returns the same function.

## `ldump.strict_mode`

```lua
ldump.strict_mode: boolean = true
```

If true (by default), `ldump` treats unserializable data as an error, if false produces a warning and replaces data with nil.

## `ldump.preserve_modules`

```lua
ldump.preserve_modules: boolean = false
```

If true (false by default), `ldump` will serialize modules through `require`.

Allows to avoid serializing the modules, captured as upvalues in functions. Works only on the modules themselves, not on the values within. Is overall safe, as Lua itself caches modules the same way.

## `ldump.require_path`

```lua
ldump.require_path: string
```

`require`-style path to the ldump module, used in deserialization.

Inferred from requiring the ldump itself, can be changed.
