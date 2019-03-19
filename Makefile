all: build

# Get the absolute path and name of the current directory.
PWD := $(abspath .)
BASE_DIR := $(notdir $(PWD))

################################################################################
##                             VERIFY GO VERSION                              ##
################################################################################
# Go 1.11+ required for Go modules.
GO_VERSION_EXP := "go1.11"
GO_VERSION_ACT := $(shell a="$$(go version | awk '{print $$3}')" && test $$(printf '%s\n%s' "$${a}" "$(GO_VERSION_EXP)" | sort | tail -n 1) = "$${a}" && printf '%s' "$${a}")
ifndef GO_VERSION_ACT
$(error Requires Go $(GO_VERSION_EXP)+ for Go module support)
endif
MOD_NAME := $(shell head -n 1 <go.mod | awk '{print $$2}')

################################################################################
##                             VERIFY BUILD PATH                              ##
################################################################################
ifneq (on,$(GO111MODULE))
export GO111MODULE := on
# The cloud provider should not be cloned inside the GOPATH.
GOPATH := $(shell go env GOPATH)
ifeq (/src/$(MOD_NAME),$(subst $(GOPATH),,$(PWD)))
$(warning This project uses Go modules and should not be cloned into the GOPATH)
endif
endif

################################################################################
##                                DEPENDENCIES                                ##
################################################################################
# Ensure Mercurial is installed.
HAS_MERCURIAL := $(shell command -v hg 2>/dev/null)
ifndef HAS_MERCURIAL
.PHONY: install-hg
install-hg:
	pip install --user Mercurial
deps: install-hg
endif

# Verify the dependencies are in place.
.PHONY: deps
deps:
	go mod download && go mod verify

################################################################################
##                              BUILD BINARIES                                ##
################################################################################
# Unless otherwise specified the binaries should be built for linux-amd64.
GOOS ?= linux
GOARCH ?= amd64

# Ensure the version is injected into the binaries via a linker flag.
VERSION := $(shell git describe --exact-match 2>/dev/null || git describe --match=$$(git rev-parse --short=8 HEAD) --always --dirty --abbrev=8)
LDFLAGS_CCM := -extldflags "-static" -w -s -X "main.version=$(VERSION)"
LDFLAGS_CSI := -extldflags "-static" -w -s -X "$(MOD_NAME)/pkg/csi/service.version=$(VERSION)"

