local ldump = require("init")
local utils = require("tests.utils")

_G.unpack = table.unpack
local pass = utils.pass


describe("ldump.preserve_modules", function()
  it("usage", function()
    ldump.preserve_modules = true
    local deterministic = require("tests.resources.deterministic")
    local f = function() return deterministic.some_value end
    local f_copy = pass(f)
    assert.are_equal(f(), f_copy())
    ldump.preserve_modules = false
  end)

  it("not usage", function()
    local deterministic = require("tests.resources.deterministic")
    local f = function() return deterministic.some_value end
    local f_copy = pass(f)
    assert.are_not_equal(f(), f_copy())
  end)

  it("not in upvalue", function()
    ldump.preserve_modules = true
    local deterministic = require("tests.resources.deterministic")
    local t = {value = deterministic}
    local t_copy = pass(t)
    assert.are_equal(t.value, t_copy.value)
    ldump.preserve_modules = false
  end)
end)
