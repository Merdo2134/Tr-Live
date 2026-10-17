#!/bin/bash
# TR Live otomatik kurulum (Oracle Cloud).
# Oracle → Compute → Instances → Create instance → en altta "Show advanced options" → "Management" sekmesi →
# "Paste cloud-init script" kutusuna bu dosyanın TAMAMINI yapıştırın.
# YALNIZCA aşağıdaki şifreyi değiştirin: en az 10 karakter, yalnızca harf ve rakam (Türkçe harf, boşluk ve
# tırnak kullanmayın). Bu şifreyle https://<sunucu-adresi>/panel açılır. Kimseyle paylaşmayın.
export PANEL_PASSWORD='BURAYA-EN-AZ-10-KARAKTER-SIFRE'

export HOME=/root
for i in 1 2 3; do
  curl -fsSL --retry 10 --retry-delay 10 --retry-all-errors \
    https://raw.githubusercontent.com/Merdo2134/Tr-Live/main/deploy/oracle/install.sh -o /root/trlive-install.sh &&
    bash /root/trlive-install.sh && break
  sleep 60
done
