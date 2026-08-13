ARG BUILD_FROM
# hadolint ignore=DL3006
FROM ${BUILD_FROM}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV LANG=C.UTF-8

# bash, curl and jq are part of the Home Assistant base image, but they are
# installed explicitly so the add-on keeps working if that ever changes.
# hadolint ignore=DL3018
RUN apk add --no-cache \
        bash \
        bind-tools \
        ca-certificates \
        curl \
        jq \
        tzdata

COPY run.sh /usr/bin/anydns
RUN chmod a+x /usr/bin/anydns

# Build metadata, filled in by the Supervisor / the add-on builder.
ARG BUILD_ARCH
ARG BUILD_DATE
ARG BUILD_DESCRIPTION
ARG BUILD_NAME
ARG BUILD_REF
ARG BUILD_REPOSITORY
ARG BUILD_VERSION

LABEL \
    io.hass.name="${BUILD_NAME}" \
    io.hass.description="${BUILD_DESCRIPTION}" \
    io.hass.arch="${BUILD_ARCH}" \
    io.hass.type="addon" \
    io.hass.version="${BUILD_VERSION}" \
    maintainer="Uros <uros.sadek.rvs@gmail.com>" \
    org.opencontainers.image.title="${BUILD_NAME}" \
    org.opencontainers.image.description="${BUILD_DESCRIPTION}" \
    org.opencontainers.image.source="https://github.com/${BUILD_REPOSITORY}" \
    org.opencontainers.image.documentation="https://github.com/${BUILD_REPOSITORY}/blob/main/anydns/DOCS.md" \
    org.opencontainers.image.licenses="MIT" \
    org.opencontainers.image.created="${BUILD_DATE}" \
    org.opencontainers.image.revision="${BUILD_REF}" \
    org.opencontainers.image.version="${BUILD_VERSION}"

CMD [ "/usr/bin/anydns" ]
