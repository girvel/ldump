local ldump = require("init")

local marked_module = {
  table = {inner = {}},
  table2 = {inner = {}},
  coroutine = coroutine.create(function() end),
}

return ldump.mark(marked_module, {
  table = "const",
  table2 = {},
  coroutine = "const",
}, ...)
