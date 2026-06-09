local WeaponIcons = {}

local aliasMap = {
  appistol = 'ap_pistol',
  carbinerifle = 'carbine_rifle',
  carbineriflemk2 = 'carbine_rifle_mk2',
  carbinerifle_mk_ii = 'carbine_rifle_mk2',
  assaultrifle = 'assault_rifle',
  assaultriflemk2 = 'assault_rifle_mk2',
  combatmg = 'combat_mg',
  combatmgmk2 = 'combat_mg_mk2',
  combatmg_mk_ii = 'combat_mg_mk2',
  heavysniper = 'heavy_sniper',
  heavysnipermk2 = 'heavy_sniper_mk2',
  heavysniper_mk_ii = 'heavy_sniper_mk2',
  pumpshotgun = 'pump_shotgun',
  pumpshotgunmk2 = 'pump_shotgun_mk2',
  pumpshotgun_mk_ii = 'pump_shotgun_mk2',
  bullpuprifle = 'bullpup_rifle',
  bullpupriflemk2 = 'bullpup_rifle_mk2',
  marksmansniper = 'marksman_rifle',
  marksmanrifle = 'marksman_rifle',
  marksmanriflemk2 = 'marksman_rifle_mk2',
  marksman_rifle_mk_ii = 'marksman_rifle_mk2',
  smgmk2 = 'smg_mk2',
  smg_mk_ii = 'smg_mk2',
  snspistol = 'sns_pistol',
  snspistolmk2 = 'snspistol_mk2',
  unholy_hellbringer = 'raycarbine',
  widowmaker = 'rayminigun',
  up_n_atomizer = 'raypistol',
  wm29pistol = 'wm29_pistol',
  navyrevolver = 'navy_revolver',
  doubleaction = 'double_action',
  servicecarbine = 'service_rifle',
}

local function prettyLabel(name)
  if type(name) ~= "string" or name == "" then
    return "Unknown Weapon"
  end
  local clean = name:gsub("^WEAPON_", "")
  clean = clean:gsub("_", " ")
  return clean:sub(1,1):upper() .. clean:sub(2):lower()
end

local function normalizeSlug(slug)
  if type(slug) ~= "string" or slug == "" then return "" end
  slug = slug:lower()
  slug = slug:gsub("mk%W?ii", "mk2")
  slug = slug:gsub("mk%W?i", "mk1")
  slug = slug:gsub("(%d+)", "%1")
  slug = slug:gsub("[^%w_%-]", "_")
  slug = slug:gsub("%-+", "_")
  slug = slug:gsub("%s+", "_")
  slug = slug:gsub("__+", "_")
  return slug
end

function WeaponIcons.resolve(payload, overrides)
  overrides = overrides or {}
  local wepName = payload and payload.name or nil
  local slug = payload and payload.slug or nil
  local label = payload and payload.label or nil

  if wepName and overrides[wepName] then
    local ref = overrides[wepName]
    return {
      name = wepName,
      label = ref.label or label or prettyLabel(wepName),
      icon = ref.icon or ("images/" .. (ref.slug or "unknown") .. ".png"),
    }
  end

  slug = normalizeSlug(slug or "")
  if slug ~= "" and overrides[slug] then
    local ref = overrides[slug]
    return {
      name = wepName,
      label = ref.label or label or prettyLabel(wepName),
      icon = ref.icon or ("images/" .. (ref.slug or slug) .. ".png"),
    }
  end

  local iconSlug = slug
  if iconSlug == "" and type(wepName) == "string" then
    iconSlug = normalizeSlug(wepName:gsub("^WEAPON_", ""))
  end
  iconSlug = aliasMap[iconSlug] or iconSlug

  if iconSlug == "" then
    iconSlug = "unknown"
  end

  local resolvedLabel = label
  if (not resolvedLabel or resolvedLabel == "" or resolvedLabel == "NULL") and wepName then
    resolvedLabel = prettyLabel(wepName)
  end

  return {
    name = wepName or "UNKNOWN",
    label = resolvedLabel or "Unknown",
    icon = ("images/%s.png"):format(iconSlug),
  }
end

return WeaponIcons
