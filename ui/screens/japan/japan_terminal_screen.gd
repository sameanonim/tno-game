class_name JapanTerminalScreen
extends PanelContainer

##
## JapanTerminalScreen: Интерактивный терминал Императорской Японии (JAP)
## Эстетика: CRT терминал спецслужб/министерств Токио (зеленый/бирюзовый/янтарный люминофор, псевдографика).
##

signal closed()

@onready var btn_close: Button = $VBox/HeaderHBox/CloseButton
@onready var lbl_header_title: Label = $VBox/HeaderHBox/TitleLabel

# Верхняя информационная панель
@onready var lbl_pm_info: Label = $VBox/TopHUD/HBox/PMLabel
@onready var lbl_tse_index: Label = $VBox/TopHUD/HBox/TSELabel
@onready var lbl_approval: Label = $VBox/TopHUD/HBox/ApprovalLabel
@onready var lbl_evidence: Label = $VBox/TopHUD/HBox/EvidenceLabel

# Вкладки
@onready var btn_tab_yasuda: Button = $VBox/TabBarHBox/BtnTabYasuda
@onready var btn_tab_diet: Button = $VBox/TabBarHBox/BtnTabDiet
@onready var btn_tab_zaibatsu: Button = $VBox/TabBarHBox/BtnTabZaibatsu
@onready var btn_tab_sphere: Button = $VBox/TabBarHBox/BtnTabSphere

# Секции
@onready var sec_yasuda: VBoxContainer = $VBox/ContentScroll/SectionsVBox/SectionYasuda
@onready var sec_diet: VBoxContainer = $VBox/ContentScroll/SectionsVBox/SectionDiet
@onready var sec_zaibatsu: VBoxContainer = $VBox/ContentScroll/SectionsVBox/SectionZaibatsu
@onready var sec_sphere: VBoxContainer = $VBox/ContentScroll/SectionsVBox/SectionSphere

# Лог внизу
@onready var lbl_log_status: Label = $VBox/BottomBar/StatusLogLabel

var japan_manager: JapanEmpireManager = null
var current_tab: String = "yasuda"


func _ready() -> void:
	_apply_terminal_styling()
	_connect_signals()
	_switch_tab("yasuda")


func setup(mgr: JapanEmpireManager) -> void:
	japan_manager = mgr
	if japan_manager != null:
		if not japan_manager.yasuda_crisis_triggered.is_connected(_on_manager_update):
			japan_manager.yasuda_crisis_triggered.connect(_on_manager_update)
		if not japan_manager.yasuda_crisis_resolved.is_connected(_on_manager_update):
			japan_manager.yasuda_crisis_resolved.connect(_on_manager_update)
		if not japan_manager.prime_minister_elected.is_connected(_on_manager_update):
			japan_manager.prime_minister_elected.connect(_on_manager_update)
		if not japan_manager.ija_ijn_balance_shifted.is_connected(_on_manager_update):
			japan_manager.ija_ijn_balance_shifted.connect(_on_manager_update)

	refresh_ui()


func _on_manager_update(_arg1 = null, _arg2 = null) -> void:
	refresh_ui()


func _apply_terminal_styling() -> void:
	TNOTheme.apply_panel_style(self, TNOTheme.COLOR_BORDER_CYAN, TNOTheme.COLOR_BG_DARK)
	if btn_close != null:
		TNOTheme.apply_button_style(btn_close, TNOTheme.COLOR_BORDER_AMBER, Color(0.12, 0.05, 0.05, 0.95))


func _connect_signals() -> void:
	if btn_close != null and not btn_close.pressed.is_connected(func(): visible = false; closed.emit()):
		btn_close.pressed.connect(func(): visible = false; closed.emit())

	if btn_tab_yasuda != null:
		btn_tab_yasuda.pressed.connect(func(): _switch_tab("yasuda"))
	if btn_tab_diet != null:
		btn_tab_diet.pressed.connect(func(): _switch_tab("diet"))
	if btn_tab_zaibatsu != null:
		btn_tab_zaibatsu.pressed.connect(func(): _switch_tab("zaibatsu"))
	if btn_tab_sphere != null:
		btn_tab_sphere.pressed.connect(func(): _switch_tab("sphere"))


