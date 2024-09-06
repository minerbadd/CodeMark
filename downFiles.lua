-- **CLI for `downFiles**.lua`....mirorring `apiFiles.lua`

local opFiles, downMark = require("opFiles"), require("downMark").cli

local function marker(extension, assets, verbose) return function(inPath, outPath) downMark(inPath, outPath, extension, assets, verbose) end end

local function downFiles(inDirectory, outDirectory, extension, assets, verbose)
  opFiles(marker(extension, assets, verbose), inDirectory, extension, outDirectory.."/")
-- expected as `opfiles(operation, directory, extension, `outDirectory)` so `marker` produces an `operation` function`
-- whose parameters `inFile` and `outName` match the arguments `opFiles` applies to `operation` `
end

return downFiles


