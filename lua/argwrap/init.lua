local M = {}

local fn = vim.fn
local api = vim.api

-- Default configuration options
local defaults = {
  tail_comma = false,
  wrap_closing_brace = true,
  padded_braces = "",
  line_prefix = "",
}

M.config = vim.deepcopy(defaults)

function M.setup(opts)
  M.config = vim.tbl_extend("force", defaults, opts or {})
end

-- Validate that a range has real start/end positions
function M.validate_range(range)
  return range
    and next(range) ~= nil
    and not (
      (range.lineStart == 0 and range.colStart == 0)
      or (range.lineEnd == 0 and range.colEnd == 0)
    )
end

-- Compare two ranges relative to cursor position
-- Returns 1 if range1 is closer/smaller, -1 if range2 is closer/smaller, 0 if equal
function M.compare_ranges(range1, range2)
  local _, line, col, _ = unpack(fn.getpos('.'))

  -- Check if we have complete range information (lineEnd and colEnd)
  local hasCompleteRange1 = range1.lineEnd and range1.colEnd
  local hasCompleteRange2 = range2.lineEnd and range2.colEnd

  -- If both ranges are complete and contain the cursor, prefer the smaller (more nested) one
  if hasCompleteRange1 and hasCompleteRange2 then
    -- Check if cursor is inside each range
    local inside1 = (range1.lineStart < line or (range1.lineStart == line and range1.colStart <= col))
                    and (range1.lineEnd > line or (range1.lineEnd == line and range1.colEnd >= col))
    local inside2 = (range2.lineStart < line or (range2.lineStart == line and range2.colStart <= col))
                    and (range2.lineEnd > line or (range2.lineEnd == line and range2.colEnd >= col))

    if inside1 and inside2 then
      -- Both ranges contain cursor, prefer the smaller (more nested) one
      local size1 = range1.lineEnd - range1.lineStart
      local size2 = range2.lineEnd - range2.lineStart

      if size1 < size2 then
        return 1  -- range1 is smaller (more nested)
      elseif size1 > size2 then
        return -1  -- range2 is smaller (more nested)
      else
        -- Same line span, compare column span
        local colSize1 = range1.colEnd - range1.colStart
        local colSize2 = range2.colEnd - range2.colStart
        if colSize1 < colSize2 then
          return 1
        elseif colSize1 > colSize2 then
          return -1
        end
      end
    elseif inside1 then
      return 1  -- Only range1 contains cursor
    elseif inside2 then
      return -1  -- Only range2 contains cursor
    end
  end

  -- Use original distance-based logic (for incomplete ranges or when cursor is outside)
  local lineDiff1 = range1.lineStart - line
  local colDiff1 = range1.colStart - col
  local lineDiff2 = range2.lineStart - line
  local colDiff2 = range2.colStart - col

  if lineDiff1 < lineDiff2 then
    return 1
  elseif lineDiff1 > lineDiff2 then
    return -1
  elseif colDiff1 < colDiff2 then
    return 1
  elseif colDiff1 > colDiff2 then
    return -1
  else
    return 0
  end
end

-- Find matching brace pair range
function M.find_range(braces)
  local filter = 'synIDattr(synID(line("."), col("."), 0), "name") =~? "string"'
  local lineStart, colStart = unpack(fn.searchpairpos(braces[1], '', braces[2], 'Wnb', filter))
  local lineEnd, colEnd = unpack(fn.searchpairpos(braces[1], '', braces[2], 'Wcn', filter))
  return { lineStart = lineStart, colStart = colStart, lineEnd = lineEnd, colEnd = colEnd }
end

-- Find closest enclosing range ((), [], {})
function M.find_closest_range()
  local ranges = {}
  for _, braces in ipairs({ { '(', ')' }, { '[', ']' }, { '{', '}' } }) do
    local range = M.find_range(braces)
    if M.validate_range(range) then
      table.insert(ranges, range)
    end
  end
  if #ranges == 0 then
    return {}
  end
  table.sort(ranges, function(a, b)
    return M.compare_ranges(a, b) == 1
  end)
  return ranges[1]
end

