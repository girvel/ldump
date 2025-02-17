local utils = {}

utils.render_table = function(headers, columns)
  local result = "| "
  local column_sizes = {}
  for i, header in ipairs(headers) do
    column_sizes[i] = #header
    for _, value in ipairs(columns[i]) do
      column_sizes[i] = math.max(column_sizes[i], #value)
    end

    result = result .. header .. string.rep(" ", column_sizes[i] - #header) .. " | "
  end

  result = result .. "\n| "

  for i, size in ipairs(column_sizes) do
    result = result .. string.rep("-", size) .. " | "
  end

  result = result .. "\n| "

  for i = 1, #columns[1] do
    if i > 1 then
      result = result .. "\n| "
    end
    for j = 1, #columns do
      local v = columns[j][i]
      result = result .. v .. string.rep(" ", column_sizes[j] - #v) .. " | "
    end
  end

  return result
end

return utils
