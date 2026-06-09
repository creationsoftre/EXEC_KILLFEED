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
local WeaponIcons = loadSharedModule("weapons")

local feedCfg = cfg.feed or {}
local debugEnabled = feedCfg.debug and feedCfg.debug.enabled
local overrides = feedCfg.weaponOverrides or {}
local streaks = {}
local seq = 0

local function nextId()
  seq = seq + 1
  return ("kf-%d"):format(seq)
end

local function applyRule(state, rule)
  if type(rule) ~= "table" then return end
  if rule.enabled ~= nil then state.enabled = rule.enabled end
  if rule.scope then state.scope = rule.scope end
  if rule.radius then state.radius = rule.radius end
  if rule.limit then state.limit = rule.limit end
  if rule.duration then state.duration = rule.duration end
end

local function resolvedSettings(payload)
  local state = {
    enabled = feedCfg.enabled ~= false,
    scope = feedCfg.defaultScope or 'session',
    radius = feedCfg.defaultRadius or 70.0,
    limit = feedCfg.limit or 6,
    duration = feedCfg.duration or 9.5,
    multi = feedCfg.multiKillWindow or 6.0,
  }
  applyRule(state, feedCfg.default)
  applyRule(state, feedCfg.sessions and feedCfg.sessions[payload.sessionId])
  applyRule(state, feedCfg.brackets and feedCfg.brackets[payload.bracket])
  applyRule(state, feedCfg.modes and feedCfg.modes[payload.mode])
  applyRule(state, feedCfg.locations and feedCfg.locations[payload.location])
  return state
end

