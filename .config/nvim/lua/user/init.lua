require("user.utils")
require("user.keybinds")
require("user.font")
require("user.mason")
require("user.lsp")
require('user.cmp').setup()
require('user.null-ls').setup()
require("user.utils")
require('user.rustaceanvim')
require('impatient')
require("telescope").load_extension("lazygit")
require('user.git')
require('user.keybinds')
require("user.oil")
require('user.telescope-settings')
require("telescope").load_extension("ui-select")
require('user.treesitter-context')
require('user.treesitter-settings')
require('user.colorscheme')
require('user.feline-settings')
require('user.dap')
require('user.gigatextstreaming').setup()


local api = vim.api

-- Global options
local options = {
    sync_time_ms = 100,
    region_border_selected_colour = "#FF00FF",
}

-- Store for all regions
---@type table<number, Region[]>
local regions = {}
---@type table<number, string>
local selected_regions = {}

-- Unique ID generator for regions
local region_id_counter = 0
local function generate_region_id()
    region_id_counter = region_id_counter + 1
    return string.format("region_%d", region_id_counter)
end

---@class Region
---@field id string
---@field bufnr number
---@field line number
---@field same_line_ordering number
---@field extmark_id number
---@field content string
---@field title? string
---@field description? string
---@field filetype? string
---@field file? string
---@field shellcmd? string
---@field sync_time_ms? number
---@field job_output string[]
---@field is_selected boolean
local Region = {}
Region.__index = Region

-- Get list of regions in a buffer sorted by line number and same_line_ordering
---@param bufnr number
---@return Region[]
local function get_sorted_regions(bufnr)
    local buffer_regions = regions[bufnr] or {}
    return vim.tbl_filter(function(r) return r end, buffer_regions)
end

---@param region Region
local function select_region(region)
    local bufnr = region.bufnr
    -- Deselect all regions in the buffer first
    if regions[bufnr] then
        for _, r in pairs(regions[bufnr]) do
            if r and r.is_selected then
                r:remove_selection_mark()
            end
        end
    end
    
    -- Clear all selections for this buffer
    selected_regions[bufnr] = nil
    
    -- Update selection and show mark
    selected_regions[bufnr] = region.id
    region:show_selection_mark()
    
    -- Update the draw order of extmarks on the same line
    update_extmark_ordering(bufnr, region.line)
end

-- Create a new region and assign a unique same_line_ordering
---@param bufnr number
---@param line number
---@param opts { filetype?: string, content: string, title?: string, description?: string, file?: string, shellcmd?: string, sync_time_ms?: number }
---@return Region
function Region.new(bufnr, line, opts)
    local self = setmetatable({}, Region)
    self.id = generate_region_id()
    self.bufnr = bufnr
    self.line = line
    local buffer_regions = regions[bufnr] or {}
    local max_ordering = 0
    for _, region in pairs(buffer_regions) do
        if region and region.line == line then
            max_ordering = math.max(max_ordering, region.same_line_ordering or 0)
        end
    end
    self.same_line_ordering = max_ordering + 1
    self.content = opts.content or ""
    self.title = opts.title
    self.description = opts.description
    self.filetype = opts.filetype
    self.file = opts.file
    self.shellcmd = opts.shellcmd
    self.sync_time_ms = opts.sync_time_ms or options.sync_time_ms
    self.job_output = {}
    self.extmark_id = self:create_extmark()
    if self.shellcmd then
        self:setup_shell_sync()
    elseif self.file then
        self:setup_file_sync()
    end
    if not regions[bufnr] then
        regions[bufnr] = {}
    end
    regions[bufnr][self.id] = self
    return self
end

