local ldump = require("init")

local marked_module = {
  table = {},
  coroutine = coroutine.create(function() end),
}

return ldump.mark(marked_module, "const", ...)
