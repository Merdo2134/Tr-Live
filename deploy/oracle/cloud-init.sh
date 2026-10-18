#!/bin/bash
# TR Live otomatik kurulum. Sadece asagidaki sifreyi degistirin (en az 10 karakter, harf ve rakam).
export PANEL_PASSWORD='BURAYA-EN-AZ-10-KARAKTER-SIFRE'
export HOME=/root
for i in 1 2 3; do
  curl -fsSL --retry 10 --retry-delay 10 --retry-all-errors https://raw.githubusercontent.com/Merdo2134/Tr-Live/main/deploy/oracle/install.sh -o /root/trlive-install.sh && bash /root/trlive-install.sh && break
  sleep 60
done
