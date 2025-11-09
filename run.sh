#!/usr/bin/env bash
# AMMLR Battery Lab - HyperOS + Termux + Root Edition
# Fitur:
# - Info detail baterai + estimasi degradasi
# - Wizard kalibrasi penuh (fisik + software)
# - Reset batterystats.bin dengan backup
# - Monitor real-time + logging ke CSV
# - Quick health estimator dari log + fuel gauge
# - Generator script maintenance otomatis (Magisk/KernelSU service.d)

# ========== CONFIG ==========
BSTAT_FILE="/data/system/batterystats.bin"
BSTAT_BACKUP_DIR="/data/system/batterystats_backups"
BAT_PATH="/sys/class/power_supply/battery"
LOG_TAG="AMMLR-BATT-LAB"
LOG_DIR="/sdcard/AMMLR"
LOG_FILE="$LOG_DIR/battery_log.csv"
SERVICE_DIR="/data/adb/service.d"
SERVICE_SCRIPT="$SERVICE_DIR/ammlr-batt-maintenance.sh"
STAMP_FILE="/data/adb/ammlr-batt.lastreset"
SAFE_CHARGE_TARGET=80   # Batas pengisian sehat (misalnya 80%)
MONITOR_INTERVAL=5      # detik untuk monitor real-time

# ========== COLORS ==========
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
MAGENTA="\e[35m"
CYAN="\e[36m"
RESET="\e[0m"
BOLD="\e[1m"

# ========== HELPER ==========
banner() {
  clear
  echo -e "${CYAN}${BOLD}"
  echo "==============================================="
  echo "       AMMLR BATTERY LAB - HYPEROS EDITION     "
  echo "==============================================="
  echo -e "${RESET}"
}

info()  { echo -e "${CYAN}[i]${RESET} $*"; }
ok()    { echo -e "${GREEN}[+]${RESET} $*"; }
warn()  { echo -e "${YELLOW}[!]${RESET} $*"; }
err()   { echo -e "${RED}[x]${RESET} $*"; }

pause() {
  echo
  read -rp "Tekan ENTER untuk lanjut..." _
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    err "Script ini harus dijalankan sebagai ROOT."
    echo
    echo "Buka Termux lalu ketik:"
    echo "  su"
    echo "lalu jalankan lagi script ini:"
    echo "  ./ammlr-battery-lab.sh"
    exit 1
  fi
}

check_battery_path() {
  if [ ! -d "$BAT_PATH" ]; then
    err "Path battery tidak ditemukan: $BAT_PATH"
    warn "Cek manual di: /sys/class/power_supply/"
    exit 1
  fi
}

init_log() {
  mkdir -p "$LOG_DIR" 2>/dev/null
  if [ ! -f "$LOG_FILE" ]; then
    echo "timestamp,capacity,voltage_uV,voltage_V,temp_raw,current_raw,status" > "$LOG_FILE"
    ok "Membuat log CSV: $LOG_FILE"
  fi
}

get_batt_val() {
  local file="$1"
  [ -f "$BAT_PATH/$file" ] && cat "$BAT_PATH/$file" 2>/dev/null || echo "N/A"
}

fmt_voltage() {
  local raw="$1"
  if [[ "$raw" =~ ^[0-9]+$ ]] && [ "${#raw}" -ge 6 ]; then
    # µV -> V
    printf "%.3f" "$(echo "$raw / 1000000" | bc -l)"
  else
    echo "$raw"
  fi
}

record_snapshot() {
  # reason hanya untuk logcat, bukan di CSV
  local reason="$1"
  check_battery_path
  init_log

  local cap volt_now volt_fmt temp cur_now status ts
  cap=$(get_batt_val "capacity")
  volt_now=$(get_batt_val "voltage_now")
  volt_fmt=$(fmt_voltage "$volt_now")
  temp=$(get_batt_val "temp")
  cur_now=$(get_batt_val "current_now")
  status=$(get_batt_val "status")
  ts=$(date +"%Y-%m-%d %H:%M:%S")

  echo "$ts,$cap,$volt_now,$volt_fmt,$temp,$cur_now,$status" >> "$LOG_FILE"
  log -t "$LOG_TAG" "Snapshot ($reason): $ts cap=${cap}% volt=${volt_fmt}V status=$status"
}

