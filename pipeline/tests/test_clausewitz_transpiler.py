"""
Unit tests for Clausewitz Lexer, AST Parser, and Transpiler.
"""

import sys
from pathlib import Path

# Add project root to sys.path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent))

from pipeline.parsers.clausewitz_transpiler import (
    ClausewitzLexer,
    ClausewitzParser,
    ASTBuilder,
    LocalizationColorTransformer,
    FocusTreeCompiler,
    parse_and_compile_clausewitz
)


def test_comments_and_preprocessor_variables():
    script = """
    # This is a comment at top
    @base_cost = 14
    @target_tag = RUS

    focus_tree = {
        id = test_tree
        focus = {
            id = focus_alpha
            cost = @base_cost # inline comment
            search_filters = { GER USA @target_tag }
        }
    }
    """
    tokens = ClausewitzLexer.tokenize(script)
    parser = ClausewitzParser(tokens)
    data = parser.parse()

    tree = data["focus_tree"]
    focus = tree["focus"]
    assert focus["id"] == "focus_alpha"
    assert focus["cost"] == 14
    assert focus["search_filters"] == ["GER", "USA", "RUS"]
    print("PASS: test_comments_and_preprocessor_variables")


def test_duplicate_keys_prerequisites():
    script = """
    focus_tree = {
        id = tree_with_prereqs
        focus = {
            id = focus_branch
            prerequisite = { focus = focus_a }
            prerequisite = { focus = focus_b focus = focus_c }
            mutually_exclusive = { focus = focus_x }
            mutually_exclusive = { focus = focus_y }
        }
    }
    """
    compiled = parse_and_compile_clausewitz(script)
    node = compiled["nodes"]["focus_branch"]

    # Prereqs must be CNF: AND groups, inside is OR
    assert len(node["prerequisites"]) == 2
    assert node["prerequisites"][0] == ["focus_a"]
    assert node["prerequisites"][1] == ["focus_b", "focus_c"]
    assert "focus_x" in node["mutually_exclusive"]
    assert "focus_y" in node["mutually_exclusive"]
    print("PASS: test_duplicate_keys_prerequisites")


def test_trigger_ast_and_comparisons():
    script = """
    focus_tree = {
        id = tree_triggers
        focus = {
            id = focus_cond
            available = {
                has_country_flag = war
                OR = {
                    check_variable = { gdp > 5 }
                    num_of_factories > 20
                }
            }
            completion_reward = {
                add_political_power = 50
                set_country_flag = economy_boosted
                country_event = { id = EVENT.100 days = 3 }
            }
            tno_midway_effects = {
                add_stability = 0.05
            }
        }
    }
    """
    compiled = parse_and_compile_clausewitz(script)
    node = compiled["nodes"]["focus_cond"]

    ast = node["available_ast"]
    assert ast["type"] == "AND"
    assert len(ast["children"]) == 2
    assert ast["children"][0] == {"op": "has_country_flag", "target": "war"}

    or_group = ast["children"][1]
    assert or_group["type"] == "OR"
    assert len(or_group["children"]) == 2

    # Check effects
    effects = node["on_completion_effects"]
    assert len(effects) == 3
    assert effects[0]["command"] == "add_political_power"
    assert effects[0]["args"] == {"value": 50}
    assert effects[1]["command"] == "set_country_flag"
    assert effects[2]["command"] == "country_event"

    # Check midway effects
    assert 0.5 in node["tno_midway_effects"]
    assert node["tno_midway_effects"][0.5][0]["command"] == "add_stability"
    print("PASS: test_trigger_ast_and_comparisons")


def test_bbcode_localization():
    raw_loc = "The war in §RWest Russia§! has ended. §GAllies§! rejoice under §YDemocracy§!."
    converted = LocalizationColorTransformer.paradox_to_bbcode(raw_loc)
    expected = "The war in [color=red]West Russia[/color] has ended. [color=green]Allies[/color] rejoice under [color=yellow]Democracy[/color]."
    assert converted == expected
    print("PASS: test_bbcode_localization")


