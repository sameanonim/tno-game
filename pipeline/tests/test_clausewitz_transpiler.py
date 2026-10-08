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


if __name__ == "__main__":
    test_comments_and_preprocessor_variables()
    test_duplicate_keys_prerequisites()
    test_trigger_ast_and_comparisons()
    test_bbcode_localization()
    print("ALL PYTHON ETL TRANSPILER TESTS PASSED SUCCESSFULLY!")
