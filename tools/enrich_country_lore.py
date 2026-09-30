import json
import sqlite3
import re
import os
import sys

sys.stdout.reconfigure(encoding='utf-8')

conn = sqlite3.connect('data/localization/localization_db.sqlite')
c = conn.cursor()

def get_loc(key, lang='ru'):
    if not key:
        return ""
    c.execute("SELECT ru, en FROM strings WHERE key = ?", (key,))
    row = c.fetchone()
    if row:
        val = row[0] if lang == 'ru' else row[1]
        if not val and lang == 'ru':
            val = row[1]
        return val or ""
    return ""

def clean_paradox_markup(text):
    if not text:
        return ""
    text = re.sub(r'§[A-Za-z0-9!_,^%\-+=\.]', '', text)
    text = re.sub(r'£[A-Za-z0-9_]+', '', text)
    text = text.replace('\r\n', '\n').strip()
    return text

chars = json.load(open('extracted_tno_data/characters_db.json', 'r', encoding='utf-8'))
manifest_file = 'data/extracted/countries_manifest.json'
manifest_data = json.load(open(manifest_file, 'r', encoding='utf-8'))
manifest_countries = manifest_data.get('countries', {})

c_index_file = 'data/countries_index.json'
c_index = json.load(open(c_index_file, 'r', encoding='utf-8'))

# Fallback curated dossiers from GameSession (in Russian and English)
GS_LORE_RU = {
    "WRS": "Западнорусский Революционный Фронт закален в Первой Западнорусской войне. Маршал Тухачевский верит, что единственным языком возрождения СССР является тотальная индустриализация ВПК и массированные танковые клинья.",
    "KOM": "Сыктывкар превратился в бурлящий котел: от коммунистов Суслова и Бухариной до ультранационалистов Гумилева и фанатиков Таборицкого. Судьба демократии висит на волоске.",
    "SVR": "Маршал Рокоссовский и генерал Батов сохранили костяк кадровых офицеров Красной Армии. Уральский военный округ готов оборонять свои рубежи и собирать русские земли без фанатизма и кровавых чисток.",
    "SVE": "Маршал Рокоссовский и генерал Батов сохранили костяк кадровых офицеров Красной Армии. Уральский военный округ готов оборонять свои рубежи и собирать русские земли без фанатизма и кровавых чисток.",
    "TYU": "Каганович считает падение Союза предательством партийных принципов. Возрождение советской державы пятилетками и тяжелой артиллерией — нерушимый завет сталинизма.",
    "TYM": "Каганович считает падение Союза предательством партийных принципов. Возрождение советской державы пятилетками и тяжелой артиллерией — нерушимый завет сталинизма.",
    "OMS": "Для Черной Лиги Россия умерла, осталась лишь миссия: возмездие Тевтону любой ценой, даже если цена — мировой ядерный пепел. Все ресурсы до копейки идут на подготовку к финальной войне.",
    "IRK": "Законные преемники союзного центра во главе с НКВД держат в кулаке Восточную Сибирь, готовясь разгромить белогвардейцев и бунтовщиков Саблина.",
    "CHT": "Молодой австралийский эмигрант Михаил Романов завлечен белоэмигрантскими атаманами Семенова и превращен в номинального царя Забайкалья.",
    "SPE": "Шпеер осознает крах рабской экономики и предлагает модернизацию системы, опираясь на технократов и реформаторов Цольферайна.",
    "BOR": "Борман опирается на партийных функционеров и госаппарат. Его кредо — сохранение наследия фюрера без опасных реформ и военных авантюр.",
    "GOR": "Геринг пошел на поводу у ультра-милитаристов Шёрнера. Единственный выход из банкротства Рейха они видят в непрерывных блицкригах по всей Евразии.",
    "HEY": "Гейдрих выступает как проводник воли Генриха Гиммлера. Спартанский террор и безжалостная чистка выродков приведут мир к очистительному пламени.",
    "USA": "Оплот свободного мира после поражения во Второй мировой войне. Под руководством Никсона страна противостоит Рейху и Японии в прокси-конфликтах, пока в Конгрессе разгорается битва за гражданские права.",
    "GER": "Гегемон Европы, стоящий на краю пропасти. Увядающий фюрер не может остановить экономическую стагнацию и надвигающуюся резню нацистских претендентов за трон.",
    "JAP": "Хозяин Азии и Тихого океана. Япония балансирует между враждующими армией (ИЯА) и флотом (ИЯФ), извлекая богатства из колониальной Сферы Сопроцветания, пока не грянул крах конгломерата Ясуда.",
    "ITA": "Италия одержала победу во Второй мировой, но проект Атлантропа иссушил Адриатику и разорил экономику. Средиземноморский Триумвират трещит по швам, а в Великом Совете Чиано ведет войну за реформы против фашистских ортодоксов.",
    "IBR": "Франсиско Франко и Антониу ди Салазар удерживают хрупкий Иберийский Союз. Единство двух диктатур подвергается испытаниям со стороны сепаратистов Каталонии и Басконии, террористов и неизбежной борьбы за престолонаследие.",
    "FRD": "Французская Республика под руководством Валери Жискар д'Эстена борется за восстановление демократической и свободной Франции, отвергая как нацистское ярмо Режима Виши, так и террор Бургундии.",
    "BRG": "Генрих Гиммлер превратил Бургундию в самый закрытый и зловещий тоталитарный лагерь на планете. За колючей проволокой СС куются планы апокалипсиса, призванного очистить Землю в ядерном пламени."
}

