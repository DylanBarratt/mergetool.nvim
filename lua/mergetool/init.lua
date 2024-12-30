---@class MergeBuffers
---@field currentChangeBuffer number The buffer ID for the current change
---@field incomingChangeBuffer number The buffer ID for incoming changes
---@field parentBuffer number The buffer ID for the parent buffer

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

---@param buffers MergeBuffers
local function populateBuffers(buffers)
  -- Set buffer content
  local lines = { "This is the first line", "This is the second line" }
  vim.api.nvim_buf_set_lines(buffers.currentChangeBuffer, 0, -1, false, lines)
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
  local buffers = loadBuffers()

  populateBuffers(buffers)
  splitBuffers(buffers)
end

local M = {}

function M.setup()
  vim.api.nvim_create_user_command("Mergetool", Main, { desc = "Git Mergetool" })
end

return M
