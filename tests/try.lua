
local function assembler(parts, result, index, piped)
  if index > #parts then return result end
  local part = parts[index]; local pipe = part == "|"
  local empty = result == ""
  local separator = (pipe or piped or empty) and " " or ", "
  return assembler(parts, result..separator..part, index + 1, pipe)
end

local function assemble(text) return assembler(text, "", 1, false) end

local text = {"(source: {:}|any): {:}", "|", "any ", "99"}
print(assemble(text))

