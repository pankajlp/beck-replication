#!/bin/zsh
# Run the elastic-net models on the rebuilt splits, stopping them if system free
# memory stays below a floor (finished models are saved, so a rerun resumes).
# Usage: scripts/run_with_memory_guard.sh <workers> [min_free_pct]
cd "$(dirname $0)/.."
workers=$1; floor=${2:-15}
stamp=$(date +%H%M)
log=derived/corrected/glmnet_guarded_$stamp.log
guard=derived/corrected/memory_guard_$stamp.log
R_LIBS_USER=$PWD/Rlib Rscript scripts/run_glmnet.R rebuilt derived/corrected/glmnet $workers > $log 2>&1 &
main=$!
low=0
while kill -0 $main 2>/dev/null; do
  sleep 15
  free=$(sysctl -n kern.memorystatus_level)
  print "$(date +%H:%M:%S) free=$free% models=$(ls derived/corrected/glmnet | wc -l | tr -d ' ')" >> $guard
  if (( free < floor )); then low=$((low + 1)); else low=0; fi
  if (( low >= 2 )); then
    print "$(date +%H:%M:%S) free memory below $floor%: stopping R" >> $guard
    kill $main
    pkill -f 'parallelly|workRSOCK'
    print "STOPPED by memory guard at $free% free"
    exit 2
  fi
done
wait $main
grep "done in" $log
