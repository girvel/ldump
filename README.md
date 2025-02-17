[API](/docs/api.md) | [Overloading serialization](/docs/overloading.md) | [Serializing modules](/docs/serializing_modules.md) | [Safety](/docs/safety.md) | [Development](/docs/development.md)

# ldump — serialization library for any lua type

`ldump` is a flexible serializer, able to serialize any data, starting with circular references, tables as keys, functions with upvalues, metatables and ending with coroutines, threads and userdata (by defining how they should be serialized). It outputs valid Lua code that recreates the original object, doing the deserialization through `load(data)()`. It aims for functionality and flexibility instead of speed and size, allowing full serialization of complex data, such as video game saves. The output is large, but can be drastically reduced with modern compression algorithms.

Inspired by [`Ser`](https://github.com/gvx/Ser). Supports Lua 5.1, 5.2, 5.3, 5.4 and LuaJIT. Tested for edge cases, such as joined upvalues and _ENV redefinition. Fully annotated in compatibility with LuaLS.

**WARNING:** `ldump`'s deserialization function is Lua's builtin `load`, which can load malicious code. Consider using JSON for untrusted data or use [safety measures](/docs/safety.md).

| Type                                      | Support      |
| ----------------------------------------- | ------------ |
| nil, boolean, number, string              | full         |
| function                                  | full         |
| userdata                                  | user-defined |
| thread                                    | user-defined |
| table                                     | full         |
| metatables[*](/docs/development.md#plans) | full         |


## TL;DR show me the code

```lua
local ldump = require("ldump")

local upvalue = 42
local world = {
  name = "New world",
  get_answer = function() return upvalue end,
}

local serialized_data = ldump(world)  -- serialize to a string
local loaded_world = load(serialized_data)()  -- deserialize the string

assert.are_equal(world.name, loaded_world.name)
assert.are_equal(world.get_answer(), loaded_world.get_answer())
```

See as a test at [/tests/test_use_case.lua:7](/tests/test_use_case.lua#L7)


## The full power of ldump

```lua
local ldump = require("ldump")

-- basic tables
local game_state = {
  player = {name = "Player"},
  boss = {name = "Boss"},
}

-- circular references & tables as keys
game_state.deleted_entities = {
  [game_state.boss] = true,
}

-- functions even with upvalues
local upvalue = 42
game_state.get_answer = function() return upvalue end

-- fundamentally non-serializable types if overridden
local create_coroutine = function()
  return coroutine.wrap(function()
    coroutine.yield(1337)
    coroutine.yield(420)
  end)
end

-- override serialization
game_state.coroutine = create_coroutine()
ldump.serializer.handlers[game_state.coroutine] = create_coroutine

local serialized_data = ldump(game_state)  -- serialize
local loaded_game_state = load(serialized_data)()  -- deserialize

-- assert
assert.are_equal(game_state.get_answer(), loaded_game_state.get_answer())
assert.are_equal(game_state.coroutine(), loaded_game_state.coroutine())
assert.are_equal(game_state.coroutine(), loaded_game_state.coroutine())

assert.are_same(game_state.player, loaded_game_state.player)
assert.are_same(game_state.boss, loaded_game_state.boss)
assert.are_same(
  game_state.deleted_entities[game_state.boss],
  loaded_game_state.deleted_entities[loaded_game_state.boss]
)
```

See as a test at [/tests/test_use_case.lua:23](/tests/test_use_case.lua#L23)


## Installation

- *Traditional way:* copy the [raw contents of init.lua from the latest release](https://raw.githubusercontent.com/girvel/ldump/refs/tags/v1.4.0/init.lua) into your `<lib>/ldump.lua`
- *Recommended way:* `git clone -b v1.4.0 https://github.com/girvel/ldump` inside the `<lib>/` — you still would be able to do `require("ldump")`, and it would allow version management through git

---

## Credits

- [paulstelian97](https://www.reddit.com/user/paulstelian97/) for providing a joined upvalue test case
- [lambda_abstraction](https://www.reddit.com/user/lambda_abstraction/) for suggesting a way to join upvalues
- [jhatemyjob](https://news.ycombinator.com/user?id=jhatemyjob) for the special characters test case
- [lifthrasiir](https://news.ycombinator.com/user?id=lifthrasiir) for pointing out safety issues
- [radioflash](https://github.com/radioflash) for suggesting a simpler module serialization logic and suggestions for publicity
