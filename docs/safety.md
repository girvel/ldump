# Safety

`ldump` is intended for serialization of all Lua types, including functions and metatables -- which are inherently unsafe. In untrusted data, there are two sources of danger:

1. `load(data)()` itself may run malicious code
2. Any manipulation with resulting data may run malicious code -- even indexing, assigning or using any operator -- due to metamethods

There is a way to make it somewhat safe. This way wouldn't work in 5.1 and would be very bothersome in LuaJIT.

```lua
local result = load(malicious_data, nil, nil, ldump.get_safe_env())()
```

Providing `ldump.get_safe_env()` as the fourth argument to `load` will limit access to lua environment for loaded data -- during both deserialization and usage. On LuaJIT, however, this will only prevent malicious code from being executed during the deserialization stage, so the only way to work with untrusted data safely would be to use `rawget` and `rawset` only.

If you are customizing serialization, you will need to extend `ldump.get_safe_env`'s result with used lua environment members.

**NOTE:** Lua 5.1's `setfenv` wouldn't make it safer
