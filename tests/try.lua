
local line =  " ():(value: any): value: any"
local inside = string.match(line, "%b():.-$") 
print(inside)

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