-- **Generate Lua Language Server `signs` (signature) files from project API repository file**

local signfiles = {}

-- **Utility Functions**

local strippers =  {"(%?)%?*", "`(.-)`", "(.-)`", "(.-)<%-", "(.-)&(.*)",  "(.-)\n"} --  "(%?)%?*" reduce multiple "?"

local function stripOther(text, index)
  if index > #strippers then return text end
  local stripped = string.gsub(text, strippers[index], "%1")
  return stripOther(stripped, index + 1)
end

local function stripSpaces(text) return string.gsub(text, "%s*(%w-)%s*", "%1") end

local function stripNewLine(text) return string.gsub(text, "\n(.+)", "%1") end

-- **Partition Text Keeping Containers Whole** (by hiding commas and pipes)

local function replace(patterns) -- generate function to replace patterns for gsub
  local function replacing(text, index)
    if index > #patterns then return text end -- each new string gets bound by the recursion
    local replaced = string.gsub(text, table.unpack(patterns[index]))
    return replacing(replaced, index + 1)
  end; return replacing
end

local function hider(text) return replace({ {",", ";"}, {"|", "!"} })(text, 1) end -- specialize replacer

local containers = { "%b{}", "%b():", "%b[]", "%b()", }

local function hide(text, index) -- hide separators inside container 
  if index > #containers then return text end 
  local hidden = string.gsub(text, containers[index], hider)
  return hide(hidden, index + 1)  -- rebind new string in recursion
end

local function restorer(text) return replace({ {";", ","}, {"!", "|"}  })(text, 1) end -- restore separators  

