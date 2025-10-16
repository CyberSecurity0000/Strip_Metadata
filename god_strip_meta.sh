#!/usr/bin/env bash
# god_strip_meta.sh â€” limpeza "nÃ­vel Deus" de metadados de MP4/MP3/AV/contÃªiner
# Uso:
#   ./god_strip_meta.sh [--backup] [--timestamp YYYYMMDDhhmm] arquivo1.mp4 arquivo2.mp4 ...
# Exemplos:
#   ./god_strip_meta.sh solyd_1.mp4
#   ./god_strip_meta.sh --backup --timestamp 200001010000 solyd_1.mp4 solyd_2.mp4
#
# O que faz (ordem):
#  1) valida prereqs (exiftool, ffmpeg). AtomicParsley / MP4Box / getfattr sÃ£o opcionais.
#  2) exiftool -all= (remove tags de arquivo)
#  3) ffmpeg remux (-map_metadata -1) pass1
#  4) AtomicParsley --strip (se disponÃ­vel)
#  5) MP4Box rewrap (se disponÃ­vel)
#  6) ffmpeg remux pass2
#  7) remove extended attributes (getfattr/setfattr) se possÃ­vel
#  8) padroniza timestamps (touch) para o valor pedido (default 2000-01-01 00:00)
#  9) checa com ffprobe/exiftool e imprime resumo
#
set -euo pipefail
IFS=$'\n\t'

# Defaults
BACKUP=0
TIMESTAMP="200001010000"   # YYYYMMDDhhmm default
VERBOSE=1

usage(){
  cat <<EOF
Uso: $0 [--backup] [--timestamp YYYYMMDDhhmm] arquivo1 [arquivo2 ...]
  --backup        : mantÃ©m cÃ³pia ORIGINAL.<ext>.bak antes de sobrescrever
  --timestamp T   : define mtime/atime (formato YYYYMMDDhhmm). default: $TIMESTAMP
  --quiet         : menos saÃ­da
EOF
  exit 1
}

# parse args
args=()
while (( $# )); do
  case "$1" in
    --backup) BACKUP=1; shift ;;
    --timestamp) TIMESTAMP="$2"; shift 2 ;;
    --quiet) VERBOSE=0; shift ;;
    -h|--help) usage ;;
    --) shift; while (( $# )); do args+=("$1"); shift; done ;;
    -*)
      echo "OpÃ§Ã£o desconhecida: $1" >&2
      usage
      ;;
    *)
      args+=("$1"); shift ;;
  esac
done