func _switch_tab(tab_name: String) -> void:
	current_tab = tab_name
	if sec_yasuda != null: sec_yasuda.visible = (tab_name == "yasuda")
	if sec_diet != null: sec_diet.visible = (tab_name == "diet")
	if sec_zaibatsu != null: sec_zaibatsu.visible = (tab_name == "zaibatsu")
	if sec_sphere != null: sec_sphere.visible = (tab_name == "sphere")

	var col_active = Color(0.0, 0.95, 1.0, 1.0)
	var col_dim = Color(0.4, 0.6, 0.55, 0.8)
	if btn_tab_yasuda != null: btn_tab_yasuda.modulate = col_active if tab_name == "yasuda" else col_dim
	if btn_tab_diet != null: btn_tab_diet.modulate = col_active if tab_name == "diet" else col_dim
	if btn_tab_zaibatsu != null: btn_tab_zaibatsu.modulate = col_active if tab_name == "zaibatsu" else col_dim
	if btn_tab_sphere != null: btn_tab_sphere.modulate = col_active if tab_name == "sphere" else col_dim

	refresh_ui()


func refresh_ui() -> void:
	if japan_manager == null:
		return

	# Верхний статус
	if lbl_pm_info != null:
		lbl_pm_info.text = "ПРЕМЬЕР: %s" % japan_manager.current_prime_minister.to_upper()
	if lbl_tse_index != null:
		var tse = japan_manager.tse_index
		lbl_tse_index.text = "БИРЖА TSE: %0.1f ПТ" % tse
		lbl_tse_index.modulate = Color(0.3, 1.0, 0.4) if tse >= 800.0 else (Color(1.0, 0.8, 0.2) if tse >= 600.0 else Color(1.0, 0.2, 0.2))
	if lbl_approval != null:
		lbl_approval.text = "ДОВЕРИЕ: %0.0f%%" % japan_manager.ino_cabinet_approval
	if lbl_evidence != null:
		lbl_evidence.text = "УЛИКИ КОРРУПЦИИ: %0.0f%%" % japan_manager.yasuda_corruption_evidence

	match current_tab:
		"yasuda": _render_yasuda_tab()
		"diet": _render_diet_tab()
		"zaibatsu": _render_zaibatsu_tab()
		"sphere": _render_sphere_tab()


# ==============================================================================
# 1. ВКЛАДКА КРИЗИСА ЯСУДА
# ==============================================================================
func _render_yasuda_tab() -> void:
	if sec_yasuda == null: return
	for c in sec_yasuda.get_children(): c.queue_free()

	var head = Label.new()
	head.text = "=== ФИНАНСОВАЯ ПАНИКА И КАТАСТРОФА ДЗАЙБАЦУ ЯСУДА ==="
	head.modulate = Color(1.0, 0.85, 0.2)
	sec_yasuda.add_child(head)

	var p_status = PanelContainer.new()
	var vb_st = VBoxContainer.new()
	p_status.add_child(vb_st)

	var st_text = ""
	match japan_manager.yasuda_phase:
		JapanEmpireManager.YasudaPhase.NORMAL:
			st_text = "[color=#88cc88]СТАТУС: БЕЗМЯТЕЖНОСТЬ.[/color] Финансовые рынки Токио стабильны, конгломерат Ясуда кредитует флот."
		JapanEmpireManager.YasudaPhase.STOCK_CRASH:
			st_text = "[color=#ff4444]СТАТУС: БИРЖЕВОЙ КРАХ (TSE CRASH)![/color] Облигации Ясуда обесценились, паника охватила империю."
		JapanEmpireManager.YasudaPhase.INVESTIGATION:
			st_text = "[color=#ffaa22]СТАТУС: ПРАВИТЕЛЬСТВЕННЫЙ КРИЗИС.[/color] Раскрыты взятки министрам. Кабинет Ино на грани падения."
		JapanEmpireManager.YasudaPhase.RESOLVED:
			st_text = "[color=#00e5ff]СТАТУС: ПРЕОДОЛЕНИЕ КРИЗИСА.[/color] Сформирован новый кабинет, рынки постепенно стабилизируются."

	var desc_lbl = RichTextLabel.new()
	desc_lbl.bbcode_enabled = true
	desc_lbl.fit_content = true
	desc_lbl.text = st_text
	vb_st.add_child(desc_lbl)
	sec_yasuda.add_child(p_status)

	# Опции разрешения кризиса
	if japan_manager.yasuda_phase in [JapanEmpireManager.YasudaPhase.STOCK_CRASH, JapanEmpireManager.YasudaPhase.INVESTIGATION]:
		var opts_lbl = Label.new()
		opts_lbl.text = "ПУТИ РАЗРЕШЕНИЯ НАЦИОНАЛЬНОГО КРИЗИСА:"
		opts_lbl.modulate = Color(0.0, 0.95, 1.0)
		sec_yasuda.add_child(opts_lbl)

		# 1. Санация Икэды
		var b_bailout = Button.new()
		b_bailout.text = "[ 1. САНАЦИЯ И СПАСЕНИЕ БАНКОВ (Икэда Хаято) — Затраты: $15.0B ]"
		b_bailout.pressed.connect(func():
			var r = japan_manager.resolve_yasuda_bailout()
			lbl_log_status.text = r["message"]
			refresh_ui()
		)
		sec_yasuda.add_child(b_bailout)

		# 2. Антикоррупционный суд Такаги
		var b_invest = Button.new()
		b_invest.text = "[ 2. АНТИКОРРУПЦИОННЫЙ СУД И ЧИСТКА (Такаги Сокити) — Затраты: 40 PC, 1 CAP ]"
		b_invest.pressed.connect(func():
			var r = japan_manager.resolve_yasuda_investigation()
			lbl_log_status.text = r["message"]
			refresh_ui()
		)
		sec_yasuda.add_child(b_invest)

		# 3. Национализация Каи
		var b_nat = Button.new()
		b_nat.text = "[ 3. НАЦИОНАЛИЗАЦИЯ И ГОСПЛАН (Кая Окинори) — Затраты: 35 PC ]"
		b_nat.pressed.connect(func():
			var r = japan_manager.resolve_yasuda_nationalize()
			lbl_log_status.text = r["message"]
			refresh_ui()
		)
		sec_yasuda.add_child(b_nat)


