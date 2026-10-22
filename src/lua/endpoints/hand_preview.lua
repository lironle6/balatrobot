local joker_preview = assert(SMODS.load_file("src/lua/utils/joker_display_preview.lua"))()

return {
  name = "hand_preview",
  description = "Read selected hand type and upgraded base chips/mult, without scoring",
  schema = {
    ids = {type = "array", required = true, items = "integer", description = "Selected API card IDs"},
  },
  requires_state = {G.STATES.SELECTING_HAND},
  execute = function(args, send_response)
    if #args.ids < 1 or #args.ids > G.hand.config.highlighted_limit then
      send_response({name = BB_ERROR_NAMES.BAD_REQUEST, message = "Select 1 to " .. G.hand.config.highlighted_limit .. " cards"})
      return
    end
    local wanted, cards = {}, {}
    for _, id in ipairs(args.ids) do
      if wanted[id] then
        send_response({name = BB_ERROR_NAMES.BAD_REQUEST, message = "Duplicate card ID"})
        return
      end
      wanted[id] = true
    end
    -- Use current hand order and IDs, so reordering cannot preview a different card.
    for _, card in ipairs(G.hand.cards) do
      if wanted[BB_CARD_IDS.get(card)] then
        if card.facing == "back" then
          send_response({available = false, reason = "Hidden cards selected"})
          return
        end
        table.insert(cards, card)
      end
    end
    if #cards ~= #args.ids then
      send_response({name = BB_ERROR_NAMES.BAD_REQUEST, message = "Selected cards are no longer in hand"})
      return
    end
    local hand, display = G.FUNCS.get_poker_hand_info(cards)
    local base = G.GAME.hands[hand]
    if not base then
      send_response({available = false, reason = "No poker hand"})
      return
    end
    send_response({available = true, hand = hand, name = display, level = base.level,
      chips = base.chips, mult = base.mult, jokers = joker_preview(cards)})
  end,
}
