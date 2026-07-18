# =========================================================
#  VProfile BROKER (RabbitMQ)  —  management + hardened base
#  build context = .  (this folder)
# =========================================================
FROM rabbitmq:3.13.7-management-alpine
LABEL maintainer="ALnaqib" \
      org.opencontainers.image.title="vprofile-rmq"

# 5672  = AMQP (used by the app)   |   15672 = management UI
EXPOSE 5672 15672
# the login user/pass are injected at runtime via RABBITMQ_DEFAULT_USER/PASS
# (a real, non-'guest' user => works over the network with no loopback tricks)
