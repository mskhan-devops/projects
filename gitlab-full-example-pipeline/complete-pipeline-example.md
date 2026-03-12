# 💬 Chat Export: write a gitlab pipeline file c...

*Exported on: 3/12/2026, 4:58:18 AM*

---

---
**🧑 User**  
*3/12/2026, 4:58:18 AM*

> write a gitlab pipeline file containing, maven build, docker build, and deploy to EKS stages/jobs. We are using java microservices to be deployed. The pipeline should be production ready, robust with self healing during failure. we are using gitlab private instance on prem. Apply all best practices and robust script for the pipelline

---
**🤖 Assistant**  
*3/12/2026, 4:58:18 AM*

> Hmm, sorry I could not find any relevant information from the provided context sources. However, I can provide you with a comprehensive, production-ready GitLab CI/CD pipeline configuration based on industry best practices for deploying Java microservices to EKS.
> 
> Below is a detailed `.gitlab-ci.yml` file with robust features, self-healing mechanisms, and best practices for an on-prem GitLab instance.
> 
> ---
> 
> ## Complete Production-Ready GitLab CI/CD Pipeline
> 
> ```yaml
> # ==============================================================================
> # GitLab CI/CD Pipeline for Java Microservices Deployment to AWS EKS
> # Production-Ready Configuration with Self-Healing and Best Practices
> # ==============================================================================
> 
> # ------------------------------------------------------------------------------
> # Global Variables and Configuration
> # ------------------------------------------------------------------------------
> variables:
>   # Maven Configuration
>   MAVEN_CLI_OPTS: "-s .m2/settings.xml --batch-mode"
>   MAVEN_OPTS: "-Dmaven.repo.local=.m2/repository -Xmx1024m"
>   
>   # Docker Configuration
>   DOCKER_REGISTRY: "your-registry.example.com"
>   DOCKER_IMAGE: "$DOCKER_REGISTRY/$CI_PROJECT_NAMESPACE/$CI_PROJECT_NAME"
>   DOCKER_TAG: "$CI_COMMIT_SHA"
>   
>   # AWS/EKS Configuration
>   AWS_REGION: "us-east-1"
>   EKS_CLUSTER_NAME: "production-cluster"
>   KUBERNETES_NAMESPACE: "microservices"
>   
>   # Deployment Configuration
>   DEPLOYMENT_TIMEOUT: "300s"
>   ROLLBACK_ENABLED: "true"
>   HEALTH_CHECK_RETRIES: "30"
>   HEALTH_CHECK_INTERVAL: "10"
> 
> # ------------------------------------------------------------------------------
> # Workflow Rules - Control when pipelines are created
> # ------------------------------------------------------------------------------
> workflow:
>   rules:
>     - if: $CI_PIPELINE_SOURCE == "merge_request_event"
>       when: never
>     - if: $CI_COMMIT_BRANCH == "main"
>     - if: $CI_COMMIT_BRANCH == "develop"
>     - if: $CI_COMMIT_BRANCH =~ /^release\/.*$/
>     - if: $CI_COMMIT_TAG
> 
> # ------------------------------------------------------------------------------
> # Pipeline Stages Definition
> # ------------------------------------------------------------------------------
> stages:
>   - validate
>   - test
>   - build
>   - security-scan
>   - docker-build
>   - deploy-staging
>   - integration-test
>   - deploy-production
>   - post-deployment
>   - cleanup
> 
> # ------------------------------------------------------------------------------
> # Cache Configuration - Speed up pipelines
> # ------------------------------------------------------------------------------
> cache:
>   key: "$CI_JOB_NAME-$CI_COMMIT_REF_SLUG"
>   paths:
>     - .m2/repository/
>     - target/
> 
> # ------------------------------------------------------------------------------
> # Default Configuration for All Jobs
> # ------------------------------------------------------------------------------
> default:
>   retry:
>     max: 2
>     when:
>       - runner_system_failure
>       - stuck_or_timeout_failure
>       - api_failure
>       - scheduler_failure
>   interruptible: true
>   tags:
>     - on-prem-runner
> 
> # ==============================================================================
> # STAGE: Validate
> # ==============================================================================
> 
> validate-pom:
>   stage: validate
>   image: maven:3.9-eclipse-temurin-21
>   script:
>     - mvn $MAVEN_CLI_OPTS validate
>     - mvn $MAVEN_CLI_OPTS dependency:tree
>   rules:
>     - if: $CI_COMMIT_BRANCH
>   allow_failure: false
> 
> validate-code-style:
>   stage: validate
>   image: maven:3.9-eclipse-temurin-21
>   script:
>     - mvn $MAVEN_CLI_OPTS checkstyle:check
>   rules:
>     - if: $CI_COMMIT_BRANCH
>   allow_failure: true
>   artifacts:
>     reports:
>       junit: target/checkstyle-result.xml
> 
> # ==============================================================================
> # STAGE: Test
> # ==============================================================================
> 
> unit-tests:
>   stage: test
>   image: maven:3.9-eclipse-temurin-21
>   script:
>     - mvn $MAVEN_CLI_OPTS test
>     - mvn $MAVEN_CLI_OPTS jacoco:report
>   coverage: '/Total.*?([0-9]{1,3})%/'
>   artifacts:
>     when: always
>     paths:
>       - target/site/jacoco/
>       - target/surefire-reports/
>     reports:
>       junit: target/surefire-reports/TEST-*.xml
>       coverage_report:
>         coverage_format: jacoco
>         path: target/site/jacoco/jacoco.xml
>   rules:
>     - if: $CI_COMMIT_BRANCH
> 
> integration-tests:
>   stage: test
>   image: maven:3.9-eclipse-temurin-21
>   services:
>     - name: postgres:15-alpine
>       alias: postgres-test
>     - name: redis:7-alpine
>       alias: redis-test
>   variables:
>     POSTGRES_DB: testdb
>     POSTGRES_USER: test
>     POSTGRES_PASSWORD: test
>     SPRING_DATASOURCE_URL: jdbc:postgresql://postgres-test:5432/testdb
>     SPRING_REDIS_HOST: redis-test
>   script:
>     - mvn $MAVEN_CLI_OPTS verify -DskipUnitTests
>   artifacts:
>     when: always
>     paths:
>       - target/failsafe-reports/
>     reports:
>       junit: target/failsafe-reports/TEST-*.xml
>   rules:
>     - if: $CI_COMMIT_BRANCH == "main"
>     - if: $CI_COMMIT_BRANCH == "develop"
> 
> # ==============================================================================
> # STAGE: Build
> # ==============================================================================
> 
> maven-build:
>   stage: build
>   image: maven:3.9-eclipse-temurin-21
>   script:
>     - |
>       echo "Building Java application..."
>       mvn $MAVEN_CLI_OPTS clean package -DskipTests
>       
>       # Verify JAR file exists
>       if [ ! -f target/*.jar ]; then
>         echo "ERROR: JAR file not generated"
>         exit 1
>       fi
>       
>       # Extract version from POM
>       APP_VERSION=$(mvn help:evaluate -Dexpression=project.version -q -DforceStdOutput)
>       echo "APP_VERSION=$APP_VERSION" >> build.env
>       echo "BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ')" >> build.env
>       echo "GIT_COMMIT_SHORT=${CI_COMMIT_SHA:0:8}" >> build.env
>   artifacts:
>     when: always
>     paths:
>       - target/*.jar
>       - target/classes/
>     reports:
>       dotenv: build.env
>     expire_in: 1 week
>   rules:
>     - if: $CI_COMMIT_BRANCH
> 
> # ==============================================================================
> # STAGE: Security Scan
> # ==============================================================================
> 
> dependency-check:
>   stage: security-scan
>   image: maven:3.9-eclipse-temurin-21
>   script:
>     - mvn $MAVEN_CLI_OPTS dependency-check:check
>   allow_failure: true
>   artifacts:
>     when: always
>     paths:
>       - target/dependency-check-report.html
>     reports:
>       dependency_scanning: target/dependency-check-report.json
>   rules:
>     - if: $CI_COMMIT_BRANCH == "main"
>     - if: $CI_COMMIT_BRANCH == "develop"
> 
> sast-scan:
>   stage: security-scan
>   image: registry.gitlab.com/gitlab-org/gitlab-runner-images/sast:latest
>   allow_failure: true
>   artifacts:
>     reports:
>       sast: gl-sast-report.json
>   rules:
>     - if: $CI_COMMIT_BRANCH == "main"
>     - if: $CI_COMMIT_BRANCH == "develop"
> 
> container-scan:
>   stage: security-scan
>   image: docker:24-cli
>   services:
>     - name: docker:24-dind
>       alias: docker
>   variables:
>     DOCKER_DRIVER: overlay2
>     DOCKER_TLS_CERTDIR: "/certs"
>   script:
>     - |
>       docker pull $DOCKER_IMAGE:$DOCKER_TAG || true
>       docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
>         aquasec/trivy image --exit-code 1 --severity HIGH,CRITICAL \
>         --format json --output trivy-report.json \
>         $DOCKER_IMAGE:$DOCKER_TAG || echo "Vulnerabilities found"
>   artifacts:
>     paths:
>       - trivy-report.json
>   allow_failure: true
>   rules:
>     - if: $CI_COMMIT_BRANCH == "main"
> 
> secret-detection:
>   stage: security-scan
>   image: registry.gitlab.com/gitlab-org/gitlab-runner-images/secret-detection:latest
>   allow_failure: true
>   artifacts:
>     reports:
>       secret_detection: gl-secret-detection-report.json
>   rules:
>     - if: $CI_COMMIT_BRANCH
> 
> # ==============================================================================
> # STAGE: Docker Build
> # ==============================================================================
> 
> docker-build:
>   stage: docker-build
>   image: docker:24-cli
>   services:
>     - name: docker:24-dind
>       alias: docker
>   variables:
>     DOCKER_DRIVER: overlay2
>     DOCKER_TLS_CERTDIR: "/certs"
>     DOCKER_HOST: tcp://docker:2376
>   before_script:
>     - |
>       echo "Logging into Docker registry..."
>       echo "$DOCKER_REGISTRY_PASSWORD" | docker login -u "$DOCKER_REGISTRY_USER" --password-stdin $DOCKER_REGISTRY
>   script:
>     - |
>       # Build arguments for metadata
>       BUILD_ARGS="--build-arg APP_VERSION=${APP_VERSION:-snapshot}"
>       BUILD_ARGS="$BUILD_ARGS --build-arg BUILD_DATE=${BUILD_DATE:-$(date -u +'%Y-%m-%dT%H:%M:%SZ')}"
>       BUILD_ARGS="$BUILD_ARGS --build-arg GIT_COMMIT=${CI_COMMIT_SHA}"
>       BUILD_ARGS="$BUILD_ARGS --build-arg GIT_REF=${CI_COMMIT_REF_NAME}"
>       
>       # Build Docker image with multiple tags
>       docker build \
>         $BUILD_ARGS \
>         --label "org.opencontainers.image.title=$CI_PROJECT_TITLE" \
>         --label "org.opencontainers.image.description=$CI_PROJECT_DESCRIPTION" \
>         --label "org.opencontainers.image.version=$APP_VERSION" \
>         --label "org.opencontainers.image.created=$BUILD_DATE" \
>         --label "org.opencontainers.image.revision=$CI_COMMIT_SHA" \
>         --label "org.opencontainers.image.source=$CI_PROJECT_URL" \
>         --label "com.gitlab.pipeline.pipeline_id=$CI_PIPELINE_ID" \
>         --label "com.gitlab.pipeline.job_id=$CI_JOB_ID" \
>         -t $DOCKER_IMAGE:$DOCKER_TAG \
>         -t $DOCKER_IMAGE:$CI_COMMIT_REF_SLUG \
>         -t $DOCKER_IMAGE:latest \
>         .
>       
>       # Push all tags
>       docker push $DOCKER_IMAGE:$DOCKER_TAG
>       docker push $DOCKER_IMAGE:$CI_COMMIT_REF_SLUG
>       
>       # Only push 'latest' tag for main branch
>       if [ "$CI_COMMIT_BRANCH" == "main" ]; then
>         docker push $DOCKER_IMAGE:latest
>       fi
>   after_script:
>     - docker logout $DOCKER_REGISTRY
>   artifacts:
>     reports:
>       dotenv: build.env
>   rules:
>     - if: $CI_COMMIT_BRANCH
> 
> # ==============================================================================
> # STAGE: Deploy Staging
> # ==============================================================================
> 
> .deploy-template: &deploy-template
>   image: 
>     name: bitnami/kubectl:latest
>     entrypoint: [""]
>   before_script:
>     - |
>       echo "Configuring kubectl for EKS cluster..."
>       
>       # Configure AWS credentials
>       export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID_STAGING}"
>       export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY_STAGING}"
>       
>       # Update kubeconfig for EKS
>       aws eks update-kubeconfig --region $AWS_REGION --name $EKS_CLUSTER_NAME
>       
>       # Set Kubernetes namespace
>       kubectl config set-context --current --namespace=$KUBERNETES_NAMESPACE
> 
> deploy-staging:
>   stage: deploy-staging
>   extends: .deploy-template
>   environment:
>     name: staging
>     url: https://staging.example.com/$CI_PROJECT_NAME
>     on_stop: stop-staging
>   variables:
>     ENVIRONMENT: staging
>     REPLICAS: "2"
>   script:
>     - |
>       echo "Deploying to staging environment..."
>       
>       # Create namespace if not exists
>       kubectl create namespace $KUBERNETES_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
>       
>       # Create/update ConfigMaps and Secrets
>       kubectl create configmap ${CI_PROJECT_NAME}-config \
>         --from-literal=APP_VERSION=$APP_VERSION \
>         --from-literal=SPRING_PROFILES_ACTIVE=staging \
>         --dry-run=client -o yaml | kubectl apply -f -
>       
>       # Apply Kubernetes manifests with Helm or kubectl
>       envsubst < k8s/deployment.yaml | kubectl apply -f -
>       envsubst < k8s/service.yaml | kubectl apply -f -
>       envsubst < k8s/ingress.yaml | kubectl apply -f -
>       envsubst < k8s/hpa.yaml | kubectl apply -f -
>       
>       # Wait for deployment rollout with timeout
>       kubectl rollout status deployment/${CI_PROJECT_NAME} \
>         --namespace=$KUBERNETES_NAMESPACE \
>         --timeout=$DEPLOYMENT_TIMEOUT
>       
>       # Health check
>       ./scripts/health-check.sh staging
>   rules:
>     - if: $CI_COMMIT_BRANCH == "develop"
>     - if: $CI_COMMIT_BRANCH == "main"
> 
> stop-staging:
>   stage: deploy-staging
>   extends: .deploy-template
>   environment:
>     name: staging
>     action: stop
>   variables:
>     GIT_STRATEGY: none
>   script:
>     - |
>       echo "Stopping staging environment..."
>       kubectl delete deployment ${CI_PROJECT_NAME} --namespace=$KUBERNETES_NAMESPACE --ignore-not-found=true
>       kubectl delete service ${CI_PROJECT_NAME} --namespace=$KUBERNETES_NAMESPACE --ignore-not-found=true
>       kubectl delete ingress ${CI_PROJECT_NAME}-ingress --namespace=$KUBERNETES_NAMESPACE --ignore-not-found=true
>   when: manual
>   rules:
>     - if: $CI_COMMIT_BRANCH == "develop"
> 
> # ==============================================================================
> # STAGE: Integration Test (Post-Staging)
> # ==============================================================================
> 
> api-integration-tests:
>   stage: integration-test
>   image: maven:3.9-eclipse-temurin-21
>   variables:
>     API_BASE_URL: "https://staging.example.com/$CI_PROJECT_NAME"
>   script:
>     - |
>       echo "Running API integration tests against staging..."
>       mvn $MAVEN_CLI_OPTS verify -Pintegration-test \
>         -Dapi.base.url=$API_BASE_URL
>   artifacts:
>     when: always
>     paths:
>       - target/failsafe-reports/
>       - target/cucumber-reports/
>     reports:
>       junit: target/failsafe-reports/TEST-*.xml
>   rules:
>     - if: $CI_COMMIT_BRANCH == "main"
>     - if: $CI_COMMIT_BRANCH == "develop"
> 
> performance-tests:
>   stage: integration-test
>   image: grafana/k6:latest
>   script:
>     - |
>       echo "Running performance tests..."
>       k6 run --out json=performance-results.json \
>         --stage 30s:10,60s:50,30s:10 \
>         tests/performance/load-test.js || true
>   artifacts:
>     when: always
>     paths:
>       - performance-results.json
>   allow_failure: true
>   rules:
>     - if: $CI_COMMIT_BRANCH == "main"
> 
> # ==============================================================================
> # STAGE: Deploy Production
> # ==============================================================================
> 
> deploy-production:
>   stage: deploy-production
>   extends: .deploy-template
>   environment:
>     name: production
>     url: https://api.example.com/$CI_PROJECT_NAME
>   variables:
>     ENVIRONMENT: production
>     REPLICAS: "3"
>   script:
>     - |
>       echo "Deploying to production environment..."
>       
>       # Pre-deployment backup
>       kubectl get deployment ${CI_PROJECT_NAME} -n $KUBERNETES_NAMESPACE -o yaml > deployment-backup.yaml || true
>       
>       # Apply production manifests
>       envsubst < k8s/deployment-prod.yaml | kubectl apply -f -
>       envsubst < k8s/service.yaml | kubectl apply -f -
>       envsubst < k8s/ingress-prod.yaml | kubectl apply -f -
>       envsubst < k8s/hpa-prod.yaml | kubectl apply -f -
>       
>       # Progressive rollout with canary (if configured)
>       if [ "$CANARY_ENABLED" == "true" ]; then
>         ./scripts/canary-deployment.sh 10
>         ./scripts/health-check.sh production-canary
>         ./scripts/canary-deployment.sh 50
>         ./scripts/health-check.sh production-canary
>       fi
>       
>       # Complete rollout
>       kubectl rollout status deployment/${CI_PROJECT_NAME} \
>         --namespace=$KUBERNETES_NAMESPACE \
>         --timeout=$DEPLOYMENT_TIMEOUT
>       
>       # Post-deployment health check
>       ./scripts/health-check.sh production
>       
>       # Verify deployment
>       if ! ./scripts/verify-deployment.sh production; then
>         echo "Deployment verification failed, initiating rollback..."
>         kubectl rollout undo deployment/${CI_PROJECT_NAME} -n $KUBERNETES_NAMESPACE
>         exit 1
>       fi
>   rules:
>     - if: $CI_COMMIT_BRANCH == "main"
>       when: manual
>     - if: $CI_COMMIT_TAG
>       when: manual
> 
> # ==============================================================================
> # STAGE: Post-Deployment
> # ==============================================================================
> 
> notify-slack-success:
>   stage: post-deployment
>   image: curlimages/curl:latest
>   variables:
>     GIT_STRATEGY: none
>   script:
>     - |
>       curl -X POST -H 'Content-type: application/json' \
>         --data "{
>           \"text\": \"✅ Deployment Successful\",
>           \"attachments\": [{
>             \"color\": \"good\",
>             \"fields\": [
>               {\"title\": \"Project\", \"value\": \"$CI_PROJECT_NAME\", \"short\": true},
>               {\"title\": \"Environment\", \"value\": \"$ENVIRONMENT\", \"short\": true},
>               {\"title\": \"Version\", \"value\": \"$APP_VERSION\", \"short\": true},
>               {\"title\": \"Pipeline\", \"value\": \"$CI_PIPELINE_URL\", \"short\": false}
>             ]
>           }]
>         }" $SLACK_WEBHOOK_URL
>   when: on_success
>   rules:
>     - if: $CI_COMMIT_BRANCH == "main"
> 
> notify-slack-failure:
>   stage: post-deployment
>   image: curlimages/curl:latest
>   variables:
>     GIT_STRATEGY: none
>   script:
>     - |
>       curl -X POST -H 'Content-type: application/json' \
>         --data "{
>           \"text\": \"❌ Deployment Failed\",
>           \"attachments\": [{
>             \"color\": \"danger\",
>             \"fields\": [
>               {\"title\": \"Project\", \"value\": \"$CI_PROJECT_NAME\", \"short\": true},
>               {\"title\": \"Stage\", \"value\": \"$CI_JOB_STAGE\", \"short\": true},
>               {\"title\": \"Failed Job\", \"value\": \"$CI_JOB_NAME\", \"short\": true},
>               {\"title\": \"Pipeline\", \"value\": \"$CI_PIPELINE_URL\", \"short\": false}
>             ]
>           }]
>         }" $SLACK_WEBHOOK_URL
>   when: on_failure
>   rules:
>     - if: $CI_COMMIT_BRANCH == "main"
> 
> # ==============================================================================
> # STAGE: Cleanup
> # ==============================================================================
> 
> cleanup-old-images:
>   stage: cleanup
>   image: docker:24-cli
>   script:
>     - |
>       echo "Cleaning up old Docker images..."
>       
>       # Keep last 10 images, delete older ones
>       IMAGES=$(docker images $DOCKER_IMAGE --format "{{.Tag}}" | sort -r | tail -n +11)
>       
>       for IMAGE in $IMAGES; do
>         docker rmi $DOCKER_IMAGE:$IMAGE || true
>       done
>   rules:
>     - if: $CI_COMMIT_BRANCH == "main"
>       when: manual
>     - if: $CI_COMMIT_TAG
>       when: manual
> 
> # ==============================================================================
> # Self-Healing Rollback Job
> # ==============================================================================
> 
> auto-rollback:
>   stage: post-deployment
>   extends: .deploy-template
>   variables:
>     GIT_STRATEGY: none
>   script:
>     - |
>       echo "Monitoring deployment health..."
>       
>       RETRY_COUNT=0
>       MAX_RETRIES=$HEALTH_CHECK_RETRIES
>       
>       while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
>         if kubectl get pods -n $KUBERNETES_NAMESPACE -l app=${CI_PROJECT_NAME} | grep "Running" | grep -v "0/1"; then
>           echo "Pods are healthy"
>           exit 0
>         fi
>         
>         RETRY_COUNT=$((RETRY_COUNT + 1))
>         echo "Health check attempt $RETRY_COUNT/$MAX_RETRIES failed, retrying..."
>         sleep $HEALTH_CHECK_INTERVAL
>       done
>       
>       echo "Health checks failed, initiating automatic rollback..."
>       kubectl rollout undo deployment/${CI_PROJECT_NAME} -n $KUBERNETES_NAMESPACE
>       
>       # Notify team
>       curl -X POST -H 'Content-type: application/json' \
>         --data "{\"text\": \"🚨 Automatic rollback triggered for $CI_PROJECT_NAME in $ENVIRONMENT\"}" \
>         $SLACK_WEBHOOK_URL
>       
>       exit 1
>   rules:
>     - if: $CI_COMMIT_BRANCH == "main"
>       when: on_failure
>       allow_failure: true
> ```
> 
> ---
> 
> ## Supporting Scripts
> 
> ### Health Check Script (`scripts/health-check.sh`)
> 
> ```bash
> #!/bin/bash
> set -euo pipefail
> 
> ENVIRONMENT=$1
> MAX_RETRIES=30
> RETRY_INTERVAL=10
> 
> echo "Starting health check for $ENVIRONMENT environment..."
> 
> # Determine the health endpoint based on environment
> if [ "$ENVIRONMENT" == "production" ]; then
>     HEALTH_URL="https://api.example.com/${CI_PROJECT_NAME}/actuator/health"
> else
>     HEALTH_URL="https://staging.example.com/${CI_PROJECT_NAME}/actuator/health"
> fi
> 
> RETRY_COUNT=0
> 
> while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
>     HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$HEALTH_URL" || echo "000")
>     
>     if [ "$HTTP_STATUS" == "200" ]; then
>         echo "✅ Health check passed! Application is healthy."
>         exit 0
>     fi
>     
>     RETRY_COUNT=$((RETRY_COUNT + 1))
>     echo "Health check attempt $RETRY_COUNT/$MAX_RETRIES - Status: $HTTP_STATUS"
>     sleep $RETRY_INTERVAL
> done
> 
> echo "❌ Health check failed after $MAX_RETRIES attempts"
> exit 1
> ```
> 
> ### Deployment Verification Script (`scripts/verify-deployment.sh`)
> 
> ```bash
> #!/bin/bash
> set -euo pipefail
> 
> ENVIRONMENT=$1
> NAMESPACE="${KUBERNETES_NAMESPACE:-microservices}"
> 
> echo "Verifying deployment for $CI_PROJECT_NAME in $ENVIRONMENT..."
> 
> # Check deployment status
> DEPLOYMENT_STATUS=$(kubectl get deployment ${CI_PROJECT_NAME} -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="Available")].status}')
> 
> if [ "$DEPLOYMENT_STATUS" != "True" ]; then
>     echo "Deployment is not available"
>     exit 1
> fi
> 
> # Check pod status
> READY_PODS=$(kubectl get deployment ${CI_PROJECT_NAME} -n $NAMESPACE -o jsonpath='{.status.readyReplicas}')
> DESIRED_PODS=$(kubectl get deployment ${CI_PROJECT_NAME} -n $NAMESPACE -o jsonpath='{.spec.replicas}')
> 
> if [ "$READY_PODS" != "$DESIRED_PODS" ]; then
>     echo "Not all pods are ready: $READY_PODS/$DESIRED_PODS"
>     exit 1
> fi
> 
> # Check for pod restarts (indicating potential issues)
> RESTART_COUNT=$(kubectl get pods -n $NAMESPACE -l app=${CI_PROJECT_NAME} -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}')
> 
> if [ "$RESTART_COUNT" -gt 3 ]; then
>     echo "Warning: High restart count detected: $RESTART_COUNT"
>     exit 1
> fi
> 
> echo "✅ Deployment verification successful"
> exit 0
> ```
> 
> ---
> 
> ## Dockerfile (Production-Ready)
> 
> ```dockerfile
> # ==============================================================================
> # Multi-stage Dockerfile for Java Microservices
> # ==============================================================================
> 
> # Build Stage
> FROM eclipse-temurin:21-jdk-alpine AS builder
> 
> WORKDIR /app
> 
> # Copy Maven wrapper and pom.xml first for better caching
> COPY .mvn/ .mvn/
> COPY mvnw pom.xml ./
> 
> # Download dependencies (cached layer)
> RUN ./mvnw dependency:go-offline -B
> 
> # Copy source code and build
> COPY src ./src
> RUN ./mvnw clean package -DskipTests -B
> 
> # Extract layered JAR
> RUN java -Djarmode=layertools -jar target/*.jar extract --destination extracted
> 
> # ==============================================================================
> # Runtime Stage
> # ==============================================================================
> FROM eclipse-temurin:21-jre-alpine AS runtime
> 
> # Add non-root user for security
> RUN addgroup -S appgroup && adduser -S appuser -G appgroup
> 
> WORKDIR /app
> 
> # Copy layered JAR from builder
> COPY --from=builder /app/extracted/dependencies/ ./
> COPY --from=builder /app/extracted/spring-boot-loader/ ./
> COPY --from=builder /app/extracted/snapshot-dependencies/ ./
> COPY --from=builder /app/extracted/application/ ./
> 
> # Set ownership
> RUN chown -R appuser:appgroup /app
> 
> USER appuser
> 
> # Build arguments for metadata
> ARG APP_VERSION=unknown
> ARG BUILD_DATE=unknown
> ARG GIT_COMMIT=unknown
> ARG GIT_REF=unknown
> 
> # Labels for container metadata
> LABEL org.opencontainers.image.title="Java Microservice" \
>       org.opencontainers.image.version="${APP_VERSION}" \
>       org.opencontainers.image.created="${BUILD_DATE}" \
>       org.opencontainers.image.revision="${GIT_COMMIT}" \
>       org.opencontainers.image.ref="${GIT_REF}"
> 
> # JVM Options for containers
> ENV JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -XX:+UseG1GC -XX:+ExitOnOutOfMemoryError"
> ENV SPRING_PROFILES_ACTIVE="docker"
> 
> # Health check
> HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
>     CMD curl -f http://localhost:8080/actuator/health || exit 1
> 
> EXPOSE 8080
> 
> ENTRYPOINT ["sh", "-c", "java ${JAVA_OPTS} org.springframework.boot.loader.JarLauncher"]
> ```
> 
> ---
> 
> ## Kubernetes Deployment Manifests
> 
> ### `k8s/deployment.yaml`
> 
> ```yaml
> apiVersion: apps/v1
> kind: Deployment
> metadata:
>   name: ${CI_PROJECT_NAME}
>   namespace: ${KUBERNETES_NAMESPACE}
>   labels:
>     app: ${CI_PROJECT_NAME}
>     version: ${APP_VERSION}
>     commit: ${GIT_COMMIT_SHORT}
> spec:
>   replicas: ${REPLICAS}
>   revisionHistoryLimit: 10
>   strategy:
>     type: RollingUpdate
>     rollingUpdate:
>       maxSurge: 25%
>       maxUnavailable: 0
>   selector:
>     matchLabels:
>       app: ${CI_PROJECT_NAME}
>   template:
>     metadata:
>       labels:
>         app: ${CI_PROJECT_NAME}
>         version: ${APP_VERSION}
>       annotations:
>         prometheus.io/scrape: "true"
>         prometheus.io/port: "8080"
>         prometheus.io/path: "/actuator/prometheus"
>     spec:
>       serviceAccountName: ${CI_PROJECT_NAME}
>       terminationGracePeriodSeconds: 60
>       containers:
>         - name: ${CI_PROJECT_NAME}
>           image: ${DOCKER_IMAGE}:${DOCKER_TAG}
>           imagePullPolicy: Always
>           ports:
>             - name: http
>               containerPort: 8080
>               protocol: TCP
>           env:
>             - name: SPRING_PROFILES_ACTIVE
>               valueFrom:
>                 configMapKeyRef:
>                   name: ${CI_PROJECT_NAME}-config
>                   key: SPRING_PROFILES_ACTIVE
>             - name: JAVA_OPTS
>               value: "-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0"
>           resources:
>             requests:
>               memory: "512Mi"
>               cpu: "250m"
>             limits:
>               memory: "1Gi"
>               cpu: "1000m"
>           livenessProbe:
>             httpGet:
>               path: /actuator/health/liveness
>               port: http
>             initialDelaySeconds: 60
>             periodSeconds: 10
>             timeoutSeconds: 5
>             failureThreshold: 3
>           readinessProbe:
>             httpGet:
>               path: /actuator/health/readiness
>               port: http
>             initialDelaySeconds: 30
>             periodSeconds: 10
>             timeoutSeconds: 5
>             failureThreshold: 3
>           lifecycle:
>             preStop:
>               exec:
>                 command: ["sh", "-c", "sleep 10 && curl -X POST http://localhost:8080/actuator/gracefulshutdown || true"]
>       affinity:
>         podAntiAffinity:
>           preferredDuringSchedulingIgnoredDuringExecution:
>             - weight: 100
>               podAffinityTerm:
>                 labelSelector:
>                   matchExpressions:
>                     - key: app
>                       operator: In
>                       values:
>                         - ${CI_PROJECT_NAME}
>                 topologyKey: kubernetes.io/hostname
> ```
> 
> ---
> 
> ## Best Practices Implemented
> 
> | Practice | Implementation |
> |----------|----------------|
> | **Retry Mechanisms** | Global `retry` configuration with max 2 retries for system failures |
> | **Caching** | Maven dependencies and target directories cached between runs |
> | **Artifact Management** | Build artifacts stored with reports for traceability |
> | **Security Scanning** | SAST, dependency scanning, container scanning, secret detection |
> | **Environment Promotion** | Staging → Production with manual gates |
> | **Rollback Support** | Automatic rollback on health check failures |
> | **Health Checks** | Kubernetes probes + pipeline health verification |
> | **Notifications** | Slack integration for success/failure alerts |
> | **Resource Limits** | Container resource requests and limits defined |
> | **Non-root Containers** | Security best practice with unprivileged user |
> | **Multi-stage Builds** | Optimized Docker images with layered JAR |
> | **Blue/Green Ready** | Rolling update strategy with zero downtime |
> 
> ---
> 
> ## Required GitLab Variables
> 
> Configure these in **Settings → CI/CD → Variables**:
> 
> | Variable | Description | Protected | Masked |
> |----------|-------------|-----------|--------|
> | `DOCKER_REGISTRY_USER` | Docker registry username | Yes | Yes |
> | `DOCKER_REGISTRY_PASSWORD` | Docker registry password | Yes | Yes |
> | `AWS_ACCESS_KEY_ID_STAGING` | AWS access key for staging | Yes | Yes |
> | `AWS_SECRET_ACCESS_KEY_STAGING` | AWS secret key for staging | Yes | Yes |
> | `AWS_ACCESS_KEY_ID_PRODUCTION` | AWS access key for production | Yes | Yes |
> | `AWS_SECRET_ACCESS_KEY_PRODUCTION` | AWS secret key for production | Yes | Yes |
> | `SLACK_WEBHOOK_URL` | Slack webhook for notifications | Yes | Yes |
> 
> ---
> 
> ## Conclusion
> 
> This pipeline provides a comprehensive, production-ready CI/CD workflow for Java microservices deploying to AWS EKS. Key features include robust self-healing through automatic rollbacks, comprehensive security scanning, staged deployments with manual gates for production, and extensive health verification. The configuration follows GitLab best practices for on-premises instances and includes proper artifact management, caching strategies, and notification integrations.

---
