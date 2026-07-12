XCODE_DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

.PHONY: test xcodebuild-test test-rime-abi test-rime-traits test-prebuilt-rime test-install-transactions generate-sample-dict build-vendored-librime build-input-method build-dmg build-release-dmg verify-distribution install-input-method install-input-method-system verify-input-method repair-input-method-sources uninstall-input-method

test:
	DEVELOPER_DIR="$(XCODE_DEVELOPER_DIR)" swift test --disable-swift-testing

xcodebuild-test:
	DEVELOPER_DIR="$(XCODE_DEVELOPER_DIR)" xcodebuild test -scheme LeftIO-Package -destination 'platform=macOS'

test-install-transactions:
	scripts/test_install_transactions.sh

test-rime-abi:
	scripts/test_rime_abi_guard.sh

test-rime-traits:
	scripts/test_rime_trait_lifetime.sh

test-prebuilt-rime:
	scripts/test_prebuilt_rime_startup.sh

generate-sample-dict:
	python3 scripts/generate_onehand_t9_dict.py scripts/sample_pinyin.tsv > data/onehand_t9.dict.yaml

build-vendored-librime:
	scripts/build_vendored_librime.sh

build-input-method:
	DEVELOPER_DIR="$(XCODE_DEVELOPER_DIR)" scripts/build_input_method_app.sh

build-dmg: build-input-method
	DEVELOPER_DIR="$(XCODE_DEVELOPER_DIR)" scripts/build_dmg.sh

build-release-dmg:
	DEVELOPER_DIR="$(XCODE_DEVELOPER_DIR)" scripts/build_release_dmg.sh

verify-distribution:
	scripts/verify_distribution.sh .build/input-method/LeftIO.app .build/dmg/LeftIO.dmg

install-input-method: build-input-method
	scripts/install_input_method_app.sh

install-input-method-system: build-input-method
	scripts/install_input_method_app_system.sh

verify-input-method:
	scripts/verify_input_method_install.sh

repair-input-method-sources:
	scripts/repair_input_method_sources.sh

uninstall-input-method:
	scripts/uninstall_input_method_app.sh
