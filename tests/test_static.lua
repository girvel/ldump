local ldump = require("init")

local pass = function(value)
  return load(ldump(value))()
end

describe("ldump.deterministic_require", function()
  it("usage", function()
    ldump.deterministic_require = true
    local deterministic = require("tests.resources.deterministic")
    local f = function() return deterministic.some_value end
    local f_copy = pass(f)
    assert.are_equal(f(), f_copy())
    ldump.deterministic_require = false
  end)

  it("not usage", function()
    local deterministic = require("tests.resources.deterministic")
    local f = function() return deterministic.some_value end
    local f_copy = pass(f)
    assert.are_not_equal(f(), f_copy())
  end)

  it("not in upvalue", function()
    ldump.deterministic_require = true
    local deterministic = require("tests.resources.deterministic")
    local t = {value = deterministic}
    local t_copy = pass(t)
    assert.are_equal(t.value, t_copy.value)
    ldump.deterministic_require = false
  end)
end)
