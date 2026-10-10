"""
Country Package Modularizer & SQLite Exporter
=============================================
Bundles all game data per country TAG into an isolated, self-contained package:
data/countries/<TAG>/
├── country_profile.json    # Canonical CountryState profile
├── country.json            # Fallback profile
├── territory.json          # Starting states, provinces, cores, manpower
├── events.json             # Country-specific narrative events
├── decisions.json          # Country-specific crisis decisions
├── leaders/                # Characters and cabinet ministers
│   ├── index.json
│   └── <leader_id>.json
├── directives/             # National focus trees DAG
│   ├── trees_manifest.json
│   ├── tree.json           # Default active tree
│   └── trees/
│       └── <tree_id>.json
├── localisation/           # Country-scoped localizations
│   ├── ru.json
│   └── en.json
└── country.sqlite          # Complete standalone SQLite database for the country

Also builds master index: data/countries/index.json and data/countries_index.json.
"""

from collections import defaultdict
import json
from pathlib import Path
import sqlite3
import sys
import time
from typing import Any, Dict, List, Optional, Set

from ..config import PipelineConfig


class CountryPackager:
    def __init__(
        self,
        config: PipelineConfig,
        countries_db: Dict[str, Dict[str, Any]],
        trees_by_tag: Dict[str, List[Dict[str, Any]]],
        events_by_cat: Dict[str, List[Dict[str, Any]]],
        decisions_by_cat: Dict[str, List[Dict[str, Any]]],
        states_db: Dict[int, Dict[str, Any]],
        loc_db: Dict[str, Dict[str, str]]
    ):
        self.config = config
        self.countries_db = countries_db
        self.trees_by_tag = trees_by_tag
        self.events_by_cat = events_by_cat
        self.decisions_by_cat = decisions_by_cat
        self.states_db = states_db
        self.loc_db = loc_db

    def package_all(self, target_tags: Optional[List[str]] = None) -> Dict[str, Any]:
        t0 = time.time()
        print(">>> [PIPELINE] [PACKAGER] Packaging country dossiers and per-country SQLite databases...")

        countries_base = self.config.data_dir / "countries"
        countries_base.mkdir(parents=True, exist_ok=True)

        # Pre-group states by owner and core
        states_by_owner: Dict[str, List[Dict[str, Any]]] = defaultdict(list)
        states_by_core: Dict[str, List[int]] = defaultdict(list)
        for sid, sdata in self.states_db.items():
            owner = (sdata.get("owner") or "").upper()
            if owner:
                states_by_owner[owner].append(sdata)
            for core in sdata.get("cores", []):
                clean_core = core.strip().upper()
                if clean_core:
                    states_by_core[clean_core].append(sid)

        # Pre-index events by country tag cues
        events_by_tag: Dict[str, List[Dict[str, Any]]] = defaultdict(list)
        for cat, ev_list in self.events_by_cat.items():
            for ev in ev_list:
                ev_id = str(ev.get("id", "")).upper()
                # Check for 3-letter tag prefix, e.g. "GER.1", "USA_10", "TNO_GER"
                for tag in self.countries_db.keys():
                    if tag in ev_id or tag in cat.upper():
                        events_by_tag[tag].append(ev)

        # Pre-index decisions by country tag cues with strict tag boundary matching
        tag_pattern_cache: Dict[str, re.Pattern] = {
            t: re.compile(rf"(?:^|_){re.escape(t)}(?:_|$)", re.IGNORECASE)
            for t in self.countries_db.keys()
        }

        russian_warlords = {
            "KOM", "WRS", "WRRF", "SAM", "OMS", "VYT", "SVR", "TYM", "TYU", "IRK",
            "BRY", "TOM", "NOV", "KEM", "MAG", "AMR", "CHT", "YAK", "ZLT", "ORE",
            "MGN", "DRL", "BKR", "TAR", "YGR", "VOR", "KAZ", "AKT", "ARL", "KOK",
            "PAV", "NPL", "KRK", "ALT", "KMC", "MIR", "KHA", "VLG", "KOS", "ONE",
            "ONG", "PRM", "SBA", "URL"
        }
        german_tags = {"GER", "BOR", "SPE", "GOR", "HEY", "BGR", "SGR", "GGR", "HGR"}

        decisions_by_tag: Dict[str, List[Dict[str, Any]]] = defaultdict(list)
        for cat_id, dec_list in self.decisions_by_cat.items():
            for dec in dec_list:
                dec_id = str(dec.get("id", "")).upper()
                req_tags = dec.get("requires_tags", [])
                if req_tags:
                    for rt in req_tags:
                        decisions_by_tag[rt.upper()].append(dec)
                    continue

                # Check strict 3-letter prefix on decision or category
                matched_tag = None
                m_dec = re.match(r"^([A-Z0-9]{3})_", dec_id)
                m_cat = re.match(r"^([A-Z0-9]{3})_", cat_id.upper())
                candidate = m_dec.group(1) if m_dec else (m_cat.group(1) if m_cat else None)
                if candidate and candidate in self.countries_db:
                    matched_tag = candidate

                if matched_tag:
                    decisions_by_tag[matched_tag].append(dec)
                elif dec.get("requires_russia") or dec_id.startswith("RUS_") or "SMUTA" in cat_id.upper():
                    for w in russian_warlords:
                        if w in self.countries_db:
                            decisions_by_tag[w].append(dec)
                elif dec.get("requires_germany") or dec_id.startswith("GER_"):
                    for g in german_tags:
                        if g in self.countries_db:
                            decisions_by_tag[g].append(dec)
                elif dec.get("requires_usa") or dec_id.startswith("USA_"):
                    decisions_by_tag["USA"].append(dec)
                elif dec.get("requires_general"):
                    for t in self.countries_db.keys():
                        decisions_by_tag[t].append(dec)

        tags_to_process = target_tags or list(self.countries_db.keys())
        processed_count = 0
        master_index: Dict[str, Dict[str, Any]] = {}

        for tag in tags_to_process:
            cdata = self.countries_db.get(tag)
            if not cdata:
                continue

            country_dir = countries_base / tag
            country_dir.mkdir(parents=True, exist_ok=True)

            # 1. Profile & CountryState
            self._write_profiles(country_dir, cdata)

            # 2. Territory
            owned_states = states_by_owner.get(tag, [])
            cored_states = states_by_core.get(tag, [])
            territory_data = self._write_territory(country_dir, tag, owned_states, cored_states)

            # 3. Leaders & Characters
            leaders = cdata.get("leaders", [])
            self._write_leaders(country_dir, leaders)

            # 4. Directives (Focus Trees)
            trees = self.trees_by_tag.get(tag, [])
            self._write_directives(country_dir, tag, trees)

            # 5. Events & Decisions
            evs = events_by_tag.get(tag, [])
            decs = decisions_by_tag.get(tag, [])
            with open(country_dir / "events.json", "w", encoding="utf-8") as f:
                json.dump(evs, f, ensure_ascii=False, indent=2)
            with open(country_dir / "decisions.json", "w", encoding="utf-8") as f:
                json.dump(decs, f, ensure_ascii=False, indent=2)

            # 6. Localisation
            self._write_localisation(country_dir, tag, cdata, leaders, trees)

            # 7. Isolated Country SQLite Database
            self._build_country_sqlite(country_dir, tag, cdata, territory_data, leaders, trees, evs, decs)

            # Master index entry
            master_index[tag] = {
                "tag": tag,
                "name": cdata.get("name_text", tag),
                "ruling_party": cdata.get("ruling_party", "unknown"),
                "capital": cdata.get("capital"),
                "states_count": len(owned_states),
                "directives_trees_count": len(trees),
                "package_path": f"res://data/countries/{tag}"
            }
            processed_count += 1

        # Write master index
        index_path = countries_base / "index.json"
        with open(index_path, "w", encoding="utf-8") as f:
            json.dump(master_index, f, ensure_ascii=False, indent=2)

        elapsed = time.time() - t0
        print(f">>> [PIPELINE] [PACKAGER] Successfully packaged {processed_count} countries in {elapsed:.2f}s!")
        return master_index

    def _write_profiles(self, country_dir: Path, cdata: Dict[str, Any]) -> None:
        profile_path = country_dir / "country.json"
        with open(profile_path, "w", encoding="utf-8") as f:
            json.dump(cdata, f, ensure_ascii=False, indent=2)

    def _write_territory(
        self,
        country_dir: Path,
        tag: str,
        owned_states: List[Dict[str, Any]],
        cored_states: List[int]
    ) -> Dict[str, Any]:
        all_provinces: List[int] = []
        total_manpower = 0
        total_resources: Dict[str, float] = defaultdict(float)

        for s in owned_states:
            all_provinces.extend(s.get("provinces", []))
            total_manpower += s.get("manpower", 0)
            res = s.get("resources", {})
            if isinstance(res, dict):
                for rk, rv in res.items():
                    try:
                        total_resources[rk] += float(rv)
                    except (ValueError, TypeError):
                        pass

        territory_data = {
            "tag": tag,
            "owned_state_ids": [s["id"] for s in owned_states],
            "core_state_ids": cored_states,
            "provinces_count": len(all_provinces),
            "provinces": all_provinces,
            "total_manpower": total_manpower,
            "total_resources": dict(total_resources)
        }
        with open(country_dir / "territory.json", "w", encoding="utf-8") as f:
            json.dump(territory_data, f, ensure_ascii=False, indent=2)
        return territory_data

    def _write_leaders(self, country_dir: Path, leaders: List[Dict[str, Any]]) -> None:
        leaders_dir = country_dir / "leaders"
        leaders_dir.mkdir(parents=True, exist_ok=True)

        leaders_index = {}
        for leader in leaders:
            lid = leader.get("id")
            if not lid:
                continue
            lpath = leaders_dir / f"{lid}.json"
            with open(lpath, "w", encoding="utf-8") as f:
                json.dump(leader, f, ensure_ascii=False, indent=2)
            leaders_index[lid] = {
                "id": lid,
                "name": leader.get("name_text", lid),
                "portraits": leader.get("portraits", {})
            }

        with open(leaders_dir / "index.json", "w", encoding="utf-8") as f:
            json.dump(leaders_index, f, ensure_ascii=False, indent=2)

    def _write_directives(self, country_dir: Path, tag: str, trees: List[Dict[str, Any]]) -> None:
        directives_dir = country_dir / "directives"
        directives_dir.mkdir(parents=True, exist_ok=True)
        trees_dir = directives_dir / "trees"
        trees_dir.mkdir(parents=True, exist_ok=True)

        manifest = {"tag": tag, "stages": {}, "trees": {}}

        for idx, tree in enumerate(trees):
            tree_id = tree.get("tree_id", f"{tag}_{idx}")
            tree_path = trees_dir / f"{tree_id}.json"
            with open(tree_path, "w", encoding="utf-8") as f:
                json.dump(tree, f, ensure_ascii=False, indent=2)

            manifest["trees"][tree_id] = {
                "id": tree_id,
                "file": f"res://data/countries/{tag}/directives/trees/{tree_id}.json",
                "count": tree.get("directives_count", 0)
            }

        with open(directives_dir / "trees_manifest.json", "w", encoding="utf-8") as f:
            json.dump(manifest, f, ensure_ascii=False, indent=2)

        # Write tree.json (default active starting tree)
        if trees:
            starting_tree = trees[0]
            with open(directives_dir / "tree.json", "w", encoding="utf-8") as f:
                json.dump(starting_tree, f, ensure_ascii=False, indent=2)

    def _write_localisation(
        self,
        country_dir: Path,
        tag: str,
        cdata: Dict[str, Any],
        leaders: List[Dict[str, Any]],
        trees: List[Dict[str, Any]]
    ) -> None:
        loc_dir = country_dir / "localisation"
        loc_dir.mkdir(parents=True, exist_ok=True)

        # Collect keys relevant to this country
        keys_to_export: Set[str] = {tag, f"{tag}_DEF", f"{tag}_ADJ"}
        for leader in leaders:
            keys_to_export.add(leader.get("name_key", ""))
        for tree in trees:
            for d in tree.get("directives", []):
                keys_to_export.add(d.get("id", ""))
                keys_to_export.add(f"{d.get('id', '')}_desc")

        ru_all = self.loc_db.get("russian", {})
        en_all = self.loc_db.get("english", {})

        ru_country = {k: ru_all[k] for k in keys_to_export if k in ru_all}
        en_country = {k: en_all[k] for k in keys_to_export if k in en_all}

        # Save country_ru.json & country_en.json (canonical for LocalizationManager)
        with open(loc_dir / "country_ru.json", "w", encoding="utf-8") as f:
            json.dump(ru_country, f, ensure_ascii=False, indent=2)
        with open(loc_dir / "country_en.json", "w", encoding="utf-8") as f:
            json.dump(en_country, f, ensure_ascii=False, indent=2)

    def _build_country_sqlite(
        self,
        country_dir: Path,
        tag: str,
        cdata: Dict[str, Any],
        territory: Dict[str, Any],
        leaders: List[Dict[str, Any]],
        trees: List[Dict[str, Any]],
        events: List[Dict[str, Any]],
        decisions: List[Dict[str, Any]]
    ) -> None:
        sqlite_path = country_dir / "country.sqlite"
        if sqlite_path.exists():
            sqlite_path.unlink()

        conn = sqlite3.connect(sqlite_path)
        cur = conn.cursor()

        # Tables: profile, territory, leaders, directives, events, decisions
        cur.execute("""
            CREATE TABLE profile (
                key TEXT PRIMARY KEY,
                value TEXT
            )
        """)
        for k, v in cdata.items():
            val_str = json.dumps(v, ensure_ascii=False) if isinstance(v, (dict, list)) else str(v)
            cur.execute("INSERT OR REPLACE INTO profile VALUES (?, ?)", (k, val_str))

        cur.execute("""
            CREATE TABLE territory (
                key TEXT PRIMARY KEY,
                value TEXT
            )
        """)
        for k, v in territory.items():
            val_str = json.dumps(v, ensure_ascii=False) if isinstance(v, (dict, list)) else str(v)
            cur.execute("INSERT OR REPLACE INTO territory VALUES (?, ?)", (k, val_str))

        cur.execute("""
            CREATE TABLE leaders (
                id TEXT PRIMARY KEY,
                name TEXT,
                data_json TEXT
            )
        """)
        for leader in leaders:
            cur.execute("INSERT OR REPLACE INTO leaders VALUES (?, ?, ?)", (
                leader.get("id", ""),
                leader.get("name_text", ""),
                json.dumps(leader, ensure_ascii=False)
            ))

        cur.execute("""
            CREATE TABLE directives (
                id TEXT PRIMARY KEY,
                tree_id TEXT,
                cost_turns INTEGER,
                data_json TEXT
            )
        """)
        for tree in trees:
            tid = tree.get("tree_id", "")
            for d in tree.get("directives", []):
                cur.execute("INSERT OR REPLACE INTO directives VALUES (?, ?, ?, ?)", (
                    d.get("id", ""),
                    tid,
                    d.get("cost_turns", 1),
                    json.dumps(d, ensure_ascii=False)
                ))

        cur.execute("""
            CREATE TABLE events (
                id TEXT PRIMARY KEY,
                type TEXT,
                title TEXT,
                data_json TEXT
            )
        """)
        for ev in events:
            cur.execute("INSERT OR REPLACE INTO events VALUES (?, ?, ?, ?)", (
                ev.get("id", ""),
                ev.get("type", "country_event"),
                ev.get("title", ""),
                json.dumps(ev, ensure_ascii=False)
            ))

        cur.execute("""
            CREATE TABLE decisions (
                id TEXT PRIMARY KEY,
                category_id TEXT,
                name TEXT,
                data_json TEXT
            )
        """)
        for dec in decisions:
            cur.execute("INSERT OR REPLACE INTO decisions VALUES (?, ?, ?, ?)", (
                dec.get("id", ""),
                dec.get("category_id", ""),
                dec.get("name", ""),
                json.dumps(dec, ensure_ascii=False)
            ))

        conn.commit()
        conn.close()
