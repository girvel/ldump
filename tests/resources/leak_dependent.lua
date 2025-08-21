local dependency = require("tests.resources.leak_dependency")

return {
  f = function()
    return dependency
  end,
}
