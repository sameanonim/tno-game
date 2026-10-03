import json
import os
import sys

sys.stdout.reconfigure(encoding='utf-8')

print("=== FIXING GERMAN CIVIL WAR CONTENDERS DATA ===")

# 1. Update data/countries/BOR/country.json
bor_country = {
  "identity": {
    "country_tag": "BOR",
    "country_name": "Reich of Martin Bormann (Party Bureaucracy)",
    "country_name_ru": "Германия (Мартин Борман / Партократы)",
    "theater": "theater_gcw",
    "geopolitical_bloc": "Einheitspakt (NSDAP Apparatus)",
    "primary_leader_id": "leader_martin_bormann",
    "leader_name": "Мартин Борман",
    "leader_title": "Партийный Секретарь НСДАП",
    "leader_portrait_path": "res://data/countries/GER/leaders/portraits/GER_martin_bormann.png",
    "ruling_ideology": "National Socialism",
    "sub_ideology": "Orthodox_National_Socialism",
    "country_color": [0.60, 0.45, 0.25, 1.0],
    "controlled_states": [56, 57, 58, 59, 60],
    "traits": [
      "Коричневое преосвященство",
      "Аппаратная паутина",
      "Консервация статуса-кво"
    ],
    "lore": "Нацизм всегда опирался в первую очередь на две вещи: националистические симпатии к собственной нации и сильного лидера, достаточно умного, чтобы уничтожить любую оппозицию на пути к абсолютной власти.\n\nМартин Борман является идеальным воплощением этой доктрины. Начав с самых низов партийной иерархии, он методично сплел невидимую бюрократическую паутину, опутавшую канцелярию фюрера, региональных гауляйтеров и всю финансовую кровеносную систему Третьего Рейха. Пока другие претенденты спорят об архитектурных утопиях или реваншистских походах, Борман контролирует назначения, партийные архивы и реальные рычаги управления государством.\n\nЕго кредо предельно ясно: сохранение незыблемого наследия Адольфа Гитлера, защита партийных привилегий и безжалостное подавление любых опасных реформ или военных авантюр, способных погубить Рейх."
  },
  "politics": {
    "political_capital": 120.0,
    "pc_gain_per_turn": 7.0,
    "max_cap": 6,
    "current_cap": 6,
    "legitimacy": 65.0,
    "radicalization": 25.0,
    "factions_loyalty": {
      "bureaucracy": 90.0,
      "nsdap_cadres": 85.0,
      "militarists": 50.0,
      "reformists": 25.0
    },
    "parties": [
      {
        "ideology_key": "national_socialism",
        "party_name": "НСДАП (Партийный Аппарат)",
        "long_name": "Национал-социалистическая немецкая рабочая партия (Канцелярия)",
        "popularity": 75.0,
        "seats": 320,
        "color": [0.60, 0.45, 0.25, 1.0],
        "is_ruling": True
      }
    ],
    "starting_laws": {
      "political": "tno_political_parties_one_party_state",
      "trade": "tno_trade_laws_closed_economy",
      "economy": "tno_economy_planned"
    }
  },
  "head_of_state": {
    "leader_id": "leader_martin_bormann",
    "leader_name": "Мартин Борман",
    "title": "Партийный Секретарь НСДАП / Коричневое Преосвященство",
    "portrait_path": "res://data/countries/GER/leaders/portraits/GER_martin_bormann.png",
    "ideology": "National Socialism",
    "competence": 4,
    "is_head_of_state": True,
    "is_military_commander": False,
    "traits": [
      "brown_eminence",
      "party_web_master",
      "status_quo_preservation"
    ]
  },
  "ministers": [],
  "commanders": [
    {
      "leader_id": "bor_ferdinand_schorner",
      "leader_name": "Фердинанд Шёрнер",
      "title": "Генерал-Фельдмаршал",
      "portrait_path": "res://data/countries/GER/leaders/portraits/GER_ferdinand_schorner.png",
      "ideology": "National Socialism",
      "competence": 3,
      "attack_skill": 7,
      "defense_skill": 5,
      "logistics_skill": 4,
      "is_head_of_state": False,
      "is_military_commander": True
    },
    {
      "leader_id": "bor_alfred_jodl",
      "leader_name": "Альфред Йодль",
      "title": "Начальник Оперативного Штаба",
      "portrait_path": "res://data/countries/GER/leaders/portraits/GER_alfred_jodl.png",
      "ideology": "National Socialism",
      "competence": 4,
      "attack_skill": 6,
      "defense_skill": 6,
      "logistics_skill": 7,
      "is_head_of_state": False,
      "is_military_commander": True
    }
  ],
  "economy": {
    "gdp_billions": 95.0,
    "real_gdp_growth": 0.035,
    "liquid_reserves_billions": 6.0,
    "national_debt_billions": 14.0,
    "debt_ceiling_ratio": 1.0,
    "is_in_fiscal_crisis": False,
    "central_bank_rate": 0.06,
    "inflation_rate": 0.045,
    "tax_rate": 0.24,
    "military_spending_share": 0.40,
    "civilian_spending_share": 0.30,
    "admin_spending_share": 0.25,
    "rd_spending_share": 0.05,
    "money_printing_this_turn": 0.0
  },
  "military": {
    "civilian_factories": 80,
    "military_factories": 60,
    "consumer_goods_ratio": 0.40,
    "manpower_pool": 380000,
    "infantry_weapons_stockpile": 45000,
    "heavy_equipment_stockpile": 800,
    "army_readiness": 65.0,
    "army_morale": 75.0,
    "war_support_percent": 80.0
  },
  "narrative": {
    "active_directives": [],
    "completed_directives": [],
    "story_flags": {
      "gcw_contender": True,
      "party_web_control": 65.0
    },
    "lore": "Нацизм всегда опирался в первую очередь на две вещи: националистические симпатии к собственной нации и сильного лидера, достаточно умного, чтобы уничтожить любую оппозицию на пути к абсолютной власти.\n\nМартин Борман является идеальным воплощением этой доктрины. Начав с самых низов партийной иерархии, он методично сплел невидимую бюрократическую паутину, опутавшую канцелярию фюрера, региональных гауляйтеров и всю финансовую кровеносную систему Третьего Рейха. Пока другие претенденты спорят об архитектурных утопиях или реваншистских походах, Борман контролирует назначения, партийные архивы и реальные рычаги управления государством.\n\nЕго кредо предельно ясно: сохранение незыблемого наследия Адольфа Гитлера, защита партийных привилегий и безжалостное подавление любых опасных реформ или военных авантюр, способных погубить Рейх."
  }
}

