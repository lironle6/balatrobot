local boss_reroll = {cost = 10}

function boss_reroll.reason()
  if G.STATE ~= G.STATES.SHOP and G.STATE ~= G.STATES.BLIND_SELECT then
    return "Boss reroll requires SHOP or BLIND_SELECT"
  end
  local game = G.GAME
  local vouchers = game.used_vouchers or {}
  local resets = game.round_resets or {}
  if not (vouchers.v_retcon or (vouchers.v_directors_cut and not resets.boss_rerolled)) then
    return "Boss reroll requires an available Director's Cut or Retcon"
  end
  if game.dollars - (game.bankrupt_at or 0) < boss_reroll.cost then
    return "Boss reroll requires $10"
  end
  if (resets.blind_states or {}).Boss == "Defeated"
    or (G.CONTROLLER.locks or {}).boss_reroll then
    return "Boss reroll unavailable"
  end
end

return boss_reroll
