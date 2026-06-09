local function loadSharedModule(name)
  local resource = GetCurrentResourceName()
  local file = ("shared/%s.lua"):format(name)
  local src = LoadResourceFile(resource, file)
  assert(src, ("[exec_killfeed] Missing file %s"):format(file))
  local chunk, err = load(src, ("@%s/%s"):format(resource, file))
  assert(chunk, err)
  local ok, result = pcall(chunk)
  assert(ok, result)
  return result
end

local cfg = loadSharedModule("config")
local debugEnabled = cfg.feed and cfg.feed.debug and cfg.feed.debug.enabled and true or false

local anchor = { x = cfg.ui.defaultAnchor.x, y = cfg.ui.defaultAnchor.y }
local isEnabled = true
local dragging = false
local resourceName = GetCurrentResourceName()

local function notifyToggle(state)
  local payload = {
    title = "Killfeed",
    description = state and "Enabled" or "Disabled",
    type = state and "success" or "error"
  }
  if lib and lib.notify then
    lib.notify(payload)
    return
  end
  local ox = exports and exports.ox_lib or nil
  if ox and ox.notify then
    ox:notify(payload)
  end
end

local function notifyMessage(text, msgType)
  local payload = {
    title = "Killfeed",
    description = text,
    type = msgType or "inform"
  }
  if lib and lib.notify then
    lib.notify(payload)
    return
  end
  local ox = exports and exports.ox_lib or nil
  if ox and ox.notify then
    ox:notify(payload)
  else
    TriggerEvent("chat:addMessage", {
      args = { "^5Killfeed", text }
    })
  end
end

local function clamp(val, min, max)
  if min and val < min then return min end
  if max and val > max then return max end
  return val
end

local function roundTo(value, precision)
  precision = precision or 0.001
  return math.floor((value / precision) + 0.5) * precision
end

local function loadAnchor()
  local saved = GetResourceKvpString("killfeed:anchor")
  if not saved or saved == "" then return end
  local x, y = saved:match("([^,]+),([^,]+)")
  x, y = tonumber(x), tonumber(y)
  if x and y then
    anchor.x = clamp(x, 0.0, 1.0)
    anchor.y = clamp(y, 0.0, 1.0)
  end
end

local function persistAnchor()
  SetResourceKvp("killfeed:anchor", ("%0.4f,%0.4f"):format(anchor.x, anchor.y))
end

local function pushConfig()
  SendNUIMessage({
    action = "killfeed:config",
    payload = {
      anchor = anchor,
      scale = cfg.ui.scale or 1.0,
      showDistance = cfg.ui.showDistance ~= false,
      showWeaponLabel = cfg.ui.showWeaponLabel ~= false,
      maxNameLength = cfg.ui.maxNameLength or 18,
      dragHint = cfg.ui.dragHint,
      colors = cfg.ui.colors or {},
    }
  })
end

local function updateState()
  SendNUIMessage({
    action = "killfeed:state",
    payload = { enabled = isEnabled }
  })
end

local function toggleFeed()
  isEnabled = not isEnabled
  updateState()
  if not isEnabled then
    SendNUIMessage({ action = "killfeed:clear" })
  end
  notifyToggle(isEnabled)
end

local function setDragging(state)
  dragging = state
  SetNuiFocus(state, state)
  if SetNuiFocusKeepInput then
    SetNuiFocusKeepInput(false)
  end
  SendNUIMessage({
    action = "killfeed:drag",
    payload = { enabled = state, anchor = anchor }
  })
end

RegisterCommand(cfg.commands.toggle, toggleFeed, false)
RegisterKeyMapping(cfg.commands.toggle, "Toggle EXEC killfeed", "keyboard", "F10")

RegisterCommand(cfg.commands.move, function()
  setDragging(not dragging)
end, false)

RegisterCommand(cfg.commands.reset, function()
  anchor.x = cfg.ui.defaultAnchor.x
  anchor.y = cfg.ui.defaultAnchor.y
  persistAnchor()
  pushConfig()
end, false)