local function slice(text) -- make table of restored parts (no partition of container)
  local parts = {}; for part, separator in string.gmatch(text, "([^,|]*)([,|]?)") do
    if part ~= "" then parts[#parts + 1] = restorer(part) end -- restore separators for each part
    if separator == "|" then parts[#parts + 1] = separator end
  end; return parts
end

local function assembler(parts, result, index, piped)
  if index > #parts then return result end
  local part = parts[index]; local pipe = part == "|"
  local empty = result == ""
  local separator = (pipe or piped or empty) and " " or ", "
  return assembler(parts, result..separator..part, index + 1, pipe)
end

local function assemble(text) return assembler(text, "", 1, false) end

-- **Handlers to Replace Tokens in Elements with LLS Words.**

local function tableToken(text) return string.gsub(text, "{:}", "table") end

local function stringToken(text) return string.gsub(text, '":"', "string") end

local function placeToken(text) return string.gsub(text, "_:", "any") end

local function anyToken(text) return string.gsub(text, "any", "any") end

local function nilToken(text) return string.gsub(text, "nil", "nil") end

local function userdataToken(text) return string.gsub(text, "@:", "userdata") end

local function booleanToken(text) return string.gsub(text, "%^:", "boolean") end

local function numberToken(text) return string.gsub(text, "#:", "number") end

local function typeTwiceToken(text) return string.gsub(text, ":([_%a%d]-):", "%1: %1") end

local function union(text) return text end

local function typeTaggedToken(text) return text end 

local function typeToken(text) return text end 

-- **Container Handlers: Make LLS entries of elements which may be or may be in containers.**

local makeEntry, array, dictionary, groupContainer, funContainer, funToken, tupleContainer, literalsContainer -- recursions

function array(text, line) -- not a tuple, just the [] marker is enough
  local beforeArray = string.match(text, "(.-)%[%]")
  local arrayEntry = makeEntry(beforeArray, line) 
  return arrayEntry.."[]" --..optional(text) 
end

local function tag(text, pattern) -- find label aka tag before pattern and ending in ":"
  local patternStart = assert(string.find(text, pattern), "missing pattern "..pattern.." in "..text)
  local beforePart = string.sub(text, 1, patternStart - 1) -- just the part before the pattern
  local beforeText = string.match(beforePart, "(.-):")
  if not beforeText then return "" end
  return beforeText..": "
end

--[[ This fails because string.match finds the inner %b pattern
local function tag(text, pattern)
  local preface, body = string.match(text, "(.*):%s-("..pattern..")")
  return preface and preface..": " or "", body
end
--]]

function dictionary(text, line)
  local keyPart = string.match(text, "%[(.-)%]") -- may include tag
  local tagPart = string.match(keyPart, "(.-):") -- [tag: keyType]:
  local key = tagPart and string.match(keyPart, ".-:(.*)$") or keyPart
  local value = string.match(text, "%[.-%]:(.*)")
  local keyEntry = makeEntry(key, line) -- process key recursively
  local valueEntry = makeEntry(value, line) -- process value recursively
  return tag(text, "%b[]").."{ ["..keyEntry.."]:"..valueEntry.." }"
end

function groupContainer(text, line) 
  local insideGroup = string.match(text, "%((.-)%)")
  local _, groupEntries = makeEntry(insideGroup, line)
  local groupEntry = assemble(groupEntries)
  return tag(text, "%b()").."("..groupEntry..")" -- ..optional(text)
end

local function tupleStrip(part)
  local stripped = string.gsub(part, "[_%w]-:([%w|]*)", "%1")
  return stripped
end

function tupleContainer(text, line) 
  local insideTable = string.match(text, "%[(.*)%]")
  local _, tableEntries = makeEntry(insideTable, line)
  local tableEntry = assemble(tableEntries)
  local stripped = tupleStrip(tableEntry) -- need to strip off any tags in table entry
  return tag(text, "%b[]").."["..stripped.."]" -- ..optional(text) 
end

function funToken(text, line)
  local returnsToken = string.match(text,  "%(%):(.-)$")
  local returnsEmpty = stripSpaces(returnsToken) == "" or returnsToken == "?"
  local returnsEntry = returnsEmpty and "function" or "fun():"..makeEntry(returnsToken, line)
  local tokenEntry = tag(text, "%(%):")..returnsEntry
  return tokenEntry
end

function funContainer(text, line) -- leaky returns, use group to contain funContainer
  local argsPart, returnsPart = string.match(text, "(%b()):(.-)$")
  local strippedReturns = stripOther(returnsPart, 1) 
  local insideArgs = string.match(argsPart, "%((.-)%)$")
  local _, argsEntries = makeEntry(insideArgs, line)
  local argsEntry = assemble(argsEntries)
  local _, returnsEntries = makeEntry(strippedReturns, line)
  local returnsEntry = assemble(returnsEntries)
  local funEntry = "fun("..argsEntry.."): "..returnsEntry
  return funEntry
end

function literalsContainer(text, line) 
  local insideLiterals = string.match(text, "{(.-)}%s*$") 
  local _, literalsParts = makeEntry(insideLiterals, line)
  local literalsPart = assemble(literalsParts)
  local literalsEntry = "{"..literalsPart.."}" --..optional(text) 
  return tag(text, "%b{}")..literalsEntry -- e.g. "{tag1: string, tag2: xyz}"
end

local finders = { -- **Ordered most carefully; matchID string for debug**.. pattern, handler, exclusions, container
  {"(%b():).-$", funContainer, "funContainer", {["():"] = true}, true },  -- true to indicate container
  {"(%b{})", literalsContainer, "literalsContainer", {["{:}"] = true}, true}, 
  {"(%b[]:).-$", dictionary, "dictionary"}, 
  {"(%b[])", tupleContainer, "tupleContainer",  {["[]"] = true, ["[:]"] = true}, true},
  {"(%(%):).-$", funToken, "functionToken"}, 
  {"(%b())", groupContainer, "groupContainer",  {["():"] = true},  true}, 
  {"(.+%[%])", array, "array"}, -- [] can't stand alone, use [:]

  {"|", union, "union"},

  {"(.+%[%])", array, "array"}, -- [] can't stand alone, use [:]
  {"(%[:%])", array, "arrayToken"},  {"({:})", tableToken,  "tableToken"}, 
  {"(#:)", numberToken, "numberToken"},   {'(":")', stringToken, "stringToken"}, 
  {"(%^:)", booleanToken, "booleanToken"}, {"(@:)", userdataToken, "userdataToken"}, 
  {"(_:)", placeToken, "placeToken"}, {"nil", nilToken, "nilToken"},  {"any", anyToken, "anyToken"},

  {":([%a%d%.]-):", typeTwiceToken, "typeTwiceToken"}, 
  {":%s-([%w%.]+)", typeTaggedToken, "typeTaggedToken"}, 
  {"([%w%.%s]*)", typeToken, "typeToken"},
}
-- **Match Elements Iterator to Make Entries**

local function contained(text, pattern, container)
  if not container then return true end
  local preface = string.match(text, "(.-)"..pattern)
  local contained = preface == ""
  return contained, preface
end

local function findMatch(part, text) -- for part
  local noSpaces = stripSpaces(part)
  for _, finder in ipairs(finders) do
    local pattern, handler, matchID, exclusions, container = table.unpack(finder)
    local found = string.match(noSpaces, pattern)
    if found then 
      local wrapped = contained(found, pattern, container)
      local exceptions = not wrapped or (exclusions and exclusions[found])
      if not exceptions then return handler, matchID end
    end
  end; error("can't find match for "..part.."in "..text)
end

local function elements(text) -- iterator
  local index, parts = 1, slice(hide(text, 1))
  return function()  
    if index > #parts then return end-- terminate iterator
    local part = parts[index]; local handler, matchID = findMatch(part, text); index = index + 1 
    return part, handler, matchID
  end
end

local verbose = false

function makeEntry(text, line) -- containers have elements (which may themselves be containers).
  if not text then error("signfiles.makeEntry: Can't parse "..line) end
  local entries = {}; for element, handler, matchID in elements(text) do
    if verbose then print(element, matchID) end
    local LLS = handler(element, line); entries[#entries + 1] = LLS 
  end;  -- new table for each recursion
  local entry = table.concat(entries, " ")
  return entry, entries -- `entries` as array for concatenation by container
end

-- **Produce LLS Lines and Write to File**

local function makeFunction(functionAPI)
  local line = functionAPI.name.."("..functionAPI.args.."): "..functionAPI.returns
  local args = stripOther(functionAPI.args, 1)
  local returns = stripOther(functionAPI.returns, 1)
  local argsContained = "("..args.."):"
  local entry = makeEntry(argsContained..returns, line)
  if not functionAPI.description then print("No description in "..line) end
  local description = "\n-- "..stripNewLine(functionAPI.description or "")
  local markLine, typeLine  = "-- "..line, "---@type "..entry
  local functionLine = "function "..functionAPI.name.."() end"
  return description.."\n"..markLine.."\n"..typeLine.."\n"..functionLine
end

local function makeType(typeAPI) -- 
  local name, line = typeAPI.name, typeAPI.name..": "..typeAPI.returns
  local supress = "---@diagnostic disable-next-line: duplicate-doc-alias"
  local qualified = string.find(name, "%.") and supress.."\n" or ""
  local returns =  makeEntry(stripOther(typeAPI.returns, 1), line)
  if not typeAPI.description then print("ERROR: no description in "..line) end
  local description = stripNewLine(typeAPI.description or "")
  return "\n-- "..line.."\n"..qualified.."---@alias "..name.." "..returns.." # "..description.."\n"
end

local doChild = {["function"] = makeFunction, ["value"] = makeType} -- api has bracketed names

function signfiles.test(libChildEntry) verbose = true; return doChild[libChildEntry.type](libChildEntry) end

local function writeLines (outLines, outFile, outName, verbose) 
  for _, line in ipairs(outLines) do outFile:write(line, "\n") end 
  if verbose then print(#outLines.." lines written in "..outName) end
end

-- **Process api** file

local function commaSplit(text)
  local items = {}; items[#items + 1] = string.match(text, "([^,]*),?"); -- first
  for item in string.gmatch(text, ",([^,]*)") do items[#items + 1] = string.gsub(item, "%s", "") end
  return items
end

local function makeExports(moduleEntry)
  if moduleEntry.returns == "" then return end
  local exportNames = commaSplit(moduleEntry.returns)
  local tables = string.rep("{}, ", #exportNames - 1).."{}"
  local libraryFirst = "local "..moduleEntry.returns.." = "..tables
  local exportItems = {}; for _, exportName in ipairs(exportNames) do 
    exportItems[#exportItems + 1] = exportName.." = "..exportName 
  end; local libraryLast = "return {"..table.concat(exportItems, ", ").."}"
  return libraryFirst, libraryLast
end

local function doModule(apiDirectory, moduleName, moduleEntry, api, verbose) 
  local outlines = {}; outlines[#outlines + 1] = "---@meta\n"
  local moduleFirst, moduleLast = makeExports(moduleEntry)
  outlines[#outlines + 1] = moduleFirst or ""
  for _, libChildEntry in pairs(moduleEntry.childs) do
    local op = doChild[libChildEntry.type]; 
    local result = op and op(libChildEntry)
    outlines[#outlines + 1] = result
  end
  for _, libraryName in ipairs(commaSplit(moduleEntry.returns)) do
    local libEntry = api[libraryName]-- find lib entry for module library
    if not libEntry then error("signfiles.doModule: unknown library "..libraryName.." for "..moduleName) end
    for _, libChildEntry in pairs(libEntry.childs) do
      local op = doChild[libChildEntry.type]; 
      local result = op and op(libChildEntry)
      outlines[#outlines + 1] = result
    end
  end; outlines[#outlines + 1] = moduleLast 
  local outName = apiDirectory..moduleName..".lua"; local outFile = assert(io.open(outName, "w"))
  writeLines(outlines, outFile, outName, verbose); outFile:flush(); outFile:close()
end

function signfiles.cli(apiDirectory, apiFile, verbose)
  local apiLoad = loadfile(apiDirectory..apiFile)
  if not apiLoad then error("signfiles: can't load "..apiDirectory..apiFile) end 
  local api = apiLoad(); for apiName, apiEntry in pairs(api) do 
    if apiEntry.type == "lib" and apiEntry.kind == "module" then 
      doModule(apiDirectory, apiName, apiEntry, api, verbose) 
    end
  end
end

return signfiles
