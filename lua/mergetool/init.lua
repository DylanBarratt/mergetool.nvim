local function getGitInfo()
  local function find_stuffs(pattern) -- TODO: better name lol
    for line_num = 1, vim.api.nvim_buf_line_count(0) do
      local line = vim.api.nvim_buf_get_lines(0, line_num - 1, line_num, false)[1]

      local start_pos = line:find(pattern)
      if start_pos then
        return line:sub(start_pos + string.len(pattern))
      end
    end
  end

  local baseHash = find_stuffs("|||||||")
  local incomingBranch = find_stuffs(">>>>>>>")

  if baseHash == "" then
    return
  end -- TODO: proper exit msg ?
  if incomingBranch == "" then
    return
  end -- TODO: proper exit msg ?

  return {
    baseHash = baseHash,
    incomingBranch = incomingBranch,
  }
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
local function populateBuffers(buffers, baseHash, incomingBranch)
  local currentContent = vim.fn.system("git show HEAD:file1.txt")
  local incomingContent = vim.fn.system("git show " .. incomingBranch .. ":file1.txt")
  local baseContent = vim.fn.system("git show " .. baseHash .. ":file1.txt")

  local function set_buf_content(buf, content)
    -- split string by new lines
    local function lines(str)
      local result = {}
      for line in str:gmatch("[^\n]+") do
        table.insert(result, line)
      end
      return result
    end

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines(content))
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

---@param buffers MergeBuffers
local function cleanup(buffers)
  vim.api.nvim_create_autocmd("BufWinLeave", {
    buffer = buffers.incomingChangeBuffer,
    callback = function(args)
      if vim.tbl_contains(buffers, args.buf) then
        vim.api.nvim_buf_delete(buffers.currentChangeBuffer, { force = true })
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufWinLeave", {
    buffer = buffers.currentChangeBuffer,
    callback = function(args)
      if vim.tbl_contains(buffers, args.buf) then
        vim.api.nvim_buf_delete(buffers.incomingChangeBuffer, { force = true })
      end
    end,
  })
end

function Main()
  -- TODO: check if this is a git repo

  local gitInfo = getGitInfo()
  if gitInfo == nil then
    return "" -- no merge conflicts found
  end

  local buffers = loadBuffers()

  populateBuffers(buffers, gitInfo.baseHash, gitInfo.incomingBranch)

  -- TODO: use user opt here
  highlightDifferences(buffers, "Visual")

  splitBuffers(buffers)

  cleanup(buffers)
end

local M = {}

function M.setup()
  vim.api.nvim_create_user_command("Mergetool", Main, { desc = "Git Mergetool" })
end

return M