-- Extract argument text inside a container
function M.extract_container_arg_text(range, line_prefix)
  local text = ''
  for lineIndex = range.lineStart, range.lineEnd do
    local lineText = fn.getline(lineIndex)
    local extractStart = (lineIndex == range.lineStart) and range.colStart or 1
    local extractEnd   = (lineIndex == range.lineEnd) and (range.colEnd - 1) or #lineText
    if extractStart <= extractEnd then
      local extract = string.sub(lineText, extractStart, extractEnd)
      extract = extract:gsub('^%s*(.-)%s*$', '%1')
      -- Remove opening brace if present
      extract = extract:gsub('^[%(%[%{]', '')
      -- Remove closing brace if present
      extract = extract:gsub('[%)%]%}]$', '')
      if vim.startswith(extract, line_prefix) then
        extract = extract:sub(#line_prefix + 1)
      end
      text = text .. extract
    end
  end
  return text
end

-- Update stack for nested quotes/braces
function M.update_scope(stack, char)
  local pairs = { ['"'] = '"', ["'"] = "'", [')'] = '(', [']'] = '[', ['}'] = '{' }
  local length = #stack
  if length > 0 and pairs[char] == stack[length] then
    table.remove(stack, length)
  elseif vim.tbl_contains(vim.tbl_values(pairs), char) then
    table.insert(stack, char)
  end
end

-- Trim whitespace and spacing around punctuation
function M.trim_argument(text)
  local trim = text:gsub('^%s*(.-)%s*$', '%1')
  trim = trim:gsub('([:=])%s%s+', '%1 ')
  trim = trim:gsub('%s%s+([:=])', ' %1')
  return trim
end

-- Split container text into argument list
function M.extract_container_args(text)
  text = text:gsub('^%s*(.-)%s*$', '%1')
  local stack, arguments, argument = {}, {}, ''

  for i = 1, #text do
    local char = text:sub(i, i)
    M.update_scope(stack, char)
    if #stack == 0 and char == ',' then
      argument = M.trim_argument(argument)
      if #argument > 0 then
        table.insert(arguments, argument)
      end
      argument = ''
    else
      argument = argument .. char
    end
  end

  argument = M.trim_argument(argument)
  argument = argument:gsub(',$', '')
  if #argument > 0 then
    table.insert(arguments, argument)
  end

  return arguments
end

-- Extract indentation, prefix, and suffix around container
function M.extract_container(range)
  local textStart = fn.getline(range.lineStart)
  local textEnd = fn.getline(range.lineEnd)
  local indent = textStart:match('^%s*')
  local prefix = textStart:sub(#indent + 1, range.colStart)
  local suffix = textEnd:sub(range.colEnd)
  return { indent = indent, prefix = prefix, suffix = suffix }
end

-- Wrap arguments into multiple lines
function M.wrap_container(range, container, arguments, wrap_brace, tail_comma, line_prefix)
  local line = range.lineStart
  fn.setline(line, container.indent .. container.prefix)

  for index, arg in ipairs(arguments) do
    local text = container.indent .. line_prefix .. arg
    if index < #arguments or tail_comma then
      text = text .. ','
    end
    fn.append(line, text)
    line = line + 1
  end

  if wrap_brace then
    fn.append(line, container.indent .. container.suffix)
  end
end

-- Collapse wrapped arguments into a single line
function M.unwrap_container(range, container, arguments, padded)
  local brace = container.prefix:sub(-1)
  local padding = padded:find(brace, 1, true) and ' ' or ''
  local text = string.format(
    '%s%s%s%s%s%s',
    container.indent,
    container.prefix,
    padding,
    table.concat(arguments, ', '),
    padding,
    container.suffix
  )
  fn.setline(range.lineStart, text)
  api.nvim_command(string.format('silent %d,%dd_', range.lineStart + 1, range.lineEnd))
end

-- Get buffer or global setting
function M.get_setting(name, default)
  local bName = 'b:argwrap_' .. name
  local gName = 'g:argwrap_' .. name
  if fn.exists(bName) == 1 then
    return fn.eval(bName)
  elseif fn.exists(gName) == 1 then
    return fn.eval(gName)
  else
    return default
  end
end

-- Toggle between wrapped and unwrapped state
function M.toggle()
  local cursor = fn.getpos('.')

  local cfg = M.config
  local line_prefix = cfg.line_prefix
  local padded = cfg.padded_braces
  local tail_comma = cfg.tail_comma
  local wrap_brace = cfg.wrap_closing_brace

  local range = M.find_closest_range()
  if not M.validate_range(range) then
    return
  end

  local arg_text = M.extract_container_arg_text(range, line_prefix)
  local arguments = M.extract_container_args(arg_text)
  if #arguments == 0 then
    return
  end

  local container = M.extract_container(range)
  if range.lineStart == range.lineEnd then
    M.wrap_container(range, container, arguments, wrap_brace, tail_comma, line_prefix)
  else
    M.unwrap_container(range, container, arguments, padded)
  end

  fn.setpos('.', cursor)
end

return M
