
local part = " op: string,  placeName: string,  borePlansFileOrLevels: string | number,  shaftPlansFile: string"
local function tupleStrip(part)
  local stripped = string.gsub(part, "[_%w]-:([%w|]*)", "%1")
  return stripped
end

print(tupleStrip(part))
--[[
local function assembler(parts, result, index, piped)
  if index > #parts then return result end
  local part = parts[index]; local pipe = part == "|"
  local empty = result == ""
  local separator = (pipe or piped or empty) and " " or ", "
  return assembler(parts, result..separator..part, index + 1, pipe)
end

local function assemble(text) return assembler(text, "", 1, false) end

local text = {"op: string", " placeName: string", " borePlansFileOrLevels: string", "|", "number", " shaftPlansFile: string"} 

print(assemble(text))

--]]