# Image URL to use all building/pushing image targets
IMG ?= yametech/nuwa-controller:v1.0.1
# Produce CRDs that work back to Kubernetes 1.11 (no version conversion)
CRD_OPTIONS ?= "crd:trivialVersions=true"


# Define os env
ifeq ($(GOOS),windows)
BINARY_EXT_LOCAL:=.exe
GOLANGCI_LINT:=golangci-lint.exe
export ARCHIVE_EXT = .zip
else
BINARY_EXT_LOCAL:=
GOLANGCI_LINT:=golangci-lint
export ARCHIVE_EXT = .tar.gz
endif

# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

all: manager

# Lint

.PHONY: lint
lint:
	# Due to https://github.com/golangci/golangci-lint/issues/580, we need to add --fix for window
	GL_DEBUG=linters_output GOPACKAGESPRINTGOLISTERRORS=1 $(GOLANGCI_LINT) run --fix  --deadline 5m

# SSL webhook local development
gen-ssl:
	pushd ssl > /dev/null && ./gen-ssl.sh && popd > /dev/null
	sh replace_ssl.sh

# Development webhook
install-devel-webhook: install
	kubectl apply -f development/webhook

uninstall-devel-webhook:
	kubectl delete -f development/webhook

debug: fmt vet manifests
	dlv debug --headless --listen=:2345 --api-version=2 --accept-multiclient

# Run tests
test: fmt vet manifests
	go test ./... -coverprofile cover.out

# Build manager binary
manager: generate fmt vet
	go build -o bin/manager main.go

# Run against the configured Kubernetes cluster in ~/.kube/config
run:
	go run ./main.go -ssl ${PWD}/ssl

# Install CRDs into a cluster
install: manifests install-devel-webhook
	kustomize build config/crd | kubectl apply -f -

# Uninstall CRDs from a cluster
uninstall: uninstall-devel-webhook
	kustomize build config/crd | kubectl delete -f -

# Deploy controller in the configured Kubernetes cluster in ~/.kube/config
deploy: manifests release
	cd config/manager && kustomize edit set image controller=${IMG}
	kustomize build config/default | kubectl apply -f -

undeploy:
	kustomize build config/default | kubectl delete -f -

release: manifests gen-ssl
	cd config/manager && kustomize edit set image controller=${IMG}
	kustomize build config/default | cat > release.yaml

# Generate manifests e.g. CRD, RBAC etc.
manifests: controller-gen
	$(CONTROLLER_GEN) $(CRD_OPTIONS) rbac:roleName=manager-role webhook paths="./..." output:crd:artifacts:config=config/crd/bases

# Run go fmt against code
fmt:
	go fmt ./...

# Run go vet against code
vet:
	go vet ./...

dep:
	go mod vendor

build: dep
	go build ./...

# Generate code
generate: controller-gen
	$(CONTROLLER_GEN) object:headerFile=./hack/boilerplate.go.txt paths="./..."

# Docker build and push
docker: docker-build docker-push

# Build the docker image , 20191122 remove test
docker-build:
	docker build . -t ${IMG}

# Push the docker image
docker-push:
	docker push ${IMG}

# find or download controller-gen
# download controller-gen if necessary
controller-gen:
ifeq (, $(shell which controller-gen))
	@{ \
	set -e ;\
	CONTROLLER_GEN_TMP_DIR=$$(mktemp -d) ;\
	cd $$CONTROLLER_GEN_TMP_DIR ;\
	go mod init tmp ;\
	go get sigs.k8s.io/controller-tools/cmd/controller-gen@v0.2.2 ;\
	rm -rf $$CONTROLLER_GEN_TMP_DIR ;\
	}
CONTROLLER_GEN=$(GOBIN)/controller-gen
else
CONTROLLER_GEN=$(shell which controller-gen)
endif

# find or download kustomize
# download kustomize if necessary
kustomize:
ifeq (, $(shell which kustomize))
	@{ \
	set -e ;\
	KUSTOMIZE_TMP_DIR=$$(mktemp -d) ;\
	cd $$KUSTOMIZE_TMP_DIR ;\
	go mod init tmp ;\
	go get github.com/kubernetes-sigs/kustomize ;\
	rm -rf $$KUSTOMIZE_TMP_DIR ;\
	}
kustomize=$(GOBIN)/kustomize
else
kustomize=$(shell which kustomize)
endif