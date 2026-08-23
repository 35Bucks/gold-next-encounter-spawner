return function(mod)
  local LEVEL_SCREEN_ID = "GoldEncounterSpawnerLevel"

  local armed = nil
  local appliedToCandidate = false
  local repeatMode = false

  local function clean(s)
    s = tostring(s or ""):upper()
    return (s:gsub("[^A-Z0-9]", ""))
  end

  local function resolveSpecies(game, raw)
    if not (game and game.data and game.data.pokemon) then return nil end

    local numeric = tonumber(raw)
    if numeric then
      numeric = math.floor(numeric)
      for id, def in pairs(game.data.pokemon) do
        if type(def) == "table" and tonumber(def.dex) == numeric then
          return id, def
        end
      end
    end

    local wanted = clean(raw)
    if wanted == "" then return nil end

    for id, def in pairs(game.data.pokemon) do
      if type(def) == "table" then
        if clean(id) == wanted or clean(def.name) == wanted then
          return id, def
        end
      end
    end

    return nil
  end

  local function showText(game, text, after)
    local TextBox = require("src.render.TextBox")
    game.stack:push(TextBox.new(game, text, after))
  end
  local keyLatch = {}

  local function pressed(input, logical, physical)
    if input:wasPressed(logical) then return true end
    if not (love and love.keyboard and love.keyboard.isDown and physical) then return false end
    local down = love.keyboard.isDown(physical)
    local was = keyLatch[physical] or false
    keyLatch[physical] = down
    return down and not was
  end

  -- Dedicated physical X fallback for BACK/CANCEL.
  -- Kept separate so it cannot interfere with native menu arrow handling.
  local function physicalXPressed()
    if not (love and love.keyboard and love.keyboard.isDown) then return false end
    local down = love.keyboard.isDown("x")
    local was = keyLatch["__physical_x"] or false
    keyLatch["__physical_x"] = down
    return down and not was
  end


  local function openLevelPicker(game, speciesId, def)
    -- Seed the physical Space-key latch before opening the level screen.
    -- Without this, the Space press used to confirm the name/ED cell can
    -- leak into the newly opened level picker on its very first use and
    -- instantly accept the default level. This changes no other controls.
    if love and love.keyboard and love.keyboard.isDown then
      keyLatch["space"] = love.keyboard.isDown("space")
    end
    mod.ui.push(game, LEVEL_SCREEN_ID, {
      species = speciesId,
      name = (def and def.name) or speciesId,
      level = 5,
    })
  end

  local function openSpeciesEntry(game)
    local NamingScreen = require("src.ui.NamingScreen")
    local screen = NamingScreen.new(game, {
      title = "POKEMON / DEX NO.?",
      default = "",
      maxLen = 12,
      onDone = function(value)
        local speciesId, def = resolveSpecies(game, value)
        if not speciesId then
          showText(game, "POKEMON NOT FOUND.\nTRY NAME OR DEX NO.", function()
            openSpeciesEntry(game)
          end)
          return
        end
        openLevelPicker(game, speciesId, def)
      end,
    })

    local originalUpdate = screen.update
    function screen:update(dt)
      if physicalXPressed() then
        game.stack:pop()
        return
      end
      if originalUpdate then originalUpdate(self, dt) end
    end

    game.stack:push(screen)
  end

  mod.content.screens:register(LEVEL_SCREEN_ID, {
    new = function(game, opts)
      opts = opts or {}
      local Font = mod.ui.Font
      local level = math.max(1, math.min(100, tonumber(opts.level) or 5))
      local species = assert(opts.species, "missing species")
      local name = tostring(opts.name or species)
      local self = { game = game, isOpaque = true }

      function self:update(dt)
        local input = game.input
        if pressed(input, "up", "up") then
          level = math.min(100, level + 1)
        elseif pressed(input, "down", "down") then
          level = math.max(1, level - 1)
        elseif pressed(input, "right", "right") then
          level = math.min(100, level + 10)
        elseif pressed(input, "left", "left") then
          level = math.max(1, level - 10)
        elseif pressed(input, "a", "space") then
          armed = { species = species, level = level, name = name }
          appliedToCandidate = false
          game.stack:pop()
          local mode = repeatMode and "REPEAT ON" or "ONE ENCOUNTER"
          showText(game, ("WILD SPAWN SET:\n%s  LV.%d\n%s"):format(name, level, mode))
        elseif physicalXPressed() or pressed(input, "b", "escape") then
          game.stack:pop()
        end
      end

      function self:draw()
        Font.drawBox(0, 0, 20, 18)
        Font.draw("WILD SPAWNER", 16, 16)
        Font.draw(name, 16, 40)
        Font.draw(("LEVEL  %d"):format(level), 16, 64)
        Font.draw("UP/DOWN  +/-1", 16, 88)
        Font.draw("LEFT/RIGHT +/-10", 8, 104)
        Font.draw("A:SET   B:BACK", 8, 128)
      end

      return self
    end,
  })

  local function openSpawnerMenu(game)
    -- Use Gen1Recomp's native Menu class instead of a custom menu screen.
    -- This makes navigation follow the player's normal control bindings,
    -- including the keyboard arrow keys on desktop/macOS.
    local Menu = require("src.ui.Menu")

    local items = {}

    local function refreshLabels()
      items[3].label = "REPEAT: " .. (repeatMode and "ON" or "OFF")
    end

    local function cancelPending()
      armed = nil
      appliedToCandidate = false
    end

    items[1] = {
      label = "SET POKEMON",
      onSelect = function()
        openSpeciesEntry(game)
      end,
    }

    items[2] = {
      label = "CANCEL PENDING",
      keepOpen = true,
      onSelect = function()
        if armed then
          cancelPending()
          showText(game, "PENDING SPAWN CANCELLED.")
        else
          showText(game, "NO SPAWN IS PENDING.")
        end
      end,
    }

    items[3] = {
      label = "REPEAT: " .. (repeatMode and "ON" or "OFF"),
      keepOpen = true,
      onSelect = function()
        repeatMode = not repeatMode
        refreshLabels()
        local state = repeatMode and "ON" or "OFF"
        showText(game, "REPEAT MODE: " .. state)
      end,
    }

    items[4] = {
      label = "EXIT",
      onSelect = function() end,
    }

    local menu = Menu.new(game, items, {
      title = "SPAWNER",
      tx = 1,
      ty = 2,
      tw = 18,
      cancelable = true,
    })

    local originalUpdate = menu.update
    function menu:update(dt)
      if physicalXPressed() then
        game.stack:pop()
        return
      end
      if originalUpdate then originalUpdate(self, dt) end
    end

    game.stack:push(menu)
  end

  -- Add digits to the naming grid so Pokedex numbers can be entered.
  mod.hooks:wrap("ui.naming.grid", function(next, grid, ctx)
    grid = next(grid, ctx)
    if not (ctx and ctx.title == "POKEMON / DEX NO.?") then return grid end

    local out = {}
    for i, row in ipairs(grid or {}) do out[i] = row end
    out[4] = { "0", "1", "2", "3", "4", "5", "6", "7", "8" }
    return out
  end, 120)

  mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
    items = next(game, items) or items
    mod.ui.insertBefore(items, "OPTION", {
      label = "SPAWNER",
      onSelect = function()
        openSpawnerMenu(game)
      end,
    })
    return items
  end, 120)

  -- Replace ordinary wild encounters while a spawn is armed.
  mod.hooks:wrap("encounter.species", function(next, enc, ctx)
    local rolled = next(enc, ctx)
    if not (armed and rolled) then return rolled end

    local kind = ctx and ctx.kind
    if kind and kind ~= "wild" and kind ~= "sweet_scent" then
      return rolled
    end

    rolled.species = armed.species
    rolled.level = armed.level
    appliedToCandidate = true
    return rolled
  end, 120)

  mod.events:on("battle.started", function(ev)
    if not (armed and appliedToCandidate and ev) then return end
    if ev.kind ~= "wild" then return end

    -- One-shot mode consumes the spawn after the battle really starts.
    -- Repeat mode keeps the same Pokemon/level armed for future encounters.
    if not repeatMode then
      armed = nil
    end
    appliedToCandidate = false
  end, 120)
end
