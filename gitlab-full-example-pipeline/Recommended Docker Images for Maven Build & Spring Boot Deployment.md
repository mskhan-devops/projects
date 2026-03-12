# Recommended Docker Images for Maven Build & Spring Boot Deployment

## Overview

For your GitLab CI/CD pipeline building Spring Boot 17 microservices and deploying to EKS, here are the most reliable, minimal, and production-ready Docker images.

---

## 🏗️ Recommended Images

### 1. **For Maven Build (Build Stage)**

| Image Tag | Size | Use Case |
|-----------|------|----------|
| `maven:3.9-eclipse-temurin-17` | ~600MB | Full build with JDK 17 |
| `maven:3.9-eclipse-temurin-17-alpine` | ~150MB | Minimal build (may have compatibility issues) |

**Recommendation:** Use `maven:3.9-eclipse-temurin-17`

### 2. **For Runtime (Final Microservice Image)**

| Image Tag | Size | Best For |
|-----------|------|----------|
| `eclipse-temurin:17-jre-alpine` | ~110MB | Minimal production runtime |
| `eclipse-temurin:17-jre` | ~220MB | Full JRE, more compatible |
| `amazoncorretto:17-alpine` | ~110MB | AWS-native, minimal |

**Recommendation:** Use `eclipse-temurin:17-jre-alpine` or `amazoncorretto:17-alpine` (AWS ecosystem)

---

## 📋 GitLab CI Pipeline Example

```yaml
stages:
  - build
  - dockerize
  - deploy

variables:
  DOCKER_DRIVER: overlay2
  DOCKER_TLS_CERTDIR: "/certs"
  MAVEN_OPTS: "-Dmaven.repo.local=.m2/repository"

# Cache Maven dependencies between jobs
cache:
  key: ${CI_COMMIT_REF_SLUG}
  paths:
    - .m2/repository/
    - target/

# ============================================
# BUILD STAGE: Compile and Test
# ============================================
build:
  stage: build
  image: maven:3.9-eclipse-temurin-17
  script:
    - mvn clean package -DskipTests=false
    - ls -la target/*.jar
  artifacts:
    paths:
      - target/*.jar
    expire_in: 1 hour
  tags:
    - docker

# ============================================
# DOCKERIZE STAGE: Build Microservice Image
# ============================================
dockerize:
  stage: dockerize
  image: docker:24-dind
  services:
    - docker:24-dind
  script:
    - docker login -u $CI_REGISTRY_USER -p $CI_REGISTRY_PASSWORD $CI_REGISTRY
    - docker build 
        --build-arg JAR_FILE=target/*.jar 
        --build-arg JAVA_OPTS="-Xms256m -Xmx512m" 
        -t $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA 
        -t $CI_REGISTRY_IMAGE:latest 
        .
    - docker push $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA
    - docker push $CI_REGISTRY_IMAGE:latest
  dependencies:
    - build
  tags:
    - docker
```

---

## 🐳 Optimized Multi-Stage Dockerfile

### Option A: Using JLink (Most Optimized)

