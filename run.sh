#!/data/data/com.termux/files/usr/bin/bash
# AMMLR Battery Lab PRO - HyperOS Root Edition (No Logs)
# Fokus: visual cakep + fitur praktis, tanpa CSV/logcat.

BSTAT_FILE="/data/system/batterystats.bin"
BSTAT_BACKUP_DIR="/data/system/batterystats_backups"
BAT_PATH="/sys/class/power_supply/battery"
SAFE_CHARGE_TARGET=80
SAFE_DISCHARGE_TARGET=25

RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"
BLUE="\e[34m"; MAGENTA="\e[35m"; CYAN="\e[36m"
RESET="\e[0m"; BOLD="\e[1m"; DIM="\e[2m"

command_exists() { command -v "$1" >/dev/null 2>&1; }

banner() {
  clear
  echo -e "${CYAN}${BOLD}"
  echo "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓"
  echo "┃        AMMLR BATTERY LAB  •  PRO           ┃"
  echo "┃           HyperOS • Root • Termux          ┃"
  echo "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛"
  echo -e "${RESET}"
}

info(){ echo -e "${CYAN}[i]${RESET} $*"; }
ok(){ echo -e "${GREEN}[+]${RESET} $*"; }
warn(){ echo -e "${YELLOW}[!]${RESET} $*"; }
err(){ echo -e "${RED}[x]${RESET} $*"; }

pause(){ echo; read -rp "Tekan ENTER untuk lanjut..." _; }

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    err "Script ini harus dijalankan sebagai ROOT."
    echo
    echo "Contoh dari Termux:"
    echo "  tsu bash batrelab-pro.sh"
    exit 1
  fi
}

get_batt_val() {
  local file="$1"
  [ -f "$BAT_PATH/$file" ] && cat "$BAT_PATH/$file" 2>/dev/null || echo "N/A"
}

fmt_voltage() {
  local raw="$1"
  if [[ "$raw" =~ ^[0-9]+$ ]] && [ "${#raw}" -ge 6 ] && command_exists bc; then
    printf "%.3f" "$(echo "$raw / 1000000" | bc -l)"
  else
    echo "$raw"
  fi
}

draw_batt_bar() {
  local cap="$1"
  [ "$cap" = "N/A" ] && echo "N/A" && return
  local blocks=$(( cap / 5 ))    # 0–20
  local i
  local color="$GREEN"
  if [ "$cap" -lt 30 ]; then color="$RED"
  elif [ "$cap" -lt 60 ]; then color="$YELLOW"
  fi

  echo -ne "${color}["
  for i in $(seq 1 20); do
    if [ "$i" -le "$blocks" ]; then
      echo -ne "█"
    else
      echo -ne "·"
    fi
  done
  echo -e "] ${cap}%${RESET}"
}

health_category() {
  local degr="$1"
  if [ "$degr" = "N/A" ]; then
    echo "UNKNOWN"
    return
  fi
  if (( $(echo "$degr < 10" | bc -l) )); then
    echo "EXCELLENT"
  elif (( $(echo "$degr < 20" | bc -l) )); then
    echo "GOOD"
  elif (( $(echo "$degr < 30" | bc -l) )); then
    echo "FAIR"
  else
    echo "WEAK"
  fi
}

