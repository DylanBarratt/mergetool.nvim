---@class GitInfo
---@field parentBranch string
---@field incomingBranch string
---@field currentBranch string
---@class GitConflicts
---@field lineNum integer
---@field currentDiff string
---@field incomingDiff string
---@field parentDiff string
---@class FileInfo
---@field gitInfo GitInfo
---@field conflicts GitConflicts
---@return FileInfo
local function loopFile(buffNum) -- TODO: better name
  local fileInfo =
    { gitInfo = { parentBranch = "", incomingBranch = "", currentBranch = "" }, conflicts = {} }

  local conflictMarkerStart = "<<<<<<<"
  local parentMarkerStart = "|||||||"
  local conflictMarkerEnd = ">>>>>>>"

  local lineNum = 1
  while lineNum < vim.api.nvim_buf_line_count(buffNum) do
    local curLine = vim.api.nvim_buf_get_lines(buffNum, lineNum - 1, lineNum, false)[1]

    -- conflict start found
    if string.find(curLine, conflictMarkerStart) then
      -- add a new conflict loc
      fileInfo.conflicts[#fileInfo.conflicts + 1] = {
        lineNum = lineNum,
        -- ERROR: this only gets one line, needs to get all lines between conflict markers
        -- currentDiff = vim.api.nvim_buf_get_lines(buffNum, lineNum, lineNum + 1, false)[1],
        -- parentDiff = vim.api.nvim_buf_get_lines(buffNum, lineNum + 2, lineNum + 3, false)[1],
        -- incomingDiff = vim.api.nvim_buf_get_lines(buffNum, lineNum + 4, lineNum + 5, false)[1],
      }

      if fileInfo.gitInfo.currentBranch == "" then
        fileInfo.gitInfo.currentBranch = string.sub(curLine, string.len(conflictMarkerStart) + 2)

        -- loop thru conflict to find other markers
        local conflictCurLine
        local lineCount = lineNum + 1
        repeat
          conflictCurLine = vim.api.nvim_buf_get_lines(buffNum, lineCount - 1, lineCount, false)[1]
          lineCount = lineCount + 1

          if string.find(conflictCurLine, parentMarkerStart) and fileInfo.gitInfo.parentBranch == "" then
            fileInfo.gitInfo.parentBranch = string.sub(conflictCurLine, string.len(parentMarkerStart) + 2)
          end

          if string.find(conflictCurLine, conflictMarkerEnd) and fileInfo.gitInfo.incomingBranch == "" then
            fileInfo.gitInfo.incomingBranch = string.sub(conflictCurLine, string.len(conflictMarkerEnd) + 2)
          end
        until string.find(conflictCurLine, conflictMarkerEnd)

        lineNum = lineCount - 1 -- skip over these lines in the loop
      end
    end

    lineNum = lineNum + 1
  end

  return fileInfo
end

---@class MergeBuffers
---@field currentChangeBuffer number The buffer ID for the current change
---@field incomingChangeBuffer number The buffer ID for incoming changes
---@field baseBuffer number The buffer ID for the base buffer
---@return MergeBuffers
local function loadBuffers()
  vim.api.nvim_command("enew")

  local baseBuffer = vim.api.nvim_get_current_buf()
  local currentChangeBuffer = vim.api.nvim_create_buf(true, true)
  local incomingChangeBuffer = vim.api.nvim_create_buf(true, true)

  vim.api.nvim_buf_set_name(currentChangeBuffer, "CURRENT")
  vim.api.nvim_buf_set_name(incomingChangeBuffer, "INCOMING")

  return {
    currentChangeBuffer = currentChangeBuffer,
    incomingChangeBuffer = incomingChangeBuffer,
    baseBuffer = baseBuffer,
  }
end

---@param buffers MergeBuffers
---@param gitInfo GitInfo
local function populateBuffers(buffers, gitInfo)
  local currentContent = vim.fn.system("git show HEAD:file1.txt")
  local incomingContent = vim.fn.system("git show " .. gitInfo.incomingBranch .. ":file1.txt")
  local baseContent = vim.fn.system("git show " .. gitInfo.parentBranch .. ":file1.txt")

  local function set_buf_content(buf, content)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(content, "\n", { trimempty = false }))
  end

  set_buf_content(buffers.currentChangeBuffer, currentContent)
  set_buf_content(buffers.incomingChangeBuffer, incomingContent)
  set_buf_content(buffers.baseBuffer, baseContent)

  -- Set the buffer to be read-only (kinda)
  local function make_buffer_read_only(buf_id)
    vim.api.nvim_set_option_value("readonly", true, { buf = buf_id })
    vim.api.nvim_set_option_value("modifiable", true, { buf = buf_id })
    vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf_id })
  end

  make_buffer_read_only(buffers.currentChangeBuffer)
  make_buffer_read_only(buffers.incomingChangeBuffer)
