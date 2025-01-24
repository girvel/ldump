local ldump = require("init")

local pass = function(x)
  return load(ldump(x))()
end

it("Basic internal marking", function()
  local marked_module = require("tests.resources.marked_module")
  assert.are_equal(marked_module, pass(marked_module))
  assert.are_equal(marked_module.table, pass(marked_module.table))
  assert.are_equal(marked_module.coroutine, pass(marked_module.coroutine))
end)
