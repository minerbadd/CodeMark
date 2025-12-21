-- **Generate Lua Language Server `signs` (signature) files from project api file**

local signfiles = {}

-- **Utility Functions**

local strippers =  {"(%?)%?*", "`(.-)`", "(.-)`", "(.-)<%-", "(.-)&(.*)",  "(.-)\n",} --  "(%?)%?*" reduce multiple "?"

local function stripOther(text, index)
  if index > #strippers then return text end
  local stripped = string.gsub(text, strippers[index], "%1")
  return stripOther(stripped, index + 1)
end

--local function stripSpaces(text) return string.gsub(text, "%s*(%w-)%s*", "%1") end

local function stripNewLine(text) return string.gsub(text, "\n(.+)", "%1") end

-- **Partition Text Keeping Containers Whole** (by hiding commas)

local containers = { "%b[]", "%b()", "%b{}",}

local function replace(patterns) -- generate function to replace patterns for gsub
  local function replacing(text, index)
    if index > #patterns then return text end 
    local replaced = string.gsub(text, table.unpack(patterns[index]))
    return replacing(replaced, index + 1)
  end; return replacing
end

local function hider(text) 
  return replace({ {",", ";"} })(text, 1) 
end -- specialize replacer

local function hide(text) -- commas to semicolons inside container 
  for _, target in ipairs(containers) do
    local found = string.match(text, target)
    if found then return string.gsub(text, target, hider) end -- apply hider to targets in text
  end; return text -- not a container: no need for hiding commas
end

local function restorer(text) return replace({ {";", ","} })(text, 1) end -- and back to commas

local function partition(pattern) -- iterator factory
  return function(text) -- make iterator for partitioning pattern in text
    local position, length = 1, string.len(text)
    return function() -- iterator on text pattern handles single and last parts
      if position > length then return end -- terminate iterator
      local first, last = string.find(text, pattern, position)
      local ending = (first and first < last) and last or length + 1
      local current = position; position = ending + 1
      return string.sub(text, current, ending - 1); -- partial string
    end
  end
end

