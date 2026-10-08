class_name TestContentLoader
extends TNOSimpleTest

##
## TestContentLoader: Юнит-тесты модульной загрузки контента TNO
##

var loader: ContentLoader = null


func setup() -> void:
	loader = ContentLoader.new()
	loader.load_all()


func teardown() -> void:
	if loader != null:
		loader.free()
		loader = null


func test_loader_initialization() -> void:
	assert_true(loader.is_ready, "ContentLoader should be ready after load_all()")
	assert_true(loader.has_extracted_data(), "ContentLoader should have extracted packages data")


func test_manifest_packages_available() -> void:
	var manifest = loader.get_available_countries_manifest()
	assert_true(not manifest.is_empty(), "Manifest must not be empty")
	assert_true(manifest.size() > 50, "Expected at least 50 modular packages indexed")


func test_country_package_loading() -> void:
	var state = loader.load_country_package("KOM")
	assert_not_null(state, "Loading country KOM should return a valid CountryState")
	assert_eq(state.country_tag, "KOM", "Loaded state tag should match requested tag")
