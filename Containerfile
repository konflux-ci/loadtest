# Builder for Go
# (this is to avoid installing all Golang dependencies to our runner image)
FROM registry.access.redhat.com/ubi10/go-toolset:latest AS builder_go
# Download dependencies based on just these two files to be able to cache the layer
COPY go.mod go.sum ./
RUN go mod download -x
# Copy rest of the source code and build it
COPY . .
RUN make build
# Test executable is OK
RUN ./bin/loadtest --help



# Builder for oc and yq
# (this is to avoid installing tar to our runner image)
FROM registry.access.redhat.com/ubi10/ubi:latest AS builder_oc
ARG TARGETARCH
# Pinned versions to avoid pulling unreviewed code from "stable"/"latest" channels
ARG OC_VERSION=4.22.8
ARG YQ_VERSION=v4.53.3
# Download and install oc, try multiple times as this is error prone
RUN attempt=1; \
    if [ "$TARGETARCH" = "arm64" ]; then \
        ARCH_SUFFIX="-arm64"; \
    else \
        ARCH_SUFFIX=""; \
    fi; \
    while true; do \
        echo "Attempt $attempt"; \
        curl -fSL https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OC_VERSION}/openshift-client-linux${ARCH_SUFFIX}.tar.gz -o /tmp/openshift-client-linux.tar.gz && \
            tar zxvf /tmp/openshift-client-linux.tar.gz -C /usr/bin/ && \
            oc version --client && \
            break; \
        if [[ $attempt -ge 5 ]]; then \
            echo "All attempts failed, giving up" >&2; \
            exit 1; \
        fi; \
        sleep 1; \
        let attempt+=1; \
    done
# Download yq (https://github.com/mikefarah/yq)
RUN attempt=1; \
    YQ_ARCH="${TARGETARCH:-amd64}"; \
    while true; do \
        echo "Attempt $attempt"; \
        curl -fSL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${YQ_ARCH}" -o /usr/bin/yq && \
            chmod +x /usr/bin/yq && \
            yq --version && \
            break; \
        if [[ $attempt -ge 5 ]]; then \
            echo "All attempts failed, giving up" >&2; \
            exit 1; \
        fi; \
        sleep 1; \
        let attempt+=1; \
    done



# Runner
FROM registry.access.redhat.com/ubi10/python-312-minimal:latest
# Include license information required by Red Hat certification
COPY LICENSE /licenses/LICENSE
# Copy loadtest binary from builder container
COPY --from=builder_go /opt/app-root/src/bin/loadtest /usr/bin/
# Copy OpenShift CLI and yq binaries from builder container
COPY --from=builder_oc /usr/bin/oc /usr/bin/
COPY --from=builder_oc /usr/bin/kubectl /usr/bin/
COPY --from=builder_oc /usr/bin/yq /usr/bin/
# Install internal CA certificate
COPY ci-scripts/config/2022-IT-Root-CA.pem \
     /etc/pki/ca-trust/source/anchors/2022-IT-Root-CA.pem
COPY requirements.txt requirements.txt
USER 0
RUN update-ca-trust
# Install dependencies for our python scripts
RUN INSTALL_PKGS="git-core jq tar xz" && \
    microdnf -y --setopt=tsflags=nodocs --setopt=install_weak_deps=0 install $INSTALL_PKGS && \
    microdnf -y clean all --enablerepo='*'
USER 1001
RUN python3 -m pip install -U pip && \
    python3 -m pip install -r requirements.txt
# Install our scripts
COPY ci-scripts/ \
     ./ci-scripts/
CMD ["sleep", "5d"]