local function restore(text) -- make table of restored parts (no partition of container)
  local parts = {}; for part in partition("([^,]-),")(text) do -- break into parts of text ending in commas
    parts[#parts + 1] = restorer(part) -- any semicolons back to commas for each part
  end; return parts
end

local function stripTag(text) 
  local parts, stripped  = restore(text), {}
  for _, part in ipairs(parts) do 
    local match = string.match(part, "[_%w]-:(.*)$")
    stripped[#stripped + 1] =  match or part 
  end
  return table.concat(stripped, ", ")
end

-- **Handlers to Replace Tokens in Elements with LLS Words.**

local function tableToken(text) return string.gsub(text, "{:}", "table") end

local function functionToken(text) return string.gsub(text, "%(:%)", "function") end

local function stringToken(text) return string.gsub(text, '":"', "string") end

local function placeToken(text) return string.gsub(text, "_:", "any") end

local function anyToken(text) return string.gsub(text, "any", "any") end

local function nilToken(text) return string.gsub(text, "nil", "nil") end

local function userdataToken(text) return string.gsub(text, "@:", "userdata") end

local function booleanToken(text) return string.gsub(text, "%^:", "boolean") end

local function numberToken(text) return string.gsub(text, "#:", "number") end

local function typeTwiceToken(text) return string.gsub(text, ":([_%a%d]-):", "%1: %1") end

local function typeTaggedToken(text) return text end 

local function typeToken(text) return text end 

-- **Container Handlers: Make LLS entries of elements which may be or may be in containers.**

local makeEntry, union, array, dictionary, groupContainer, funContainer, tupleContainer, literalsContainer -- mutual recursions

function union(text, line)
  local beforeText, afterText = string.match(text, "(.-)|(.*)")
  local beforeEntry = makeEntry(beforeText, line) 
  local afterEntry = makeEntry(afterText, line)
  return beforeEntry.."|"..afterEntry
end

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
  local insideGroup = string.gsub(text, "%((.-)%)", "%1")
  local groupEntry = makeEntry(insideGroup, line)
  return tag(text, "%b()").."("..groupEntry..")" -- ..optional(text)
end

function tupleContainer(text, line) 
  local insideTable = string.match(text, "%[(.*)%]")
  local tableEntry = makeEntry(insideTable, line)
  local stripped = stripTag(tableEntry) -- need to strip off any tags in table entry
  return tag(text, "%b[]").."["..stripped.."]" -- ..optional(text) 
end

function funContainer(text, line) -- leaky returns, use group to contain funContainer
  local argsPart, returnsPart = string.match(text, "(%b()):(.-)$")
  local strippedReturns = stripOther(returnsPart, 1) 
  local argsEntry = makeEntry(argsPart, line)
  local returnsEntry = makeEntry(strippedReturns, line)
  local funEntry = "fun"..argsEntry..": "..returnsEntry
  return funEntry
end

function literalsContainer(text, line) 
  local insideLiterals = string.match(text, "{(.-)}%s*$") 
  local literalsParts = makeEntry(insideLiterals, line)
  local literalsEntry = "{"..literalsParts.."}" --..optional(text) 
  return tag(text, "%b{}")..literalsEntry -- e.g. "{tag1: string, tag2: xyz}"
end

local finders = { -- **Ordered most carefully; matchID string for debug**

  {"({:})", tableToken,  "tableToken"}, {"(%(:%))", functionToken, "functionToken"}, {"(%[:%])", array, "arrayToken"},

  {"|", union, "union"},

  {"(%b():.-$)", funContainer, "funContainer"},  
  {"(%b{})", literalsContainer, "literalsContainer"}, 
  {"(%b[]):", dictionary, "dictionary"}, 
  {"(%b[])", tupleContainer, "tupleContainer"},
  {"(%b())", groupContainer, "groupContainer"}, 

  {"(.+%[%])", array, "array"}, -- [] can't stand alone, use [:]

  {"(#:)", numberToken, "numberToken"},   {'(":")', stringToken, "stringToken"}, 
  {"(%^:)", booleanToken, "booleanToken"}, {"(@:)", userdataToken, "userdataToken"}, 
  {"(_:)", placeToken, "placeToken"}, {"nil", nilToken, "nilToken"},  {"any", anyToken, "anyToken"},

  {":([%a%d%.]-):", typeTwiceToken, "typeTwiceToken"}, 
  {":%s-([%w%.]+)", typeTaggedToken, "typeTaggedToken"}, 
  {"([%w%.%s]*)", typeToken, "typeToken"}
}
-- **Match Elements Iterator to Make Entries**

local function findMatch(part) -- for part
  for _, finder in ipairs(finders) do
    local pattern, handler, matchID = table.unpack(finder)
    local found = string.match(part, pattern)
    if found and found ~= "[]" then 
      return handler, matchID 
    end
  end
end

local function elements(text) -- iterator
  local index, parts = 1, restore(hide(text))
  return function() 
    if index > #parts then return end-- terminate iterator
    local part = parts[index]; local handler, matchID = findMatch(part); index = index + 1 
    return part, handler, matchID
  end
end

local verbose = false

function makeEntry(text, line) -- containers have elements (which may themselves be containers).
  if not text then 
    error("signfiles.makeEntry: Can't parse "..line) 
  end
  local entries = {}; for element, handler, matchID in elements(text) do
    if verbose then print(element, matchID) end
    local LLS = handler(element, line); entries[#entries + 1] = LLS 
  end;  -- new table for each recursion
  local entry = table.concat(entries, ", ")
  return entry, entries -- as string and table
end

-- **Produce LLS Lines and Write to File**

local function makeFunction(functionAPI)
  local line = functionAPI.name.."("..functionAPI.args.."): "..functionAPI.returns
  local args = makeEntry(stripOther(functionAPI.args, 1), line)  -- a string
  local returns = makeEntry(stripOther(functionAPI.returns, 1), line)
  if not functionAPI.description then print("No description in "..line) end
  local description = "\n-- "..stripNewLine(functionAPI.description or "")
  local markLine, typeLine  = "-- "..line, "---@type fun("..args.."): "..(returns or "")
  local functionLine = "function "..functionAPI.name.."() end"
  return description.."\n"..markLine.."\n"..typeLine.."\n"..functionLine
end

local function makeType(typeAPI) -- 
  local name, line = typeAPI.name, typeAPI.name..": "..typeAPI.returns
  local supress = "---@diagnostic disable-next-line: duplicate-doc-alias"
  local qualified = string.find(name, "%.") and supress.."\n" or ""
  local returns =  makeEntry(stripOther(typeAPI.returns, 1), line)
  if not typeAPI.description then print("No description in "..line) end
  local description = stripNewLine(typeAPI.description or "")
  return "\n-- "..line.."\n"..qualified.."---@alias "..name.." "..returns.." # "..description.."\n"
end

local doChild = {["function"] = makeFunction, ["value"] = makeType} -- api has bracketed names

function signfiles.test(libChildEntry) verbose = false; return doChild[libChildEntry.type](libChildEntry) end

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
