package.path = package.path .. ";./benchmark/_deps/?.lua"
local ldump = require("init")
local binser = require("binser")
local bitser = require("bitser")
local inspect = require("inspect")
local utils = require("benchmark.utils")
math.randomseed(os.time())


--[[
  output should look like this:

  iterations: 10

  serializer               | serialization time | deserialization time | memory
  ------------------------ | ------------------ | -------------------- | ------
  binser                   | 1.32 s             | 2.22 s               | 1.3 KB
  bitser                   | 1.31 s             | 2.01 s               | 1.3 KB
  ldump raw                | 1.5 s              | 3 s                  | 200 KB
  ldump with compression_1 | 1.6 s              | 3.3 s                | 2 KB
  ldump with compression_2 | 1.7 s              | 3.8 s                | 2.5 KB

  maybe binser/bitser should be attempted with compression too
]]


-- data --
-- should include large array with gaps, containing entities with repeating fields
local data = {
  entities = {},
}

local field_names = {}

local a_pos = string.byte("a")
local random_letter = function()
  return string.char(a_pos + math.random(0, 25))
end

local random_string = function(min_length, max_length)
  local result = ""
  for _ = 1, math.random(min_length, max_length) do
    result = result .. random_letter()
  end
  return result
end

for _ = 0, 40 do
  table.insert(field_names, random_string(3, 11))
end

local random_value
random_value = function()
  local r = math.random()

  if r < .2 then
    return math.random() < .4
  elseif r < .5 then
    return random_string(2, 20)
  else
    return math.random() * 65536
  end
end

local random_table = function(min_fields_n, max_fields_n)
  local result = {}
  for _ = 1, math.random(min_fields_n, max_fields_n) do
    result[field_names[math.random(#field_names)]] = random_value()
  end
  return result
end

for i = 1, 10000 do
  if math.random() < 0.2 then
    data.entities[i] = random_table(1, 20)
  else
    data.entities[i] = nil
  end
end


-- logic --

local serializers = {
  {
    name = "ldump",
    serialize = ldump,
    deserialize = function(data)
      return load(data)()
    end,
  },
  {
    name = "binser",
    serialize = binser.serialize,
    deserialize = binser.deserialize,
  },
  {
    name = "bitser",
    serialize = bitser.dumps,
    deserialize = bitser.loads,
  }
}

local names = {}
local serialize_ts = {}
local deserialize_ts = {}
local memory_usages = {}

for i, serializer in ipairs(serializers) do
  names[i] = serializer.name

  local serialize_t = os.clock()
  local serialized = serializer.serialize(data)
  serialize_ts[i] = ("%.3f s"):format(os.clock() - serialize_t)

  local deserialize_t = os.clock()
  _ = serializer.deserialize(serialized)
  deserialize_ts[i] = ("%.3f s"):format(os.clock() - deserialize_t)

  memory_usages[i] = ("%.3f KB"):format(#serialized / 1024)
end

local headers = {"serializer", "serialize time", "deserialize time", "memory"}

print(utils.render_table(headers, {names, serialize_ts, deserialize_ts, memory_usages}))
