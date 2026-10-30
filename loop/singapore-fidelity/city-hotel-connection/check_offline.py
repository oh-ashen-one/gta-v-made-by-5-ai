#!/usr/bin/env python3
"""CPU-only geometry/configuration and source-contract checks. Never runs Godot.
These checks are intentionally not represented as native traversal or gameplay.
"""
import hashlib,json,re,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
G=ROOT/'game'
L=json.loads((G/'data/mbs-interior/city_access.json').read_text())
C=(G/'src/world/mbs_interior/city_hotel_access.gd').read_text()
S=(G/'src/core/game_state.gd').read_text()
M=(G/'src/main.gd').read_text()

def method(text,name):
    return text.split('func '+name+'(',1)[1].split('\nfunc ',1)[0]

class OfflineContract(unittest.TestCase):
    def test_entry_matches_current_south_tower(self):
        source=(G/'src/world/downtown/landmarks/mbs.gd').read_text()
        offsets=json.loads(re.search(r'const TOWER_DX := (\[[^\n]+\])',source)[1])
        self.assertEqual(L['entrance_offset'][0],offsets[2])
        # Current eastern tower ground shell begins at -12-33=-45m.
        # The doorway crossing is outside it by more than the .36m player radius.
        self.assertLess(L['entrance_offset'][2]+.36,-45)
        self.assertLess(L['entrance_offset'][2]+L['trigger_depth'],-45)
    def test_approach_has_capsule_and_prop_clearance(self):
        x,z,w,d=L['approach_rect_relative_xz'];dx=L['entrance_offset'][0]
        for i in range(101):
            pz=-63+(-47+63)*i/100
            self.assertTrue(x+.38<dx<x+w-.38 and z+.38<pz<z+d-.38)
        self.assertGreaterEqual(L['door_width']-2*.36,3.0)
    def test_route_stays_on_current_mbs_site(self):
        # Main plan's existing forecourt, after the Bayfront footway at z=-765.
        plan=(G/'src/world/downtown/plan.gd').read_text()
        self.assertIn('"mbs_site": {"rect": Rect2(-330.0, -765.0, 390.0, 105.0)',plan)
        for offset in [L['entrance_offset'],L['exit_offset']]:
            x,z=-118+offset[0],-705+offset[2]
            self.assertTrue(-330<x<60 and -765<z<-660)
    def test_no_new_driving_lane_ramp(self):
        entry=method(C,'_build_entrance')
        self.assertNotIn('col_beam(',entry)
        self.assertNotIn('road.width',entry)
    def test_all_dressing_respects_the_same_entrance_keepout(self):
        for name in ['plazas','planting','roads']:
            source=(G/f'src/world/downtown/{name}.gd').read_text()
            self.assertIn('city_access_layout.gd").approach_contains(',source)
    def test_existing_spaces_and_floor_geometry(self):
        inventory=json.loads((G/'data/mbs-interior/inventory.json').read_text())
        floors={r['id']:r for r in inventory['hotel_floors']}
        for kind,id in L['floor_ids'].items():
            floor=floors[id];g=floor['geometry']
            self.assertIn(floor['program'],['guest_floor','spa'])
            self.assertGreaterEqual(g['corridor_width_m'],2.4)
            self.assertGreater(g['clear_height_m'],1.75+.25)
            # The actual factory uses this corridor center, not the atrium void.
            z=g['void_min_z_m']-g['corridor_width_m']/2
            self.assertLess(z+.36,g['void_min_z_m'])
            self.assertGreater(z-.36,-g['cross_m']/2)
            self.assertGreater(L['stage_heights'][kind],400)
    def test_streaming_regions_cannot_overlap_each_other(self):
        heights=L['stage_heights']
        self.assertLess(heights['lobby']+76+5,heights['guest'])
        self.assertLess(heights['guest']+5,heights['spa'])
        self.assertLess(heights['spa']+5,1000)
    def test_preview_removed_and_normal_game_installs_access(self):
        self.assertFalse((G/'src/scenes/hotel_preview.tscn').exists())
        hud=(G/'src/ui/hud.gd').read_text()
        self.assertNotIn('hotel_preview',M+hud)
        self.assertNotIn('MBS hotel interior · Preview',hud)
        self.assertIn('hotel_access.setup(self)',M)
        self.assertNotIn('change_scene',C)
        self.assertNotIn('Player.new',C)
        self.assertNotIn('WorldBuilder.new',C)
    def test_visit_preserves_player_and_city_objects(self):
        suspend=method(C,'_suspend_city')
        self.assertIn('child==player',suspend)
        self.assertIn('child==main.hud',suspend)
        self.assertIn('"mode":child.process_mode',suspend)
        self.assertIn('"freeze":n.freeze',suspend)
        self.assertIn('n!=visual',suspend)
        self.assertNotIn('queue_free',suspend)
        self.assertNotIn('mission.restart',C)
        self.assertNotIn('Game.health=',C)
        self.assertIn('player.reset_action_state(false)',C)
    def test_entry_and_lift_guards_are_present(self):
        guards=method(C,'can_use')
        for guard in ['transitioning','Game.simulation_paused','main.started','player.alive','Game.health<=0','Game.MODE_FOOT','player.current_vehicle!=null','player.busy','is_visible_in_tree','_interaction_visible']:
            self.assertIn(guard,guards)
        build=method(C,'_construct_region')
        self.assertIn('["guest_lift","service_lift"]',build)
        self.assertIn('module.transition_requested.connect',build)
    def test_landing_guard_precedes_city_suspend(self):
        transition=method(C,'enter_space')
        self.assertLess(transition.index('_arrival_clear'),transition.index('_suspend_city'))
        self.assertIn('token!=_generation',transition)
        self.assertIn('not outside.is_finite()',transition)
    def test_save_never_writes_streaming_coordinates(self):
        save=method(C,'decorate_save')
        self.assertIn('var at:=_outside_landing',save)
        self.assertNotIn('player.global_position',save)
        self.assertNotIn('stage_heights',save)
        self.assertIn('data["hotel_visit"]={"version":1,"space":active_space}',save)
        write=method(S,'save_game')
        self.assertLess(write.index('hotel.decorate_save(data)'),write.index('_validate_save_data(data)'))
        self.assertIn('hotel.transitioning:return false',write)
    def test_invalid_load_has_no_partial_hotel_exit(self):
        load=method(S,'load_game')
        self.assertLess(load.index('_validate_save_data(parsed)'),load.index('hotel.leave_hotel(false)'))
        self.assertLess(load.index('hotel.leave_hotel(false)'),load.index('health = float'))
        self.assertIn('parsed.has("hotel_visit")',load)
        self.assertIn('hotel.transitioning:return false',load)
        layout=(G/'src/world/mbs_interior/city_access_layout.gd').read_text()
        validator=method(layout,'valid_visit')
        self.assertIn('value.size()!=2',validator)
        self.assertIn('["lobby","guest","spa"]',validator)
    def test_leave_is_noop_in_normal_city_and_death_restores_city(self):
        leave=method(C,'leave_hotel')
        self.assertLess(leave.index('active_space.is_empty() and not transitioning:return true'),leave.index('_move_player'))
        death=method(S,'respawn')
        self.assertLess(death.index('hotel.leave_hotel(false)'),death.index('body.respawn_at'))
    def test_no_engine_or_gpu_calls_in_offline_tool(self):
        self.assertNotIn('subprocess',Path(__file__).read_text().split('class OfflineContract')[0])

if __name__=='__main__':
    suite=unittest.defaultTestLoader.loadTestsFromTestCase(OfflineContract)
    result=unittest.TextTestRunner(verbosity=2).run(suite)
    receipt={'scope':'CPU-only numeric geometry, configuration and static source-contract checks; NOT native engine behavior, traversal, performance or rendering','tests':result.testsRun,'failures':len(result.failures),'errors':len(result.errors),'engine_started':False,'gpu_used':False,'files_sha256':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [G/'data/mbs-interior/city_access.json',G/'src/world/mbs_interior/city_hotel_access.gd',G/'src/world/mbs_interior/city_access_layout.gd',G/'src/main.gd',G/'src/core/game_state.gd']}}
    Path(__file__).with_name('OFFLINE_CHECKS.json').write_text(json.dumps(receipt,indent=2)+'\n')
    raise SystemExit(0 if result.wasSuccessful() else 1)
