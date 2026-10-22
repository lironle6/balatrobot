-- Synchronous, display-only bridge for the reviewed JokerDisplay stable definitions.
local function shallow(t)
    local out = {}
    for k, v in pairs(t or {}) do out[k] = v end
    return setmetatable(out, getmetatable(t))
end

local function copy_data(t, seen)
    if type(t) ~= 'table' then return t end
    seen = seen or {}
    if seen[t] then return seen[t] end
    local out = {}
    seen[t] = out
    for k, v in pairs(t) do out[k] = copy_data(v, seen) end
    return setmetatable(out, getmetatable(t))
end

local function forbidden()
    error('Unavailable in display-only preview', 0)
end

return function(cards, owned)
    local real_G, real_JD, real_SMODS = G, JokerDisplay, SMODS
    local physical = real_G and real_G.jokers and real_G.jokers.cards or {}
    local blank = {}
    for i, joker in ipairs(physical) do blank[i] = {id = BB_CARD_IDS.get(joker), rows = {}} end
    if not real_JD or not real_G.GAME or type(cards) ~= 'table' then return blank end
    -- Baseline displays never select cards or inspect stale hands outside hand selection.
    if owned then cards = {} end
    local visible_hand = real_G.STATE == real_G.STATES.SELECTING_HAND and real_G.hand or nil
    if not owned and (not visible_hand or #cards == 0) then return blank end

    local present, wanted = {}, {}
    for _, card in ipairs(visible_hand and visible_hand.cards or {}) do
        -- Do this before inspecting abilities, ranks, suits, or constructing shadows.
        if card.facing ~= 'front' then return blank end
        present[card] = true
    end
    for _, card in ipairs(cards) do
        if not present[card] or wanted[card] then return blank end
        wanted[card] = true
    end

    local undo = {}
    local function replace(t, key, value)
        local previous = rawget(t, key)
        undo[#undo + 1] = function() rawset(t, key, previous) end
        rawset(t, key, value)
    end
    local ok, result = xpcall(function()
        local JD = shallow(real_JD)
        replace(_G, 'JokerDisplay', JD)
        local shadows = {}
        local function shadow(card)
            if shadows[card] then return shadows[card] end
            local out = shallow(card)
            shadows[card] = out
            out.ability = copy_data(card.ability)
            out.base = copy_data(card.base)
            out.joker_display_values = {}
            out.children = {}
            out.highlighted = wanted[card] or false
            -- Display callbacks must never fall through to gameplay/UI methods.
            for _, key in ipairs({'calculate_joker', 'add_to_deck', 'remove_from_deck',
                'set_ability', 'set_debuff', 'remove', 'save', 'load', 'click',
                'highlight', 'juice_up', 'initialize_joker_display', 'update_joker_display'}) do
                out[key] = forbidden
            end
            return out
        end
        local function area(original)
            local out = shallow(original)
            out.cards = {}
            for i, card in ipairs(original and original.cards or {}) do out.cards[i] = shadow(card) end
            for _, card in ipairs(out.cards) do card.area = out end
            return out
        end
        local hand, jokers, play = area(visible_hand), area(real_G.jokers), area(nil)
        local selected = {}
        for _, card in ipairs(cards) do selected[#selected + 1] = shadow(card) end
        selected = JD.sort_cards(selected)
        hand.highlighted = selected
        local game = setmetatable({}, {__index = function(_, key)
            if key == 'pseudorandom' or tostring(key):lower():find('seed', 1, true) then forbidden() end
            return real_G.GAME[key]
        end})
        -- Preserve only public deck size; placeholders carry no card identities or order.
        local deck_cards = {}
        for i = 1, #(real_G.deck and real_G.deck.cards or {}) do deck_cards[i] = false end
        local deck = setmetatable({cards = deck_cards}, {__index = forbidden, __newindex = forbidden})
        local preview_G = setmetatable({hand = hand, jokers = jokers, play = play, GAME = game, deck = deck}, {
            __index = function(_, key)
                if key == 'playing_cards' then forbidden() end
                return real_G[key]
            end
        })
        replace(_G, 'G', preview_G)
        if real_SMODS then
            local preview_SMODS = shallow(real_SMODS)
            -- JD.evaluate_hand calls scoring contexts in modern SMODS; never dispatch them.
            preview_SMODS.calculate_context = function() return {} end
            preview_SMODS.trigger_effects = function() return {} end
            replace(_G, 'SMODS', preview_SMODS)
        end
        for _, key in ipairs({'pseudorandom', 'pseudoseed', 'pseudorandom_element',
            'pseudoshuffle', 'save_run', 'draw_card', 'eval_card'}) do
            replace(_G, key, forbidden)
        end
        replace(math, 'random', forbidden)
        replace(math, 'randomseed', forbidden)
        if love and love.math then
            for _, key in ipairs({'random', 'randomNormal', 'setRandomSeed', 'newRandomGenerator'}) do
                replace(love.math, key, forbidden)
            end
        end
        JD.get_display_areas = function() return {jokers} end
        JD.current_hand = selected
        local text, poker_hands, scoring_hand = 'NULL', {}, {}
        if #selected > 0 then text, poker_hands, scoring_hand = JD.evaluate_hand(selected) end
        if text == 'Unknown' then return blank end
        JD.current_hand_info = {text = text, poker_hands = poker_hands, scoring_hand = scoring_hand}

        -- Establish every copy before any retrigger calculation, independent of Joker order.
        for _, joker in ipairs(jokers.cards) do
            local definition = JD.Definitions[joker.config.center.key]
            if definition and definition.get_blueprint_joker then
                local copied, debuffed = JD.calculate_blueprint_copy(joker)
                JD.copy_display(joker, copied, debuffed)
                -- Prevent JD.copy_display from initializing real UI nodes on later calls.
                joker.joker_display_values.blueprint_initialized = false
            end
        end
        local calculated, failed = {}, {}
        local function calculate(joker)
            if calculated[joker] then return not failed[joker] end
            calculated[joker] = true
            local definition = JD.Definitions[joker.config.center.key]
            local success = pcall(function()
                joker.joker_display_values.trigger_count = JD.calculate_joker_triggers(joker)
                if definition and definition.calc_function then definition.calc_function(joker) end
            end)
            failed[joker] = not success
            return success
        end
        for _, joker in ipairs(jokers.cards) do calculate(joker) end

        local function resolve(path, card)
            if type(path) ~= 'string' then return path end
            local parts = JD.strsplit(path, '.')
            local value = parts[1] == 'card' and card or _G[parts[1]]
            -- Match JD's path resolution, including retaining the parent for absent segments.
            for i = 2, #parts do if value[parts[i]] then value = value[parts[i]] end end
            return value
        end
        local function colour(value)
            if type(value) == 'function' then value = value() end
            if type(value) == 'table' and value.ref_table then value = value.ref_table[value.ref_value] end
            if value == G.C.CHIPS then return 'chips' end
            if value == G.C.MULT or value == G.C.XMULT then return 'mult' end
            return 'neutral'
        end
        local function row(nodes, defaults, source, parent)
            local parts, colours = {}, {}
            local function flatten(node, inherited)
                if not node then return end
                if node.border_nodes then
                    local border = node.border_colour or G.C.XMULT
                    for _, child in ipairs(node.border_nodes) do flatten(child, border) end
                    return
                end
                if node.dynatext then
                    -- Animated/random text has no single deterministic value; do not choose a roll.
                    error('Animated display unavailable', 0)
                end
                local value = node.text
                if node.ref_value and (node.ref_table or node.custom_table_function) then
                    local reference = node.custom_table_function and node.custom_table_function(source)
                        or resolve(node.ref_table, source)
                    value = reference and reference[node.ref_value]
                end
                if value == nil then return end
                if type(value) == 'function' then value = value() end

                local formatted = JD.text_format(value, {
                    config = {signed = node.signed, retrigger_type = node.retrigger_type},
                    UIBox = {parent = parent}
                })
                parts[#parts + 1] = formatted
                local c = colour(inherited or node.colour or defaults and defaults.colour)
                if c ~= 'neutral' then colours[c] = true end
            end
            for _, node in ipairs(nodes or {}) do flatten(node) end
            -- +0 and X1 are meaningful conditional displays, not missing data.
            local content = table.concat(parts)
            if content == '' then return nil end
            return {text = content, color = colours.chips and not colours.mult and 'chips'
                or colours.mult and not colours.chips and 'mult' or 'neutral'}
        end
        local output = {}
        for i, joker in ipairs(jokers.cards) do
            local success, rows = pcall(function()
                if joker.debuff or joker.facing == 'back' or failed[joker] then return {} end
                local source = joker.joker_display_values.blueprint_ability_joker or joker
                if joker.joker_display_values.blueprint_debuff or failed[source] or source.debuff then return {} end
                local definition = JD.Definitions[source.config.center.key]
                if not definition then return {} end
                if source.joker_display_values.is_active == false or source.joker_display_values.active == false then return {} end
                local main = row(definition.text or definition.line_1, definition.text_config, source, joker)
                if not main then return {} end
                local out = {main}
                -- Odds descriptions are part of the display, not sampled outcomes.
                for n = #(definition.extra or {}), 1, -1 do
                    local extra = row(definition.extra[n], definition.extra_config, source, joker)
                    if extra then out[#out + 1] = extra end
                end
                return out
            end)
            output[i] = {id = BB_CARD_IDS.get(physical[i]), rows = success and rows or {}}
        end
        return output
    end, function() return nil end)
    for i = #undo, 1, -1 do undo[i]() end
    return ok and result or blank
end