---@param bufnr number
---@param line number
---@param opts { content: string, title?: string, description?: string, priority: number }
local function create_plain_extmark_raw(bufnr, line, opts)
    local lines = vim.split(opts.content, "\n", { plain = true })
    local virt_lines = {}
    local separator = string.rep("─", 60)
    table.insert(virt_lines, {{"┌" .. separator .. "┐", "FloatBorder"}})
    if opts.title then
        table.insert(virt_lines, {{opts.title, 'Normal'}})
    end
    if opts.description then
        table.insert(virt_lines, {{opts.description, 'Comment'}})
    end
    for _, line_content in ipairs(lines) do
        table.insert(virt_lines, {{line_content, 'Normal'}})
    end
    table.insert(virt_lines, {{"└" .. separator .. "┘", "FloatBorder"}})
    local ns_id = api.nvim_create_namespace('syntax_highlighted_extmark')
    local extmark_id = api.nvim_buf_set_extmark(bufnr, ns_id, line, 0, {
        virt_lines = virt_lines,
        virt_lines_above = true,
        priority = opts.priority,
    })
    return extmark_id
end

---@param bufnr number
---@param line number
---@param opts { filetype: string, content: string, title?: string, description?: string, priority: number }
local function create_syntax_extmark_raw(bufnr, line, opts)
    local temp_bufnr = api.nvim_create_buf(false, true)
    api.nvim_buf_set_option(temp_bufnr, 'filetype', opts.filetype)
    api.nvim_buf_set_lines(temp_bufnr, 0, -1, false, vim.split(opts.content, "\n", { plain = true }))
    local parser = vim.treesitter.get_parser(temp_bufnr, opts.filetype)
    parser:parse()
    local virt_lines = {}
    local separator = string.rep("─", 60)
    table.insert(virt_lines, {{"┌" .. separator .. "┐", "FloatBorder"}})
    if opts.title then
        table.insert(virt_lines, {{opts.title, 'Normal'}})
    end
    if opts.description then
        table.insert(virt_lines, {{opts.description, 'Comment'}})
    end
    local lines = vim.split(opts.content, "\n", { plain = true })
    for line_num = 0, #lines - 1 do
        local line_content = lines[line_num + 1]
        local line_chunks = {}
        local processed = {}
        for i = 1, #line_content do
            processed[i] = false
        end
        local line_captures = {}
        for col = 0, #line_content - 1 do
            local captures = vim.treesitter.get_captures_at_pos(temp_bufnr, line_num, col)
            if #captures > 0 then
                local current_capture = captures[#captures]
                table.insert(line_captures, {
                    col = col,
                    capture = current_capture.capture
                })
            end
        end
        table.sort(line_captures, function(a, b)
            return a.col < b.col
        end)
        local current_pos = 0
        for i, capture in ipairs(line_captures) do
            if not processed[capture.col + 1] then
                if current_pos < capture.col then
                    local text = string.sub(line_content, current_pos + 1, capture.col)
                    if text ~= "" then
                        table.insert(line_chunks, {text, 'Normal'})
                    end
                end
                local span_end = capture.col
                for j = i + 1, #line_captures do
                    if line_captures[j].col == span_end + 1 and 
                       line_captures[j].capture == capture.capture then
                        span_end = line_captures[j].col
                    else
                        break
                    end
                end
                local text = string.sub(line_content, capture.col + 1, span_end + 1)
                if text ~= "" then
                    table.insert(line_chunks, {text, '@' .. capture.capture})
                end
                for pos = capture.col + 1, span_end + 1 do
                    processed[pos] = true
                end
                current_pos = span_end + 1
            end
        end
        if current_pos < #line_content then
            local text = string.sub(line_content, current_pos + 1)
            if text ~= "" then
                table.insert(line_chunks, {text, 'Normal'})
            end
        end
        if #line_chunks == 0 and line_content ~= "" then
            table.insert(line_chunks, {line_content, 'Normal'})
        end
        table.insert(virt_lines, line_chunks)
    end
    table.insert(virt_lines, {{"└" .. separator .. "┘", "FloatBorder"}})
    vim.schedule(function()
        pcall(api.nvim_buf_delete, temp_bufnr, { force = true })
    end)
    local ns_id = api.nvim_create_namespace('syntax_highlighted_extmark')
    local extmark_id = api.nvim_buf_set_extmark(bufnr, ns_id, line, 0, {
        virt_lines = virt_lines,
        virt_lines_above = true,
        priority = opts.priority,
    })
    return extmark_id
end


function Region:create_extmark()
    local same_line_regions = {}
    -- Find all regions on the same line
    if regions[self.bufnr] then
        for _, region in pairs(regions[self.bufnr]) do
            if region and region.line == self.line and region.id ~= self.id then
                table.insert(same_line_regions, region)
            end
        end
    end
    
    -- Sort by same_line_ordering to ensure consistent ordering
    table.sort(same_line_regions, function(a, b)
        return a.same_line_ordering < b.same_line_ordering
    end)
    
    log_debug("Creating extmark for region", self.id, "on line", self.line)
    for _, region in ipairs(same_line_regions) do
        log_debug("Found existing region", region.id, "with ordering:", region.same_line_ordering)
    end
    
    if self.filetype then
        return create_syntax_extmark_raw(self.bufnr, self.line, {
            content = self.content,
            title = (self.title or "") .. " [p:" .. self.same_line_ordering .. "]",
            description = self.description,
            filetype = self.filetype,
            priority = self.same_line_ordering
        })
    else
        return create_plain_extmark_raw(self.bufnr, self.line, {
            content = self.content,
            title = (self.title or "") .. " [p:" .. self.same_line_ordering .. "]",
            description = self.description,
            priority = self.same_line_ordering
        })
    end
end

function Region:update_content(new_content)
    if new_content ~= self.content then
        self.content = new_content
        -- Store current selection state
        local was_selected = self.is_selected
        -- Delete old extmark
        api.nvim_buf_del_extmark(self.bufnr, api.nvim_create_namespace('syntax_highlighted_extmark'), self.extmark_id)
        -- Create new extmark
        self.extmark_id = self:create_extmark()
        -- Reapply selection if it was selected
        if was_selected then
            self:show_selection_mark()
        end
        -- Update the ordering of all extmarks on the same line
        update_extmark_ordering(self.bufnr, self.line)
    end
end

function Region:show_selection_mark()
    local ns_id = api.nvim_create_namespace('syntax_highlighted_extmark')
    local details = api.nvim_buf_get_extmark_by_id(self.bufnr, ns_id, self.extmark_id, {details = true})
    
    -- Ensure no other regions are selected in this buffer
    if regions[self.bufnr] then
        for _, region in pairs(regions[self.bufnr]) do
            if region and region.id ~= self.id and region.is_selected then
                region:remove_selection_mark()
            end
        end
    end
    
    -- Mark region as selected
    self.is_selected = true
    
    -- Update the visual appearance
    local virt_lines = details[3].virt_lines
    if virt_lines and #virt_lines > 0 then
        -- Define our own highlight for selected borders
        vim.cmd(string.format([[highlight RegionBorderSelected guifg=%s gui=bold]], options.region_border_selected_colour))
        -- Update top border
        virt_lines[1] = {{virt_lines[1][1][1], "RegionBorderSelected"}}
        -- Update bottom border
        virt_lines[#virt_lines] = {{virt_lines[#virt_lines][1][1], "RegionBorderSelected"}}
        -- Reapply the extmark with updated colors
        api.nvim_buf_del_extmark(self.bufnr, ns_id, self.extmark_id)
        self.extmark_id = api.nvim_buf_set_extmark(self.bufnr, ns_id, details[1], details[2], {
            virt_lines = virt_lines,
            virt_lines_above = true,
            priority = self.same_line_ordering
        })
    end
end

function Region:remove_selection_mark()
    local ns_id = api.nvim_create_namespace('syntax_highlighted_extmark')
    local details = api.nvim_buf_get_extmark_by_id(self.bufnr, ns_id, self.extmark_id, {details = true})
    -- Mark region as not selected
    self.is_selected = false
    -- Correct access pattern
    local virt_lines = details[3].virt_lines
    if virt_lines and #virt_lines > 0 then
        -- Reset borders
        virt_lines[1] = {{virt_lines[1][1][1], "FloatBorder"}}
        virt_lines[#virt_lines] = {{virt_lines[#virt_lines][1][1], "FloatBorder"}}
        -- Reapply the extmark with updated colors
        api.nvim_buf_del_extmark(self.bufnr, ns_id, self.extmark_id)
        self.extmark_id = api.nvim_buf_set_extmark(self.bufnr, ns_id, details[1], details[2], {
            virt_lines = virt_lines,
            virt_lines_above = true,
            priority = self.same_line_ordering
        })
    end
end

function deselect_region()
    local bufnr = api.nvim_get_current_buf()
    
    -- Deselect all regions in the buffer
    if regions[bufnr] then
        for _, region in pairs(regions[bufnr]) do
            if region and region.is_selected then
                region:remove_selection_mark()
            end
        end
    end
    
    -- Clear selection state
    selected_regions[bufnr] = nil
    
    -- Update the draw order of extmarks
    if regions[bufnr] then
        for _, region in pairs(regions[bufnr]) do
            if region then
                update_extmark_ordering(bufnr, region.line)
            end
        end
    end
end

function delete_region()
    local bufnr = api.nvim_get_current_buf()
    local selected_id = selected_regions[bufnr]
    if selected_id and regions[bufnr] and regions[bufnr][selected_id] then
        local region = regions[bufnr][selected_id]
        -- Remove the region from the buffer's region list
        for i, r in ipairs(regions[bufnr]) do
            if r.id == region.id then
                table.remove(regions[bufnr], i)
                break
            end
        end
        region:destroy()
        selected_regions[bufnr] = nil
        -- Update the draw order of extmarks on the same line
        update_extmark_ordering(bufnr, region.line)
    end
end

function Region:destroy()
    -- Clean up timer
    if self.timer then
        self.timer:stop()
        self.timer = nil
    end
    -- Clean up job
    if self.job_id then
        vim.fn.jobstop(self.job_id)
        self.job_id = nil
    end
    -- Remove extmark
    api.nvim_buf_del_extmark(self.bufnr, api.nvim_create_namespace('syntax_highlighted_extmark'), self.extmark_id)
    -- Remove from regions store
    if regions[self.bufnr] then
        regions[self.bufnr][self.id] = nil
    end
end
function Region:setup_file_sync()
    -- Clean up existing timer if any
    if self.timer then
        self.timer:stop()
        self.timer = nil
    end
    -- Create new timer for file sync
    self.timer = vim.loop.new_timer()
    self.timer:start(0, self.sync_time_ms, vim.schedule_wrap(function()
        -- Read file content
        local ok, content = pcall(vim.fn.readfile, self.file)
        if ok then
            -- Update content if changed
            local new_content = table.concat(content, "\n")
            self:update_content(new_content)
        end
    end))
end

function Region:setup_shell_sync()
    -- Clean up existing job if any
    if self.job_id then
        vim.fn.jobstop(self.job_id)
        self.job_id = nil
    end
    -- Clear previous output
    self.job_output = {}

    --print("Starting command:", self.shellcmd) -- Debug

    -- Start the shell command
    self.job_id = vim.fn.jobstart(self.shellcmd, {
        on_stdout = function(_, data)
            --print("stdout received:", vim.inspect(data)) -- Debug
            if data and #data > 0 then
                -- Filter out empty lines at the end (jobstart often includes an empty last line)
                if data[#data] == "" then
                    table.remove(data)
                end
                if #data > 0 then
                    vim.list_extend(self.job_output, data)
                    -- Keep only last 50 lines
                    if #self.job_output > 50 then
                        local start = #self.job_output - 50 + 1
                        self.job_output = { unpack(self.job_output, start) }
                    end
                    -- Force an immediate update
                    vim.schedule(function()
                        local new_content = table.concat(self.job_output, "\n")
                        self:update_content(new_content)
                    end)
                end
            end
        end,
        on_stderr = function(_, data)
            --print("stderr received:", vim.inspect(data)) -- Debug
            if data and #data > 0 then
                if data[#data] == "" then
                    table.remove(data)
                end
                if #data > 0 then
                    vim.list_extend(self.job_output, data)
                    if #self.job_output > 50 then
                        local start = #self.job_output - 50 + 1
                        self.job_output = { unpack(self.job_output, start) }
                    end
                    -- Force an immediate update
                    vim.schedule(function()
                        local new_content = table.concat(self.job_output, "\n")
                        self:update_content(new_content)
                    end)
                end
            end
        end,
        stdout_buffered = false,  -- Changed to false for more immediate updates
        stderr_buffered = false   -- Changed to false for more immediate updates
    })

    --print("Job ID:", self.job_id) -- Debug

    -- Set up timer to sync job output
    self.timer = vim.loop.new_timer()
    self.timer:start(0, self.sync_time_ms, vim.schedule_wrap(function()
        --print("Timer tick, output lines:", #self.job_output) -- Debug
        local new_content = table.concat(self.job_output, "\n")
        self:update_content(new_content)
    end))
end

function select_region_near_cursor()
    local bufnr = api.nvim_get_current_buf()
    local cursor_pos = api.nvim_win_get_cursor(0)
    local cursor_line = cursor_pos[1]
    local closest_region = nil
    local closest_distance = math.huge
    local sorted_regions = get_sorted_regions(bufnr)

    for _, region in ipairs(sorted_regions) do
        if region.id ~= selected_regions[bufnr] then  -- Ignore the currently selected region
            local distance = math.abs(region.line - cursor_line)
            -- If distance is equal, prefer the region with lower same_line_ordering
            if distance < closest_distance or (distance == closest_distance and region.same_line_ordering < (closest_region and closest_region.same_line_ordering or math.huge)) then
                closest_region = region
                closest_distance = distance
            end
        end
    end

    if closest_region then
        select_region(closest_region)
    end
end

---@param region Region
local function select_region(region)
    local old_selected_id = selected_regions[region.bufnr]
    if old_selected_id and regions[region.bufnr] and regions[region.bufnr][old_selected_id] then
        -- Deselect previously selected region
        regions[region.bufnr][old_selected_id]:remove_selection_mark()
    end
    -- Remove old selection
    selected_regions[region.bufnr] = nil
    -- Only update if this isn't the region we just deselected
    if region.id ~= old_selected_id then
        -- Update selection and show mark
        selected_regions[region.bufnr] = region.id
        region:show_selection_mark()
    end
end

-- Updates extmark draw order to match region creation order
function update_extmark_ordering(bufnr, line)
    local ns_id = api.nvim_create_namespace('syntax_highlighted_extmark')
    local line_regions = {}
    if regions[bufnr] then
        for _, region in pairs(regions[bufnr]) do
            if region and region.line == line then
                table.insert(line_regions, region)
            end
        end
    end
    table.sort(line_regions, function(a, b)
        return a.same_line_ordering < b.same_line_ordering
    end)
    for _, region in ipairs(line_regions) do
        local details = api.nvim_buf_get_extmark_by_id(bufnr, ns_id, region.extmark_id, {details = true})
        if details and details[3] then
            api.nvim_buf_del_extmark(bufnr, ns_id, region.extmark_id)
            region.extmark_id = api.nvim_buf_set_extmark(bufnr, ns_id, details[1], details[2], {
                virt_lines = details[3].virt_lines,
                virt_lines_above = true,
                priority = 100 + region.same_line_ordering
            })
        end
    end
end

function create_highlighted_extmark(bufnr, line, opts)
    -- Validate inputs
    if not (opts.content or opts.shellcmd or opts.file) then
        error("One of content, shellcmd, or file is required in opts")
        return
    end

    -- If on line 1, insert empty line above and adjust target line
    local target_line = line
    if line == 0 then
        -- Get all windows showing this buffer
        local wins = vim.fn.win_findbuf(bufnr)
        -- Store cursor positions
        local cursor_positions = {}
        for _, win in ipairs(wins) do
            cursor_positions[win] = api.nvim_win_get_cursor(win)
        end
        
        -- Insert the line
        api.nvim_buf_set_lines(bufnr, 0, 0, false, {""})
        
        -- Adjust stored cursor positions
        for _, win in ipairs(wins) do
            local pos = cursor_positions[win]
            api.nvim_win_set_cursor(win, {pos[1] + 1, pos[2]})
        end

        -- Target line is now 1 (original line 1)
        target_line = 1
    end
    
    -- Create new region
    local region = Region.new(bufnr, target_line, opts)
    
    -- Update the draw order of extmarks on the same line
    update_extmark_ordering(bufnr, region.line)

    return region.id
end

function select_next_region()
    local bufnr = api.nvim_get_current_buf()
    local sorted_regions = get_sorted_regions(bufnr)
    if #sorted_regions == 0 then return end
    
    local current_id = selected_regions[bufnr]
    if not current_id then
        -- If no selection, select first region
        select_region(sorted_regions[1])
        return
    end
    
    -- Find current region's index
    local current_idx = nil
    for i, region in ipairs(sorted_regions) do
        if region.id == current_id then
            current_idx = i
            break
        end
    end
    
    if current_idx then
        -- Select next region (wrap around to start if at end)
        local next_idx = (current_idx % #sorted_regions) + 1
        select_region(sorted_regions[next_idx])
    end
end

function select_prev_region()
    local bufnr = api.nvim_get_current_buf()
    local sorted_regions = get_sorted_regions(bufnr)
    if #sorted_regions == 0 then return end
    
    local current_id = selected_regions[bufnr]
    if not current_id then
        -- If no selection, select last region
        select_region(sorted_regions[#sorted_regions])
        return
    end
    
    -- Find current region's index
    local current_idx = nil
    for i, region in ipairs(sorted_regions) do
        if region.id == current_id then
            current_idx = i
            break
        end
    end
    
    if current_idx then
        -- Select previous region (wrap around to end if at start)
        local prev_idx = ((current_idx - 2) % #sorted_regions) + 1
        select_region(sorted_regions[prev_idx])
    end
end

function paste_region()
    local bufnr = api.nvim_get_current_buf()
    local selected_id = selected_regions[bufnr]
    if selected_id and regions[bufnr] then
        for _, region in ipairs(regions[bufnr]) do
            if region.id == selected_id then
                local lines = {}
                
                -- Add title if present
                if region.title then
                    table.insert(lines, region.title)
                end
                
                -- Add description if present
                if region.description then
                    table.insert(lines, region.description)
                end
                
                -- Add content
                local content_lines = vim.split(region.content, "\n", { plain = true })
                vim.list_extend(lines, content_lines)
                
                -- Insert at region's line
                api.nvim_buf_set_lines(bufnr, region.line, region.line, false, lines)
                
                -- Delete the region after pasting
                delete_region()
                break
            end
        end
    end
end

-- Function to create floating window for command input
function create_command_window()
    -- Calculate window size and position
    local width = 60
    local height = 1
    local win_opts = {
        relative = "editor",
        width = width,
        height = height,
        col = math.floor((vim.o.columns - width) / 2),
        row = math.floor(vim.o.lines / 3),
        style = "minimal",
        border = "rounded"
    }

    -- Store the target buffer before opening floating window
    local target_bufnr = api.nvim_get_current_buf()
    local cursor_pos = api.nvim_win_get_cursor(0)
    local current_line = cursor_pos[1] - 1

    -- Create temp file using nvim's built-in function
    local tmp_file = vim.fn.tempname()

    -- Create buffer for command input and set path
    local buf = api.nvim_create_buf(false, true)
    vim.fn.bufload(buf)  -- Ensure buffer is loaded
    api.nvim_buf_set_name(buf, tmp_file)
    api.nvim_buf_set_option(buf, 'buftype', '')
    api.nvim_buf_set_option(buf, 'swapfile', false)

    -- Create window
    local win = api.nvim_open_win(buf, true, win_opts)
    api.nvim_win_set_option(win, 'winblend', 10)
    api.nvim_win_set_option(win, 'winhighlight', 'Normal:Normal,FloatBorder:FloatBorder')

    -- Function to close the window and optionally execute command
    local function close_and_execute(execute)
        local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
        local cmd = lines[1]
        -- Close the window first
        api.nvim_win_close(win, true)
        -- Schedule buffer deletion to avoid errors
        vim.schedule(function()
            if api.nvim_buf_is_valid(buf) then
                api.nvim_buf_delete(buf, { force = true })
            end
            -- Clean up temp file
            vim.fn.delete(tmp_file)

            -- Ensure target buffer is in normal mode
            vim.api.nvim_set_current_buf(target_bufnr)
            vim.cmd('stopinsert')

            if execute and cmd and cmd ~= "" then
                -- Create the region with the command
                create_highlighted_extmark(target_bufnr, current_line, {
                    shellcmd = cmd,
                    title = "Command Output: ",
                    description = cmd,
                })
            end
        end)
    end

    -- Set up autocommands for the buffer
    local group = api.nvim_create_augroup("CommandWindowGroup", { clear = true })
    
    -- Handle Enter key in insert mode
    api.nvim_create_autocmd("InsertEnter", {
        buffer = buf,
        group = group,
        callback = function()
            vim.keymap.set('i', '<CR>', function()
                close_and_execute(true)
            end, { buffer = buf, silent = true })
        end
    })

    -- Handle write commands
    api.nvim_create_autocmd("BufWriteCmd", {
        buffer = buf,
        group = group,
        callback = function()
            close_and_execute(true)
            return true
        end
    })

    -- Handle Escape in normal mode - now includes an implicit write
    vim.keymap.set('n', '<Esc>', function()
        -- Save current content
        if api.nvim_buf_is_valid(buf) then
            close_and_execute(true)  -- Changed to true to execute command
        end
    end, { buffer = buf, silent = true })

    -- Set prompt and enter insert mode
    api.nvim_buf_set_lines(buf, 0, -1, false, {""})
    vim.cmd('startinsert')

    -- Add title above the window
    local title_buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_lines(title_buf, 0, -1, false, {"Enter shell command:"})
    
    local title_win = api.nvim_open_win(title_buf, false, {
        relative = "editor",
        width = width,
        height = 1,
        col = win_opts.col,
        row = win_opts.row - 1,
        style = "minimal",
        focusable = false,
    })

    -- Clean up title window when command window closes
    api.nvim_create_autocmd("WinClosed", {
        pattern = tostring(win),
        callback = function()
            if api.nvim_win_is_valid(title_win) then
                api.nvim_win_close(title_win, true)
            end
            -- Also delete the title buffer
            if api.nvim_buf_is_valid(title_buf) then
                vim.schedule(function()
                    api.nvim_buf_delete(title_buf, { force = true })
                end)
            end
        end,
        once = true
    })
end

-- Debug logging function
function log_debug(...)
    local args = {...}
    local log_line = ""
    for i, v in ipairs(args) do
        if type(v) == "table" then
            log_line = log_line .. vim.inspect(v)
        else
            log_line = log_line .. tostring(v)
        end
        if i < #args then
            log_line = log_line .. " "
        end
    end
    -- Append to log file with timestamp
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local f = io.open(os.getenv("HOME") .. "/nvim_debug.log", "a")
    if f then
        f:write(string.format("[%s] %s\n", timestamp, log_line))
        f:close()
    end
end

-- Set up autocommands for cleanup
vim.api.nvim_create_autocmd("BufDelete", {
    callback = function(args)
        local bufnr = args.buf
        local buffer_regions = regions[bufnr] or {}
        for _, region in ipairs(buffer_regions) do
            region:destroy()
        end
        regions[bufnr] = nil
    end
})
-- Bind keys
-- vim.keymap.set('n', '<leader>h', add_highlighted_code_above_cursor, { desc = "Add highlighted code above cursor", noremap = true, silent = true })
vim.keymap.set('n', '<leader>rs', select_region_near_cursor, { desc = "Select nearest region", silent = true })
vim.keymap.set('n', '<leader>rf', select_next_region, { desc = "Select next region", silent = true })
vim.keymap.set('n', '<leader>rb', select_prev_region, { desc = "Select previous region", silent = true })
vim.keymap.set('n', '<leader>rS', deselect_region, { desc = "Deselect region", silent = true })
vim.keymap.set('n', '<leader>rx', delete_region, { desc = "Delete selected region", silent = true })
vim.keymap.set('n', '<leader>rp', paste_region, { desc = "Paste selected region", silent = true })
vim.keymap.set('n', '<leader>rq', create_command_window, { desc = "Create command region", silent = true })
--vim.keymap.set('n', '<leader>rz', fold_selected, { desc = "Hide contents of region", silent = true })
