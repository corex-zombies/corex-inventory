from pathlib import Path
import unittest

from lupa import LuaRuntime


MODULE_PATH = Path(__file__).resolve().parents[1] / "server" / "stacking.lua"


class InventoryStackingTests(unittest.TestCase):
    def load_module(self):
        self.assertTrue(MODULE_PATH.exists(), "server/stacking.lua must exist")
        lua = LuaRuntime(unpack_returned_tuples=True)
        stacking = lua.execute(MODULE_PATH.read_text(encoding="utf-8"))
        return lua, stacking

    def test_has_item_sums_matching_slots(self):
        lua, stacking = self.load_module()
        items = lua.eval("{{name='bandage', count=3}, {name='bandage', count=3}}")
        self.assertEqual(stacking.Count(items, "bandage"), 6)
        self.assertTrue(stacking.HasItem(items, "bandage", 5))

    def test_remove_consumes_across_slots_atomically(self):
        lua, stacking = self.load_module()
        items = lua.eval(
            "{{name='cloth', count=3, slot='a'}, {name='cloth', count=3, slot='b'}}"
        )
        before = stacking.Serialize(items)
        ok, error = stacking.Remove(items, "cloth", 7)
        self.assertFalse(ok)
        self.assertEqual(error, "not_enough")
        self.assertEqual(stacking.Serialize(items), before)
        self.assertTrue(stacking.Remove(items, "cloth", 5))
        self.assertEqual(stacking.Count(items, "cloth"), 1)

    def test_add_fills_existing_stacks_and_respects_max_stack(self):
        lua, stacking = self.load_module()
        items = lua.eval(
            "{{name='bandage', count=7, slot='a', metadata={}}, "
            " {name='bandage', count=6, slot='b', metadata={}}}"
        )
        definition = lua.eval("{stackable=true, maxStack=10}")
        free = lua.eval("{{x=3,y=1}}")
        next_slot = lua.eval("(function() local n=0; return function() n=n+1; return 'n'..n end end)()")
        self.assertTrue(stacking.Add(items, definition, "bandage", 4, lua.table(), free, next_slot, False))
        counts = sorted(int(item.count) for item in items.values())
        self.assertEqual(counts, [7, 10])

    def test_required_new_slots_accounts_for_existing_capacity(self):
        lua, stacking = self.load_module()
        items = lua.eval("{{name='bandage', count=7, metadata={}}}")
        definition = lua.eval("{stackable=true, maxStack=10}")
        self.assertIsNotNone(stacking.RequiredNewSlots, "RequiredNewSlots must be exported")
        self.assertEqual(stacking.RequiredNewSlots(items, definition, "bandage", 14, lua.table(), False), 2)
        self.assertEqual(stacking.RequiredNewSlots(items, definition, "WEAPON_PISTOL", 2, lua.table(), True), 2)

    def test_add_preflight_does_not_mutate_when_grid_is_full(self):
        lua, stacking = self.load_module()
        items = lua.eval("{{name='bandage', count=10, slot='a', metadata={}}}")
        definition = lua.eval("{stackable=true, maxStack=10}")
        before = stacking.Serialize(items)
        ok, error = stacking.Add(items, definition, "bandage", 1, lua.table(), lua.table(), lua.eval("function() return 'n' end"), False)
        self.assertFalse(ok)
        self.assertEqual(error, "no_space")
        self.assertEqual(stacking.Serialize(items), before)

    def test_metadata_mismatch_does_not_merge(self):
        lua, stacking = self.load_module()
        items = lua.eval(
            "{{name='water', count=2, slot='a', metadata={quality='clean'}}, "
            " {name='water', count=2, slot='b', metadata={quality='dirty'}}}"
        )
        definition = lua.eval("{stackable=true, maxStack=10}")
        ok, error = stacking.MergeSlots(items, "a", "b", definition, False)
        self.assertFalse(ok)
        self.assertEqual(error, "metadata_mismatch")
        self.assertEqual(stacking.Count(items, "water"), 4)

    def test_full_and_partial_drag_merges(self):
        lua, stacking = self.load_module()
        definition = lua.eval("{stackable=true, maxStack=10}")

        full = lua.eval(
            "{{name='bandage', count=4, slot='source', metadata={}}, "
            " {name='bandage', count=3, slot='target', metadata={}}}"
        )
        self.assertTrue(stacking.MergeSlots(full, "source", "target", definition, False))
        self.assertEqual(len(list(full.values())), 1)
        self.assertEqual(int(full[1].count), 7)

        partial = lua.eval(
            "{{name='bandage', count=7, slot='source', metadata={}}, "
            " {name='bandage', count=8, slot='target', metadata={}}}"
        )
        self.assertTrue(stacking.MergeSlots(partial, "source", "target", definition, False))
        by_slot = {item.slot: int(item.count) for item in partial.values()}
        self.assertEqual(by_slot, {"source": 5, "target": 10})

    def test_weapons_are_always_separate(self):
        lua, stacking = self.load_module()
        items = lua.table()
        definition = lua.eval("{stackable=true, maxStack=99}")
        free = lua.eval("{{x=1,y=1},{x=3,y=1}}")
        next_slot = lua.eval("(function() local n=0; return function() n=n+1; return 'w'..n end end)()")
        self.assertTrue(stacking.Add(items, definition, "WEAPON_PISTOL", 2, lua.table(), free, next_slot, True))
        self.assertEqual([int(item.count) for item in items.values()], [1, 1])


if __name__ == "__main__":
    unittest.main(verbosity=2)
