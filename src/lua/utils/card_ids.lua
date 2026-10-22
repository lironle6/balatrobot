-- Keep API identity separate from native sort order, including duplicate saved sort_ids.
if BB_CARD_IDS then return BB_CARD_IDS end

local ids = {}
local assigned = setmetatable({}, {__mode = "k"})
local owners = setmetatable({}, {__mode = "v"})
local high = 0

local function valid(id)
  return type(id) == "number" and id >= 0 and id < math.huge and id % 1 == 0
end

function ids.advance(card)
  if valid(G.sort_id) then high = math.max(high, G.sort_id) end
  if card and valid(card.sort_id) then high = math.max(high, card.sort_id) end
  G.sort_id = high
end

function ids.get(card)
  if assigned[card] then return assigned[card] end
  ids.advance(card)
  local id = card.sort_id
  if not valid(id) or (owners[id] and owners[id] ~= card) then
    high = high + 1
    id = high
    G.sort_id = high
  end
  assigned[card], owners[id] = id, card
  return id
end

function ids.repair()
  -- Reserve the full native range before allocating any replacement API IDs.
  ids.advance()
  for _, card in pairs(G.I and G.I.CARD or {}) do ids.advance(card) end
  for _, card in pairs(G.playing_cards or {}) do ids.advance(card) end
  for _, card in pairs(G.I and G.I.CARD or {}) do ids.get(card) end
  for _, card in pairs(G.playing_cards or {}) do ids.get(card) end
end

local native_load = Card.load
local function loaded(card, ...)
  ids.advance(card)
  return ...
end
Card.load = function(self, ...)
  return loaded(self, native_load(self, ...))
end

BB_CARD_IDS = ids
ids.repair()
return ids
