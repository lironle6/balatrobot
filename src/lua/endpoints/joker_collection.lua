return {
  name = "joker_collection",
  description = "Read Joker collection unlock and discovery status",
  schema = {},
  requires_state = nil,
  execute = function(_, send_response)
    local jokers = {}
    for _, center in ipairs(G.P_CENTER_POOLS.Joker) do
      table.insert(jokers, {
        key = center.key,
        name = center.name,
        rarity = center.rarity,
        unlocked = center.unlocked == true,
        discovered = center.discovered == true,
      })
    end
    send_response({ jokers = jokers })
  end,
}