local function addWatcher(out, seen, value)
  if not value then return end
  local id = tonumber(value) or value
  if not id or seen[id] then return end
  seen[id] = true
  out[#out+1] = id
end

local function centerFromPayload(payload)
  if payload.origin then return payload.origin end
  if payload.coords and payload.coords.killer then return payload.coords.killer end
  if payload.coords and payload.coords.victim then return payload.coords.victim end
  if payload.zone and payload.zone.center then return payload.zone.center end
  return nil
end

local function collectWatchers(payload, settings)
  local watchers, seen = {}, {}
  local scope = settings.scope or 'session'
  if debugEnabled then
    print(("[exec_killfeed] Collecting watchers scope=%s bucket=%s location=%s"):format(
      scope,
      tostring(payload.bucket),
      tostring(payload.location)
    ))
  end

  if scope == 'global' then
    for _, id in ipairs(GetPlayers()) do
      addWatcher(watchers, seen, tonumber(id) or id)
    end
    return watchers, seen
  end

  if scope == 'bucket' and payload.bucket then
    for _, id in ipairs(GetPlayers()) do
      local numeric = tonumber(id) or id
      local route = GetPlayerRoutingBucket(numeric)
      if route == payload.bucket then
        addWatcher(watchers, seen, numeric)
      end
    end
    return watchers, seen
  end

  if scope == 'radius' then
    local radius = settings.radius
    if feedCfg.useZoneRadius and (not radius or radius <= 0.0) then
      local zone = payload.zone
      if zone then
        radius = zone.sessionRadius or zone.domeRadius or zone.arenaRadius or radius
      end
    end
    if not radius or radius <= 0.0 then
      radius = feedCfg.defaultRadius or 60.0
    end
    local center = centerFromPayload(payload)
    if center then
      local radiusSq = radius * radius
      local allowSpectators = feedCfg.allowSpectatorsInRadius ~= false
      for _, id in ipairs(GetPlayers()) do
        local numeric = tonumber(id) or id
        local ped = GetPlayerPed(numeric)
        if ped ~= 0 then
          local pos = GetEntityCoords(ped)
          local dx = pos.x - center.x
          local dy = pos.y - center.y
          if (dx * dx + dy * dy) <= radiusSq then
            if allowSpectators or (payload.players and payload.players[numeric]) then
              addWatcher(watchers, seen, numeric)
            end
          elseif feedCfg.preferSessionPlayers and payload.players and payload.players[numeric] then
            addWatcher(watchers, seen, numeric)
          end
        end
      end
    end
  end

  if payload.players then
    for pid, allowed in pairs(payload.players) do
      if allowed then
        addWatcher(watchers, seen, pid)
      end
    end
  end

  return watchers, seen
end

local function trackStreak(killerId, windowSeconds)
  if not killerId then return 1 end
  local now = GetGameTimer()
  local window = math.max(1, math.floor(windowSeconds or 6.0))
  local info = streaks[killerId]
  if info and (now - info.ts) <= (window * 1000) then
    info.count = info.count + 1
    info.ts = now
    return info.count
  end
  streaks[killerId] = { count = 1, ts = now }
  return 1
end

local function buildTags(payload, settings, streakCount)
  local tags = {}
  if payload.headshot then
    tags[#tags+1] = { label = "HEADSHOT", kind = "headshot" }
  end
  if payload.distance then
    local dist = payload.distance
    if feedCfg.extremeShotThreshold and dist >= feedCfg.extremeShotThreshold then
      tags[#tags+1] = { label = "EXTREME RANGE", kind = "extreme" }
    elseif feedCfg.longshotThreshold and dist >= feedCfg.longshotThreshold then
      tags[#tags+1] = { label = "LONG SHOT", kind = "longshot" }
    end
  end
  if streakCount and streakCount >= 2 then
    local names = {
      [2] = "DOUBLE KILL",
      [3] = "TRIPLE KILL",
      [4] = "QUAD FEED",
    }
    local label = names[streakCount] or ("%dx STREAK"):format(streakCount)
    tags[#tags+1] = { label = label, kind = "streak", value = streakCount }
  end
  return tags
end

local function sanitizePlayer(ref)
  if type(ref) ~= "table" then return { id = 0, name = "Unknown" } end
  return {
    id = ref.id or 0,
    name = ref.name or "Unknown",
    team = ref.team,
  }
end

local function pushToClients(payload)
  local settings = resolvedSettings(payload)
  if debugEnabled then
    print(("[exec_killfeed] Resolved settings: scope=%s radius=%.2f limit=%d duration=%.2f"):format(
      tostring(settings.scope),
      tonumber(settings.radius or 0),
      tonumber(settings.limit or 0),
      tonumber(settings.duration or 0)
    ))
  end
  if not settings.enabled then return end

  local watchers, seen = collectWatchers(payload, settings)
  seen = seen or {}
  if type(payload.forceTargets) == "table" then
    for _, forced in ipairs(payload.forceTargets) do
      addWatcher(watchers, seen, forced)
    end
  end

  if #watchers == 0 then
    if debugEnabled then
      print(("[exec_killfeed] No watchers for kill event (scope=%s, location=%s, bucket=%s)"):format(
        settings.scope or "nil",
        payload.location or "nil",
        payload.bucket or "nil"
      ))
    end
    return 0
  end

  local streakCount = trackStreak(payload.killer and payload.killer.id, settings.multi)
  local tags = buildTags(payload, settings, streakCount)
  local weapon = WeaponIcons.resolve(payload.weapon or {}, overrides)

  payload.forceTargets = nil

  local data = {
    id = nextId(),
    killer = sanitizePlayer(payload.killer),
    victim = sanitizePlayer(payload.victim),
    weapon = weapon,
    distance = payload.distance,
    headshot = payload.headshot or false,
    tags = tags,
    streak = streakCount,
    sessionId = payload.sessionId,
    location = payload.location,
    bracket = payload.bracket,
    mode = payload.mode,
    radius = (settings.scope == 'radius') and settings.radius or nil,
    duration = settings.duration,
    limit = settings.limit,
    timestamp = os.time(),
  }

  if type(watchers) == "table" then
    for idx = 1, #watchers do
      TriggerClientEvent("exec_killfeed:pushEntry", watchers[idx], data)
    end
  else
    TriggerClientEvent("exec_killfeed:pushEntry", watchers or -1, data)
  end
  if debugEnabled then
    print(("[exec_killfeed] Dispatched kill: killer=%s victim=%s viewers=%d headshot=%s distance=%s weapon=%s"):format(
      data.killer.name or data.killer.id,
      data.victim.name or data.victim.id,
      #watchers,
      tostring(data.headshot),
      tostring(data.distance),
      data.weapon.name or "unknown"
    ))
  end
  return #watchers, data
end

AddEventHandler("exec_killfeed:onKill", function(eventPayload)
  if type(eventPayload) ~= "table" then return end
  pushToClients(eventPayload)
end)

exports("PushKill", function(eventPayload)
  pushToClients(eventPayload)
end)

AddEventHandler("playerDropped", function()
  streaks[source] = nil
end)

local function notifyTester(src, message, msgType)
  msgType = msgType or "inform"
  if debugEnabled then
    print(("[exec_killfeed] %s"):format(message))
  end
  if src <= 0 then
    print(("[exec_killfeed] %s"):format(message))
    return
  end
  local ok = pcall(function()
    TriggerClientEvent("ox_lib:notify", src, {
      title = "Killfeed",
      description = message,
      type = msgType
    })
  end)
  if not ok then
    TriggerClientEvent("chat:addMessage", src, {
      args = { "^5Killfeed", message }
    })
  end
end

local function parseTestArgs(args)
  local opts = { headshot = false }
  if type(args) ~= "table" then return opts end
  for _, raw in ipairs(args) do
    local num = tonumber(raw)
    if num and not opts.victimId and GetPlayerName(num) then
      opts.victimId = num
      opts.victimName = GetPlayerName(num)
    else
      local value = tostring(raw or "")
      local lower = value:lower()
      if lower == "headshot" or lower == "hs" then
        opts.headshot = true
      elseif lower:find("^dist[:=]") or lower:find("^distance[:=]") then
        local val = tonumber(lower:match("[:=]%s*(%d+%.?%d*)"))
        if val then opts.distance = val end
      elseif lower:find("^weapon[:=]") then
        local weapon = value:match("[:=]%s*(.+)")
        if weapon and weapon ~= "" then
          weapon = weapon:upper()
          if not weapon:find("^WEAPON_") then
            weapon = "WEAPON_" .. weapon
          end
          opts.weapon = weapon
        end
      elseif not opts.victimName then
        opts.victimName = value
      end
    end
  end
  return opts
end

local function buildTestPayload(src, opts)
  opts = opts or {}
  local ped = GetPlayerPed(src)
  if ped == 0 then return nil, "Player ped missing." end

  local killerPos = GetEntityCoords(ped)
  local heading = GetEntityHeading(ped)
  local dist = opts.distance or math.random(18, 65)
  local headingRad = math.rad(heading or 0.0)
  local victimPos = vector3(
    killerPos.x + math.cos(headingRad) * dist,
    killerPos.y + math.sin(headingRad) * dist,
    killerPos.z
  )

  local victimId = opts.victimId or 0
  local victimName = opts.victimName or (victimId > 0 and (GetPlayerName(victimId) or ("[" .. victimId .. "]"))) or "Target Dummy"

  local players = { [src] = true }
  if victimId > 0 then
    players[victimId] = true
  end

  local weaponName = opts.weapon or "WEAPON_CARBINERIFLE"

  return {
    sessionId = 0,
    bucket = GetPlayerRoutingBucket(src),
    location = "test_zone",
    bracket = "ffa",
    mode = "sandbox",
    killer = {
      id = src,
      name = GetPlayerName(src) or ("[" .. src .. "]")
    },
    victim = {
      id = victimId,
      name = victimName
    },
    weapon = { name = weaponName },
    distance = dist,
    headshot = opts.headshot or false,
    origin = killerPos,
    coords = { killer = killerPos, victim = victimPos },
    zone = { center = killerPos, sessionRadius = feedCfg.defaultRadius or 70.0 },
    players = players,
    forceTargets = { src },
  }, nil
end

RegisterCommand("killfeed_test", function(source, args)
  if source == 0 then
    print("[exec_killfeed] Run /killfeed_test from an in-game client.")
    return
  end

  local opts = parseTestArgs(args or {})
  local payload, err = buildTestPayload(source, opts)
  if not payload then
    notifyTester(source, err or "Unable to build test payload.")
    return
  end

  local sent, snapshot = pushToClients(payload)
  if debugEnabled then
    local viewers = sent or 0
    print(("[exec_killfeed] Test payload dispatched to %d viewer%s."):format(
      viewers,
      viewers == 1 and "" or "s"
    ))
  end
  if (sent or 0) == 0 and snapshot and source > 0 then
    TriggerClientEvent("exec_killfeed:pushEntry", source, snapshot)
    sent = 1
    if debugEnabled then
      print("[exec_killfeed] Forced fallback snapshot to tester.")
    end
  end

  notifyTester(source, ("Test kill pushed to %d viewer%s%s."):format(
    sent,
    sent == 1 and "" or "s",
    opts.headshot and " (headshot)" or ""
  ))
end, false)