# ==============================================================================
# 2. ВКЛАДКА ПАЛАТЫ ПЭРОВ И ДАЙЭТА
# ==============================================================================
func _render_diet_tab() -> void:
	if sec_diet == null: return
	for c in sec_diet.get_children(): c.queue_free()

	var head = Label.new()
	head.text = "=== ПАЛАТА ПЭРОВ (KIZOKUIN) И ИМПЕРАТОРСКИЙ ДАЙЭТ ==="
	head.modulate = Color(0.0, 0.95, 1.0)
	sec_diet.add_child(head)

	for f_key in japan_manager.factions_diet.keys():
		var f = japan_manager.factions_diet[f_key]
		var card = PanelContainer.new()
		var vb = VBoxContainer.new()
		card.add_child(vb)

		var bar = _ascii_bar(float(f["loyalty"]) / 100.0, 15)
		var h = Label.new()
		h.text = "%s | МАНДАТЫ: %d | ЛОЯЛЬНОСТЬ: [%s] %0.0f%%" % [f["name"].to_upper(), f["seats"], bar, f["loyalty"]]
		h.modulate = Color(1.0, 0.85, 0.3)
		vb.add_child(h)

		var desc = Label.new()
		desc.text = f["desc"]
		desc.modulate = Color(0.7, 0.8, 0.75)
		vb.add_child(desc)

		var btn_elect = Button.new()
		btn_elect.text = "[ НАЗНАЧИТЬ ПРЕМЬЕР-МИНИСТРОМ: %s ]" % f["leader"].to_upper()
		btn_elect.disabled = (japan_manager.active_prime_minister_key == f_key)
		btn_elect.pressed.connect(func():
			japan_manager.appoint_prime_minister(f_key)
			lbl_log_status.text = "ПРЕМЬЕР-МИНИСТР НАЗНАЧЕН: %s. Древо директив активировано." % f["leader"]
			refresh_ui()
		)
		vb.add_child(btn_elect)

		sec_diet.add_child(card)


