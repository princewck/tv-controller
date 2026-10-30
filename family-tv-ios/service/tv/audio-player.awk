# 适配本机Android14的当前players快照。绝不扫描Events log中的历史event:started。
# awk -v app_uid=10038 -v app_pids=' 1234 5678 ' -f audio-player.awk audio.txt
BEGIN { section=0; recognized=0; active=0 }
/^[[:space:]]*players:[[:space:]]*$/ { section=1; recognized=1; next }
section && /^[[:space:]]*(ducked players|faded out players|muted player|banned uids|Events log)/ { section=0 }
section && /AudioPlaybackConfiguration/ {
  if ($0 !~ /state:(idle|started|paused|stopped|released)/) next
  owner=$0
  sub(/^.*u\/pid:/,"",owner)
  if (owner==$0) { owner=$0; sub(/^.*uid\/pid:/,"",owner) }
  split(owner,parts,"/"); uid=parts[1]; pid=parts[2]; sub(/[^0-9].*$/,"",pid)
  # 常规应用使用UID；系统共享UID仅匹配进程，避免把小爱提示音算成视频。
  belongs=(uid==app_uid && app_uid>=10000) || (pid!="" && index(app_pids," " pid " ")>0)
  if(belongs && /state:started([[:space:]]|$)/ && !/type:android.media.SoundPool/ && /usage=USAGE_(MEDIA|UNKNOWN)/) active=1
}
END { if(!recognized) print "unknown"; else if(active) print "true"; else print "false" }