# The cloud controller binary.
CCM_BIN_NAME := vsphere-cloud-controller-manager
CCM_BIN := $(CCM_BIN_NAME).$(GOOS)_$(GOARCH)
build-ccm: $(CCM_BIN)
ifndef CCM_BIN_SRCS
CCM_BIN_SRCS := cmd/$(CCM_BIN_NAME)/main.go go.mod go.sum
CCM_BIN_SRCS += $(addsuffix /*,$(shell go list -f '{{ join .Deps "\n" }}' ./cmd/$(CCM_BIN_NAME) | grep $(MOD_NAME) | sed 's~$(MOD_NAME)~.~'))
export CCM_BIN_SRCS
endif
$(CCM_BIN): $(CCM_BIN_SRCS)
	CGO_ENABLED=0 GOOS=$(GOOS) GOARCH=$(GOARCH) go build -ldflags '$(LDFLAGS_CCM)' -o $@ $<
	@touch $@

# The CSI binary.
CSI_BIN_NAME := vsphere-csi
CSI_BIN := $(CSI_BIN_NAME).$(GOOS)_$(GOARCH)
build-csi: $(CSI_BIN)
ifndef CSI_BIN_SRCS
CSI_BIN_SRCS := cmd/$(CSI_BIN_NAME)/main.go go.mod go.sum
CSI_BIN_SRCS += $(addsuffix /*,$(shell go list -f '{{ join .Deps "\n" }}' ./cmd/$(CSI_BIN_NAME) | grep $(MOD_NAME) | sed 's~$(MOD_NAME)~.~'))
export CSI_BIN_SRCS
endif
$(CSI_BIN): $(CSI_BIN_SRCS)
	CGO_ENABLED=0 GOOS=$(GOOS) GOARCH=$(GOARCH) go build -ldflags '$(LDFLAGS_CSI)' -o $@ $<
	@touch $@

# The default build target.
build: $(CCM_BIN) $(CSI_BIN)
build-with-docker:
	hack/make.sh

################################################################################
##                                   DIST                                     ##
################################################################################
DIST_CCM_NAME := cloud-provider-vsphere-$(VERSION)
DIST_CCM_TGZ := $(DIST_CCM_NAME)-$(GOOS)_$(GOARCH).tar.gz
dist-ccm-tgz: $(DIST_CCM_TGZ)
$(DIST_CCM_TGZ): $(CCM_BIN)
	_temp_dir=$$(mktemp -d) && cp $< "$${_temp_dir}/$(CCM_BIN_NAME)" && \
	tar czf $@ README.md LICENSE -C "$${_temp_dir}" "$(CCM_BIN_NAME)" && \
	rm -fr "$${_temp_dir}"

DIST_CCM_ZIP := $(DIST_CCM_NAME)-$(GOOS)_$(GOARCH).zip
dist-ccm-zip: $(DIST_CCM_ZIP)
$(DIST_CCM_ZIP): $(CCM_BIN)
	_temp_dir=$$(mktemp -d) && cp $< "$${_temp_dir}/$(CCM_BIN_NAME)" && \
	zip -j $@ README.md LICENSE "$${_temp_dir}/$(CCM_BIN_NAME)" && \
	rm -fr "$${_temp_dir}"

dist-ccm: dist-ccm-tgz dist-ccm-zip

DIST_CSI_NAME := vsphere-csi-$(VERSION)
DIST_CSI_TGZ := $(DIST_CSI_NAME)-$(GOOS)_$(GOARCH).tar.gz
dist-csi-tgz: $(DIST_CSI_TGZ)
$(DIST_CSI_TGZ): $(CSI_BIN)
	_temp_dir=$$(mktemp -d) && cp $< "$${_temp_dir}/$(CSI_BIN_NAME)" && \
	tar czf $@ README.md LICENSE -C "$${_temp_dir}" "$(CSI_BIN_NAME)" && \
	rm -fr "$${_temp_dir}"

DIST_CSI_ZIP := $(DIST_CSI_NAME)-$(GOOS)_$(GOARCH).zip
dist-csi-zip: $(DIST_CSI_ZIP)
$(DIST_CSI_ZIP): $(CSI_BIN)
	_temp_dir=$$(mktemp -d) && cp $< "$${_temp_dir}/$(CSI_BIN_NAME)" && \
	zip -j $@ README.md LICENSE "$${_temp_dir}/$(CSI_BIN_NAME)" && \
	rm -fr "$${_temp_dir}"

dist-csi: dist-csi-tgz dist-csi-zip

dist: dist-ccm dist-csi

################################################################################
##                                 CLEAN                                      ##
################################################################################
.PHONY: clean
clean:
	@rm -f $(CCM_BIN) cloud-provider-vsphere-*.tar.gz cloud-provider-vsphere-*.zip \
		$(CSI_BIN) vsphere-csi-*.tar.gz vsphere-csi-*.zip \
		image-*-*.tar image-*-latest.tar
	GO111MODULE=off go clean -i -x . ./cmd/$(CCM_BIN_NAME) ./cmd/$(CSI_BIN_NAME)

################################################################################
##                                CROSS BUILD                                 ##
################################################################################

# Defining X_BUILD_DISABLED prevents the cross-build and cross-dist targets
# from being defined. This is to improve performance when invoking x-build
# or x-dist targets that invoke this Makefile. The nested call does not need
# to provide cross-build or cross-dist targets since it's the result of one.
ifndef X_BUILD_DISABLED

export X_BUILD_DISABLED := 1

# Modify this list to add new cross-build and cross-dist targets.
X_TARGETS ?= darwin_amd64 linux_amd64 linux_386 linux_arm linux_arm64 linux_ppc64le

X_TARGETS := $(filter-out $(GOOS)_$(GOARCH),$(X_TARGETS))

X_CCM_BINS := $(addprefix $(CCM_BIN_NAME).,$(X_TARGETS))
$(X_CCM_BINS):
	GOOS=$(word 1,$(subst _, ,$(subst $(CCM_BIN_NAME).,,$@))) GOARCH=$(word 2,$(subst _, ,$(subst $(CCM_BIN_NAME).,,$@))) $(MAKE) build-ccm

X_CSI_BINS := $(addprefix $(CSI_BIN_NAME).,$(X_TARGETS))
$(X_CSI_BINS):
	GOOS=$(word 1,$(subst _, ,$(subst $(CSI_BIN_NAME).,,$@))) GOARCH=$(word 2,$(subst _, ,$(subst $(CSI_BIN_NAME).,,$@))) $(MAKE) build-csi

x-build-ccm: $(CCM_BIN) $(X_CCM_BINS)
x-build-csi: $(CSI_BIN) $(X_CSI_BINS)

x-build: x-build-ccm x-build-csi

################################################################################
##                                CROSS DIST                                  ##
################################################################################

X_DIST_CCM_TARGETS := $(X_TARGETS)
X_DIST_CCM_TARGETS := $(addprefix $(DIST_CCM_NAME)-,$(X_DIST_CCM_TARGETS))
X_DIST_CCM_TGZS := $(addsuffix .tar.gz,$(X_DIST_CCM_TARGETS))
X_DIST_CCM_ZIPS := $(addsuffix .zip,$(X_DIST_CCM_TARGETS))
$(X_DIST_CCM_TGZS):
	GOOS=$(word 1,$(subst _, ,$(subst $(DIST_CCM_NAME)-,,$@))) GOARCH=$(word 2,$(subst _, ,$(subst $(DIST_CCM_NAME)-,,$(subst .tar.gz,,$@)))) $(MAKE) dist-ccm-tgz
$(X_DIST_CCM_ZIPS):
	GOOS=$(word 1,$(subst _, ,$(subst $(DIST_CCM_NAME)-,,$@))) GOARCH=$(word 2,$(subst _, ,$(subst $(DIST_CCM_NAME)-,,$(subst .zip,,$@)))) $(MAKE) dist-ccm-zip

X_DIST_CSI_TARGETS := $(X_TARGETS)
X_DIST_CSI_TARGETS := $(addprefix $(DIST_CSI_NAME)-,$(X_DIST_CSI_TARGETS))
X_DIST_CSI_TGZS := $(addsuffix .tar.gz,$(X_DIST_CSI_TARGETS))
X_DIST_CSI_ZIPS := $(addsuffix .zip,$(X_DIST_CSI_TARGETS))
$(X_DIST_CSI_TGZS):
	GOOS=$(word 1,$(subst _, ,$(subst $(DIST_CSI_NAME)-,,$@))) GOARCH=$(word 2,$(subst _, ,$(subst $(DIST_CSI_NAME)-,,$(subst .tar.gz,,$@)))) $(MAKE) dist-csi-tgz
$(X_DIST_CSI_ZIPS):
	GOOS=$(word 1,$(subst _, ,$(subst $(DIST_CSI_NAME)-,,$@))) GOARCH=$(word 2,$(subst _, ,$(subst $(DIST_CSI_NAME)-,,$(subst .zip,,$@)))) $(MAKE) dist-csi-zip

x-dist-ccm-tgzs: $(DIST_CCM_TGZ) $(X_DIST_CCM_TGZS)
x-dist-ccm-zips: $(DIST_CCM_ZIP) $(X_DIST_CCM_ZIPS)
x-dist-ccm: x-dist-ccm-tgzs x-dist-ccm-zips

x-dist-csi-tgzs: $(DIST_CSI_TGZ) $(X_DIST_CSI_TGZS)
x-dist-csi-zips: $(DIST_CSI_ZIP) $(X_DIST_CSI_ZIPS)
x-dist-csi: x-dist-csi-tgzs x-dist-csi-zips

x-dist: x-dist-ccm x-dist-csi

################################################################################
##                               CROSS CLEAN                                  ##
################################################################################

X_CLEAN_TARGETS := $(addprefix clean-,$(X_TARGETS))
.PHONY: $(X_CLEAN_TARGETS)
$(X_CLEAN_TARGETS):
	GOOS=$(word 1,$(subst _, ,$(subst clean-,,$@))) GOARCH=$(word 2,$(subst _, ,$(subst clean-,,$@))) $(MAKE) clean

.PHONY: x-clean
x-clean: clean $(X_CLEAN_TARGETS)

endif # ifndef X_BUILD_DISABLED

################################################################################
##                                 TESTING                                    ##
################################################################################
PKGS_WITH_TESTS := $(sort $(shell find . -name "*_test.go" -type f -exec dirname \{\} \;))
TEST_FLAGS ?= -v
.PHONY: unit build-unit-tests
unit:
	env -u VSPHERE_SERVER -u VSPHERE_PASSWORD -u VSPHERE_USER go test $(TEST_FLAGS) -tags=unit $(PKGS_WITH_TESTS)
build-unit-tests:
	$(foreach pkg,$(PKGS_WITH_TESTS),go test $(TEST_FLAGS) -c -tags=unit $(pkg); )

# The default test target.
.PHONY: test build-tests
test: unit
build-tests: build-unit-tests

.PHONY: cover
cover: TEST_FLAGS += -cover
cover: test

################################################################################
##                                 LINTING                                    ##
################################################################################
.PHONY: fmt
fmt:
	find . -name "*.go" | grep -v vendor | xargs gofmt -s -w

.PHONY: vet
vet:
	go vet ./...

HAS_LINT := $(shell command -v golint 2>/dev/null)
.PHONY: lint
lint:
ifndef HAS_LINT
	cd / && GO111MODULE=off go get -u github.com/golang/lint/golint
endif
	go list ./... | xargs golint -set_exit_status | sed 's~$(PWD)~.~'

.PHONY: check
check:
	{ $(MAKE) fmt  || exit_code_1="$${?}"; } && \
	{ $(MAKE) vet  || exit_code_2="$${?}"; } && \
	{ $(MAKE) lint || exit_code_3="$${?}"; } && \
	{ [ -z "$${exit_code_1}" ] || echo "fmt  failed: $${exit_code_1}" 1>&2; } && \
	{ [ -z "$${exit_code_2}" ] || echo "vet  failed: $${exit_code_2}" 1>&2; } && \
	{ [ -z "$${exit_code_3}" ] || echo "lint failed: $${exit_code_3}" 1>&2; } && \
	{ [ -z "$${exit_code_1}" ] || exit "$${exit_code_1}"; } && \
	{ [ -z "$${exit_code_2}" ] || exit "$${exit_code_2}"; } && \
	{ [ -z "$${exit_code_3}" ] || exit "$${exit_code_3}"; } && \
	exit 0

.PHONY: check-warn
check-warn:
	-$(MAKE) check

################################################################################
##                                 BUILD IMAGES                               ##
################################################################################
REGISTRY ?= gcr.io/cloud-provider-vsphere

IMAGE_CCM := $(REGISTRY)/vsphere-cloud-controller-manager
IMAGE_CCM_TAR := image-ccm-$(VERSION).tar
build-ccm-image ccm-image: $(IMAGE_CCM_TAR)
ifneq ($(GOOS),linux)
$(IMAGE_CCM) $(IMAGE_CCM_TAR):
	$(error Please set GOOS=linux for building $@)
else
$(IMAGE_CCM) $(IMAGE_CCM_TAR): $(CCM_BIN)
	cp -f $< cluster/images/controller-manager/vsphere-cloud-controller-manager
	docker build -t $(IMAGE_CCM):$(VERSION) cluster/images/controller-manager
	docker tag $(IMAGE_CCM):$(VERSION) $(IMAGE_CCM):latest
	docker save $(IMAGE_CCM):$(VERSION) -o $@
	docker save $(IMAGE_CCM):$(VERSION) -o image-ccm-latest.tar
endif

IMAGE_CSI := $(REGISTRY)/vsphere-csi
IMAGE_CSI_TAR := image-csi-$(VERSION).tar
build-csi-image csi-image: $(IMAGE_CSI_TAR)
ifneq ($(GOOS),linux)
$(IMAGE_CSI) $(IMAGE_CSI_TAR):
	$(error Please set GOOS=linux for building $@)
else
$(IMAGE_CSI) $(IMAGE_CSI_TAR): $(CSI_BIN)
	cp -f $< cluster/images/csi/vsphere-csi
	docker build -t $(IMAGE_CSI):$(VERSION) cluster/images/csi
	docker tag $(IMAGE_CSI):$(VERSION) $(IMAGE_CSI):latest
	docker save $(IMAGE_CSI):$(VERSION) -o $@
	docker save $(IMAGE_CSI):$(VERSION) -o image-csi-latest.tar
endif

build-images images: build-ccm-image build-csi-image

################################################################################
##                                  PUSH IMAGES                               ##
################################################################################
.PHONY: login-to-image-registry
login-to-image-registry:
# Push images to a gcr.io registry.
ifneq (,$(findstring gcr.io,$(REGISTRY))) # begin gcr.io
# Log into the registry with a gcr.io JSON key file.
ifneq (,$(strip $(GCR_KEY_FILE))) # begin gcr.io-key
	@echo "logging into gcr.io registry with key file"
	docker login -u _json_key --password-stdin https://gcr.io <"$(GCR_KEY_FILE)"
# Log into the registry with a Docker gcloud auth helper.
else # end gcr.io-key / begin gcr.io-gcloud
	@command -v gcloud >/dev/null 2>&1 || \
	  { echo 'gcloud auth helper unavailable' 1>&2; exit 1; }
	@grep -F 'gcr.io": "gcloud"' "$(HOME)/.docker/config.json" >/dev/null 2>&1 || \
	  { gcloud auth configure-docker --quiet || \
	    echo 'gcloud helper registration failed' 1>&2; exit 1; }
	@echo "logging into gcr.io registry with gcloud auth helper"
endif # end gcr.io-gcloud / end gcr.io
# Push images to a Docker registry.
else # begin docker
# Log into the registry with a Docker username and password.
ifneq (,$(strip $(DOCKER_USERNAME))) # begin docker-username
ifneq (,$(strip $(DOCKER_PASSWORD))) # begin docker-password
	@echo "logging into docker registry with username and password"
	docker login -u="$(DOCKER_USERNAME)" -p="$(DOCKER_PASSWORD)"
endif # end docker-password
endif # end docker-username
endif # end docker

.PHONY: push-$(IMAGE_CCM) upload-$(IMAGE_CCM)
push-ccm-image upload-ccm-image: upload-$(IMAGE_CCM)
push-$(IMAGE_CCM) upload-$(IMAGE_CCM): $(IMAGE_CCM_TAR) login-to-image-registry
	docker push $(IMAGE_CCM):$(VERSION)
	docker push $(IMAGE_CCM):latest

.PHONY: push-$(IMAGE_CSI) upload-$(IMAGE_CSI)
push-csi-image upload-csi-image: upload-$(IMAGE_CSI)
push-$(IMAGE_CSI) upload-$(IMAGE_CSI): $(IMAGE_CSI_TAR) login-to-image-registry
	docker push $(IMAGE_CSI):$(VERSION)
	docker push $(IMAGE_CSI):latest

.PHONY: push-images upload-images
push-images upload-images: upload-ccm-image upload-csi-image

################################################################################
##                               PRINT VERISON                                ##
################################################################################
.PHONY: version
version:
	@echo $(VERSION)

################################################################################
##                                TODO(akutz)                                 ##
################################################################################
TODO := docs godoc releasenotes translation
.PHONY: $(TODO)
$(TODO):
	@echo "$@ not yet implemented"