show_batt_info() {
  banner
  check_battery_path

  local cap volt_now volt_fmt temp cur_now chg_full chg_design status
  cap=$(get_batt_val "capacity")
  volt_now=$(get_batt_val "voltage_now")
  volt_fmt=$(fmt_voltage "$volt_now")
  temp=$(get_batt_val "temp")
  cur_now=$(get_batt_val "current_now")
  chg_full=$(get_batt_val "charge_full")
  chg_design=$(get_batt_val "charge_full_design")
  status=$(get_batt_val "status")

  echo -e "${BOLD}Informasi Baterai Saat Ini:${RESET}"
  echo -e "  Status              : ${GREEN}$status${RESET}"
  echo -e "  Persentase          : ${YELLOW}$cap %${RESET}"
  echo -e "  Tegangan            : ${YELLOW}$volt_fmt V${RESET} (raw: $volt_now)"
  echo -e "  Suhu (raw)          : $temp"
  echo -e "  Arus (raw)          : $cur_now"
  echo -e "  Kapasitas Real      : $chg_full µAh"
  echo -e "  Kapasitas Desain    : $chg_design µAh"

  if [[ "$chg_full" != "N/A" && "$chg_design" != "N/A" && "$chg_design" -gt 0 ]]; then
    local degr
    degr=$(echo "100 - ($chg_full * 100 / $chg_design)" | bc -l | awk '{printf "%.1f", $0}')
    echo -e "  Perkiraan Degradasi : ${MAGENTA}$degr %${RESET}"
  fi

  echo
  init_log
  record_snapshot "show_batt_info"
  ok "Snapshot kondisi baterai tersimpan di log CSV."
  echo
  pause
}

reset_batterystats() {
  banner
  info "Mode Reset batterystats.bin (sinkronisasi software)."

  check_battery_path
  local cap status
  cap=$(get_batt_val "capacity")
  status=$(get_batt_val "status")

  echo -e "${BOLD}Saran teknis sebelum reset:${RESET}"
  echo "  1. Idealnya baterai sedang 95–100 %."
  echo "  2. Sebaiknya device sedang di-charge (status: Charging/Full)."
  echo
  echo "Status sekarang:"
  echo "  Persentase : $cap %"
  echo "  Status     : $status"
  echo

  read -rp "Lanjut reset batterystats.bin? (y/N): " ans
  case "$ans" in
    y|Y) ;;
    *) warn "Dibatalkan oleh user."; pause; return ;;
  esac

  mkdir -p "$BSTAT_BACKUP_DIR" 2>/dev/null

  if [ -f "$BSTAT_FILE" ]; then
    local ts
    ts=$(date +"%Y%m%d-%H%M%S")
    cp "$BSTAT_FILE" "$BSTAT_BACKUP_DIR/batterystats.bin.$ts.bak" 2>/dev/null && \
      ok "Backup: $BSTAT_BACKUP_DIR/batterystats.bin.$ts.bak"
  else
    warn "batterystats.bin tidak ditemukan, mungkin sudah dihapus sebelumnya."
  fi

  if rm -f "$BSTAT_FILE" 2>/dev/null; then
    echo -ne "${MAGENTA}Menghapus batterystats.bin dan memicu regenerasi oleh sistem...${RESET}\n"
    for i in {1..30}; do
      echo -ne "#"
      sleep 0.03
    done
    echo
    ok "batterystats.bin dihapus."
    log -t "$LOG_TAG" "Reset batterystats.bin (manual) oleh AMMLR Battery Lab."
    record_snapshot "after_batterystats_reset"
    echo
    warn "Rekomendasi:"
    echo "  - Biarkan HP tetap di-charge hingga benar-benar 100 %."
    echo "  - Reboot setelah penuh, lalu pakai normal beberapa siklus."
  else
    err "Gagal menghapus $BSTAT_FILE (periksa izin/root)."
  fi
  echo
  pause
}

wizard_calibration() {
  banner
  echo -e "${BOLD}WIZARD KALIBRASI PENUH (fisik + software)${RESET}"
  echo
  echo "Langkah yang disarankan:"
  echo "  1. Gunakan HP sampai benar-benar mati sendiri karena lowbat."
  echo "  2. Biarkan mati ±30 menit (stabilkan tegangan dasar)."
  echo "  3. Charge HP dalam keadaan MATI sampai 100 %."
  echo "  4. Setelah 100 %, biarkan tetap terhubung charger ±60 menit."
  echo "  5. Nyalakan HP, buka Termux (root), jalankan reset batterystats."
  echo
  read -rp "Sudah melakukan langkah 1–4 di atas? (y/N): " ans
  case "$ans" in
    y|Y)
      reset_batterystats
      ;;
    *)
      warn "Lakukan dulu langkah fisik (1–4), baru jalankan wizard ini lagi."
      pause
      ;;
  esac
}

