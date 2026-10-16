export PATH := $(CURDIR)/.tools/bin:$(PATH)
IMAGE ?= quay.io/kubermatic/support

.PHONY: tools lint test image e2e release

tools:
	hack/install-tools.sh
