# TNO Localization Audit & Normalization Report

**Date:** 2026-09-22 14:37:12  
**Execution Duration:** 77.96 seconds  

## 1. Executive Summary

| Metric | Value |
| :--- | :--- |
| **Total Files Scanned** | 1,439 |
| **Total Unique Keys** | 306,489 |
| **English Keys** | 303,163 |
| **Russian Native Keys** | 305,827 |
| **Untranslated Fallback Keys** | 662 |
| **Translation Coverage (RU/EN)** | **100.9%** |

## 2. Syntax Cleaning & Normalization

| Repair Category | Count |
| :--- | :--- |
| Multiline Strings Stitched | 1,533 |
| Unclosed Quotes Repaired | 4,062 |
| Interior Quotes Fixed (`« »`) | 327,723 |
| Clausewitz Color Tags Stripped (`§.`) | 517,910 |
| HoI4 Tokens Normalized to `{param}` | 37,267 |
| Nested `$KEY$` References Resolved | 20,543 |
| Circular References Prevented | 0 |

## 3. Top Missing Keys Requested by Game

Found **291** keys requested by game data but absent from text catalogs.

| # | Missing Key Name |
| :--- | :--- |
| 1 | `...` |
| 2 | `0.25` |
| 3 | `0.5` |
| 4 | `0.75` |
| 5 | `1` |
| 6 | `3-1` |
| 7 | `AAN` |
| 8 | `ADL_blankfocus` |
| 9 | `AP-UD` |
| 10 | `ARG_Rodolfo_Tecera_del_Franco` |
| 11 | `ARPANET` |
| 12 | `Adrift` |
| 13 | `Adygea` |
| 14 | `Afar` |
| 15 | `Albania` |
| 16 | `Alican` |
| 17 | `Amen.` |
| 18 | `America` |
| 19 | `Amur` |
| 20 | `Apokalipsys` |
| 21 | `Avaria` |
| 22 | `Aybar` |
| 23 | `BASIC` |
| 24 | `BOR_Foreign_DummyFocus` |
| 25 | `BOR_Foreign_Ostland_DummyFocus` |
| 26 | `BOR_Kaukasien_Dummy` |
| 27 | `BOR_Phase2_Foreign_Dummy` |
| 28 | `BOR_example` |
| 29 | `BOR_foreign_phase1` |
| 30 | `BR` |
| 31 | `BRR` |
| 32 | `BRS` |
| 33 | `BRY` |
| 34 | `BSQ_Ignacio_Iturbide` |
| 35 | `BSQ_Jesus_Maria_Leizaola` |
| 36 | `BSQ_Julen_Gimon` |
| 37 | `BSQ_Mariano_Sanchez` |
| 38 | `BTA` |
| 39 | `Banality` |
| 40 | `Barbados` |
| 41 | `Belize` |
| 42 | `Bellum` |
| 43 | `Bermuda` |
| 44 | `Blut` |
| 45 | `Bodyn` |
| 46 | `Buddy-Budd` |
| 47 | `C1.` |
| 48 | `CAM_Ea_Sichau` |
| 49 | `CAM_Hou_Yuon` |
| 50 | `CAM_Khieu_Samphan` |
| ... | *and 241 more keys* |