monitor_batt() {
  banner
  check_battery_path
  init_log

  echo -e "${BOLD}Mode Monitor Real-time + Optional Logging${RESET}"
  echo
  echo "  - Menampilkan status tiap $MONITOR_INTERVAL detik."
  echo "  - Bisa auto-log ke CSV: $LOG_FILE"
  echo "  - Tekan Ctrl + C untuk berhenti."
  echo
  read -rp "Aktifkan logging ke CSV juga? (y/N): " logans
  local do_log=0
  case "$logans" in
    y|Y) do_log=1 ;;
    *) do_log=0 ;;
  esac

  echo
  echo -e "${YELLOW}Mulai monitor... (Ctrl + C untuk stop)${RESET}"
  echo

  while true; do
    local cap volt_now volt_fmt temp status
    cap=$(get_batt_val "capacity")
    volt_now=$(get_batt_val "voltage_now")
    volt_fmt=$(fmt_voltage "$volt_now")
    temp=$(get_batt_val "temp")
    status=$(get_batt_val "status")

    printf "\rStatus: %-9s | %3s %% | %6s V | temp(raw): %-8s " "$status" "$cap" "$volt_fmt" "$temp"

    if [ "$do_log" -eq 1 ]; then
      local ts
      ts=$(date +"%Y-%m-%d %H:%M:%S")
      echo "$ts,$cap,$volt_now,$volt_fmt,$temp,$(get_batt_val "current_now"),$status" >> "$LOG_FILE"
    fi

    sleep "$MONITOR_INTERVAL"
  done
}

safe_charge_assistant() {
  banner
  check_battery_path

  local target="$SAFE_CHARGE_TARGET"
  echo -e "${BOLD}Safe Charging Assistant${RESET}"
  echo
  echo "Mode ini akan memantau baterai dan mengingatkan ketika persentase"
  echo "mencapai target sehat (default: $SAFE_CHARGE_TARGET %)."
  echo
  read -rp "Target persentase (default $SAFE_CHARGE_TARGET): " inp
  if [[ "$inp" =~ ^[0-9]+$ ]] && [ "$inp" -ge 40 ] && [ "$inp" -le 100 ]; then
    target="$inp"
  fi

  echo
  echo -e "${YELLOW}Monitoring sampai baterai mencapai $target % ... (Ctrl + C untuk berhenti)${RESET}"
  echo

  while true; do
    local cap status
    cap=$(get_batt_val "capacity")
    status=$(get_batt_val "status")

    printf "\rStatus: %-9s | %3s %%   " "$status" "$cap"

    if [[ "$status" == "Charging" || "$status" == "Full" ]]; then
      if [ "$cap" -ge "$target" ]; then
        echo
        ok "Baterai sudah mencapai $cap % (target: $target %)."
        if command_exists termux-toast; then
          termux-toast "AMMLR: Lepaskan charger, baterai sudah $cap %"
        fi
        if command_exists termux-vibrate; then
          termux-vibrate -d 800
        fi
        record_snapshot "safe_charge_target_reached"
        break
      fi
    fi

    sleep 5
  done
  echo
  pause
}

health_from_log() {
  banner
  init_log

  if [ ! -s "$LOG_FILE" ]; then
    warn "Log masih kosong: $LOG_FILE"
    echo "Gunakan dulu mode monitor atau info untuk mengisinya."
    echo
    pause
    return
  fi

  echo -e "${BOLD}Quick Health Estimator dari Log${RESET}"
  echo
  echo "  - Data ini BUKAN pengganti fuel gauge."
  echo "  - Tapi memberi gambaran kasar stabilitas baterai."
  echo

  # ambil beberapa statistik kasar
  local total_lines cap_min cap_max volt_min volt_max
  total_lines=$(wc -l < "$LOG_FILE")
  cap_min=$(awk -F',' 'NR>1 {if(min=="" || $2<min) min=$2} END{print min}' "$LOG_FILE")
  cap_max=$(awk -F',' 'NR>1 {if(max=="" || $2>max) max=$2} END{print max}' "$LOG_FILE")
  volt_min=$(awk -F',' 'NR>1 {if(min=="" || $4<min) min=$4} END{print min}' "$LOG_FILE")
  volt_max=$(awk -F',' 'NR>1 {if(max=="" || $4>max) max=$4} END{print max}' "$LOG_FILE")

  echo "  Total sampel log   : $((total_lines - 1))"
  echo "  Kapasitas min/max  : $cap_min %  /  $cap_max %"
  echo "  Tegangan min/max   : $volt_min V / $volt_max V"
  echo

  local chg_full chg_design
  chg_full=$(get_batt_val "charge_full")
  chg_design=$(get_batt_val "charge_full_design")

  if [[ "$chg_full" != "N/A" && "$chg_design" != "N/A" && "$chg_design" -gt 0 ]]; then
    local degr
    degr=$(echo "100 - ($chg_full * 100 / $chg_design)" | bc -l | awk '{printf "%.1f", $0}')
    echo -e "Fuel gauge report:"
    echo -e "  - Kapasitas Real      : $chg_full µAh"
    echo -e "  - Kapasitas Desain    : $chg_design µAh"
    echo -e "  - Est. Degradasi      : ${MAGENTA}$degr %${RESET}"
    echo
  fi

  echo "File log ini bisa kamu tarik ke PC/laptop dan di-plot (Excel, Python, dsb)"
  echo "untuk analisis lebih dalam (grafik % vs waktu, voltage drop, dll)."
  echo
  pause
}

