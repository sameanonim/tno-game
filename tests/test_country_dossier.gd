class_name TestCountryDossier
extends TNOSimpleTest

##
## TestCountryDossier: Тестирование генерации досье лидеров и фоллбэка для малых наций (DEF-17)
##


func test_canonical_country_dossier() -> void:
	var dossier = CountryDossierProvider.get_country_dossier("USA")
	assert_false(dossier.is_empty(), "Досье США должно быть загружено")
	assert_eq(dossier["tag"], "USA", "Тег должен быть USA")
	assert_true(str(dossier["leader_name"]).contains("Никсон") or str(dossier["leader_name"]).contains("Nixon"), "Лидером США должен быть Никсон")


func test_minor_country_fallback_generation() -> void:
	# Запрашиваем Парагвай (PAR), у которого нет отдельного country.json, но есть папка лидеров
	var dossier = CountryDossierProvider.get_country_dossier("PAR")
	assert_false(dossier.is_empty(), "Досье малой нации должно быть успешно сгенерировано")
	assert_eq(dossier["tag"], "PAR", "Тег должен быть PAR")
	assert_false(str(dossier["leader_name"]).contains("Жуков"), "Лидер Парагвая не должен быть Жуковым")
	assert_false(str(dossier["leader_name"]).contains("Ворошилов"), "Лидер Парагвая не должен быть Ворошиловым")

	var p_path = str(dossier["portrait_path"])
	assert_true(p_path.ends_with(".png"), "Путь портрета должен указывать на PNG")
	assert_true(ResourceLoader.exists(p_path) or FileAccess.file_exists(p_path), "Файл портрета должен физически существовать")

	assert_true(float(dossier["starting_gdp"]) > 0.0, "ВВП должен быть положительным")
	assert_true(int(dossier["starting_manpower"]) > 0, "Людские ресурсы должны быть положительными")
	assert_true(int(dossier["starting_factories"]) > 0, "Количество фабрик должно быть положительным")
