#!/usr/bin/env bash
# Снимки системы: snapper + snap-pac + grub-btrfs.
# Перед каждым pacman -S/-Syu делается снимок «до» и «после»; снимки видны в меню GRUB
# (подменю «Arch Linux snapshots»), с них можно загрузиться, если обновление сломало систему.
#
# Требования: корень на btrfs в подтоме @, загрузчик GRUB.
# Запуск: sudo bash pc/tools/snapper-setup.sh   (повторный запуск безопасен — сделанное пропускается)
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "запусти через sudo" >&2; exit 1; }
say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
stamp=$(date +%Y%m%d-%H%M%S)
user=${SUDO_USER:-}

[ "$(findmnt -no FSTYPE /)" = btrfs ] || { echo "корень не на btrfs" >&2; exit 1; }
case $(findmnt -no OPTIONS /) in *subvol=/@,*|*subvol=/@) ;; *) echo "корень не в подтоме @" >&2; exit 1 ;; esac
UUID=$(findmnt -no UUID /)
opts=$(findmnt -no OPTIONS / | tr , '\n' | grep -v -E '^(subvol|subvolid)=' | paste -sd,)

say "1. Пакеты"
pacman -S --needed --noconfirm snapper snap-pac grub-btrfs inotify-tools

say "2. Конфиг snapper для /"
[ -f /etc/snapper/configs/root ] || snapper -c root create-config /

say "3. Снимки — в отдельный подтом @snapshots (не внутри @, иначе откат невозможен)"
if ! findmnt -n /.snapshots >/dev/null; then
    # create-config сделал вложенный подтом /.snapshots внутри @ — заменяем его
    btrfs subvolume show /.snapshots >/dev/null 2>&1 && btrfs subvolume delete /.snapshots
    top=$(mktemp -d)
    mount -o subvolid=5 UUID="$UUID" "$top"
    [ -d "$top/@snapshots" ] || btrfs subvolume create "$top/@snapshots"
    umount "$top"; rmdir "$top"
    mkdir -p /.snapshots
    grep -q '[[:space:]]/.snapshots[[:space:]]' /etc/fstab || \
        printf 'UUID=%s\t/.snapshots\tbtrfs\t%s,subvol=/@snapshots\t0 0\n' "$UUID" "$opts" >> /etc/fstab
    systemctl daemon-reload
    mount /.snapshots
fi
chmod 750 /.snapshots

say "4. Кэш pacman — отдельный подтом, чтобы старые пакеты не застревали в снимках"
pkg=/var/cache/pacman/pkg
if [ "$(stat -c %i $pkg)" != 256 ]; then        # inode 256 = корень подтома
    mv $pkg $pkg.old
    btrfs subvolume create $pkg
    cp -a --reflink=auto $pkg.old/. $pkg/
    rm -rf $pkg.old
fi

say "5. Лимиты: снимки только при pacman (до/после), без почасовых"
snapper -c root set-config TIMELINE_CREATE=no NUMBER_CLEANUP=yes NUMBER_LIMIT=10 NUMBER_LIMIT_IMPORTANT=5
if [ -n "$user" ]; then
    snapper -c root set-config "ALLOW_USERS=$user" SYNC_ACL=yes    # snapper list без sudo
fi

say "6. initramfs: хук для загрузки снимков (они только для чтения → overlayfs)"
grep -q 'grub-btrfs-overlayfs' /etc/mkinitcpio.conf || \
    sed -i -E '/^HOOKS=/ s/\)$/ grub-btrfs-overlayfs)/' /etc/mkinitcpio.conf
# Если система грузится через UKI (GRUB → arch-linux.efi), обычного initramfs нет,
# а grub-btrfs грузит снимки только с vmlinuz + initramfs — собираем его рядом с UKI.
for preset in /etc/mkinitcpio.d/*.preset; do
    grep -q '^default_uki=' "$preset" || continue
    grep -q '^default_image=' "$preset" && continue
    kname=$(basename "$preset" .preset)
    cp "$preset" "$preset.bak-$stamp"
    sed -i "/^default_uki=/i default_image=\"/boot/initramfs-$kname.img\"" "$preset"
    say "   $preset: + default_image (initramfs-$kname.img)"
done
mkinitcpio -P

say "7. GRUB: параметры ядра из UKI нужны и пунктам снимков"
# zswap.enabled=0 — при zram; в UKI он зашит в /etc/kernel/cmdline, а снимки берут GRUB_CMDLINE_LINUX
if grep -qw 'zswap.enabled=0' /proc/cmdline && ! grep -q 'zswap.enabled=0' /etc/default/grub; then
    cp /etc/default/grub "/etc/default/grub.bak-$stamp"
    sed -i -E 's/^GRUB_CMDLINE_LINUX="(.*)"/GRUB_CMDLINE_LINUX="\1 zswap.enabled=0"/; s/^GRUB_CMDLINE_LINUX=" /GRUB_CMDLINE_LINUX="/' \
        /etc/default/grub
fi

say "8. Службы: очистка старых снимков, обновление меню GRUB при новом снимке"
systemctl enable --now snapper-cleanup.timer grub-btrfsd.service

say "9. Первый снимок и меню GRUB"
snapper -c root list --columns description | grep -q 'после настройки snapper' || \
    snapper -c root create -d "после настройки snapper" -c number --userdata important=yes
grub-mkconfig -o /boot/grub/grub.cfg

say "Готово. Проверка пунктов снимков:"
grep -E '^\s*(linux|initrd) ' /boot/grub/grub-btrfs.cfg | head -2
snapper -c root list
