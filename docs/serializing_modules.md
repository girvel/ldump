# Serializing modules

Lua treats modules as functions, returning normal data (in contrast with static languages). For a serializer, there is little difference between data from a module and normal data generated at runtime. This leads to serializing library contents with the data referencing it, which is an expected behaviour (and default for ldump), but, generally, an undesirable one.

## Setting [`preserve_modules`](/docs/api.md#ldumppreserve_modules) flag

If `ldump.preserve_modules` is set to `true`, any reference to any module in the serialized data would be set to deserialize through `require`. It would work only with the modules themselves, not with the data inside them. For example, here no library code will be serialized:

```lua
local library = require("library")

local f = function()
  return library.foo() .. library.bar()
end

_ = ldump(f)
```

But here it will:

```lua
local library = require("library")
local foo = library.foo
local bar = library.bar

local f = function()
  return foo() .. bar()
end

_ = ldump(f)
```
