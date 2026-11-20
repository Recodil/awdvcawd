# win11-mem - на что уходит оперативная память (по программам, с учётом общих библиотек).
# Запускать через sudo, иначе системные службы не видны: sudo win11-mem
echo "== Память, МБ =="
awk '/^(MemTotal|MemAvailable|Cached|Shmem|SwapTotal|SwapFree):/ { printf "%-14s %6d\n", $1, $2 / 1024 }' /proc/meminfo
echo "(Cached - копии файлов с диска; система отдаёт эту память программам мгновенно, это не расход."
echo " Настоящий расход = MemTotal − MemAvailable.)"
echo
echo "== По программам, МБ =="
for d in /proc/[0-9]*; do
  [ -r "$d/smaps_rollup" ] || continue
  pss="$(awk '/^Pss:/ { s += $2 } END { print s + 0 }' "$d/smaps_rollup" 2>/dev/null)"
  [ "${pss:-0}" -gt 0 ] || continue
  name="$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null | awk '{ n = split($1, a, "/"); print a[n] }')"
  [ -n "$name" ] || name="$(cat "$d/comm" 2>/dev/null)"
  # у сценариев (python, bash…) показываем, какой именно сценарий запущен
  case "$name" in
    python*|.python*|bash|sh|perl|node|lua*)
      script="$(tr '\0' '\n' < "$d/cmdline" 2>/dev/null | sed 1d | grep -v '^-' | head -n 1)"
      [ -n "$script" ] && name="$name:${script##*/}" ;;
  esac
  echo "$pss ${name#.}"
done | sed 's/-wrapped$//' | awk '{ m[$2] += $1; c[$2]++ } END { for (k in m) printf "%7.0f  %s (%d)\n", m[k] / 1024, k, c[k] }' | sort -rn | head -n 25
[ "$(id -u)" -eq 0 ] || echo "(показаны только ваши программы; полная картина: sudo win11-mem)"