end

---@param buffers MergeBuffers
---@param hlGroup string
local function highlightDifferences(buffers, hlGroup)
  -- TODO: could this be made more eficient by being done in the initial fileInfo loop instead?
  local buf1_lines = vim.api.nvim_buf_get_lines(buffers.currentChangeBuffer, 0, -1, false)
  local buf2_lines = vim.api.nvim_buf_get_lines(buffers.incomingChangeBuffer, 0, -1, false)

  for i = 1, math.max(#buf1_lines, #buf2_lines) do
    local line1 = buf1_lines[i] or ""
    local line2 = buf2_lines[i] or ""

    for j = 1, math.max(#line1, #line2) do
      local char1 = line1:sub(j, j)
      local char2 = line2:sub(j, j)

      if char1 ~= char2 then
        if j <= #line1 then
          vim.api.nvim_buf_add_highlight(buffers.currentChangeBuffer, -1, hlGroup, i - 1, j - 1, j)
        end
        if j <= #line2 then
          vim.api.nvim_buf_add_highlight(buffers.incomingChangeBuffer, -1, hlGroup, i - 1, j - 1, j)
        end
      end
    end
  end
end

---@param buffers MergeBuffers
local function splitBuffers(buffers)
  vim.api.nvim_open_win(buffers.currentChangeBuffer, false, {
    split = "left",
    win = -1,
  })

  vim.api.nvim_open_win(buffers.incomingChangeBuffer, false, {
    split = "right",
    win = -1,
  })

  -- move base buffer below others
  vim.cmd("wincmd J")
end

-- ---@param buffers MergeBuffers
-- local function cleanup(buffers)
--   vim.api.nvim_create_autocmd("BufWinLeave", {
--     buffer = buffers.incomingChangeBuffer,
--     callback = function(args)
--       if vim.tbl_contains(buffers, args.buf) then
--         vim.api.nvim_buf_delete(buffers.currentChangeBuffer, { force = true })
--       end
--     end,
--   })
--   vim.api.nvim_create_autocmd("BufWinLeave", {
--     buffer = buffers.currentChangeBuffer,
--     callback = function(args)
--       if vim.tbl_contains(buffers, args.buf) then
--         vim.api.nvim_buf_delete(buffers.incomingChangeBuffer, { force = true })
--       end
--     end,
--   })
-- end

-- create a command that can only be used in the merge editor
---@param buffers MergeBuffers
---@param conflicts GitConflicts
local function userCommand(buffers, conflicts)
  local function setParent(new)
    local newLines = vim.split(new, "\n", { trimempty = false })
    vim.api.nvim_buf_set_lines(
      buffers.baseBuffer,
      -- ERROR: only changes one line
      conflicts[1].lineNum - 1,
      conflicts[1].lineNum + #newLines - 1,
      false,
      newLines
    )
  end

  vim.api.nvim_create_user_command("Mergetool", function(event)
    if event.args == "current" then
      setParent(conflicts[1].currentDiff)
    elseif event.args == "incoming" then
      setParent(conflicts[1].incomingDiff)
    elseif event.args == "parent" then
      setParent(conflicts[1].parentDiff)
    else
      print("incorrect argument, please use current, incoming, or parent")
    end
  end, {
    complete = function()
      return { "current", "incoming", "parent" }
    end,
    nargs = 1,
  })
end

function Main()
  -- TODO: check if this is a git repo
  -- TODO: stop execution if no conflicts found

  -- TODO: could add a user opt/command input to choose the buffer here
  local fileInfo = loopFile(0)
  local buffers = loadBuffers()

  populateBuffers(buffers, fileInfo.gitInfo)

  -- TODO: use user opt here
  highlightDifferences(buffers, "Visual")

  -- display the buffers
  splitBuffers(buffers)

  userCommand(buffers, fileInfo.conflicts)

  -- cleanup(buffers)
end

local M = {}

function M.setup()
  vim.api.nvim_create_user_command("Mergetool", Main, { desc = "Git Mergetool" })
end

return M