show_batt_dashboard() {
  banner
  local cap volt_now volt_fmt temp cur_now chg_full chg_design status tech health
  cap=$(get_batt_val "capacity")
  volt_now=$(get_batt_val "voltage_now")
  volt_fmt=$(fmt_voltage "$volt_now")
  temp=$(get_batt_val "temp")
  cur_now=$(get_batt_val "current_now")
  chg_full=$(get_batt_val "charge_full")
  chg_design=$(get_batt_val "charge_full_design")
  status=$(get_batt_val "status")
  tech=$(get_batt_val "technology")
  health=$(get_batt_val "health")

  echo -e "${BOLD}◎ Battery Dashboard${RESET}"
  echo

  echo -e "  ${DIM}Visual Meter:${RESET}"
  echo -n "  "; draw_batt_bar "$cap"
  echo

  echo -e "  ${DIM}Detail:${RESET}"
  echo -e "  • Status        : ${GREEN}$status${RESET}"
  echo -e "  • Kapasitas     : ${YELLOW}$cap %${RESET}"
  echo -e "  • Tegangan      : ${YELLOW}$volt_fmt V${RESET}  ${DIM}(raw: $volt_now)${RESET}"
  echo -e "  • Suhu (raw)    : $temp"
  echo -e "  • Arus (raw)    : $cur_now"
  echo -e "  • Teknologi     : $tech"
  echo -e "  • Health Flag   : $health"
  echo -e "  • Full vs Design: $chg_full µAh  /  $chg_design µAh"
  echo

  local degr="N/A"
  if [[ "$chg_full" != "N/A" && "$chg_design" != "N/A" && "$chg_design" -gt 0 && $(command_exists bc; echo $?) -eq 0 ]]; then
    degr=$(echo "100 - ($chg_full * 100 / $chg_design)" | bc -l | awk '{printf "%.1f", $0}')
  fi
  local hcat
  hcat=$(health_category "$degr")

  echo -e "  ${DIM}Health Estimator:${RESET}"
  echo -e "  • Perkiraan Degradasi : ${MAGENTA}$degr %${RESET}"
  echo -e "  • Kategori            : ${CYAN}$hcat${RESET}"
  echo

  echo -e "  ${DIM}Saran Cepat:${RESET}"
  if [ "$degr" != "N/A" ]; then
    if (( $(echo "$degr < 10" | bc -l) )); then
      echo "  • Kondisi baterai masih sangat sehat. Boleh fast charge sesekali."
    elif (( $(echo "$degr < 20" | bc -l) )); then
      echo "  • Normal untuk pemakaian harian. Jaga di 20–85% kalau mau awet."
    elif (( $(echo "$degr < 30" | bc -l) )); then
      echo "  • Sudah mulai aus, hindari panas berlebih & charge sampai 100% terus-terusan."
    else
      echo "  • Degradasi tinggi. Siapkan opsi ganti baterai kalau mulai suka drop mendadak."
    fi
  else
    echo "  • Fuel gauge tidak memberi data lengkap. Perlakukan baterai dengan pola sehat 20–85%."
  fi

  # suhu kasar
  if [ "$temp" != "N/A" ] && command_exists bc; then
    # banyak device pakai 0.1°C, tapi kita nggak paksa convert, hanya threshold kasar
    if (( $(echo "$temp > 450" | bc -l) )); then
      echo -e "  • ${RED}Peringatan: suhu tinggi, kurangi beban (game, kamera, hotspot).${RESET}"
    fi
  fi

  echo
  pause
}

reset_batterystats() {
  banner
  info "Reset batterystats.bin (sinkronisasi statistik software)."
  echo
  echo "Tips:"
  echo "  • Idealnya baterai sedang 95–100% dan terhubung charger."
  echo "  • Setelah reset, reboot saat sudah 100% untuk sinkron terbaik."
  echo
  read -rp "Lanjut reset sekarang? (y/N): " ans
  case "$ans" in
    y|Y) ;;
    *) warn "Dibatalkan."; pause; return ;;
  esac

  mkdir -p "$BSTAT_BACKUP_DIR" 2>/dev/null
  if [ -f "$BSTAT_FILE" ]; then
    local ts
    ts=$(date +%Y%m%d-%H%M%S)
    cp "$BSTAT_FILE" "$BSTAT_BACKUP_DIR/batterystats.bin.$ts.bak" 2>/dev/null && \
      ok "Backup → $BSTAT_BACKUP_DIR/batterystats.bin.$ts.bak"
  else
    warn "batterystats.bin tidak ditemukan (mungkin sudah pernah dihapus)."
  fi

  if rm -f "$BSTAT_FILE" 2>/dev/null; then
    echo -ne "${MAGENTA}Menghapus batterystats.bin dan memicu regenerasi sistem...${RESET}\n"
    for i in $(seq 1 30); do
      echo -ne "█"
      sleep 0.03
    done
    echo
    ok "batterystats.bin dihapus."
  else
    err "Gagal menghapus $BSTAT_FILE (izin/root?)."
  fi
  echo
  pause
}