with open('data/countries/BOR/country.json', 'w', encoding='utf-8') as f:
    json.dump(bor_country, f, indent=2, ensure_ascii=False)
print("✓ Updated data/countries/BOR/country.json (Martin Bormann)")

# 2. Update data/countries/GOR/country.json
gor_country = {
  "identity": {
    "country_tag": "GOR",
    "country_name": "Reich of Hermann Göring (Militarist Junta)",
    "country_name_ru": "Германия (Герман Геринг / Милитаристская Хунта)",
    "theater": "theater_gcw",
    "geopolitical_bloc": "Einheitspakt (Wehrmacht Militarists)",
    "primary_leader_id": "leader_hermann_goering",
    "leader_name": "Герман Геринг",
    "leader_title": "Рейхсмаршал Великогермании",
    "leader_portrait_path": "res://data/countries/GER/leaders/portraits/GER_hermann_goring.png",
    "ruling_ideology": "National Socialism",
    "sub_ideology": "Militarism",
    "country_color": [0.48, 0.52, 0.58, 1.0],
    "controlled_states": [61, 62, 63, 64, 65],
    "traits": [
      "Марионетка Шёрнера",
      "Экономика непрерывного грабежа",
      "Воздушный триумф"
    ],
    "lore": "Геринг однажды сделал публичное заявление, что если вражеские бомбардировщики посмеют дойти до Рейха, то навечно после этого его будут называть не иначе как «Герман Майер». Военный триумф Люфтваффе во Второй мировой войне вознес его на вершину славы — Рейхсмаршал стал национальным героем, купающимся в невиданной роскоши.\n\nОднако за фасадом популярности и парадных мундиров скрывается марионетка ультра-радикальных генералов во главе с Фердинандом Шёрнером. Генералитет Вермахта рассматривает Геринга как идеальную ширму для установления открытой военной хунты. Экономический кризис Рейха милитаристы намерены решать единственным известным им способом — бесконечной эскалацией и грабительскими блицкригами по всей Евразии.\n\nЕсли Геринг одержит победу, немецкая военная машина вновь сорвется с цепи, превращая весь континент в арену тотальной войны и непрекращающегося разграбления."
  },
  "politics": {
    "political_capital": 60.0,
    "pc_gain_per_turn": 4.5,
    "max_cap": 5,
    "current_cap": 5,
    "legitimacy": 50.0,
    "radicalization": 30.0,
    "factions_loyalty": {
      "militarists": 95.0,
      "luftwaffe": 90.0,
      "bureaucracy": 35.0,
      "reformists": 20.0
    },
    "parties": [
      {
        "ideology_key": "national_socialism",
        "party_name": "НСДАП (Милитаристское крыло)",
        "long_name": "Национал-социалистическая немецкая рабочая партия (Фракция Вермахта)",
        "popularity": 50.0,
        "seats": 220,
        "color": [0.48, 0.52, 0.58, 1.0],
        "is_ruling": True
      }
    ],
    "starting_laws": {
      "political": "tno_political_parties_one_party_state",
      "trade": "tno_trade_laws_war_economy",
      "economy": "tno_economy_militarized"
    }
  },
  "head_of_state": {
    "leader_id": "leader_hermann_goering",
    "leader_name": "Герман Геринг",
    "title": "Рейхсмаршал Великогермании / Глава Люфтваффе",
    "portrait_path": "res://data/countries/GER/leaders/portraits/GER_hermann_goring.png",
    "ideology": "National Socialism",
    "competence": 3,
    "is_head_of_state": True,
    "is_military_commander": True,
    "traits": [
      "luftwaffe_triumph",
      "puppet_of_schorner",
      "plunder_economy_doctrine"
    ]
  },
  "ministers": [],
  "commanders": [
    {
      "leader_id": "gor_erhard_milch",
      "leader_name": "Эрхард Мильх",
      "title": "Генерал-Инспектор Люфтваффе",
      "portrait_path": "res://data/countries/GER/leaders/portraits/GER_erhard_milch.png",
      "ideology": "National Socialism",
      "competence": 4,
      "attack_skill": 7,
      "defense_skill": 4,
      "logistics_skill": 7,
      "is_head_of_state": False,
      "is_military_commander": True
    },
    {
      "leader_id": "gor_hermann_ramcke",
      "leader_name": "Герман-Бернхард Рамке",
      "title": "Генерал Парашютных Войск",
      "portrait_path": "res://data/countries/GER/leaders/portraits/GER_hermann_bernhard_ramcke.png",
      "ideology": "Fascism",
      "competence": 4,
      "attack_skill": 8,
      "defense_skill": 5,
      "logistics_skill": 5,
      "is_head_of_state": False,
      "is_military_commander": True
    }
  ],
  "economy": {
    "gdp_billions": 90.0,
    "real_gdp_growth": 0.02,
    "liquid_reserves_billions": 3.0,
    "national_debt_billions": 18.0,
    "debt_ceiling_ratio": 1.5,
    "is_in_fiscal_crisis": False,
    "central_bank_rate": 0.07,
    "inflation_rate": 0.06,
    "tax_rate": 0.28,
    "military_spending_share": 0.60,
    "civilian_spending_share": 0.20,
    "admin_spending_share": 0.15,
    "rd_spending_share": 0.05,
    "money_printing_this_turn": 0.0
  },
  "military": {
    "civilian_factories": 60,
    "military_factories": 90,
    "consumer_goods_ratio": 0.25,
    "manpower_pool": 420000,
    "infantry_weapons_stockpile": 50000,
    "heavy_equipment_stockpile": 1200,
    "army_readiness": 75.0,
    "army_morale": 85.0,
    "war_support_percent": 90.0
  },
  "narrative": {
    "active_directives": [],
    "completed_directives": [],
    "story_flags": {
      "gcw_contender": True,
      "militarist_influence": 80.0
    },
    "lore": "Геринг однажды сделал публичное заявление, что если вражеские бомбардировщики посмеют дойти до Рейха, то навечно после этого его будут называть не иначе как «Герман Майер». Военный триумф Люфтваффе во Второй мировой войне вознес его на вершину славы — Рейхсмаршал стал национальным героем, купающимся в невиданной роскоши.\n\nОднако за фасадом популярности и парадных мундиров скрывается марионетка ультра-радикальных генералов во главе с Фердинандом Шёрнером. Генералитет Вермахта рассматривает Геринга как идеальную ширму для установления открытой военной хунты. Экономический кризис Рейха милитаристы намерены решать единственным известным им способом — бесконечной эскалацией и грабительскими блицкригами по всей Евразии.\n\nЕсли Геринг одержит победу, немецкая военная машина вновь сорвется с цепи, превращая весь континент в арену тотальной войны и непрекращающегося разграбления."
  }
}

