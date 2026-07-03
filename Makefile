XCODE_DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

.PHONY: test xcodebuild-test generate-sample-dict

test:
	DEVELOPER_DIR="$(XCODE_DEVELOPER_DIR)" swift test --disable-swift-testing

xcodebuild-test:
	DEVELOPER_DIR="$(XCODE_DEVELOPER_DIR)" xcodebuild test -scheme LeftIO-Package -destination 'platform=macOS'

generate-sample-dict:
	python3 scripts/generate_onehand_t9_dict.py scripts/sample_pinyin.tsv > data/onehand_t9.dict.yaml
