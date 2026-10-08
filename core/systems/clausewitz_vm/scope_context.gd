class_name ScopeContext
extends RefCounted

"""
ScopeContext: Represents execution context stack for Clausewitz script evaluation.
Carries references to ROOT (CountryState), THIS (current node or object),
PREV (previous enclosing scope), and FROM (originator country/event context).
"""

var root: CountryState = null
var this_obj: Object = null
var prev: ScopeContext = null
var from_country: CountryState = null


func _init(
	p_root: CountryState = null,
	p_this: Object = null,
	p_prev: ScopeContext = null,
	p_from: CountryState = null
) -> void:
	root = p_root
	this_obj = p_this
	prev = p_prev
	from_country = p_from if p_from != null else p_root


"""Returns country tag of the root context, or empty StringName if unset."""
func get_root_tag() -> StringName:
	if root and not root.country_tag.is_empty():
		return StringName(root.country_tag)
	return &""


"""Pushes a new sub-scope with this context as PREV."""
func push_scope(p_this: Object = null, p_root: CountryState = null) -> ScopeContext:
	var next_root = p_root if p_root != null else root
	return ScopeContext.new(next_root, p_this, self, from_country)
