local bevy_crates_cache = nil

local function get_bevy_cache()
  if bevy_crates_cache ~= nil then
    return bevy_crates_cache
  end
  local cache_dir = os.getenv('XDG_CACHE_HOME') or os.getenv('HOME') .. '/.cache'
  local bevy_cache_dir = cache_dir .. '/bevy'
  local bevy_crates_file = bevy_cache_dir .. '/bevy_crates'
  local file = io.open(bevy_crates_file, 'r')
  if not file then
    return nil
  end
  bevy_crates_cache = {}
  for line in file:lines() do
    local crate = line:match('^%s*(.-)%s*$')
    if crate ~= '' and not crate:match('^#') then
      bevy_crates_cache[crate] = true
    end
  end
  file:close()
  return bevy_crates_cache
end

local function resolve_relative_url(base_url, relative_url)
  -- Parse base URL
  local base_parts = {}
  for part in base_url:gmatch('[^/]+') do
    table.insert(base_parts, part)
  end
  -- Remove the last part (filename)
  table.remove(base_parts)
  -- Process relative URL
  for part in relative_url:gmatch('[^/]+') do
    if part == '..' then
      table.remove(base_parts)
    elseif part ~= '.' then
      table.insert(base_parts, part)
    end
  end
  local result = table.concat(base_parts, '/')
  -- Fix broken protocol
  result = result:gsub('^https:/', 'https://')
  return result
end

local function modify_openDocs_url(url)
  -- local debug_info = {}
  -- table.insert(debug_info, "=== START ===")
  -- table.insert(debug_info, "Original URL: " .. url)
  -- Always copy to clipboard at start
  -- vim.fn.setreg('+', table.concat(debug_info, "\n"))

  -- Quick check: if not a bevy_* crate, just open and return
  local crate_name = url:match('https://docs%.rs/(bevy_[^/]+)/')
  if not crate_name then
    -- table.insert(debug_info, "Not a bevy_* crate, opening as-is")
    -- vim.fn.setreg('+', table.concat(debug_info, "\n"))
    vim.fn.jobstart({'xdg-open', url}, {detach = true})
    return
  end
  --table.insert(debug_info, "Detected bevy_* crate: " .. crate_name)
  -- vim.fn.setreg('+', table.concat(debug_info, "\n"))
  local cache = get_bevy_cache()
  if not cache or not cache[crate_name] then
    -- table.insert(debug_info, "Crate not in cache or cache not found")
    -- vim.fn.setreg('+', table.concat(debug_info, "\n"))
    vim.fn.jobstart({'xdg-open', url}, {detach = true})
    return
  end
  -- table.insert(debug_info, "Crate found in cache, fetching HTML...")
  -- vim.fn.setreg('+', table.concat(debug_info, "\n"))
  -- Fetch HTML and parse meta refresh to get canonical URL
  vim.fn.jobstart(
    {'curl', '-s', url},
    {
      stdout_buffered = true,
      on_stdout = function(_, data)
        -- table.insert(debug_info, "=== CURL CALLBACK ===")
        -- vim.fn.setreg('+', table.concat(debug_info, "\n"))
        if not data then
          -- table.insert(debug_info, "No data from curl")
          -- vim.fn.setreg('+', table.concat(debug_info, "\n"))
          return
        end
        local html = table.concat(data, '\n')
        -- table.insert(debug_info, "HTML length: " .. #html)
        -- vim.fn.setreg('+', table.concat(debug_info, "\n"))
        local meta_refresh = html:match('meta%s+http%-equiv="refresh"%s+content="[^"]*URL=([^"]+)"')
        local canonical_url = url
        if meta_refresh then
          canonical_url = resolve_relative_url(url, meta_refresh)
          -- table.insert(debug_info, "Meta refresh found: " .. meta_refresh)
        else
          -- table.insert(debug_info, "No meta refresh found, using original URL")
        end
        -- table.insert(debug_info, "Canonical URL: " .. canonical_url)
        -- vim.fn.setreg('+', table.concat(debug_info, "\n"))
        local c_crate, c_version, _c_path_crate, c_rest = canonical_url:match('https://docs%.rs/([^/]+)/([^/]+)/([^/]+)(.*)')
        -- table.insert(debug_info, "Parsed canonical - crate: " .. tostring(c_crate))
        -- vim.fn.setreg('+', table.concat(debug_info, "\n"))
        if c_crate and c_crate:match('^bevy_') and cache[c_crate] then
          local suffix = c_crate:match('^bevy_(.+)$')
          -- table.insert(debug_info, "Transforming: " .. c_crate .. " -> bevy/" .. suffix)
          c_rest = c_rest:gsub('^/' .. suffix .. '/', '/')
          -- table.insert(debug_info, "After removing duplicate: " .. c_rest)
          local final_url = string.format(
            'https://docs.rs/bevy/%s/bevy/%s%s',
            c_version,
            suffix,
            c_rest
          )
          -- table.insert(debug_info, "Final URL: " .. final_url)
          -- vim.fn.setreg('+', table.concat(debug_info, "\n"))
          vim.fn.jobstart({'xdg-open', final_url}, {detach = true})
        else
          -- table.insert(debug_info, "Opening original URL")
          -- vim.fn.setreg('+', table.concat(debug_info, "\n"))
          vim.fn.jobstart({'xdg-open', url}, {detach = true})
        end
      end
    }
  )
end
