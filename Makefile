XCODE_DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

.PHONY: test xcodebuild-test generate-sample-dict build-input-method install-input-method install-input-method-system uninstall-input-method

test:
	DEVELOPER_DIR="$(XCODE_DEVELOPER_DIR)" swift test --disable-swift-testing

xcodebuild-test:
	DEVELOPER_DIR="$(XCODE_DEVELOPER_DIR)" xcodebuild test -scheme LeftIO-Package -destination 'platform=macOS'

generate-sample-dict:
	python3 scripts/generate_onehand_t9_dict.py scripts/sample_pinyin.tsv > data/onehand_t9.dict.yaml

build-input-method:
	DEVELOPER_DIR="$(XCODE_DEVELOPER_DIR)" scripts/build_input_method_app.sh

install-input-method: build-input-method
	scripts/install_input_method_app.sh

install-input-method-system: build-input-method
	scripts/install_input_method_app_system.sh

uninstall-input-method:
	rm -rf "$(HOME)/Library/Input Methods/LeftIO.app"
	-rm -rf "$(HOME)/Applications/LeftIO.app"
	-osascript -e 'do shell script "rm -rf /Library/Input\\\\ Methods/LeftIO.app; rm -rf /Applications/LeftIO.app" with administrator privileges'
	-pkill -x LeftIOInputMethod
