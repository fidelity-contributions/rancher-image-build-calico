SEVERITIES = HIGH,CRITICAL

UNAME_M = $(shell uname -m)
ARCH=
ifeq ($(UNAME_M), x86_64)
	ARCH=amd64
else ifeq ($(UNAME_M), aarch64)
	ARCH=arm64
else 
	ARCH=$(UNAME_M)
endif

ifndef TARGET_PLATFORMS
	ifeq ($(UNAME_M), x86_64)
		TARGET_PLATFORMS:=linux/amd64
	else ifeq ($(UNAME_M), aarch64)
		TARGET_PLATFORMS:=linux/arm64
	else 
		TARGET_PLATFORMS:=linux/$(UNAME_M)
	endif
endif

BUILD_META=-build$(shell date +%Y%m%d)
ORG ?= rancher
TAG ?= ${GITHUB_ACTION_TAG}
REGISTRY_IMAGE ?= $(ORG)/hardened-calico
META_LABELS ?= ${META_LABELS}

K3S_ROOT_VERSION ?= v0.14.0

ifeq ($(TAG),)
TAG := v3.28.1$(BUILD_META)
endif

IMAGE ?= $(REGISTRY_IMAGE):$(TAG)

ifeq (,$(filter %$(BUILD_META),$(TAG)))
$(error TAG $(TAG) needs to end with build metadata: $(BUILD_META))
endif

.PHONY: image-build
image-build:
	docker buildx build --no-cache \
		--platform=$(ARCH) \
		--pull \
		--build-arg TAG=$(TAG:$(BUILD_META)=) \
		--build-arg K3S_ROOT_VERSION=$(K3S_ROOT_VERSION) \
		--tag $(IMAGE) \
		--tag $(IMAGE)-$(ARCH) \
		--load \
		.

.PHONY: push-image
push-image:
	docker buildx build \
		--sbom=true \
		--attest type=provenance,mode=max \
		--platform=$(TARGET_PLATFORMS) \
		--build-arg TAG=$(TAG:$(BUILD_META)=) \
		--build-arg K3S_ROOT_VERSION=$(K3S_ROOT_VERSION) \
		--outputs type=image,name=$(REGISTRY_IMAGE),push-by-digest=true,name-canonical=true,push=true \
		--tag $(IMAGE) \
		--tag $(IMAGE)-$(ARCH) \
		--label $(META_LABELS) \
		--push \
		--iidfile /tmp/image.digest \
		--metadata-file /tmp/metadata.json \
		.

	# Create directory for storing digests
	@mkdir -p /tmp/digests

	FULL_DIGEST := $(shell jq -r '.containerimage.digest' /tmp/metadata.json)
	DIGEST_SHA := $(shell echo $(FULL_DIGEST) | sed 's/^sha256://')

	@echo $(DIGEST_SHA) > "/tmp/digests/$(DIGEST_SHA)"


.PHONY: manifest-push
manifest-push:
	TAGS := $(shell echo '$(DOCKER_METADATA_OUTPUT_JSON)' | jq -r '.tags | map("-t " + .) | join(" ")')

	IMAGE_DIGESTS := $(shell for digest_file in *; do \
		echo -n "$(REGISTRY_IMAGE)@sha256:$$digest_file "; \
	done)

	@echo "Tags to be used: $(TAGS)"
	@echo "Image digests: $(IMAGE_DIGESTS)"

	docker buildx imagetools create $(TAGS) $(IMAGE_DIGESTS)

.PHONY: image-push
image-push:
	docker push $(ORG)/hardened-calico:$(TAG)-$(ARCH)

.PHONY: image-scan
image-scan:
	trivy image --severity $(SEVERITIES) --no-progress --ignore-unfixed $(ORG)/hardened-calico:$(TAG)

PHONY: log
log:
	@echo "ARCH=$(ARCH)"
	@echo "TAG=$(TAG:$(BUILD_META)=)"
	@echo "ORG=$(ORG)"
	@echo "PKG=$(PKG)"
	@echo "SRC=$(SRC)"
	@echo "BUILD_META=$(BUILD_META)"
	@echo "UNAME_M=$(UNAME_M)"