def test_relative_coordinates_and_metadata():
    script = """
    focus_tree = {
        id = test_tree_relative
        country = { factor = 0 modifier = { tag = SAM } }
        focus = {
            id = root_focus
            x = 10
            y = 2
            cost = 14
            mutually_exclusive = { focus = alt_focus }
            cancel_if_invalid = no
            allow_branch = {
                has_country_flag = sam_crisis_active
            }
        }
        focus = {
            id = child_focus
            relative_position_id = root_focus
            x = 2
            y = 1
            cost = 7
            custom_effect_tooltip = SAM_reorganize_army_tt
            prerequisite = { focus = root_focus }
            completion_reward = {
                subtract_from_variable = { which = sam_tension value = 10 }
                load_focus_tree = sam_post_crisis_tree
            }
        }
        focus = {
            id = alt_focus
            x = 15
            y = 2
            cost = 14
        }
    }
    """
    compiled = parse_and_compile_clausewitz(script)
    nodes = compiled["nodes"]

    root = nodes["root_focus"]
    child = nodes["child_focus"]
    alt = nodes["alt_focus"]

    # Root coordinates
    assert root["grid_coord"] == [10, 2]
    assert root["cancel_if_invalid"] is False
    assert root["allow_branch_ast"]["type"] == "AND"
    assert root["allow_branch_ast"]["children"][0]["op"] == "has_country_flag"
    assert root["allow_branch_ast"]["children"][0]["target"] == "sam_crisis_active"

    # Child coordinates resolved via relative_position_id: 10 + 2 = 12, 2 + 1 = 3
    assert child["relative_position_id"] == "root_focus"
    assert child["grid_coord"] == [12, 3]
    assert child["custom_tooltip_id"] == "SAM_reorganize_army_tt"

    # Symmetrized mutually exclusive
    assert "alt_focus" in root["mutually_exclusive"]
    assert "root_focus" in alt["mutually_exclusive"]

    # Instructions
    effects = child["on_completion_effects"]
    assert len(effects) == 2
    assert effects[0]["command"] == "subtract_from_variable"
    assert effects[0]["args"]["which"] == "sam_tension"
    assert effects[1]["command"] == "load_focus_tree"
    print("PASS: test_relative_coordinates_and_metadata")


def test_event_parser_and_bundle():
    from pipeline.parsers.clausewitz_transpiler import ClausewitzEventParser, transpile_tno_bundle

    event_script = """
    add_namespace = SAM_crisis

    country_event = {
        id = SAM_crisis.1
        title = SAM_crisis.1.t
        desc = SAM_crisis.1.d
        picture = GFX_report_event_samara

        is_triggered_only = yes

        option = {
            name = SAM_crisis.1.a
            add_political_power = 25
            add_to_variable = { which = sam_tension value = 5 }
        }
        option = {
            name = SAM_crisis.1.b
            add_stability = -0.05
            set_country_flag = sam_vlasov_sick
        }
    }
    """

    loc_yml = '''l_russian:
  SAM_crisis.1.t:0 "Кризис в руководстве КОНР"
  SAM_crisis.1.d:0 "В Самаре нарастает напряженность."
  SAM_crisis.1.a:0 "Мы сохраним порядок."
  SAM_crisis.1.b:0 "Грядут тяжелые времена."
'''

    events = ClausewitzEventParser.parse_events(event_script)
    assert len(events) == 1
    ev = events[0]
    assert ev["event_id"] == "SAM_crisis.1"
    assert ev["is_triggered_only"] is True
    assert len(ev["options"]) == 2
    assert ev["options"][0]["title"] == "SAM_crisis.1.a"
    assert ev["options"][0]["rewards"][0]["command"] == "add_political_power"

    bundle = transpile_tno_bundle(
        focus_script="""focus_tree = { id = sam_test focus = { id = f1 x = 0 y = 0 } }""",
        loc_yml=loc_yml,
        events_script=event_script,
        tree_id="sam_test"
    )
    assert "tree" in bundle and "nodes" in bundle["tree"]
    assert "localization" in bundle
    assert bundle["localization"]["SAM_crisis.1.t"] == "Кризис в руководстве КОНР"
    assert len(bundle["events"]) == 1
    print("PASS: test_event_parser_and_bundle")


if __name__ == "__main__":
    test_comments_and_preprocessor_variables()
    test_duplicate_keys_prerequisites()
    test_trigger_ast_and_comparisons()
    test_bbcode_localization()
    test_relative_coordinates_and_metadata()
    test_event_parser_and_bundle()
    print("ALL PYTHON ETL TRANSPILER TESTS PASSED SUCCESSFULLY!")

