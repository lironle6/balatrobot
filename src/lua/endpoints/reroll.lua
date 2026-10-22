-- src/lua/endpoints/reroll.lua
local boss_reroll = assert(SMODS.load_file("src/lua/utils/boss_reroll.lua"))()

-- ==========================================================================
-- Reroll Endpoint Params
-- ==========================================================================

---@class Request.Endpoint.Reroll.Params

-- ==========================================================================
-- Reroll Endpoint
-- ==========================================================================

---@type Endpoint
return {

  name = "reroll",

  description = "Reroll shop cards, or the Boss Blind with boss=true",

  schema = { boss = { type = "boolean", required = false } },

  requires_state = { G.STATES.SHOP, G.STATES.BLIND_SELECT },

  ---@param params Request.Endpoint.Reroll.Params
  ---@param send_response fun(response: Response.Endpoint)
  execute = function(params, send_response)
    if params and params.boss then
      local reason = boss_reroll.reason()
      if reason then
        send_response({ name = BB_ERROR_NAMES.NOT_ALLOWED, message = reason })
        return
      end
      local before = G.GAME.dollars
      G.FUNCS.reroll_boss(nil)
      G.E_MANAGER:add_event(Event({
        trigger = "condition", blocking = false,
        func = function()
          if G.GAME.dollars == before - boss_reroll.cost and not G.CONTROLLER.locks.boss_reroll then
            save_run()
            send_response(BB_GAMESTATE.get_gamestate())
            return true
          end
          return false
        end,
      }))
      return
    end
    if G.STATE ~= G.STATES.SHOP then
      send_response({ name = BB_ERROR_NAMES.INVALID_STATE, message = "Shop reroll requires SHOP" })
      return
    end
    -- Check affordability (accounting for Credit Card joker via bankrupt_at)
    local reroll_cost = G.GAME.current_round and G.GAME.current_round.reroll_cost or 0
    local available_money = G.GAME.dollars - G.GAME.bankrupt_at

    if reroll_cost > 0 and available_money < reroll_cost then
      send_response({
        message = "Not enough dollars to reroll. Available: " .. available_money .. ", Required: " .. reroll_cost,
        name = BB_ERROR_NAMES.NOT_ALLOWED,
      })
      return
    end

    -- Log reroll with cost and money
    sendDebugMessage(string.format("Rerolling shop (cost=$%d, money=$%d)", reroll_cost, G.GAME.dollars), "BB.ENDPOINTS")
    G.FUNCS.reroll_shop(nil)

    -- Wait for shop state to confirm reroll completed
    G.E_MANAGER:add_event(Event({
      trigger = "condition",
      blocking = false,
      func = function()
        local done = G.STATE == G.STATES.SHOP
        if done then
          sendDebugMessage(string.format("Return reroll() money=$%d", G.GAME.dollars), "BB.ENDPOINTS")
          send_response(BB_GAMESTATE.get_gamestate())
        end
        return done
      end,
    }))
  end,
}
