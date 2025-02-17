-- NOTICE all tests in this file are represented in the corresponding files, and should be updated
--   there each time they are updated here

local utils = require("tests.utils")
_G.unpack = table.unpack or unpack
_G.load = utils.load


describe("README.md", function()
  it("Basic use case", function()
    local ldump = require("init")

    local upvalue = 42
    local world = {
      name = "New world",
      get_answer = function() return upvalue end,
    }

    local serialized_data = ldump(world)  -- serialize to a string
    local loaded_world = load(serialized_data)()  -- deserialize the string

    assert.are_equal(world.name, loaded_world.name)
    assert.are_equal(world.get_answer(), loaded_world.get_answer())
  end)

  it("Serializing any lua data", function()
    local ldump = require("init")

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
  end)
end)

describe("docs/api.md", function()
  it("Using metatables for serialization override", function()
    local ldump = require("init")

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

    assert.is_true(math.abs(t.creation_time - t_copy.creation_time) < 0.0001)
    assert.are_equal(coroutine.resume(t.inner), coroutine.resume(t_copy.inner))
    assert.are_equal(coroutine.resume(t.inner), coroutine.resume(t_copy.inner))
  end)

  it("Using serializer.handlers for serialization override", function()
    local ldump = require("init")

    local create_coroutine = function()
      return coroutine.create(function()
        coroutine.yield(1)
        coroutine.yield(2)
      end)
    end

    local c = create_coroutine()
    ldump.serializer.handlers[c] = create_coroutine
    local serialized_data = ldump(c)
    local c_copy = load(serialized_data)()

    assert.are_equal(coroutine.resume(c), coroutine.resume(c_copy))
    assert.are_equal(coroutine.resume(c), coroutine.resume(c_copy))
  end)
end)

describe("docs/overloading.md", function()
  it("Simple example of deserializer", function()
    local ldump = require("init")
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

    assert.are_same(value, value_copy)
  end)
end)
