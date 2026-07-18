# =========================================================
#  VProfile CACHE (Memcached)  —  tiny hardened image
#  build context = .  (this folder)
# =========================================================
FROM memcached:1.6.31-alpine
LABEL maintainer="ALnaqib" \
      org.opencontainers.image.title="vprofile-mc"

EXPOSE 11211
# -m 64  : cap RAM at 64 MB   |  -l 0.0.0.0 : listen on the pod network
# the base image already runs as the unprivileged 'memcache' user
CMD ["memcached", "-m", "64", "-l", "0.0.0.0", "-p", "11211"]
