# =========================================================
#  VProfile DB (MySQL 8)  —  pre-seeded 'accounts' database
#  build context = ../../src   (the source-code repo root)
# =========================================================
FROM mysql:8.0.40
LABEL maintainer="ALnaqib" \
      org.opencontainers.image.title="vprofile-db"

# database name is fixed; ALL passwords come at runtime from a k8s Secret
ENV MYSQL_DATABASE=accounts

# any *.sql here runs ONCE on first boot (empty data dir), in file order
# (db_backup.sql is a MySQL 5.7 dump; imports cleanly into MySQL 8.0)
COPY src/main/resources/db_backup.sql /docker-entrypoint-initdb.d/10-db_backup.sql

EXPOSE 3306
# NOTE: the official mysql image already runs as the unprivileged 'mysql' user
