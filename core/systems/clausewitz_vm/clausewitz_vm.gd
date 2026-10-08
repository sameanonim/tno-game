class_name ClausewitzVM
extends RefCounted

"""
ClausewitzVM: Top-level Virtual Machine orchestrating ScopeContext,
VariableRegistry, TriggerEvaluator, and EffectExecutor.
Provides convenient high-level APIs for evaluating focus tree conditions
and executing narrative effects.
"""

var registry: VariableRegistry = null
var evaluator: TriggerEvaluator = null
var executor: EffectExecutor = null


func _init(p_registry: VariableRegistry = null) -> void:
	registry = p_registry if p_registry != null else VariableRegistry.new()
	evaluator = TriggerEvaluator.new(registry)
	executor = EffectExecutor.new(registry)
	executor.instruction_executed.connect(_on_instruction_executed)


func _on_instruction_executed(_instruction: ClausewitzInstruction, _scope: ScopeContext) -> void:
	# Hook for event logging, debugger telemetry and signal bus propagation
	pass


"""Evaluates an AST condition against a root CountryState."""
func eval_condition(ast: Dictionary, root: CountryState, default_fallback: bool = true) -> bool:
	var scope := ScopeContext.new(root)
	return evaluator.evaluate(ast, scope, default_fallback)


"""Executes a list of instructions against a root CountryState."""
func execute_effects(instructions: Array[ClausewitzInstruction], root: CountryState) -> void:
	var scope := ScopeContext.new(root)
	executor.execute_all(instructions, scope)


"""Creates a new ScopeContext bound to this VM."""
func create_scope(root: CountryState, this_obj: Object = null) -> ScopeContext:
	return ScopeContext.new(root, this_obj)
