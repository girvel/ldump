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

it("Marking from the outside", function()
  local deterministic = require("tests.resources.deterministic")
  ldump.mark_module("tests.resources.deterministic", {})
  assert.are_equal(deterministic, pass(deterministic))
  assert.are_not_equal(deterministic.some_value, pass(deterministic.some_value))

  ldump.serializer.handlers[deterministic] = nil
end)

it("const shouldn't leak into function upvalues, may begin to mark dependencies", function()
  ldump.mark_module("tests.resources.leak_dependent", "const")
end)

it("upvalues can be marked manually", function()
  local ok, result = pcall(ldump.mark_module, "tests.resources.leak_dependent", {
    f = {
      dependency = "const",
    }
  })

  assert.is_false(ok)
end)
