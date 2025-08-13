local ldump = require("init")

local pass = function(x)
  return load(ldump(x))()
end

it("Basic internal marking", function()
  local marked_module = require("tests.resources.marked_const_module")
  assert.are_equal(marked_module, pass(marked_module))
  assert.are_equal(marked_module.table, pass(marked_module.table))
  assert.are_equal(marked_module.coroutine, pass(marked_module.coroutine))
end)

it("Internal marking with a schema", function()
  local marked_module = require("tests.resources.marked_module")
  assert.are_equal(marked_module, pass(marked_module))
  assert.are_equal(marked_module.table, pass(marked_module.table))
  assert.are_equal(marked_module.table.inner, pass(marked_module.table.inner))
  assert.are_equal(marked_module.table2, pass(marked_module.table2))
  assert.are_not_equal(marked_module.table2.inner, pass(marked_module.table2.inner))
  assert.are_equal(marked_module.coroutine, pass(marked_module.coroutine))
end)

-- it("Marking upvalues", function()
--   local marked_upvalues = require("tests.resources.marked_upvalues")
--   local upvalue1, upvalue2 = marked_upvalues.f()
--   local copy1, copy2 = pass(marked_upvalues.f)()
--   assert.are_equal(upvalue1, copy1)
--   assert.are_equal(upvalue2, copy2)
-- end)
--
-- TODO marking upvalues? is it meaningful/possible considering the parent function should be static?

it("Marking from the outside", function()
  local deterministic = require("tests.resources.deterministic")
  ldump.mark_module("tests.resources.deterministic", {})
  assert.are_equal(deterministic, pass(deterministic))
  assert.are_not_equal(deterministic.some_value, pass(deterministic.some_value))

  ldump.serializer.handlers[deterministic] = nil
end)