wizard_calibration() {
  banner
  echo -e "${BOLD}Kalibrasi Penuh • Fisik + Software${RESET}"
  echo
  echo "Step rekomendasi:"
  echo "  1. Pakai HP sampai mati sendiri (0%)."
  echo "  2. Biarkan mati ±30 menit."
  echo "  3. Charge dalam keadaan MATI sampai 100%."
  echo "  4. Setelah 100%, biarkan tersambung ±60 menit lagi."
  echo "  5. Nyalakan, masuk Termux root, jalankan reset batterystats."
  echo
  read -rp "Sudah selesai step 1–4 di atas? (y/N): " a
  case "$a" in
    y|Y) reset_batterystats ;;
    *)   warn "Selesaikan dulu step fisik, baru jalankan wizard."; pause ;;
  esac
}

live_monitor() {
  banner
  echo -e "${BOLD}Live Monitor (Ctrl + C untuk berhenti)${RESET}"
  echo
  echo -e "${DIM}Format: Status | % | Tegangan | Suhu | Meter${RESET}"
  echo
  while true; do
    local cap volt_now volt_fmt temp status
    cap=$(get_batt_val "capacity")
    volt_now=$(get_batt_val "voltage_now")
    volt_fmt=$(fmt_voltage "$volt_now")
    temp=$(get_batt_val "temp")
    status=$(get_batt_val "status")

    # buat satu baris, lalu meter di ujung
    local line="Status: $status  |  ${cap}%  |  ${volt_fmt}V  |  temp: $temp"
    printf "\r%-60s " "$line"
    # meter kecil
    echo -ne " "
    draw_batt_bar "$cap" | tr '\n' ' '
    sleep 3
  done
}

safe_charge_assistant() {
  banner
  echo -e "${BOLD}Safe Charge Assistant${RESET}"
  echo
  echo "Jaga baterai supaya tidak terlalu sering 100%."
  echo "Target default: ${SAFE_CHARGE_TARGET}%."
  echo
  read -rp "Target persentase (ENTER = $SAFE_CHARGE_TARGET): " t
  local target="${t:-$SAFE_CHARGE_TARGET}"

  echo
  echo "Monitoring sampai baterai mencapai $target% (Ctrl + C untuk batal)..."
  while true; do
    local cap status
    cap=$(get_batt_val "capacity")
    status=$(get_batt_val "status")
    printf "\rStatus: %-9s | %3s %%   " "$status" "$cap"

    if [ "$status" = "Charging" ] || [ "$status" = "Full" ]; then
      if [ "$cap" != "N/A" ] && [ "$cap" -ge "$target" ]; then
        echo
        ok "Baterai sudah $cap%. Cabut charger."
        command_exists termux-vibrate && termux-vibrate -d 800
        command_exists termux-toast && termux-toast "AMMLR: Lepas charger, baterai sudah $cap %"
        break
      fi
    fi
    sleep 5
  done
  echo
  pause
}

