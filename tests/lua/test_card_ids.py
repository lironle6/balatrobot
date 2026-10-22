"""Isolated regression tests; no game, saves, or external packages required."""
import ctypes
import ctypes.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class CardIdentityTest(unittest.TestCase):
    def test_identity_and_load_counter(self):
        library = next((name for version in ("lua5.4", "lua5.3")
                        if (name := ctypes.util.find_library(version))), None)
        if not library:
            self.fail("Installed liblua5.4 or liblua5.3 required; no packages installed")
        lua = ctypes.CDLL(library)
        lua.luaL_newstate.restype = ctypes.c_void_p
        lua.luaL_openlibs.argtypes = [ctypes.c_void_p]
        lua.luaL_loadstring.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        lua.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int,
                                  ctypes.c_int, ctypes.c_ssize_t, ctypes.c_void_p]
        lua.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
        lua.lua_tolstring.restype = ctypes.c_char_p
        lua.lua_close.argtypes = [ctypes.c_void_p]
        state = lua.luaL_newstate()
        self.assertTrue(state)
        lua.luaL_openlibs(state)
        code = r'''
G = {sort_id = 2, I = {CARD = {}}, playing_cards = {}}
Card = {load = function(self, saved, marker)
  self.sort_id = saved
  return marker, nil, "tail"
end}
local a, b, c = {sort_id = 318}, {sort_id = 318}, {sort_id = 319}
G.I.CARD = {a, b, c, a}
G.playing_cards = {c, a, b}
local ids = dofile("src/lua/utils/card_ids.lua")
assert(G.sort_id >= 319, "startup counter")
local ai, bi, ci = ids.get(a), ids.get(b), ids.get(c)
assert(ai ~= bi and ai ~= ci and bi ~= ci, "duplicate IDs repaired")
assert(a.sort_id == 318 and b.sort_id == 318 and c.sort_id == 319,
       "native sort attributes unchanged")
G.I.CARD = {c, b, a}
for _ = 1, 5 do
  ids.repair()
  assert(ids.get(a) == ai and ids.get(b) == bi and ids.get(c) == ci,
         "stable through reorder and repeated serialization")
end
local loaded = {}
local first, middle, last = Card.load(loaded, 5000, "return")
assert(first == "return" and middle == nil and last == "tail", "native returns")
assert(G.sort_id >= 5000, "native load raises counter")
Card.load({}, 12)
assert(G.sort_id >= 5000, "lower saved IDs never lower counter")
G.sort_id = G.sort_id + 1
local fresh = {sort_id = G.sort_id}
assert(fresh.sort_id > 5000, "future native allocation")
assert(ids.get(fresh) ~= ids.get(loaded), "loaded/fresh unique")
local duplicate = {sort_id = 318}
assert(ids.get(duplicate) ~= ai and ids.get(duplicate) ~= bi, "late duplicate")
local missing = ids.get({})
assert(type(missing) == "number", "missing ID gets numeric identity")
-- Simulate a restored run resetting its counter after native loads.
G.sort_id = 0
G.I.CARD = {loaded, fresh, duplicate, a, b, c}
ids.repair()
assert(G.sort_id >= fresh.sort_id, "post snapshot repair counter")
assert(ids.get(a) == ai and ids.get(b) == bi, "snapshot repair stable")
local wrapper = Card.load
assert(dofile("src/lua/utils/card_ids.lua") == ids and Card.load == wrapper,
       "installation idempotent")
-- Exercise preview lookup against the API IDs, not native duplicate IDs.
SMODS = {load_file = function() return function() return function() return {} end end end}
G.STATES = {SELECTING_HAND = 1}
G.hand = {cards = {a, b}, config = {highlighted_limit = 5}}
a.facing, b.facing = "front", "front"
G.GAME = {hands = {High = {level = 1, chips = 5, mult = 1}}}
G.FUNCS = {get_poker_hand_info = function(cards)
  assert(#cards == 1 and cards[1] == b, "exact duplicate-ID card selected")
  return "High", "High Card"
end}
BB_ERROR_NAMES = {BAD_REQUEST = "BAD_REQUEST"}
local endpoint = dofile("src/lua/endpoints/hand_preview.lua")
local result
endpoint.execute({ids = {bi}}, function(value) result = value end)
assert(result.available == true, "preview uses API identity")
b.facing = "back"
endpoint.execute({ids = {bi}}, function(value) result = value end)
assert(result.available == false, "hidden-card refusal preserved")
'''
        # Paths are fixed test source paths, never save paths.
        import os
        previous = Path.cwd()
        try:
            os.chdir(ROOT)
            status = lua.luaL_loadstring(state, code.encode())
            if status == 0:
                status = lua.lua_pcallk(state, 0, 0, 0, 0, None)
            error = lua.lua_tolstring(state, -1, None) if status else None
            self.assertEqual(status, 0, error.decode() if error else "Lua failed")
        finally:
            os.chdir(previous)
            lua.lua_close(state)


if __name__ == "__main__":
    unittest.main()
