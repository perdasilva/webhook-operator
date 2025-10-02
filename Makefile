# VERSION defines the project version for the bundle.
# Update this value when you upgrade the version of your project.
# To re-generate a bundle for another specific version without changing the standard setup, you can:
# - use the VERSION as arg of the bundle target (e.g make bundle VERSION=0.0.2)
# - use environment variables to overwrite this value (e.g export VERSION=0.0.2)
VERSION ?= 0.0.5

# CHANNELS define the bundle channels used in the bundle.
# Add a new line here if you would like to change its default config. (E.g CHANNELS = "candidate,fast,stable")
# To re-generate a bundle for other specific channels without changing the standard setup, you can:
# - use the CHANNELS as arg of the bundle target (e.g make bundle CHANNELS=candidate,fast,stable)
# - use environment variables to overwrite this value (e.g export CHANNELS="candidate,fast,stable")
ifneq ($(origin CHANNELS), undefined)
BUNDLE_CHANNELS := --channels=$(CHANNELS)
endif

# DEFAULT_CHANNEL defines the default channel used in the bundle.
# Add a new line here if you would like to change its default config. (E.g DEFAULT_CHANNEL = "stable")
# To re-generate a bundle for any other default channel without changing the default setup, you can:
# - use the DEFAULT_CHANNEL as arg of the bundle target (e.g make bundle DEFAULT_CHANNEL=stable)
# - use environment variables to overwrite this value (e.g export DEFAULT_CHANNEL="stable")
ifneq ($(origin DEFAULT_CHANNEL), undefined)
BUNDLE_DEFAULT_CHANNEL := --default-channel=$(DEFAULT_CHANNEL)
endif
BUNDLE_METADATA_OPTS ?= $(BUNDLE_CHANNELS) $(BUNDLE_DEFAULT_CHANNEL)

# IMAGE_TAG_BASE defines the docker.io namespace and part of the image name for remote images.
# This variable is used to construct full image tags for bundle and catalog images.
#
# For example, running 'make bundle-build bundle-push catalog-build catalog-push' will build and push both
# quay.io/olmtest/webhook-operator:$VERSION and quay.io/olmtest/webhook-operator-bundle:$VERSION.
IMAGE_TAG_BASE ?= quay.io/olmtest/webhook-operator

TAG ?= v$(VERSION)

# BUNDLE_IMG defines the image:tag used for the bundle.
# You can use it as an arg. (E.g make bundle-build BUNDLE_IMG=<some-registry>/<project-name-bundle>:<tag>)
BUNDLE_IMG_BASE ?= $(IMAGE_TAG_BASE)-bundle

# The image tag given to the resulting catalog image (e.g. make catalog-build CATALOG_IMG=example.com/operator-catalog:v0.2.0).
CATALOG_IMG_BASE ?= $(IMAGE_TAG_BASE)-index

# BUNDLE_GEN_FLAGS are the flags passed to the operator-sdk generate bundle command
BUNDLE_GEN_FLAGS ?= -q --overwrite --version $(VERSION) $(BUNDLE_METADATA_OPTS)

# USE_IMAGE_DIGESTS defines if images are resolved via tags or digests
# You can enable this value if you would like to use SHA Based Digests
# To enable set flag to true
USE_IMAGE_DIGESTS ?= false
ifeq ($(USE_IMAGE_DIGESTS), true)
	BUNDLE_GEN_FLAGS += --use-image-digests
endif

# Image URL to use all building/pushing image targets
IMG ?= quay.io/olmtest/webhook-operator:$(TAG)
BUNDLE_IMAGE = $(BUNDLE_IMG_BASE):$(TAG)
CATALOG_IMAGE = $(CATALOG_IMG_BASE):$(TAG)

# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

# CONTAINER_TOOL defines the container tool to be used for building images.
# Be aware that the target commands are only tested with Docker which is
# scaffolded by default. However, you might want to replace it to use other
# tools. (i.e. podman)
CONTAINER_TOOL ?= docker

# Setting SHELL to bash allows bash commands to be executed by recipes.
# Options are set to exit when a recipe line exits non-zero or a piped command fails.
SHELL = /usr/bin/env bash -o pipefail
.SHELLFLAGS = -ec
export ROOT_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))

