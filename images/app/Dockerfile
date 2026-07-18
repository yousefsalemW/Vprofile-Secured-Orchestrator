# =========================================================
#  VProfile APP (Tomcat)  —  multi-stage secure image
#  build context = ../../src   (the source-code repo root)
# =========================================================

# ---------- Stage 1: build the WAR ----------
FROM maven:3.9.9-eclipse-temurin-11 AS build
WORKDIR /workspace

# copy sources
COPY pom.xml .
COPY src ./src

# service hostnames + credentials injected at build time (NOT hard-coded)
ARG DB_HOST=db01.vprofile
ARG DB_USER=admin
ARG DB_PASS=admin123
ARG MC_HOST=mc01.vprofile
ARG RMQ_HOST=rmq01.vprofile
ARG RMQ_USER=vprofile
ARG RMQ_PASS=guest

# rewrite application.properties to point at the k8s Services, then build
RUN set -eux; p=src/main/resources/application.properties; \
    sed -i "s#jdbc:mysql://db01:#jdbc:mysql://${DB_HOST}:#"            "$p"; \
    sed -i "s#^jdbc.username=.*#jdbc.username=${DB_USER}#"            "$p"; \
    sed -i "s#^jdbc.password=.*#jdbc.password=${DB_PASS}#"            "$p"; \
    sed -i "s#memcached.active.host=mc01#memcached.active.host=${MC_HOST}#"   "$p"; \
    sed -i "s#memcached.standBy.host=mc01#memcached.standBy.host=${MC_HOST}#" "$p"; \
    sed -i "s#rabbitmq.address=rmq01#rabbitmq.address=${RMQ_HOST}#"    "$p"; \
    sed -i "s#^rabbitmq.username=.*#rabbitmq.username=${RMQ_USER}#"    "$p"; \
    sed -i "s#^rabbitmq.password=.*#rabbitmq.password=${RMQ_PASS}#"    "$p"; \
    mvn -q -B clean package -DskipTests

# ---------- Stage 2: minimal runtime ----------
FROM tomcat:9.0.98-jre11-temurin-jammy
LABEL maintainer="ALnaqib" \
      org.opencontainers.image.title="vprofile-app" \
      org.opencontainers.image.source="https://github.com/yousefsalemW"

# clean default apps, drop only our artifact as ROOT
RUN rm -rf /usr/local/tomcat/webapps/*
COPY --from=build /workspace/target/vprofile-v2.war /usr/local/tomcat/webapps/ROOT.war

# run as an unprivileged user (hardening)
RUN groupadd -r tomcat && useradd -r -g tomcat -d /usr/local/tomcat tomcat \
    && chown -R tomcat:tomcat /usr/local/tomcat
USER tomcat

EXPOSE 8080
CMD ["catalina.sh", "run"]
