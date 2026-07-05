XCODE_DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

.PHONY: test xcodebuild-test generate-sample-dict build-vendored-librime build-input-method build-dmg install-input-method install-input-method-system verify-input-method uninstall-input-method

test:
	DEVELOPER_DIR="$(XCODE_DEVELOPER_DIR)" swift test --disable-swift-testing

xcodebuild-test:
	DEVELOPER_DIR="$(XCODE_DEVELOPER_DIR)" xcodebuild test -scheme LeftIO-Package -destination 'platform=macOS'

generate-sample-dict:
	python3 scripts/generate_onehand_t9_dict.py scripts/sample_pinyin.tsv > data/onehand_t9.dict.yaml

build-vendored-librime:
	scripts/build_vendored_librime.sh

build-input-method:
	DEVELOPER_DIR="$(XCODE_DEVELOPER_DIR)" scripts/build_input_method_app.sh

build-dmg: build-input-method
	DEVELOPER_DIR="$(XCODE_DEVELOPER_DIR)" scripts/build_dmg.sh

install-input-method: build-input-method
	scripts/install_input_method_app.sh

install-input-method-system: build-input-method
	scripts/install_input_method_app_system.sh

verify-input-method:
	scripts/verify_input_method_install.sh

uninstall-input-method:
	scripts/uninstall_input_method_app.sh