# Tools
KUBECTL ?= kubectl

# bingo manages consistent tooling versions for things like kind, kustomize, etc.
include .bingo/Variables.mk

.PHONY: all
all: build

##@ General

# The help target prints out all targets with their descriptions organized
# beneath their categories. The categories are represented by '##@' and the
# target descriptions by '##'. The awk command is responsible for reading the
# entire set of makefiles included in this invocation, looking for lines of the
# file as xyz: ## something, and then pretty-format the target and help. Then,
# if there's a line with ##@ something, that gets pretty-printed as a category.
# More info on the usage of ANSI control characters for terminal formatting:
# https://en.wikipedia.org/wiki/ANSI_escape_code#SGR_parameters
# More info on the awk command:
# http://linuxcommand.org/lc3_adv_awk.php

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Development

.PHONY: manifests
manifests: $(CONTROLLER_GEN) ## Generate WebhookConfiguration, ClusterRole and CustomResourceDefinition objects.
	$(CONTROLLER_GEN) --load-build-tags=$(GO_BUILD_TAGS) rbac:roleName=manager-role crd webhook paths="./..." output:crd:artifacts:config=config/crd/bases

.PHONY: generate
generate: $(CONTROLLER_GEN) ## Generate code containing DeepCopy, DeepCopyInto, and DeepCopyObject method implementations.
	$(CONTROLLER_GEN) --load-build-tags=$(GO_BUILD_TAGS) object:headerFile="hack/boilerplate.go.txt" paths="./..."

.PHONY: fmt
fmt: ## Run go fmt against code.
	go fmt ./...

.PHONY: vet
vet: ## Run go vet against code.
	go vet ./...

.PHONY: test
test: $(SETUP_ENVTEST) manifests generate fmt vet ## Run tests.
	KUBEBUILDER_ASSETS="$(shell $(SETUP_ENVTEST) use -p path $(ENVTEST_VERSION) $(SETUP_ENVTEST_BIN_DIR_OVERRIDE))" go test $$(go list ./... | grep -v /e2e) -coverprofile cover.out

.PHONY: tidy
tidy:
	go mod tidy

.PHONY: verify
verify: tidy fmt bundle catalog manifests generate
	git diff --exit-code

# TODO(user): To use a different vendor for e2e tests, modify the setup under 'tests/e2e'.
# The default setup assumes Kind is pre-installed and builds/loads the Manager Docker image locally.
# CertManager is installed by default; skip with:
# - CERT_MANAGER_INSTALL_SKIP=true
KIND_CLUSTER ?= webhook-operator-test-e2e

.PHONY: setup-test-e2e
setup-test-e2e: $(KIND) ## Set up a Kind cluster for e2e tests if it does not exist
	@command -v $(KIND) >/dev/null 2>&1 || { \
		echo "Kind is not installed. Please install Kind manually."; \
		exit 1; \
	}
	@case "$$($(KIND) get clusters)" in \
		*"$(KIND_CLUSTER)"*) \
			echo "Kind cluster '$(KIND_CLUSTER)' already exists. Skipping creation." ;; \
		*) \
			echo "Creating Kind cluster '$(KIND_CLUSTER)'..."; \
			$(KIND) create cluster --name $(KIND_CLUSTER) ;; \
	esac

.PHONY: test-e2e
test-e2e: setup-test-e2e manifests generate fmt vet ## Run the e2e tests. Expected an isolated environment using Kind.
	KIND=$(KIND) KIND_CLUSTER=$(KIND_CLUSTER) go test -tags=e2e ./test/e2e/ -v -ginkgo.v
	$(MAKE) cleanup-test-e2e

.PHONY: cleanup-test-e2e
cleanup-test-e2e: ## Tear down the Kind cluster used for e2e tests
	@$(KIND) delete cluster --name $(KIND_CLUSTER)

.PHONY: lint
lint: $(GOLANGCI_LINT) ## Run golangci-lint linter
	$(GOLANGCI_LINT) run