safe_discharge_assistant() {
  banner
  echo -e "${BOLD}Safe Discharge Assistant${RESET}"
  echo
  echo "Mode ini bantu mengingatkan saat baterai turun ke level aman"
  echo "untuk mulai charge, misalnya 20–30%."
  echo
  read -rp "Target batas bawah (ENTER = $SAFE_DISCHARGE_TARGET): " t
  local target="${t:-$SAFE_DISCHARGE_TARGET}"

  echo
  echo "Monitoring sampai baterai turun ke $target% (Ctrl + C untuk batal)..."
  while true; do
    local cap status
    cap=$(get_batt_val "capacity")
    status=$(get_batt_val "status")
    printf "\rStatus: %-9s | %3s %%   " "$status" "$cap"

    if [ "$status" = "Discharging" ] || [ "$status" = "Not charging" ]; then
      if [ "$cap" != "N/A" ] && [ "$cap" -le "$target" ]; then
        echo
        ok "Baterai sudah turun ke $cap%. Saat yang bagus untuk mulai charge."
        command_exists termux-vibrate && termux-vibrate -d 800
        command_exists termux-toast && termux-toast "AMMLR: Saatnya charge (batre $cap %)"
        break
      fi
    fi
    sleep 5
  done
  echo
  pause
}

quick_diag() {
  banner
  echo -e "${BOLD}Quick Diagnostic${RESET}"
  echo
  local cap status health tech chg_full chg_design
  cap=$(get_batt_val "capacity")
  status=$(get_batt_val "status")
  health=$(get_batt_val "health")
  tech=$(get_batt_val "technology")
  chg_full=$(get_batt_val "charge_full")
  chg_design=$(get_batt_val "charge_full_design")

  echo "Ringkasan:"
  echo "  • Status OS      : $status"
  echo "  • Persen sekarang: $cap %"
  echo "  • Health flag    : $health"
  echo "  • Teknologi cell : $tech"
  echo "  • Full/Design    : $chg_full / $chg_design µAh"
  echo

  echo "Analisa singkat:"
  if [ "$cap" != "N/A" ] && [ "$cap" -le 15 ] && [ "$status" = "Discharging" ]; then
    echo "  • Baterai sudah kritis, kurangi beban dan segera charge."
  fi

  if [ "$health" = "Dead" ] || [ "$health" = "Overheat" ]; then
    echo -e "  • ${RED}Flag health jelek. Pertimbangkan ganti baterai.${RESET}"
  elif [ "$health" = "Good" ] || [ "$health" = "Cold" ] || [ "$health" = "Warm" ]; then
    echo "  • Health dari kernel masih dianggap normal."
  fi

  if [ "$chg_full" != "N/A" ] && [ "$chg_design" != "N/A" ] && [ "$chg_design" -gt 0 ] && command_exists bc; then
    local degr
    degr=$(echo "100 - ($chg_full * 100 / $chg_design)" | bc -l | awk '{printf "%.1f", $0}')
    echo "  • Degradasi estimasi sekitar $degr %."
  fi

  echo
  echo "Jika setelah kalibrasi penuh status tetap aneh (drop mendadak, mati di 20%),"
  echo "itu cenderung masalah fisik cell, bukan hanya software."
  echo
  pause
}

main_menu() {
  while true; do
    banner
    echo -e "${BOLD}Menu:${RESET}"
    echo "  1) Kalibrasi Penuh (Fisik + Reset batterystats)"
    echo "  2) Reset batterystats.bin saja"
    echo "  3) Battery Dashboard (visual + health + tips)"
    echo "  4) Live Monitor (status real-time)"
    echo "  5) Safe Charge Assistant (batas atas %)"
    echo "  6) Safe Discharge Assistant (batas bawah %)"
    echo "  7) Quick Diagnostic (analisa singkat)"
    echo "  0) Keluar"
    echo
    read -rp "Pilih: " n
    case "$n" in
      1) wizard_calibration ;;
      2) reset_batterystats ;;
      3) show_batt_dashboard ;;
      4) live_monitor ;;
      5) safe_charge_assistant ;;
      6) safe_discharge_assistant ;;
      7) quick_diag ;;
      0) banner; ok "Keluar dari AMMLR Battery Lab PRO. 🔋"; exit 0 ;;
      *) warn "Pilihan tidak valid."; sleep 1 ;;
    esac
  done
}

need_root
main_menu
