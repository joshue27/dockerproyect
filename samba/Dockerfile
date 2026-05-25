# Samba AD DC con entrypoint fixeado
# Basado en linuxcrafts/samba-ad-dc pero construido desde Alpine
# para evitar depender del upstream y poder debuggear provisioning
#
# Build: docker compose build samba-ad-dc
# O manual: docker build -t sistemaventas-samba:local ./samba

FROM alpine:3.18

ARG BUILD_DATE
ARG VERSION

LABEL Mantainer="dockerproyect" \
      Description="Samba4 AD DC with fixed entrypoint (provisioning debug)"

# Instalar Samba AD DC
RUN apk --no-cache --no-progress --update add samba-dc && \
    mkdir -p /samba/etc/smb.conf.d

# Puertos: DNS, KDC, LDAP, LDAPS, SMB, CATALOG, RPC
EXPOSE 53 53/udp 88 88/udp 135 389 389/udp 445 464 464/udp 636 3268 3269 50000-55000

VOLUME [ "/samba", "/bind-dns", "/ntp_signd", "/users" ]

HEALTHCHECK --interval=60s --timeout=15s --start-period=60s --retries=3 \
    CMD smbclient -L \\localhost -U % -m SMB3 2>/dev/null || exit 1

COPY smb.conf /samba/etc/smb.conf
COPY smb.conf.d/ /samba/etc/smb.conf.d/
COPY docker-entrypoint /samba-ad-dc

RUN chmod +x /samba-ad-dc

ENTRYPOINT ["/samba-ad-dc"]
