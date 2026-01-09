--[[
## -- CodeMark: Produce LLS Signature Files, Zerobrane API, Markdown and HTML Documentation
--]]
local apiFiles, signFiles, downFiles = require("apiFiles"), require("signFiles"), require("downFiles")

local function marker(apiDirectory, apiFile, sourceDirectories, docsDirectories, codeDirectories, verbose)

-- `opFiles` applies `operation` on files matching an `extension` in `directory` derived from `MUSE`
-- as `opfiles(operation, directory, extension, outDirectory)` 

-- `downFiles` supplies a `codedown` closure over `extension` and `verbose` for the `opFiles` operation 
-- `markFiles` supplies a `codemark` closure over `apiFile` and `verbose` and a defaut `lua` extension
-- The constructs reuse file operations in `opFiles` and the `Zerobrane` operations in `apiMark`

  os.remove(apiDirectory..apiFile)-- for fresh start project repository

  for _, sourceDirectory in ipairs(sourceDirectories) do -- make apifile project repository
    apiFiles(sourceDirectory, apiDirectory, apiFile, verbose) 
  end
  for _, sourceDirectory in ipairs(sourceDirectories) do -- two passes to resolve CodeMark copy entries
    apiFiles(sourceDirectory, apiDirectory, apiFile, verbose)
  end; print("API Repository in "..apiDirectory..apiFile)

  signFiles.cli(apiDirectory, apiFile, verbose) -- make sign files for Lua Language Server from project repository apifile 
  print("LLS signature files in "..apiDirectory)

  for _, directory in ipairs(docsDirectories) do -- make html from 
    downFiles(directory, directory, "md", verbose)
    print("HTML files from markdown files in "..directory)
  end

  for index, sourceDirectory in ipairs(sourceDirectories) do -- make html from Lua files in source
    downFiles(sourceDirectory, codeDirectories[index], "lua", verbose)
    print("HTML files from "..sourceDirectory.." in "..codeDirectories[index])
  end; 
end

local function helper(helps, help) -- output concatenated help file from helps directory files
---@diagnostic disable-next-line: undefined-global
  local helpers = {}; for helpFile in lfs.dir(helps) do  
    -- `helps` must be aligned with `sign` fields of `HELP` file marks 
    local extension = string.match(helpFile, "%.(%a*)$")
    if extension == "txt" then
      local helpPath = helps..helpFile; local helpFileHandle = io.open(helpPath, "r")
      if helpFileHandle then 
        local helpLines = helpFileHandle:read("*all"); helpFileHandle:close()
        local helpLine = string.gsub(helpLines, "\n \n", ": ")
        helpers[#helpers + 1] = string.gsub(helpLine, "\n", "")
      end
    end
  end; local helpText = table.concat(helpers, "\n\n")
  local helpsHandle = assert(io.open(help, "w"))
  helpsHandle:write(helpText); helpsHandle:close()
  print("Help files from "..helps.." in "..help)
end

return {marker = marker, helper = helper, }