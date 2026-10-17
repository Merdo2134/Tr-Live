#!/usr/bin/env bash
# Güvenlik duvarı kuralları (her açılışta ve kurulumda çalışır; tekrar çalıştırmak güvenli).
set -uo pipefail
if systemctl is-active --quiet firewalld 2>/dev/null; then
  # Oracle Linux: firewalld.
  for p in 80/tcp 443/tcp 7881/tcp 7882/udp; do
    firewall-cmd -q --permanent --add-port=$p 2>/dev/null || true
  done
  firewall-cmd -q --permanent --zone=trusted --add-source=172.16.0.0/12 2>/dev/null || true
  firewall-cmd -q --reload 2>/dev/null || true
else
  # Ubuntu: Oracle imajı 22 dışındaki gelen bağlantıları iptables ile reddeder; gerekli portlar en üste eklenir.
  allow() { iptables -C INPUT "$@" -j ACCEPT 2>/dev/null || iptables -I INPUT 1 "$@" -j ACCEPT; }
  allow -p tcp --dport 80
  allow -p tcp --dport 443
  allow -p tcp --dport 7881
  allow -p udp --dport 7882
  # Docker içindeki uygulama sunucusunun aynı makinedeki LiveKit'e (7880) ulaşması.
  allow -s 172.16.0.0/12 -p tcp --dport 7880
fi
# Konteynerler bulut meta-veri adresine (kurulum betiği ve şifre orada) erişemesin.
if iptables -L DOCKER-USER -n >/dev/null 2>&1; then
  iptables -C DOCKER-USER -d 169.254.169.254 -j REJECT 2>/dev/null || iptables -I DOCKER-USER -d 169.254.169.254 -j REJECT
fi
exit 0
