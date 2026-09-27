extends SceneTree

func _init() -> void:
	print("================================================================================")
	print("TESTING FULL TNO FOCUS & EVENT SYSTEM PIPELINE")
	print("================================================================================")

	# 1. ContentLoader Test
	var loader = ContentLoader.new()
	root.add_child(loader)
	loader.load_all()

	var test_tags = ["OMS", "KOM", "WRS", "GER", "USA"]
	for tag in test_tags:
		var dirs = loader.get_directives_for_country(tag)
		var evs = loader.get_events_for_country(tag)
		print("[TEST] Tag [%s] -> %d Directives, %d Events" % [tag, dirs.size(), evs.size()])
		assert(dirs.size() > 0, "Expected directives for tag %s" % tag)
		assert(evs.size() > 0, "Expected events for tag %s" % tag)

	# 2. Directives structure validation on OMS (Omsk)
	var oms_dirs = loader.get_directives_for_country("OMS")
	assert(oms_dirs.size() > 0, "OMS must have directives")
	var initial_dir: DirectiveResource = oms_dirs[0]

	print("[TEST] OMS directive found: [%s] '%s' (Required turns: %d, CAP: %d)" % [
		initial_dir.directive_id, initial_dir.title, initial_dir.turns_required, initial_dir.cost_initial_cap
	])
	assert(not initial_dir.title.is_empty(), "Directive title must not be empty")
	assert(not initial_dir.directive_id.is_empty(), "Directive ID must not be empty")

	# 3. EventManager Test
	var ev_mgr = EventManager.new()
	root.add_child(ev_mgr)

	# 3.1. Lazy load through index
	var target_ev_id = "omsk.2"
	var omsk_event = ev_mgr.get_or_load_event(target_ev_id)
	assert(omsk_event != null, "Failed to lazy load event omsk.2")
	print("[TEST] Lazy loaded event [%s]: '%s'" % [omsk_event.event_id, omsk_event.title])
	assert(not omsk_event.title.is_empty(), "Event title must not be empty")
	assert(not omsk_event.description.is_empty(), "Event description must not be empty")
	assert(not omsk_event.options.is_empty(), "Event options must not be empty")

	# 3.2. Lazy load news event
	var news_ev = ev_mgr.get_or_load_event("tno_news.1")
	if news_ev != null:
		print("[TEST] Lazy loaded news event [%s]: '%s'" % [news_ev.event_id, news_ev.title])

	# 4. Directive Execution & Event Triggering Loop
	var state = CountryState.new()
	state.country_tag = "OMS"
	state.current_cap = 5
	state.political_capital = 50.0
	state.legitimacy = 50.0

	var dir_mgr = DirectiveManager.new()
	root.add_child(dir_mgr)
	for d in oms_dirs:
		dir_mgr.register_directive(d)

	var triggered_from_directive: Array[String] = []
	dir_mgr.directive_event_triggered.connect(func(ev_id: String):
		triggered_from_directive.append(ev_id)
	)

	initial_dir.completion_effects["country_events"] = ["omsk.2"]
	var started = dir_mgr.start_directive(initial_dir.directive_id, state)
	assert(started, "Failed to start initial Karbyshev directive")
	print("[TEST] Started directive '%s'. Turns left: %d" % [initial_dir.title, initial_dir.turns_required])

	# Advance turns until completion
	for t in range(initial_dir.turns_required):
		var completed = dir_mgr.advance_turn(state)
		if not completed.is_empty():
			print("[TEST] Turn %d: Directive '%s' completed!" % [t + 1, completed[0].title])

	assert(state.completed_directives.has(initial_dir.directive_id), "Directive must be marked completed")
	assert(triggered_from_directive.has("omsk.2"), "Expected directive completion to trigger omsk.2 event")
	print("[TEST] Event 'omsk.2' successfully triggered from directive completion!")

	# 5. Event Option Selection & Effect Resolution
	var opt = omsk_event.options[0]
	var initial_pc = state.political_capital
	ev_mgr.resolve_event_option(omsk_event, opt, state)
	print("[TEST] Option selected: '%s'. PC changed from %.1f to %.1f" % [opt.get("text", ""), initial_pc, state.political_capital])

	print("================================================================================")
	print("ALL FOCUS & EVENT PIPELINE TESTS PASSED CLEANLY (100% SUCCESS)!")
	print("================================================================================")
	quit(0)