.PHONY: lint-fix
lint-fix: $(GOLANGCI_LINT) ## Run golangci-lint linter and perform fixes
	$(GOLANGCI_LINT) run --fix

.PHONY: lint-config
lint-config: $(GOLANGCI_LINT) ## Verify golangci-lint linter configuration
	$(GOLANGCI_LINT) config verify

##@ Build
ifeq ($(origin CGO_ENABLED), undefined)
CGO_ENABLED := 0
endif
export CGO_ENABLED

export GIT_REPO := $(shell go list -m)
export VERSION_PATH := ${GIT_REPO}/internal/shared/version
export GO_BUILD_TAGS := containers_image_openpgp
export GO_BUILD_ASMFLAGS := all=-trimpath=$(PWD)
export GO_BUILD_GCFLAGS := all=-trimpath=$(PWD)
export GO_BUILD_EXTRA_FLAGS :=
export GO_BUILD_LDFLAGS := -s -w \
    -X '$(VERSION_PATH).version=$(VERSION)' \
    -X '$(VERSION_PATH).gitCommit=$(GIT_COMMIT)' \

.PHONY: build
build: manifests generate fmt vet ## Build manager binary.
	go build $(GO_BUILD_FLAGS) $(GO_BUILD_EXTRA_FLAGS) -tags '$(GO_BUILD_TAGS)' -ldflags '$(GO_BUILD_LDFLAGS)' -gcflags '$(GO_BUILD_GCFLAGS)' -asmflags '$(GO_BUILD_ASMFLAGS)' -o $(BUILDBIN)/manager cmd/main.go

.PHONY: build-linux go-build-linux
build-linux: go-build-linux #EXHELP Build manager binary for GOOS=linux and local GOARCH.
go-build-linux: BUILDBIN := bin/linux
go-build-linux: export GOOS=linux
go-build-linux: export GOARCH=amd64
go-build-linux: build

.PHONY: run
run: manifests generate fmt vet ## Run a controller from your host.
	go run ./cmd/main.go

# If you wish to build the manager image targeting other platforms you can use the --platform flag.
# (i.e. docker build --platform linux/arm64). However, you must enable docker buildKit for it.
# More info: https://docs.docker.com/develop/develop-images/build_enhancements/
.PHONY: docker-build
docker-build: build-linux ## Build docker image with the manager.
	$(CONTAINER_TOOL) build -t ${IMG} -f Dockerfile bin/linux

.PHONY: docker-push
docker-push: ## Push docker image with the manager.
	$(CONTAINER_TOOL) push ${IMG}

.PHONY: build-installer
build-installer: manifests generate $(KUSTOMIZE) ## Generate a consolidated YAML with CRDs and deployment.
	mkdir -p dist
	cd config/manager && $(KUSTOMIZE) edit set image controller=${IMG}
	$(KUSTOMIZE) build config/default > dist/install.yaml

##@ Deployment

ifndef ignore-not-found
  ignore-not-found = false
endif

.PHONY: install
install: manifests $(KUSTOMIZE) ## Install CRDs into the K8s cluster specified in ~/.kube/config.
	$(KUSTOMIZE) build config/crd | $(KUBECTL) apply -f -

.PHONY: uninstall
uninstall: manifests $(KUSTOMIZE) ## Uninstall CRDs from the K8s cluster specified in ~/.kube/config. Call with ignore-not-found=true to ignore resource not found errors during deletion.
	$(KUSTOMIZE) build config/crd | $(KUBECTL) delete --ignore-not-found=$(ignore-not-found) -f -

.PHONY: deploy
deploy: manifests $(KUSTOMIZE) ## Deploy controller to the K8s cluster specified in ~/.kube/config.
	cd config/manager && $(KUSTOMIZE) edit set image controller=${IMG}
	$(KUSTOMIZE) build config/default | $(KUBECTL) apply -f -

.PHONY: undeploy
undeploy: $(KUSTOMIZE) ## Undeploy controller from the K8s cluster specified in ~/.kube/config. Call with ignore-not-found=true to ignore resource not found errors during deletion.
	$(KUSTOMIZE) build config/default | $(KUBECTL) delete --ignore-not-found=$(ignore-not-found) -f -