GS_LORE_EN = {
    "WRS": "The West Russian Revolutionary Front was tempered in the First West Russian War. Marshal Tukhachevsky believes the only language for USSR restoration is total industrialization and armored spearheads.",
    "KOM": "Syktyvkar has become a boiling cauldron: from the communists Suslov and Bukharina to ultranationalist Gumilyov and the fanatic Taboritsky. The fate of Russian democracy hangs by a thread.",
    "SVR": "Marshal Rokossovsky and General Batov preserved the core of the Red Army's officer corps. Sverdlovsk stands ready to guard its borders and unite Russian lands with pragmatic discipline.",
    "SVE": "Marshal Rokossovsky and General Batov preserved the core of the Red Army's officer corps. Sverdlovsk stands ready to guard its borders and unite Russian lands with pragmatic discipline.",
    "TYU": "Kaganovich views the fall of the Union as betrayal of core party tenets. Restoring the Soviet powerhouse through relentless five-year plans is Stalin's sacred legacy.",
    "TYM": "Kaganovich views the fall of the Union as betrayal of core party tenets. Restoring the Soviet powerhouse through relentless five-year plans is Stalin's sacred legacy.",
    "OMS": "To the Black League, Russia is dead; only the mission remains: vengeance against the Teuton at all costs, even nuclear apocalypse. Every resource goes toward the Great Trial.",
    "IRK": "The legitimate heirs to the Soviet central authority under the NKVD hold Eastern Siberia in an iron grip, preparing to crush both White Guard renegades and Sablin's mutineers.",
    "CHT": "The young Australian emigre Mikhail Romanov was lured by Semenov's White Cossack atamans and crowned nominal Tsar of Transbaikal.",
    "SPE": "Speer realizes the slave economy is bankrupt and proposes modernizing the Reich by rallying technocrats, students, and Zollverein reformers.",
    "BOR": "Bormann relies on the NSDAP party apparatus and bureaucracy. His doctrine is preserving the Fuhrer's status quo without radical reforms or risky military gambles.",
    "GOR": "Göring has allied with Schörner's militarists. They believe the only escape from economic collapse is continuous blitzkrieg and plunder across Eurasia.",
    "HEY": "Heydrich acts as Heinrich Himmler's dagger in Germany. Spartan SS terror and brutal purges aim to cleanse the world through nuclear fire.",
    "USA": "Bastion of the free world following defeat in WWII. Under Nixon, the US confronts the Reich and Japan in proxy conflicts while civil rights struggles tear Congress apart.",
    "GER": "Hegemon of Europe teetering on the precipice. The aging Fuhrer cannot halt economic stagnation or the looming civil war among Nazi contenders.",
    "JAP": "Master of Asia and the Pacific. Japan balances between feuding Army (IJA) and Navy (IJN) factions while extracting wealth from the Sphere until the Yasuda crash hits.",
    "ITA": "Victorious in WWII yet devastated by Atlantropa, Italy faces economic ruin. The Triumvirate is fracturing, while Ciano battles Fascist hardliners in the Grand Council.",
    "IBR": "Franco and Salazar maintain the fragile Iberian Union against regional separatism, terrorism, and an inevitable succession crisis.",
    "FRD": "The French Republic under Valéry Giscard d'Estaing fights to restore a free, democratic France, rejecting both the Vichy regime and Burgundian terror.",
    "BRG": "Himmler transformed Burgundy into the most horrific totalitarian prison-state on Earth. Behind SS barbed wire, plans are forged for the ultimate nuclear cleansing."
}