with open('data/countries/GOR/country.json', 'w', encoding='utf-8') as f:
    json.dump(gor_country, f, indent=2, ensure_ascii=False)
print("✓ Updated data/countries/GOR/country.json (Hermann Göring)")

# 3. Update data/countries_index.json
countries_idx_path = 'data/countries_index.json'
with open(countries_idx_path, 'r', encoding='utf-8') as f:
    c_index = json.load(f)

for item in c_index:
    tag = item.get('tag')
    if tag == 'BOR':
        item['name_ru'] = "Германия (Мартин Борман / Партократы)"
        item['name_en'] = "Reich of Martin Bormann (Party Bureaucracy)"
        item['ruling_ideology'] = "National Socialism"
        item['leader_name'] = "Мартин Борман"
        item['leader_portrait_path'] = "res://data/countries/GER/leaders/portraits/GER_martin_bormann.png"
        item['country_color'] = [0.60, 0.45, 0.25, 1.0]
        item['has_content'] = True
    elif tag == 'GOR':
        item['name_ru'] = "Германия (Герман Геринг / Милитаристы)"
        item['name_en'] = "Reich of Hermann Göring (Militarist Junta)"
        item['ruling_ideology'] = "National Socialism"
        item['leader_name'] = "Герман Геринг"
        item['leader_portrait_path'] = "res://data/countries/GER/leaders/portraits/GER_hermann_goring.png"
        item['country_color'] = [0.48, 0.52, 0.58, 1.0]
        item['has_content'] = True
    elif tag == 'SPE':
        item['name_ru'] = "Германия (Альберт Шпеер / Реформаторы)"
        item['name_en'] = "Reich of Albert Speer (Reformists)"
        item['ruling_ideology'] = "Fascism"
        item['leader_name'] = "Альберт Шпеер"
        item['leader_portrait_path'] = "res://data/countries/GER/leaders/portraits/GER_albert_speer.png"
        item['country_color'] = [0.85, 0.65, 0.20, 1.0]
        item['has_content'] = True
    elif tag == 'HEY':
        item['name_ru'] = "Германия (Рейнхард Гейдрих / Черный Орден СС)"
        item['name_en'] = "SS-Reich of Reinhard Heydrich"
        item['ruling_ideology'] = "Burgundian System"
        item['leader_name'] = "Рейнхард Гейдрих"
        item['leader_portrait_path'] = "res://data/countries/GER/leaders/portraits/GER_reinhard_heydrich.png"
        item['country_color'] = [0.18, 0.18, 0.24, 1.0]
        item['has_content'] = True

