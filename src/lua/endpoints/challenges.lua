local function rule_text(prefix, rule)
  local lines = G.localization.misc.v_text[prefix .. rule.id]
  if not lines then return rule.id .. (rule.value and (": " .. tostring(rule.value)) or "") end
  local text = table.concat(lines, " "):gsub("{[^}]*}", "")
  return (text:gsub("#1#", function() return tostring(rule.value or "") end))
end

local function item_name(item)
  local center = G.P_CENTERS[item.id] or G.P_TAGS[item.id] or G.P_BLINDS[item.id]
  local name = center and center.name or item.id
  if item.edition then name = name .. " (" .. item.edition .. ")" end
  if item.eternal then name = name .. " (Eternal)" end
  if item.pinned then name = name .. " (Pinned)" end
  return name
end

return {
  name = "challenges",
  description = "Read challenge names, rules, starting items and progress",
  schema = {},
  requires_state = nil,
  execute = function(_, send_response)
    local profile = G.PROFILES[G.SETTINGS.profile]
    local completed = profile.challenge_progress and profile.challenge_progress.completed or {}
    local challenges = {}
    for i, challenge in ipairs(G.CHALLENGES) do
      local details = {}
      for _, rule in ipairs(challenge.rules and challenge.rules.custom or {}) do
        table.insert(details, rule_text("ch_c_", rule))
      end
      for _, rule in ipairs(challenge.rules and challenge.rules.modifiers or {}) do
        table.insert(details, rule_text("ch_m_", rule))
      end
      for _, group in ipairs({{"jokers", "Jokers"}, {"consumeables", "Consumables"}, {"vouchers", "Vouchers"}}) do
        local names = {}
        for _, item in ipairs(challenge[group[1]] or {}) do table.insert(names, item_name(item)) end
        if #names > 0 then table.insert(details, group[2] .. ": " .. table.concat(names, ", ")) end
      end
      if challenge.deck then
        if challenge.deck.cards then table.insert(details, "Starting deck: " .. #challenge.deck.cards .. " cards") end
        for _, key in ipairs({"enhancement", "edition", "seal", "yes_ranks", "no_ranks", "yes_suits", "no_suits"}) do
          local value = challenge.deck[key]
          if value then
            if type(value) == "table" then
              local keys = {}
              for k, enabled in pairs(value) do if enabled then table.insert(keys, tostring(k)) end end
              table.sort(keys)
              value = table.concat(keys, ", ")
            end
            table.insert(details, "Deck " .. key:gsub("_", " ") .. ": " .. tostring(value))
          end
        end
      end
      for _, key in ipairs({"banned_cards", "banned_tags", "banned_other"}) do
        local names = {}
        for _, item in ipairs(challenge.restrictions and challenge.restrictions[key] or {}) do
          table.insert(names, item_name(item))
        end
        if #names > 0 then table.insert(details, "Banned: " .. table.concat(names, ", ")) end
      end
      table.insert(challenges, {
        id = challenge.id,
        name = localize(challenge.id, "challenge_names"),
        unlocked = (profile.challenges_unlocked or 0) >= i,
        completed = completed[challenge.id] == true,
        details = details,
      })
    end
    send_response({challenges = challenges})
  end,
}