RegisterNUICallback("killfeed:ready", function(_, cb)
  pushConfig()
  updateState()
  cb("ok")
end)

RegisterNUICallback("killfeed:savePosition", function(data, cb)
  if type(data) == "table" then
    local bounds = cfg.ui.bounds or {}
    local minX = bounds.minX or 0.0
    local maxX = bounds.maxX or 1.0
    local minY = bounds.minY or 0.0
    local maxY = bounds.maxY or 1.0
    anchor.x = clamp(roundTo(data.x or anchor.x, cfg.ui.dragSnap or 0.005), minX, maxX)
    anchor.y = clamp(roundTo(data.y or anchor.y, cfg.ui.dragSnap or 0.005), minY, maxY)
    persistAnchor()
    pushConfig()
  end
  setDragging(false)
  cb("ok")
end)

RegisterNUICallback("killfeed:exitDrag", function(_, cb)
  setDragging(false)
  cb("ok")
end)

RegisterNetEvent("exec_killfeed:pushEntry", function(payload)
  if type(payload) ~= "table" then return end
  if not isEnabled then return end
  if debugEnabled then
    local killer = payload.killer and (payload.killer.name or payload.killer.id) or "?"
    local victim = payload.victim and (payload.victim.name or payload.victim.id) or "?"
    print(("[exec_killfeed] client received kill id=%s killer=%s victim=%s headshot=%s"):format(
      tostring(payload.id),
      tostring(killer),
      tostring(victim),
      tostring(payload.headshot)
    ))
  end
  SendNUIMessage({ action = "killfeed:push", payload = payload })
  if cfg.ui.enableSound ~= false and payload.tags then
    for _, tag in ipairs(payload.tags) do
      if tag.kind == "streak" and tag.value and tag.value >= 3 then
        PlaySoundFrontend(-1, "Event_Message_Purple", "GTAO_FM_Events_Soundset", false)
        break
      end
    end
  end
end)

RegisterNetEvent("exec_killfeed:clear", function()
  SendNUIMessage({ action = "killfeed:clear" })
end)

local function pushPreviewEntry()
  local now = GetGameTimer()
  local payload = {
    id = ("preview-%d"):format(now),
    killer = { id = -1, name = "Preview" },
    victim = { id = -2, name = "Target Dummy" },
    weapon = { label = "Carbine Rifle", icon = "images/carbine_rifle.png" },
    distance = math.random(25, 80),
    headshot = true,
    tags = { { label = "HEADSHOT", kind = "headshot" }, { label = "PREVIEW", kind = "streak" } },
    duration = (cfg.feed and cfg.feed.duration) or 6.0,
    limit = (cfg.feed and cfg.feed.limit) or 6,
  }
  SendNUIMessage({ action = "killfeed:push", payload = payload })
end

RegisterCommand("killfeed_preview", function()
  if not isEnabled then
    notifyMessage("Enable the killfeed first with /killfeed.", "error")
    return
  end
  pushPreviewEntry()
  notifyMessage("Preview entry spawned (local only).", "success")
end, false)

exports("SetEnabled", function(state)
  if type(state) == "boolean" then
    isEnabled = state
    updateState()
  end
end)

exports("SetAnchor", function(x, y)
  if type(x) == "number" and type(y) == "number" then
    anchor.x = clamp(x, 0.0, 1.0)
    anchor.y = clamp(y, 0.0, 1.0)
    persistAnchor()
    pushConfig()
  end
end)

CreateThread(function()
  Wait(500)
  loadAnchor()
  pushConfig()
  updateState()
end)

AddEventHandler("onResourceStop", function(res)
  if res ~= resourceName then return end
  if dragging then
    SetNuiFocus(false, false)
    if SetNuiFocusKeepInput then
      SetNuiFocusKeepInput(false)
    end
  end
end)