with open(countries_idx_path, 'w', encoding='utf-8') as f:
    json.dump(c_index, f, indent=2, ensure_ascii=False)
print("✓ Updated data/countries_index.json (BOR, GOR, SPE, HEY)")

# 4. Update data/countries/index.json
short_idx_path = 'data/countries/index.json'
with open(short_idx_path, 'r', encoding='utf-8') as f:
    short_index = json.load(f)

for item in short_index:
    tag = item.get('tag')
    if tag == 'BOR':
        item['name'] = "Reich of Martin Bormann (Party Bureaucracy)"
        item['name_ru'] = "Германия (Мартин Борман / Партократы)"
        item['theater'] = "theater_gcw"
        item['ruling_ideology'] = "National Socialism"
        item['sub_ideology'] = "Orthodox_National_Socialism"
        item['primary_leader_name'] = "Мартин Борман"
        item['primary_leader_portrait'] = "res://data/countries/GER/leaders/portraits/GER_martin_bormann.png"
        item['difficulty_rating'] = "●●○○○ (НИЗКАЯ)"
        item['geopolitical_bloc'] = "Einheitspakt (NSDAP Apparatus)"
        item['starting_gdp'] = 95.0
        item['starting_factories'] = 140
    elif tag == 'GOR':
        item['name'] = "Reich of Hermann Göring (Militarist Junta)"
        item['name_ru'] = "Германия (Герман Геринг / Милитаристы)"
        item['theater'] = "theater_gcw"
        item['ruling_ideology'] = "National Socialism"
        item['sub_ideology'] = "Militarism"
        item['primary_leader_name'] = "Герман Геринг"
        item['primary_leader_portrait'] = "res://data/countries/GER/leaders/portraits/GER_hermann_goring.png"
        item['difficulty_rating'] = "●●●●○ (ВЫСОКАЯ)"
        item['geopolitical_bloc'] = "Einheitspakt (Wehrmacht Militarists)"
        item['starting_gdp'] = 90.0
        item['starting_factories'] = 150
    elif tag == 'SPE':
        item['theater'] = "theater_gcw"
        item['primary_leader_name'] = "Альберт Шпеер"
        item['primary_leader_portrait'] = "res://data/countries/GER/leaders/portraits/GER_albert_speer.png"
    elif tag == 'HEY':
        item['theater'] = "theater_gcw"
        item['primary_leader_name'] = "Рейнхард Гейдрих"
        item['primary_leader_portrait'] = "res://data/countries/GER/leaders/portraits/GER_reinhard_heydrich.png"

