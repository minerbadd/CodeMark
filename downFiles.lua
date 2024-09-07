-- **CLI for `downFiles**.lua`....mirorring `apiFiles.lua`

local opFiles, downMark = require("opFiles"), require("downMark").cli

local function marker(extension, html, verbose)
  return function(inPath, outPath) 
    downMark(inPath, outPath, extension, html, verbose)
  end
end

local function downFiles(inDirectory, outDirectory, extension, html, verbose)
  opFiles(marker(extension, html, verbose), inDirectory, extension, outDirectory.."/")
-- expected as `opfiles(operation, directory, extension, `outDirectory)` so `marker` produces an `operation` function`
-- whose parameters `inFile` and `outName` match the arguments `opFiles` applies to `operation` `
end

return downFiles