# Explicit leader desc key overrides for famous countries
KNOWN_LEADER_KEYS = {
    "VYT": "POLITICS_TSAR_VLADIMIR_DESC",
    "SAM": "POLITICS_ANDREY_VLASOV_DESC",
    "TYU": "POLITICS_LAZAR_KAGANOVICH_DESC",
    "TYM": "POLITICS_LAZAR_KAGANOVICH_DESC",
    "OMS": "POLITICS_DMITRY_KARBYSHEV_DESC",
    "KEM": "POLITICS_RURIK_II_DESC",
    "CHT": "POLITICS_TSAR_MIKHAIL_DESC",
    "SPE": "POLITICS_SPEER_GERMANY_DESC",
    "BOR": "POLITICS_MARTIN_BORMANN_DESC",
    "GOR": "POLITICS_HERMANN_GORING_DESC",
    "HEY": "POLITICS_REINHARD_HEYDRICH_DESC",
    "ITA": "POLITICS_CIANO_DESC",
    "IBR": "POLITICS_FRANCISCO_FRANCO_DESC",
    "MAN": "POLITICS_PUYI_DESC",
    "TUR": "POLITICS_ISMET_INONU_DESC",
    "THA": "POLITICS_PLAEK_PHIBUNSONGKHRAM_DESC",
    "USA": "POLITICS_RICHARD_NIXON_DESC",
    "JAP": "POLITICS_HIROYA_INO_DESC",
    "WRS": "POLITICS_ALEXANDER_YEGOROV_DESC",
    "KOM": "POLITICS_NIKOLAI_VOZNESENSKY_DESC",
    "TOM": "POLITICS_BORIS_PASTERNAK_DESC",
    "NOV": "POLITICS_ALEXANDER_POKRYSHKIN_DESC",
    "IRK": "POLITICS_GENRIKH_YAGODA_DESC",
    "ENG": "POLITICS_BARRY_DOMVILE_DESC",
    "BRG": "POLITICS_HEINRICH_HIMMLER_DESC",
    "SCO": "POLITICS_ROBERT_MCINTYRE_DESC",
    "WAL": "POLITICS_SAUNDERS_LEWIS_DESC",
    "IRE": "POLITICS_Sean_Lemass_desc",
    "GNG": "POLITICS_SUZUKI_TEIICHI_DESC",
    "BLR": "POLITICS_MICHAL_VITUSKA",
    "BSQ": "POLITICS_TELESFORO_MONZON_DESC",
    "DST": "POLITICS_OTTO_DRECHSLER_DESC",
    "JST": "POLITICS_FRIEDRICH_JECKELN_DESC",
    "MST": "POLITICS_ANDREAS_MEYER_LANDRUT_DESC",
    "PPR": "POLITICS_CARLOS_ANTUNES_DESC",
    "SPS": "POLITICS_CARLOS_INIESTA_CANO_DESC",
    "TBA": "POLITICS_HORACIO_FERNANDEZ_INGUANZO_DESC",
    "UKR": "POLITICS_ERICH_KOCH_DESC"
}

def extract_best_lore(tag, item, lang='ru'):
    # 1. Check THENEWORDER_DESC
    tno_desc = clean_paradox_markup(get_loc(f"{tag}_THENEWORDER_DESC", lang))
    if tno_desc and len(tno_desc) > 80:
        return tno_desc

    # 2. Check explicit leader key override
    if tag in KNOWN_LEADER_KEYS:
        lk = KNOWN_LEADER_KEYS[tag]
        l_text = clean_paradox_markup(get_loc(lk, lang))
        if l_text and len(l_text) > 80:
            return l_text

    # 3. Check manifest lore
    man_c = manifest_countries.get(tag, {})
    m_lore = clean_paradox_markup(man_c.get('lore', ''))
    if m_lore and len(m_lore) > 80:
        if lang == 'ru':
            return m_lore
        else:
            # Check if leader has english desc
            lead = man_c.get('primary_leader', {})
            lid = lead.get('leader_id', '')
            if lid and lid in chars:
                cls = chars[lid].get('country_leader')
                if cls:
                    if isinstance(cls, dict): cls = [cls]
                    for cl in cls:
                        if cl.get('desc'):
                            en_val = clean_paradox_markup(get_loc(cl['desc'], 'en'))
                            if en_val and len(en_val) > 80:
                                return en_val

    # 4. Check curated game_session lore
    if lang == 'ru' and tag in GS_LORE_RU:
        return GS_LORE_RU[tag]
    if lang == 'en' and tag in GS_LORE_EN:
        return GS_LORE_EN[tag]

    # 5. Check primary_leader_id from country.json
    c_json_path = f"data/countries/{tag}/country.json"
    if os.path.exists(c_json_path):
        try:
            cdata = json.load(open(c_json_path, 'r', encoding='utf-8'))
            pl_id = cdata.get('identity', {}).get('primary_leader_id', '')
            if pl_id and pl_id in chars:
                cls = chars[pl_id].get('country_leader')
                if cls:
                    if isinstance(cls, dict): cls = [cls]
                    for cl in cls:
                        if cl.get('desc'):
                            txt = clean_paradox_markup(get_loc(cl['desc'], lang))
                            if txt and len(txt) > 80:
                                return txt
        except Exception:
            pass

    # 6. Check tag_desc
    td = clean_paradox_markup(get_loc(f"{tag}_desc", lang))
    if td and len(td) > 80:
        return td

    # 7. Fallback synthesis
    c_name_ru = item.get('name_ru', item.get('name_en', tag))
    c_name_en = item.get('name_en', item.get('name_ru', tag))
    leader = item.get('leader_name', 'UNKNOWN')
    ideo_ru = get_loc(item.get('ruling_ideology', 'Neutral'), 'ru') or item.get('ruling_ideology', 'Neutral')
    ideo_en = get_loc(item.get('ruling_ideology', 'Neutral'), 'en') or item.get('ruling_ideology', 'Neutral')

    if lang == 'ru':
        return f"Государство {c_name_ru}. В 1962 году находится под управлением режима направления [{ideo_ru}], во главе с {leader}. Страна балансирует в реалиях Нового Порядка, защищая свой суверенитет и региональные интересы среди глобального кризиса сверхдержав."
    else:
        return f"The nation of {c_name_en}. In 1962, it is governed under a [{ideo_en}] administration led by {leader}. Balancing the harsh geopolitical realities of the New Order, the nation strives to preserve sovereignty and regional stability amid superpower cold war tensions."

