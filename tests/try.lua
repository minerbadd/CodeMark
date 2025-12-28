local function tag(text, pattern)
  local preface, body = string.match(text, pattern)-- string.match(text, "(.*):%s-("..pattern..")")
  return preface, body
end

local text1 = " {:bores:, ores: {name: \":\", fixtures: \":\"[], path: \":\"[], work: plan.work} }"
local result1 = tag(text1, "(.-):?%s-(%b{})")
print(result1)

--[[
local text2 = " abc [def [ghi jkl] mno] pqr "
local result2 = string.match(text2, "(%b[])")
print(result2)
--]]

--[[
local part = " op: string,  placeName: string,  borePlansFileOrLevels: string | number,  shaftPlansFile: string"
local function tupleStrip(part)
  local stripped = string.gsub(part, "[_%w]-:([%w|]*)", "%1")
  return stripped
end

print(tupleStrip(part))
--]]
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