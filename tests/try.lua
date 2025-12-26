

local function partition(pattern) -- iterator factory
  return function(text) -- make iterator for partitioning pattern in text
    if not text then
      error("no text")
    end
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


local line = "{part:():, close:(): }"
local bs, be = string.find(line, "(%b{})" )

print(bs == 1, be == #line)

-- print(line, found)
--[[
local part1 = "puttings: \":\"[] "
local part2 = " :[puttings: \":\"[] , direction: \":\", distance: #:]"
local pattern = ":%b[]" --"[\"%a]+(%[%])"
local found1 = string.find(part1, pattern)
local found2 = string.find(part2, pattern)
print(part1, pattern, found1)
print(part2, pattern, found2)
--]]

--"(theTestSetTablePath:\":\", theTestSetName:\":\", theTestName:\":\"): {part:():, close:():} "
