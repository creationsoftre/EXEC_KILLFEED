local config = {}

config.commands = {
  toggle = 'killfeed',
  move = 'killfeed_move',
  reset = 'killfeed_resetpos',
}

config.feed = {
  enabled = true,
  limit = 6,
  duration = 6.0,
  multiKillWindow = 6.0,
  debug = {
    enabled = false,
  },
  defaultScope = 'global', -- radius | session | bucket | global
  defaultRadius = 70.0,
  useZoneRadius = true,
  allowSpectatorsInRadius = true,
  preferSessionPlayers = true,
  showHeadshotTagSeconds = 4.0,
  longshotThreshold = 65.0,
  extremeShotThreshold = 110.0,
  sessions = {},
  brackets = {
    ['1v1'] = { limit = 4, radius = 45.0, scope = 'session' },
    ['2v2'] = { limit = 5, radius = 55.0 },
    gangwar = { scope = 'global', radius = 140.0, limit = 8, duration = 12.0 },
  },
  modes = {},
  locations = {
    legion_square = { radius = 58.0 },
    jungle = { radius = 54.0 },
    mirror_park = { radius = 60.0 },
  },
  weaponOverrides = {
    -- ["WEAPON_GADGETPISTOL"] = { label = "Gadget Pistol", icon = "images/perico_pistol.png" },
  },
}

config.ui = {
  defaultAnchor = { x = 0.985, y = 0.16 },
  bounds = { minX = 0.2, maxX = 0.995, minY = 0.04, maxY = 0.8 },
  scale = 1.0,
  dragSnap = 0.005,
  showDistance = false,
  showWeaponLabel = false,
  enableSound = true,
  maxNameLength = 18,
  dragHint = "Drag to reposition.\nUse Confirm to save or Cancel to exit.",
  colors = {
    text = '#FFFFFF',
    muted = '#A8A8A8',
    accent = '#39FF14',
    accentDark = '#2EE60F',
    killer = '#57FF35',
    victim = '#FF3030',
    surface = 'rgba(4, 6, 8, 0.84)',
    surfaceAlt = 'rgba(9, 11, 13, 0.92)',
    stroke = 'rgba(57, 255, 20, 0.42)',
    placeholderBorder = '#2A2C30',
    placeholderBg = 'rgba(20, 21, 23, 0.85)',
    entryFrom = 'rgba(5, 8, 8, 0.92)',
    entryTo = 'rgba(8, 10, 12, 0.86)',
    entryBorder = 'rgba(57, 255, 20, 0.48)',
    dragBorder = 'rgba(57, 255, 20, 0.35)',
    dragOverlayBg = 'rgba(0, 0, 0, 0.6)',
    dragCancelBorder = '#FF3B3B',
  },
}

return config
