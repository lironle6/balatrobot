return {
  name = "start_challenge",
  description = "Start an unlocked challenge from the main menu",
  schema = { id = {type = "string", required = true, description = "Challenge ID"} },
  requires_state = {G.STATES.MENU},
  execute = function(args, send_response)
    local index
    for i, challenge in ipairs(G.CHALLENGES) do
      if challenge.id == args.id then index = i; break end
    end
    if not index then
      send_response({name = BB_ERROR_NAMES.BAD_REQUEST, message = "Unknown challenge ID"})
      return
    end
    if (G.PROFILES[G.SETTINGS.profile].challenges_unlocked or 0) < index then
      send_response({name = BB_ERROR_NAMES.NOT_ALLOWED, message = "Challenge is locked"})
      return
    end
    G.FUNCS.start_challenge_run({config = {id = index}})
    G.E_MANAGER:add_event(Event({
      no_delete = true,
      trigger = "condition",
      blocking = false,
      func = function()
        local done = G.GAME.challenge == args.id and G.blind_select_opts ~= nil
          and G.blind_select_opts.small ~= nil
          and G.blind_select_opts.small:get_UIE_by_ID("tag_Small") ~= nil
        if done then send_response(BB_GAMESTATE.get_gamestate()) end
        return done
      end,
    }))
  end,
}