```dockerfile
# ============================================
# Stage 1: Build with JDK
# ============================================
FROM maven:3.9-eclipse-temurin-17 AS builder

WORKDIR /build

# Copy pom.xml first for dependency caching
COPY pom.xml .
RUN mvn dependency:go-offline -B

# Copy source code
COPY src ./src

# Build the application
RUN mvn clean package -DskipTests

# ============================================
# Stage 2: Create minimal JRE with jlink
# ============================================
FROM eclipse-temurin:17-jdk-alpine AS jre-builder

WORKDIR /jre

# Create minimal JRE using jlink
RUN $JAVA_HOME/bin/jlink \
    --module-path $JAVA_HOME/jmods \
    --add-modules java.base,java.logging,java.xml,jav.annotation,\
java.sql,javafx.base,java.desktop,java.instrument,java.management,\
java.management.rmi,java.naming,java.net.http,java.scripting,\
java.security.jgss,java.smartcardio,java.transaction.xa,java.prefs,\
java.datatransfer,java.xml.crypto,java.se \
    --output /jre \
    --strip-debug \
    --no-man-pages \
    --no-header-files

# ============================================
# Stage 3: Final Runtime Image
# ============================================
FROM alpine:3.18

# Install CA certificates and create non-root user
RUN apk add --no-cache \
        ca-certificates \
        curl \
        bash \
    && addgroup -g 1000 appgroup \
    && adduser -u 1000 -G appgroup -s /bin/sh -D appuser

WORKDIR /app

# Copy JAR file
COPY --from=builder /build/target/*.jar app.jar

# Copy custom JRE (optional - use for maximum optimization)
# COPY --from=jre-builder /jre /opt/java/openjdk

# Set environment variables
ENV JAVA_HOME=/opt/java/openjdk \
    JAVA_OPTS="-Xms256m -Xmx512m -XX:+UseG1GC -XX:+HeapDumpOnOutOfMemoryError" \
    USER=appuser \
    GROUP=appgroup

# Create volume for logs
VOLUME /app/logs

# Switch to non-root user
USER appuser

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8080/actuator/health || exit 1

# Expose application port
EXPOSE 8080

# Entrypoint
ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar app.jar"]
```

### Option B: Simpler Approach (Recommended)

```dockerfile
# ============================================
# Stage 1: Build
# ============================================
FROM maven:3.9-eclipse-temurin-17 AS builder

WORKDIR /build

# Cache dependencies
COPY pom.xml .
RUN mvn dependency:go-offline -B

# Build
COPY src ./src
RUN mvn clean package -DskipTests -Pprod

# ============================================
# Stage 2: Runtime (Minimal)
# ============================================
FROM eclipse-temurin:17-jre-alpine

WORKDIR /app

# Add non-root user
RUN addgroup -g 1000 -S spring && \
    adduser -u 1000 -S spring -G spring

# Copy artifact
COPY --from=builder /build/target/*.jar app.jar

# Set permissions
RUN chown -R spring:spring /app

# Environment
ENV JAVA_OPTS="-Xms256m -Xmx512m -XX:+UseG1GC" \
    JAVA_APP_JAR="app.jar"

USER spring:spring

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=60s \
    CMD wget --quiet --tries=1 --spider http://localhost:8080/actuator/health || exit 1

ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar $JAVA_APP_JAR"]
```

---

## 🎯 EKS Deployment with Helm (GitLab Job)

```yaml
deploy-eks:
  stage: deploy
  image: bitnami/kubectl:latest
  script:
    - aws eks update-kubeconfig --name $EKS_CLUSTER_NAME --region $AWS_REGION
    - kubectl set image deployment/$SERVICE_NAME \
        $CONTAINER_NAME=$CI_REGISTRY_IMAGE:$CI_COMMIT_SHA \
        -n $NAMESPACE
    - kubectl rollout status deployment/$SERVICE_NAME -n $NAMESPACE
  environment:
    name: production
  only:
    - main
  tags:
    - kubernetes
```

---

## 📊 Image Size Comparison

| Approach | Image Size |
|----------|-------------|
| `openjdk:17-slim` | ~450MB |
| `eclipse-temurin:17-jre` | ~220MB |
| `eclipse-temurin:17-jre-alpine` | ~110MB |
| Custom jlink | ~80-100MB |

---

## ✅ Best Practices Summary

1. **Use Eclipse Temurin** (formerly AdoptOpenJDK) - most reliable and widely tested
2. **Use Alpine base** for minimal image size
3. **Use JRE not JDK** - saves ~100MB
4. **Multi-stage builds** - separate build from runtime
5. **Cache Maven dependencies** in GitLab CI
6. **Use non-root user** in production
7. **Add health checks** for Kubernetes liveness/readiness
8. **Set JVM memory limits** to prevent OOMKill in K8s

---

Would you like me to provide additional configurations like:
- Helm charts for EKS deployment
- GitLab CI variables setup
- Security scanning in CI pipeline

