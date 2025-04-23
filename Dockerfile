# syntax=docker.io/docker/dockerfile:1.7-labs

# Build stage
FROM eclipse-temurin:21-jdk-noble AS build
FROM node

# Specify Railway-injected build-time variables
ARG RAILWAY_SERVICE_ID
ARG RAILWAY_ENVIRONMENT

RUN echo $RAILWAY_SERVICE_ID

# Copy source (excluding entrypoint)
COPY --exclude=entrypoint.sh . /home/reposilite-build
WORKDIR /home/reposilite-build

# Use a cache mount for Gradle dependencies (prefixed with Railway service key)
# Format: --mount=type=cache,id=s/<service-name>-<target-path>,target=<target-path>
RUN --mount=type=cache,id=s/4b65819e-0980-4a27-806f-53978fe90d6f-/root/.gradle,target=/root/.gradle <<EOF
  export GRADLE_OPTS="-Djdk.lang.Process.launchMechanism=vfork"
  ./gradlew :reposilite-backend:shadowJar --no-daemon --stacktrace
EOF

# Build-time metadata stage
ARG BUILD_DATE
ARG VCS_REF
ARG VERSION
LABEL org.label-schema.build-date=$BUILD_DATE \
      org.label-schema.name="Reposilite" \
      org.label-schema.description="Lightweight repository management software dedicated for the Maven artifacts" \
      org.label-schema.url="https://reposilite.com" \
      org.label-schema.vcs-ref=$VCS_REF \
      org.label-schema.vcs-url="https://github.com/dzikoysk/reposilite" \
      org.label-schema.vendor="dzikoysk" \
      org.label-schema.version=$VERSION \
      org.label-schema.schema-version="1.0"

# Run stage
FROM eclipse-temurin:21-jre-noble AS run

# Setup runtime directories
RUN mkdir -p /app/data /var/log/reposilite
WORKDIR /app

# Import application code
COPY --chmod=755 entrypoint.sh entrypoint.sh
COPY --from=build /home/reposilite-build/reposilite-backend/build/libs/reposilite-3*.jar reposilite.jar

# Healthcheck
HEALTHCHECK --interval=30s --timeout=30s --start-period=15s \
    --retries=3 CMD [ "sh", "-c", "URL=$(cat /app/data/.local/reposilite.address); echo -n \"curl $URL... \"; \
    ( \
        curl -sf $URL > /dev/null\
    ) && echo OK || ( \
        echo Fail && exit 2\
    )"]

ENTRYPOINT ["/app/entrypoint.sh"]
EXPOSE 8080
