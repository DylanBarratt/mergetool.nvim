---@class MergeBuffers
---@field currentChangeBuffer number The buffer ID for the current change
---@field incomingChangeBuffer number The buffer ID for incoming changes
---@field parentBuffer number The buffer ID for the parent buffer

---@param pattern string # the pattern to find the stuffs with
---@return string # the commit hash of the base
local function find_stuffs(pattern) -- TODO: better name lol
  for line_num = 1, vim.api.nvim_buf_line_count(0) do
    local line = vim.api.nvim_buf_get_lines(0, line_num - 1, line_num, false)[1]

    local start_pos = line:find(pattern)
    if start_pos then
      return line:sub(start_pos + string.len(pattern))
    end
  end
end

---@return MergeBuffers
local function loadBuffers()
  -- open a new empty window
  vim.api.nvim_command("enew")

  local currentChangeBuffer = vim.api.nvim_get_current_buf()
  local incomingChangeBuffer = vim.api.nvim_create_buf(true, true)
  local parentBuffer = vim.api.nvim_create_buf(true, true)

  return {
    currentChangeBuffer = currentChangeBuffer,
    incomingChangeBuffer = incomingChangeBuffer,
    parentBuffer = parentBuffer,
  }
end
local function lines(str)
  local result = {}
  for line in str:gmatch '[^\n]+' do
    table.insert(result, line)
  end
  return result
end

---@param buffers MergeBuffers
local function populateBuffers(buffers, parentHash, incomingBranch)
  -- Set buffer content
  -- vim.api.nvim_buf_set_lines(buffers.currentChangeBuffer, 0, -1, false, output)

  local currentContent = vim.fn.system("git show HEAD:file1.txt")
  local incomingContent = vim.fn.system("git show " .. parentHash .. ":file1.txt")
  local parentContent = vim.fn.system("git show " .. incomingBranch .. ":file1.txt")

  vim.api.nvim_buf_set_lines(buffers.currentChangeBuffer, 0, -1, false, lines(currentContent))
  vim.api.nvim_buf_set_lines(buffers.incomingChangeBuffer, 0, -1, false, lines(incomingContent))
  vim.api.nvim_buf_set_lines(buffers.parentBuffer, 0, -1, false, lines(parentContent))
end

---@param buffers MergeBuffers
local function splitBuffers(buffers)
  -- the current buffer ( a newly opened one from loadBuffers ) is pushed to the left
  vim.api.nvim_open_win(buffers.incomingChangeBuffer, false, {
    split = "right",
    win = -1,
  })

  vim.api.nvim_open_win(buffers.parentBuffer, true, {
    split = "below",
    win = -1,
  })
end

function Main()
  -- TODO: check if this is a git repo
  local baseHash = find_stuffs("|||||||")
  local incomingBranch = find_stuffs(">>>>>>>")

  if baseHash == "" then return end -- TODO: proper exit msg
  if incomingBranch == "" then return end -- TODO: proper exit msg

  local buffers = loadBuffers()

  populateBuffers(buffers, baseHash, incomingBranch)

  splitBuffers(buffers)
end

local M = {}

function M.setup()
  vim.api.nvim_create_user_command("Mergetool", Main, { desc = "Git Mergetool" })
end

return M