with open(short_idx_path, 'w', encoding='utf-8') as f:
    json.dump(short_index, f, indent=2, ensure_ascii=False)
print("✓ Updated data/countries/index.json (BOR, GOR, SPE, HEY)")

# 5. Update data/extracted/countries_manifest.json
manifest_path = 'data/extracted/countries_manifest.json'
with open(manifest_path, 'r', encoding='utf-8') as f:
    manifest = json.load(f)

if 'countries' in manifest:
    c_map = manifest['countries']
    if 'BOR' in c_map:
        c_map['BOR']['name'] = "Reich of Martin Bormann"
        c_map['BOR']['name_ru'] = "Германия (Мартин Борман / Партократы)"
        c_map['BOR']['theater'] = "theater_gcw"
        c_map['BOR']['leader'] = "Мартин Борман"
        c_map['BOR']['primary_leader'] = {
            "leader_id": "leader_martin_bormann",
            "leader_name": "Мартин Борман",
            "title": "Партийный Секретарь НСДАП",
            "portrait_path": "res://data/countries/GER/leaders/portraits/GER_martin_bormann.png",
            "traits": ["Коричневое преосвященство", "Аппаратная паутина", "Консервация статуса-кво"],
            "lore": bor_country['identity']['lore']
        }
    if 'GOR' in c_map:
        c_map['GOR']['name'] = "Reich of Hermann Göring"
        c_map['GOR']['name_ru'] = "Германия (Герман Геринг / Милитаристы)"
        c_map['GOR']['theater'] = "theater_gcw"
        c_map['GOR']['leader'] = "Герман Геринг"
        c_map['GOR']['primary_leader'] = {
            "leader_id": "leader_hermann_goering",
            "leader_name": "Герман Геринг",
            "title": "Рейхсмаршал Великогермании",
            "portrait_path": "res://data/countries/GER/leaders/portraits/GER_hermann_goring.png",
            "traits": ["Марионетка Шёрнера", "Экономика непрерывного грабежа", "Воздушный триумф"],
            "lore": gor_country['identity']['lore']
        }
    if 'SPE' in c_map:
        c_map['SPE']['theater'] = "theater_gcw"
        c_map['SPE']['leader'] = "Альберт Шпеер"
        c_map['SPE']['primary_leader']['portrait_path'] = "res://data/countries/GER/leaders/portraits/GER_albert_speer.png"
    if 'HEY' in c_map:
        c_map['HEY']['theater'] = "theater_gcw"
        c_map['HEY']['leader'] = "Рейнхард Гейдрих"
        c_map['HEY']['primary_leader']['portrait_path'] = "res://data/countries/GER/leaders/portraits/GER_reinhard_heydrich.png"