# Build master dictionaries for RU and EN
ru_lore_map = {}
en_lore_map = {}

# All known tags
all_tags = set(manifest_countries.keys())
for item in c_index:
    all_tags.add(item.get('tag', ''))
for tag in KNOWN_LEADER_KEYS.keys():
    all_tags.add(tag)
for tag in GS_LORE_RU.keys():
    all_tags.add(tag)
all_tags.discard('')

item_by_tag = {item.get('tag', ''): item for item in c_index}

for tag in sorted(all_tags):
    item = item_by_tag.get(tag, {
        "tag": tag,
        "name_ru": tag,
        "name_en": tag,
        "leader_name": "UNKNOWN",
        "ruling_ideology": "Neutral"
    })
    ru_text = extract_best_lore(tag, item, 'ru')
    en_text = extract_best_lore(tag, item, 'en')

    ru_lore_map[f"{tag}_lore"] = ru_text
    en_lore_map[f"{tag}_lore"] = en_text

print(f"Generated {len(ru_lore_map)} Russian lore entries and {len(en_lore_map)} English lore entries.")

# Write to data/localization/common/country_lore_ru.json and country_lore_en.json
os.makedirs("data/localization/common", exist_ok=True)

lore_ru_file = "data/localization/common/country_lore_ru.json"
lore_en_file = "data/localization/common/country_lore_en.json"

json.dump({"locale": "ru", "total_strings": len(ru_lore_map), "strings": ru_lore_map}, open(lore_ru_file, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
json.dump({"locale": "en", "total_strings": len(en_lore_map), "strings": en_lore_map}, open(lore_en_file, "w", encoding="utf-8"), ensure_ascii=False, indent=2)

print(f"Saved {lore_ru_file} and {lore_en_file}")

# Update data/extracted/countries_manifest.json with lore
updated_manifest_count = 0
for tag, lore in ru_lore_map.items():
    clean_tag = tag.replace("_lore", "")
    if clean_tag in manifest_countries:
        existing = manifest_countries[clean_tag].get('lore', '')
        if not existing or len(existing) < 50:
            manifest_countries[clean_tag]['lore'] = lore
            updated_manifest_count += 1
    else:
        # Add entry if it's a prominent tag like SPE, BOR, GOR, HEY, TYU, etc.
        manifest_countries[clean_tag] = {
            "tag": clean_tag,
            "name": clean_tag,
            "lore": lore,
            "starting_gdp": 15.0,
            "starting_manpower": 50000,
            "starting_factories": 25,
            "difficulty_rating": "●●●○○ (СРЕДНЯЯ)",
            "primary_leader": {"leader_name": "UNKNOWN", "lore": lore, "traits": []}
        }
        updated_manifest_count += 1

manifest_data['countries'] = manifest_countries
json.dump(manifest_data, open(manifest_file, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
print(f"Updated {updated_manifest_count} countries in {manifest_file}")

# Also inject into country.json for all tags
updated_country_json_count = 0
for tag in sorted(all_tags):
    c_path = f"data/countries/{tag}/country.json"
    if os.path.exists(c_path):
        try:
            cdata = json.load(open(c_path, 'r', encoding='utf-8'))
            lore_ru = ru_lore_map.get(f"{tag}_lore", "")
            if lore_ru:
                if 'narrative' not in cdata:
                    cdata['narrative'] = {}
                cdata['narrative']['lore'] = lore_ru
                cdata['identity']['lore'] = lore_ru
                json.dump(cdata, open(c_path, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
                updated_country_json_count += 1
        except Exception as e:
            pass

print(f"Updated lore in {updated_country_json_count} country.json files!")