generate_service_script() {
  banner
  echo -e "${BOLD}Generator Maintenance Script (Magisk/KernelSU service.d)${RESET}"
  echo
  echo "Script ini akan membuat:"
  echo "  $SERVICE_SCRIPT"
  echo
  echo "Fungsi:"
  echo "  - Otomatis jalan saat boot (via Magisk/KernelSU)."
  echo "  - HANYA reset batterystats.bin jika terakhir reset > 30 hari."
  echo "  - Menyimpan timestamp di: $STAMP_FILE"
  echo

  if [ ! -d "$SERVICE_DIR" ]; then
    err "Folder service.d belum ada: $SERVICE_DIR"
    warn "Pastikan Magisk/KernelSU terpasang dan mendukung /data/adb/service.d"
    echo
    pause
    return
  fi

  read -rp "Lanjut buat maintenance script? (y/N): " ans
  case "$ans" in
    y|Y) ;;
    *) warn "Dibatalkan."; pause; return ;;
  esac

  cat > "$SERVICE_SCRIPT" <<'EOF'
#!/system/bin/sh
# AMMLR Battery Maintenance - Auto batterystats reset (per 30 hari+)
BSTAT_FILE="/data/system/batterystats.bin"
STAMP_FILE="/data/adb/ammlr-batt.lastreset"
LOG_TAG="AMMLR-BATT-MAINT"
RESET_INTERVAL_DAYS=30

log() {
  /system/bin/log -t "$LOG_TAG" "$*"
}

if [ "$(id -u)" -ne 0 ]; then
  exit 0
fi

now=$(date +%s 2>/dev/null)
[ -z "$now" ] && exit 0

if [ ! -f "$STAMP_FILE" ]; then
  echo "$now" > "$STAMP_FILE"
  log "First run, set initial timestamp: $now"
  exit 0
fi

last=$(cat "$STAMP_FILE" 2>/dev/null)
[ -z "$last" ] && last="$now"

diff_sec=$(( now - last ))
if [ "$diff_sec" -lt 0 ]; then
  echo "$now" > "$STAMP_FILE"
  log "Timestamp anomali, reset ke now: $now"
  exit 0
fi

days=$(( diff_sec / 86400 ))

if [ "$days" -ge "$RESET_INTERVAL_DAYS" ]; then
  if [ -f "$BSTAT_FILE" ]; then
    cp "$BSTAT_FILE" "${BSTAT_FILE}.auto.bak_$(date +%Y%m%d-%H%M%S)" 2>/dev/null
  fi
  rm -f "$BSTAT_FILE" 2>/dev/null && \
    log "Auto-reset batterystats.bin, last reset $days hari lalu."
  echo "$now" > "$STAMP_FILE"
else
  log "Skip auto-reset (baru $days hari sejak reset terakhir)."
fi
EOF

  chmod 755 "$SERVICE_SCRIPT"
  ok "Maintenance script dibuat: $SERVICE_SCRIPT"
  echo
  echo "Jika service.d aktif, script ini akan jalan otomatis saat boot."
  echo
  pause
}

main_menu() {
  while true; do
    banner
    echo -e "${BOLD}Pilih menu:${RESET}"
    echo "  1) Wizard Kalibrasi Penuh (fisik + software)"
    echo "  2) Reset batterystats.bin saja (manual, cepat)"
    echo "  3) Tampilkan info detail baterai + snapshot log"
    echo "  4) Monitor baterai real-time (+ optional logging)"
    echo "  5) Safe Charging Assistant (ingatkan di target %)"
    echo "  6) Quick Health Estimator dari log CSV"
    echo "  7) Generate maintenance script (Magisk/KernelSU service.d)"
    echo "  0) Keluar"
    echo
    read -rp "Pilihanmu: " choice

    case "$choice" in
      1) wizard_calibration ;;
      2) reset_batterystats ;;
      3) show_batt_info ;;
      4) monitor_batt ;;
      5) safe_charge_assistant ;;
      6) health_from_log ;;
      7) generate_service_script ;;
      0) banner; ok "Keluar dari AMMLR Battery Lab. Jaga batre tetap waras. 🔋"; exit 0 ;;
      *) warn "Pilihan tidak dikenal."; sleep 1 ;;
    esac
  done
}

# ========== ENTRY ==========
need_root
main_menu