##@ Dependencies

# Extract Kubernetes client-go version used to set the version to the PSA labels, for ENVTEST and KIND
ifeq ($(origin K8S_VERSION), undefined)
K8S_VERSION := $(shell go list -m k8s.io/client-go | cut -d" " -f2 | sed -E 's/^v0\.([0-9]+)\.[0-9]+$$/1.\1/')
endif

# Ensure ENVTEST_VERSION follows correct "X.Y.x" format
ENVTEST_VERSION := $(K8S_VERSION).x

# By default setup-envtest binary will write to $XDG_DATA_HOME, or $HOME/.local/share if that is not defined.
# If $HOME is not set, we need to specify a binary directory to prevent an error in setup-envtest.
# Useful for some CI/CD environments that set neither $XDG_DATA_HOME nor $HOME.
SETUP_ENVTEST_BIN_DIR_OVERRIDE += --bin-dir $(ROOT_DIR)/bin/envtest-binaries
ifeq ($(shell [[ $$HOME == "" || $$HOME == "/" ]] && [[ $$XDG_DATA_HOME == "" ]] && echo true ), true)
	SETUP_ENVTEST_BIN_DIR_OVERRIDE += --bin-dir /tmp/envtest-binaries
endif

.PHONY: envtest-k8s-bins #HELP Uses setup-envtest to download and install the binaries required to run ENVTEST-test based locally at the project/bin directory.
envtest-k8s-bins: $(SETUP_ENVTEST)
	mkdir -p $(ROOT_DIR)/bin
	$(SETUP_ENVTEST) use -p env $(ENVTEST_VERSION) $(SETUP_ENVTEST_BIN_DIR_OVERRIDE)

.PHONY: bundle
bundle: manifests $(KUSTOMIZE) $(OPERATOR_SDK) $(YQ) ## Generate bundle manifests and metadata, then validate generated files.
	$(OPERATOR_SDK) generate kustomize manifests -q
	cd config/manager && $(KUSTOMIZE) edit set image controller=$(IMG)
	$(KUSTOMIZE) build config/manifests | $(OPERATOR_SDK) generate bundle $(BUNDLE_GEN_FLAGS)
	$(OPERATOR_SDK) bundle validate ./bundle
	# remove cluster service version creation timestamp to not generate changes everytime the bundle is rebuilt
	$(YQ) -i 'del(.metadata.annotations.createdAt)' bundle/manifests/webhook-operator.clusterserviceversion.yaml


.PHONY: bundle-build
bundle-build: ## Build the bundle image.
	$(CONTAINER_TOOL) build -f bundle.Dockerfile -t $(BUNDLE_IMG) .

.PHONY: bundle-push
bundle-push: ## Push the bundle image.
	$(MAKE) docker-push IMG=$(BUNDLE_IMG)

.PHONY: catalog
catalog: $(OPM)
	@# Create base catalog from template
	sed "s/{{ VERSION }}/$(VERSION)/g" catalog/catalog.tpl > catalog/catalog.json
	@# Add bundle FBC
	$(OPM) render ./bundle >> catalog/catalog.json


ifeq ($(origin ENABLE_RELEASE_PIPELINE), undefined)
ENABLE_RELEASE_PIPELINE := false
endif
ifeq ($(origin GORELEASER_ARGS), undefined)
GORELEASER_ARGS := --snapshot --clean
endif

export ENABLE_RELEASE_PIPELINE
export GORELEASER_ARGS

.PHONY: release
release: $(GORELEASER) bundle catalog #EXHELP Runs goreleaser. By default, this will run only as a snapshot and will not publish any artifacts unless it is run with different arguments. To override the arguments, run with "GORELEASER_ARGS=...". When run as a github action from a tag, this target will publish a full release.
	CONTROLLER_IMAGE=$(IMAGE_TAG_BASE) BUNDLE_IMAGE=$(BUNDLE_IMG_BASE) CATALOG_IMAGE=$(CATALOG_IMG_BASE) TAG=$(TAG) $(GORELEASER) $(GORELEASER_ARGS)
