local ldump = require("init")

local upvalue1 = {}
local upvalue2 = {}

local marked_upvalues = {
  f = function()
    return upvalue1, upvalue2
  end,
}

return ldump.mark(marked_upvalues, {
  f = {
    upvalue1 = "const",
  }
}, ...)