# ==============================================================================
# 3. ВКЛАДКА ДЗАЙБАЦУ И АРМИЯ VS ФЛОТ
# ==============================================================================
func _render_zaibatsu_tab() -> void:
	if sec_zaibatsu == null: return
	for c in sec_zaibatsu.get_children(): c.queue_free()

	# Секция Дзайбацу
	var h_z = Label.new()
	h_z.text = "ВЕЛИКИЕ ФИНАНСОВО-ПРОМЫШЛЕННЫЕ ДЗАЙБАЦУ:"
	h_z.modulate = Color(1.0, 0.85, 0.2)
	sec_zaibatsu.add_child(h_z)

	var p_z = PanelContainer.new()
	var vb_z = VBoxContainer.new()
	p_z.add_child(vb_z)

	for z_key in japan_manager.zaibatsu_influence.keys():
		var val = japan_manager.zaibatsu_influence[z_key]
		var b = _ascii_bar(val / 100.0, 15)
		var l = Label.new()
		l.text = "%-12s: [%s] %0.1f%%" % [z_key, b, val]
		vb_z.add_child(l)
	sec_zaibatsu.add_child(p_z)

	# Секция IJA vs IJN
	var h_m = Label.new()
	h_m.text = "СОПЕРНИЧЕСТВО АРМИИ (ИЯА) И ФЛОТА (ИЯФ):"
	h_m.modulate = Color(0.2, 0.95, 0.6)
	sec_zaibatsu.add_child(h_m)

	var p_m = PanelContainer.new()
	var vb_m = VBoxContainer.new()
	p_m.add_child(vb_m)

	var bal = japan_manager.ija_ijn_balance
	var bal_str = "РАВНОВЕСИЕ"
	if bal < -30.0: bal_str = "ДИКТАТ АРМИИ (IJA)"
	elif bal > 30.0: bal_str = "ДОМИНИРОВАНИЕ ФЛОТА (IJN)"

	var l_bal = Label.new()
	l_bal.text = "БАЛАНС: %0.1f (%s) | Квота стали Армии: %0.0f%% | Квота нефти Флота: %0.0f%%" % [
		bal, bal_str, japan_manager.army_steel_quota, japan_manager.navy_oil_quota
	]
	vb_m.add_child(l_bal)

	var hbox_acts = HBoxContainer.new()
	var b_army = Button.new()
	b_army.text = "[ ПРИОРИТЕТ АРМИИ (15 PC) ]"
	b_army.pressed.connect(func():
		var r = japan_manager.allocate_resources_to_army()
		lbl_log_status.text = r["message"]
		refresh_ui()
	)
	hbox_acts.add_child(b_army)

	var b_navy = Button.new()
	b_navy.text = "[ ПРИОРИТЕТ ФЛОТУ (15 PC) ]"
	b_navy.pressed.connect(func():
		var r = japan_manager.allocate_resources_to_navy()
		lbl_log_status.text = r["message"]
		refresh_ui()
	)
	hbox_acts.add_child(b_navy)
	vb_m.add_child(hbox_acts)

	sec_zaibatsu.add_child(p_m)


# ==============================================================================
# 4. ВКЛАДКА СФЕРЫ СОПРОЦВЕТАНИЯ
# ==============================================================================
func _render_sphere_tab() -> void:
	if sec_sphere == null: return
	for c in sec_sphere.get_children(): c.queue_free()

	var head = Label.new()
	head.text = "=== ВЕЛИКАЯ ВОСТОЧНОАЗИАТСКАЯ СФЕРА СОПРОЦВЕТАНИЯ (GEACPS) ==="
	head.modulate = Color(0.0, 0.95, 1.0)
	sec_sphere.add_child(head)

	for m_tag in japan_manager.sphere_members.keys():
		var m = japan_manager.sphere_members[m_tag]
		var card = PanelContainer.new()
		var vb = VBoxContainer.new()
		card.add_child(vb)

		var l_bar = _ascii_bar(float(m["loyalty"]) / 100.0, 10)
		var u_bar = _ascii_bar(float(m["unrest"]) / 100.0, 10)

		var title = Label.new()
		title.text = "%s [%s] | ФАБРИКИ В БЮДЖЕТ: +%d" % [m["name"].to_upper(), m_tag, m["tribute_factories"]]
		title.modulate = Color(1.0, 0.85, 0.3)
		vb.add_child(title)

		var stat = Label.new()
		stat.text = "ЛОЯЛЬНОСТЬ: [%s] %0.0f%% | НЕДОВОЛЬСТВО: [%s] %0.0f%%" % [l_bar, m["loyalty"], u_bar, m["unrest"]]
		vb.add_child(stat)

		var btn_pacify = Button.new()
		btn_pacify.text = "[ НАПРАВИТЬ КЭМПЭЙТАЙ (5000 рекрутов, 15 PC) ]"
		btn_pacify.pressed.connect(func():
			var r = japan_manager.suppress_sphere_insurgency(m_tag)
			lbl_log_status.text = r["message"]
			refresh_ui()
		)
		vb.add_child(btn_pacify)

		sec_sphere.add_child(card)


func _ascii_bar(ratio: float, length: int) -> String:
	var r = clampf(ratio, 0.0, 1.0)
	var filled = int(round(r * length))
	var s = ""
	for i in range(filled): s += "█"
	for i in range(length - filled): s += "░"
	return s
