.PHONY: fmt fmt-lint

# swift-format
fmt:
	swift format --in-place --recursive SoraQuickStart

# swift-format lint
fmt-lint:
	swift format lint --strict --parallel --recursive SoraQuickStart

# すべてを実行
all: fmt-lint fmt