if [ ${#args[@]} -lt 1 ]; then
  usage
fi

# check required commands
for cmd in exiftool ffmpeg ffprobe; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Erro: '$cmd' nÃ£o instalado. Instale (ex: apt install exiftool ffmpeg) e rode novamente." >&2
    exit 2
  fi
done

HAS_ATOMICPARSLEY=0
HAS_MP4BOX=0
HAS_GETFATTR=0
if command -v AtomicParsley >/dev/null 2>&1; then HAS_ATOMICPARSLEY=1; fi
if command -v MP4Box >/dev/null 2>&1; then HAS_MP4BOX=1; fi
if command -v getfattr >/dev/null 2>&1 && command -v setfattr >/dev/null 2>&1; then HAS_GETFATTR=1; fi

log(){ if [ "$VERBOSE" -eq 1 ]; then echo -e "$@"; fi }

# safe tmpdir
TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/stripmeta.XXXXXX")"
trap 'rm -rf "$TMPDIR"' EXIT

for src in "${args[@]}"; do
  if [ ! -f "$src" ]; then
    echo "Pulando: '$src' nÃ£o encontrado."
    continue
  fi

  log "================================================================="
  log "Iniciando limpeza: $src"

  # create backup if requested
  if [ "$BACKUP" -eq 1 ]; then
    bak="${src}.orig.bak"
    cp -a -- "$src" "$bak"
    log "Backup: $bak"
  fi

  # preserve perms/owner
  perms="$(stat -c '%a' -- "$src")"
  owner="$(stat -c '%u:%g' -- "$src")"

  base="$(basename "$src")"
  tmp1="${TMPDIR}/${base}.exif.mp4"
  tmp2="${TMPDIR}/${base}.ff1.mp4"
  tmp3="${TMPDIR}/${base}.mp4box.mp4"
  tmp4="${TMPDIR}/${base}.ff2.mp4"

  # 1) exiftool remove tags (file-level)
  log "[1/9] exiftool - removing file-level metadata..."
  if exiftool -all= -overwrite_original "$src" >/dev/null 2>&1; then
    log "  exiftool OK"
  else
    log "  exiftool falhou (continuando)"
  fi

  # 2) ffmpeg pass1: remux without metadata
  log "[2/9] ffmpeg remux pass1 (remove container metadata)..."
  if ffmpeg -loglevel error -y -i "$src" -map_metadata -1 -c copy "$tmp2"; then
    mv -f "$tmp2" "$src"
    log "  ffmpeg pass1 OK"
  else
    log "  ffmpeg pass1 falhou (continuando)"
    rm -f "$tmp2" || true
  fi

  # 3) AtomicParsley
  if [ "$HAS_ATOMICPARSLEY" -eq 1 ]; then
    log "[3/9] AtomicParsley strip atoms..."
    if AtomicParsley "$src" --overWrite --strip >/dev/null 2>&1; then
      log "  AtomicParsley OK"
    else
      log "  AtomicParsley falhou (continuando)"
    fi
  else
    log "[3/9] AtomicParsley nÃ£o instalado â€” pulando."
  fi

  # 4) MP4Box rewrap (if available)
  if [ "$HAS_MP4BOX" -eq 1 ]; then
    log "[4/9] MP4Box rewrap..."
    if MP4Box -add "$src" -new "$tmp3" >/dev/null 2>&1; then
      mv -f "$tmp3" "$src"
      log "  MP4Box OK"
    else
      log "  MP4Box falhou (continuando)"
      rm -f "$tmp3" || true
    fi
  else
    log "[4/9] MP4Box nÃ£o instalado â€” pulando."
  fi

  # 5) ffmpeg pass2
  log "[5/9] ffmpeg remux pass2 (garantia)..."
  if ffmpeg -loglevel error -y -i "$src" -map_metadata -1 -c copy "$tmp4"; then
    mv -f "$tmp4" "$src"
    log "  ffmpeg pass2 OK"
  else
    log "  ffmpeg pass2 falhou (continuando)"
    rm -f "$tmp4" || true
  fi

  # 6) remove extended attributes (xattrs) se possÃ­vel
  if [ "$HAS_GETFATTR" -eq 1 ]; then
    log "[6/9] removendo extended attributes (xattrs)..."
    # getfattr -d returns list; parse keys
    mapfile -t attrs < <(getfattr -d --absolute-names -m - "$src" 2>/dev/null | sed -n 's/^# file:.*//; /:/p' || true)
    # alternativa simples: usar getfattr -d -m - "$src" and parse lines with "user.*"
    # We'll try to remove common xattrs safely:
    for attr in $(getfattr -d -m - --absolute-names "$src" 2>/dev/null | awk -F= '/^/ {print $1}' | sed 's/^[ \t]*//;s/:$//'); do
      if [ -n "$attr" ]; then
        # remove
        setfattr -x "$attr" "$src" 2>/dev/null || true
      fi
    done
    log "  xattrs (se existiam) tentadas remover."
  else
    log "[6/9] getfattr/setfattr nÃ£o disponÃ­veis â€” pulando remoÃ§Ã£o de xattrs."
  fi

  # 7) zero out common metadata fields via exiftool again (double ensure)
  log "[7/9] exiftool - nochmals cleanup (double-check)..."
  exiftool -overwrite_original -TagsFromFile /dev/null "$src" >/dev/null 2>&1 || true

  # 8) padroniza timestamps (touch)
  log "[8/9] padronizando timestamps para $TIMESTAMP ..."
  # convert YYYYMMDDhhmm to touch -t format (same)
  if [[ ! "$TIMESTAMP" =~ ^[0-9]{12}$ ]]; then
    echo "Timestamp invÃ¡lido: $TIMESTAMP (usar YYYYMMDDhhmm)" >&2
  else
    touch -t "$TIMESTAMP" "$src" || true
    # set access time same as mtime (use utimes via touch above usually sets both)
  fi

  # 9) final verification
  log "[9/9] verificaÃ§Ã£o final (ffprobe/exiftool resumo)..."
  ffprobe_out="$(ffprobe -v quiet -show_entries format_tags -of default=noprint_wrappers=1:nokey=1 "$src" 2>/dev/null || true)"
  exif_out="$(exiftool -s -G1 "$src" 2>/dev/null || true)"
  if [ -z "$ffprobe_out" ] && ! echo "$exif_out" | grep -qiE 'Artist|Title|Comment|Creator|Description|Software|Encoder|Copyright|Create Date|Modify Date'; then
    log "OK â€” sem tags detectÃ¡veis. Arquivo pronto para publicaÃ§Ã£o: $src"
  else
    echo "AtenÃ§Ã£o â€” algo ainda foi detectado para $src:"
    echo "---- ffprobe tags ----"
    echo "$ffprobe_out"
    echo "---- exiftool (trecho) ----"
    echo "$exif_out" | sed -n '1,80p'
    echo "Nota: valores como 'Major Brand', 'Duration', 'Image Width/Height' sÃ£o metadados padrÃ£o do container e nÃ£o contÃªm dados pessoais."
  fi

  # restore perms/owner if possible
  chmod -- "$perms" "$src" 2>/dev/null || true
  # chown may require root; skip if fails
  chown "$owner" "$src" 2>/dev/null || true

done

log "================================================================="
log "ConcluÃ­do. Lembrete: operaÃ§Ã£o foi realizada sobrescrevendo os arquivos (sem backup por padrÃ£o)."
exit 0
