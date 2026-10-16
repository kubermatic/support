export PATH := $(CURDIR)/.tools/bin:$(PATH)
IMAGE ?= quay.io/kubermatic/support

.PHONY: tools lint test image e2e release

tools:
	hack/install-tools.sh

lint:
	shellcheck -s sh node-collector/*.sh
	shellcheck hack/*.sh $(wildcard test/*.sh)

test: tools
	$(CURDIR)/.tools/bin/bats test/

image:
	docker build --build-arg VERSION=$$(cat node-collector/VERSION) -t $(IMAGE):dev node-collector

e2e: tools
	test/e2e.sh

release:
	hack/release-image.sh $$(cat node-collector/VERSION)