with open(manifest_path, 'w', encoding='utf-8') as f:
    json.dump(manifest, f, indent=2, ensure_ascii=False)
print("✓ Updated data/extracted/countries_manifest.json")

# 6. Update country_lore_ru.json and country_lore_en.json
ru_lore_path = 'data/localization/common/country_lore_ru.json'
with open(ru_lore_path, 'r', encoding='utf-8') as f:
    ru_lore = json.load(f)

ru_lore['BOR_lore'] = bor_country['identity']['lore']
ru_lore['GOR_lore'] = gor_country['identity']['lore']
ru_lore['SPE_lore'] = "Много вещей можно сказать об Альберте Шпеере, но никто не сможет отрицать амбициозность этого человека.\n\nВ отличие от других, он вступил в партию не из-за пламенных речей, а из холодного расчета архитектора. Став личным другом Гитлера и рейхсминистром вооружений, он построил военную машину Рейха. Однако мирное время обнажило банкротство рабской экономики. Теперь Шпеер возглавляет движение реформаторов Цольферайна, стремясь модернизировать Германию и спасти её от коллапса."
ru_lore['HEY_lore'] = "У Гейдриха множество имен: Светловолосый зверь, Пражский мясник, Юный бог смерти. Пережив покушение, он железной рукой подавил сопротивление на Востоке. Ныне Гейдрих — главный проводник воли Генриха Гиммлера в Германии. Его Черный Орден СС готовится установить спартанский порядок и очистить мир в огне ядерного апокалипсиса."

with open(ru_lore_path, 'w', encoding='utf-8') as f:
    json.dump(ru_lore, f, indent=2, ensure_ascii=False)
print("✓ Updated country_lore_ru.json")

en_lore_path = 'data/localization/common/country_lore_en.json'
with open(en_lore_path, 'r', encoding='utf-8') as f:
    en_lore = json.load(f)

en_lore['BOR_lore'] = "Bormann relies on the NSDAP party apparatus and state bureaucracy. His doctrine is preserving the Fuhrer's status quo without radical reforms or risky military gambles, consolidating power through an intricate web of party loyalty."
en_lore['GOR_lore'] = "Göring has allied with Schörner's militarists. They believe the only escape from economic collapse is continuous blitzkrieg and plunder across Eurasia, driving the Wehrmacht into endless conquest."
en_lore['SPE_lore'] = "Speer realizes the slave economy is bankrupt and proposes modernizing the Reich by rallying technocrats, students, and Zollverein reformers to rebuild Germany into a functional superpower."
en_lore['HEY_lore'] = "Heydrich acts as Heinrich Himmler's dagger in Germany. Spartan SS terror, brutal purges, and fanatical devotion aim to bring about the ultimate nuclear cleansing of the globe."

with open(en_lore_path, 'w', encoding='utf-8') as f:
    json.dump(en_lore, f, indent=2, ensure_ascii=False)
print("✓ Updated country_lore_en.json")

print("=== ALL GCW CONTENDERS DATA UPDATED SUCCESSFULLY ===")
