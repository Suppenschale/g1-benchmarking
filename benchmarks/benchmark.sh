#!/usr/bin/env bash
set -u

JAVA="$1"

DACAPO_JAR="./dacapo-23.11-chopin.jar"
RENAISSANCE_JAR="./renaissance-gpl-0.16.1.jar"

RESULT_DIR="../results"
LOG_DIR="${RESULT_DIR}/logs"

mkdir -p "${RESULT_DIR}"
mkdir -p "${LOG_DIR}"

# ============================================================
# Logging
# ============================================================

LOGOPTS="gc,gc+plab=trace,gc_testing=trace"

# ============================================================
# Benchmark configurations
# ============================================================

declare -A DACAPO_BENCHES=(
  [avrora]="5m"
  [batik]="200m"       #"175m"   out of heap      
  [biojava]="150m"    #93m"     runs +60s
# [cassandra]="174m"            Does not run on JKD26 (no security manager)
  [eclipse]="135m"
  [fop]="20m"         #13m      out of heap
  [graphchi]="175m"
  [h2]="700m"         #"681m"   out of heap
  # [h2o]="72m"                 Does not run on JDK26 (JDK <= 17)
  [jme]="1000m"       #"29m"    out of heap (with -XX:+DisableExplicitGC b
  [jython]="50m"      #"25m"    runs +60s
  [kafka]="250m"      #"201"    out of heap
  [luindex]="29m"
  [lusearch]="30m"    #"19m"    runs +60s
  [pmd]="191m"
  [spring]="55m"
  [sunflow]="33m"
  [tomcat]="21m"
  #[tradebeans]="135m"          Does not run on JKD26 (java.lang.UnsupportedOperationException: Setting a system-wide Policy object is not supported)
  #[tradesoap]="91m"            Does not run on JKD26 (java.lang.UnsupportedOperationException: Setting a system-wide Policy object is not supported)
  [xalan]="13m"
  [zxing]="183m"
)

declare -A RENAISSANCE_BENCHES=(
  [akka-uct]="512m" 
  [als]="512m"
  [chi-square]="512m"
  [db-shootout]="96m" 
  [dec-tree]="512m"
  [dotty]="64m"
  [finagle-chirper]="1024m"
  [finagle-http]="96m"
  [fj-kmeans]="128m"
  [future-genetic]="16m"
  [gauss-mix]="512m"
  [log-regression]="512m"
  [mnemonics]="48m"
  [movie-lens]="512m"
  [naive-bayes]="1536m"
  [neo4j-analytics]="1536m"
  [page-rank]="768m"
  [par-mnemonics]="48m"
  [philosophers]="16m"
  [reactors]="512m"
  [rx-scrabble]="48m"
  [scala-doku]="48m"
  [scala-kmeans]="32m"
  [scala-stm-bench7]="512m"
  [scrabble]="128m"
)

CONFIGS=(
  "baseline"
  "survivor"
  "humongous"
)

# Number of repetitions
RUNS=5


# ============================================================
# Helper functions
# ============================================================

double_heap() {
  local heap="$1"
  local value="${heap%m}"

  echo "$(( value * 2 ))m"
}


get_gc_flags() {
  local config="$1"

  case "${config}" in

    baseline)
      echo "-XX:-G1UseSurvivorHoles"
      ;;

    survivor)
      echo "-XX:+G1UseSurvivorHoles"
      ;;

    humongous)
      echo "-XX:+G1UseHumongousHoles"
      ;;

    old)
      echo "-XX:+G1UseOldHoles"
      ;;

    all)
      echo "-XX:+G1UseSurvivorHoles"
      echo "-XX:+G1UseHumongousHoles"
      echo "-XX:+G1UseOldHoles"
      ;;

    *)
      echo "ERROR: Unknown configuration: ${config}" >&2
      return 1
      ;;

  esac
}


# ============================================================
# CSV files
# ============================================================

GC_CSV="${RESULT_DIR}/gc_stats.csv"
TIMING_CSV="${RESULT_DIR}/timing_stats.csv"
RUNTIME_CSV="${RESULT_DIR}/runtime_stats.csv"

echo "suite,benchmark,heap,config,structure,iteration,young_gc,full_gc,young_pause_ms,full_pause_ms,total_pause_ms" \
  > "${GC_CSV}"

echo "suite,benchmark,heap,config,structure,iteration,operation,gen,size,time_us,result" \
  > "${TIMING_CSV}"

echo "suite,benchmark,heap,config,structure,iteration,time_ms" \
  > "${RUNTIME_CSV}"


# ============================================================
# Parse timing information
# ============================================================

parse_timing() {

  local suite="$1"
  local benchmark="$2"
  local heap="$3"
  local config="$4"
  local structure="$5"
  local log="$6"


  if [[ "${suite}" == "dacapo" ]]; then

    # --------------------------------------------------------
    # DaCapo
    #
    # Example:
    #
    # ===== DaCapo 23.11-chopin sunflow starting warmup 1 =====
    #
    # Timing lines occurring after this belong to warmup 1.
    #
    # The final:
    #
    # ===== DaCapo ... starting =====
    #
    # is the measured iteration.
    # --------------------------------------------------------

    awk \
      -v suite="${suite}" \
      -v benchmark="${benchmark}" \
      -v heap="${heap}" \
      -v config="${config}" \
      -v structure="${structure}" '

      BEGIN {
        iteration = ""
      }


      /===== DaCapo .* starting warmup [0-9]+ =====/ {

        if (match($0, /starting warmup [0-9]+/)) {

          text = substr($0, RSTART, RLENGTH)

          gsub(/starting warmup /, "", text)

          iteration = "warmup_" text
        }

        next
      }


      /===== DaCapo .* starting =====/ &&
      !/starting warmup/ {

        iteration = "measurement"

        next
      }


      /timing:/ {

        if (iteration == "")
          next

        line = $0

        pos = index(line, "timing:")

        if (pos == 0)
          next

        timing = substr(line, pos + 7)

        n = split(timing, fields, ":")

        if (n >= 5) {

          operator  = fields[1]
          gen       = fields[2]
          size      = fields[3]
          time_ms   = fields[4]
          result    = fields[5]

          print suite "," \
                benchmark "," \
                heap "," \
                config "," \
                structure "," \
                iteration "," \
                operator "," \
                gen "," \
                size "," \
                time_ms "," \
                result
        }
      }

    ' "${log}" >> "${TIMING_CSV}"


  else

    # --------------------------------------------------------
    # Renaissance
    #
    # Example:
    #
    # ====== philosophers (scala) [default],
    #        iteration 0 completed (3264.991 ms) ======
    #
    # ====== philosophers (scala) [default],
    #        iteration 1 started ======
    #
    # The iteration number is explicitly printed.
    # --------------------------------------------------------

    awk \
      -v suite="${suite}" \
      -v benchmark="${benchmark}" \
      -v heap="${heap}" \
      -v config="${config}" \
      -v structure="${structure}" '

      BEGIN {
        iteration = ""
      }


      /iteration [0-9]+ started/ {

        if (match($0, /iteration [0-9]+ started/)) {

          text = substr($0, RSTART, RLENGTH)

          gsub(/iteration /, "", text)
          gsub(/ started/, "", text)

          iteration = text
        }

        next
      }


      /timing:/ {

        if (iteration == "")
          next

        line = $0

        pos = index(line, "timing:")

        if (pos == 0)
          next

        timing = substr(line, pos + 7)

        n = split(timing, fields, ":")

        if (n >= 5) {

          operator  = fields[1]
          gen       = fields[2]
          size      = fields[3]
          time_ms   = fields[4]
          result    = fields[5]

          print suite "," \
                benchmark "," \
                heap "," \
                config "," \
                structure "," \
                iteration "," \
                operator "," \
                gen "," \
                size "," \
                time_ms "," \
                result
        }
      }

    ' "${log}" >> "${TIMING_CSV}"

  fi
}


# ============================================================
# Parse runtime information
# ============================================================

parse_runtime() {

  local suite="$1"
  local benchmark="$2"
  local heap="$3"
  local config="$4"
  local structure="$5"
  local log="$6"


  if [[ "${suite}" == "dacapo" ]]; then

    # --------------------------------------------------------
    # DaCapo
    #
    # Example:
    #
    # ===== ... completed warmup 1 in 7077 msec =====
    #
    # ===== ... PASSED in 9561 msec =====
    #
    # We record the 9 warmups and the final measurement.
    # --------------------------------------------------------

    awk \
      -v suite="${suite}" \
      -v benchmark="${benchmark}" \
      -v heap="${heap}" \
      -v config="${config}" \
      -v structure="${structure}" '

      /===== DaCapo .* completed warmup [0-9]+ in [0-9]+ msec =====/ {

        if (match($0, /completed warmup [0-9]+ in [0-9]+ msec/)) {

          text = substr($0, RSTART, RLENGTH)

          n = split(text, fields, " ")

          # fields:
          # completed
          # warmup
          # N
          # in
          # TIME
          # msec

          iteration = "warmup_" fields[3]
          time_ms = fields[5]

          print suite "," \
                benchmark "," \
                heap "," \
                config "," \
                structure "," \
                iteration "," \
                time_ms
        }

        next
      }


      /===== DaCapo .* PASSED in [0-9]+ msec =====/ {

        if (match($0, /PASSED in [0-9]+ msec/)) {

          text = substr($0, RSTART, RLENGTH)

          n = split(text, fields, " ")

          # fields:
          # PASSED
          # in
          # TIME
          # msec

          iteration = "measurement"
          time_ms = fields[3]

          print suite "," \
                benchmark "," \
                heap "," \
                config "," \
                structure "," \
                iteration "," \
                time_ms
        }

        next
      }

    ' "${log}" >> "${RUNTIME_CSV}"


  else

    # --------------------------------------------------------
    # Renaissance
    #
    # Example:
    #
    # ====== philosophers (scala) [default],
    # iteration 0 completed (3264.991 ms) ======
    #
    # --------------------------------------------------------

    awk \
      -v suite="${suite}" \
      -v benchmark="${benchmark}" \
      -v heap="${heap}" \
      -v config="${config}" \
      -v structure="${structure}" '

      /iteration [0-9]+ completed \([0-9]+\.[0-9]+ ms\)/ {

        if (match($0, /iteration [0-9]+ completed \([0-9]+\.[0-9]+ ms\)/)) {

          text = substr($0, RSTART, RLENGTH)

          n = split(text, fields, " ")

          # fields:
          # iteration
          # N
          # completed
          # (TIME
          # ms)

          iteration = fields[2]

          time_ms = fields[4]

          gsub(/\(/, "", time_ms)

          print suite "," \
                benchmark "," \
                heap "," \
                config "," \
                structure "," \
                iteration "," \
                time_ms
        }

        next
      }

    ' "${log}" >> "${RUNTIME_CSV}"

  fi
}


# ============================================================
# Parse GC information
# ============================================================

parse_gc() {

  local suite="$1"
  local benchmark="$2"
  local heap="$3"
  local config="$4"
  local structure="$5"
  local log="$6"


  if [[ "${suite}" == "dacapo" ]]; then

    # --------------------------------------------------------
    # DaCapo
    #
    # Warmups 1..9 + final measurement.
    # --------------------------------------------------------

    awk \
      -v suite="${suite}" \
      -v benchmark="${benchmark}" \
      -v heap="${heap}" \
      -v config="${config}" \
      -v structure="${structure}" '

      BEGIN {

        iteration = ""

        young_count[""] = 0
        full_count[""] = 0

        young_pause[""] = 0
        full_pause[""] = 0
      }


      /===== DaCapo .* starting warmup [0-9]+ =====/ {

        if (match($0, /starting warmup [0-9]+/)) {

          text = substr($0, RSTART, RLENGTH)

          gsub(/starting warmup /, "", text)

          iteration = "warmup_" text
        }

        next
      }


      /===== DaCapo .* starting =====/ &&
      !/starting warmup/ {

        iteration = "measurement"

        next
      }


      /Pause Young/ {

        if (iteration == "")
          next

        young_count[iteration]++

        for (i = 1; i <= NF; i++) {

          if ($i ~ /^[0-9]+(\.[0-9]+)?ms$/) {

            value = $i
            sub(/ms$/, "", value)

            young_pause[iteration] += value

            break
          }
        }

        next
      }


      /Pause Full/ {

        if (iteration == "")
          next

        full_count[iteration]++

        for (i = 1; i <= NF; i++) {

          if ($i ~ /^[0-9]+(\.[0-9]+)?ms$/) {

            value = $i
            sub(/ms$/, "", value)

            full_pause[iteration] += value

            break
          }
        }

        next
      }


      END {

        for (i = 1; i <= 4; i++) {

          iteration_name = "warmup_" i

          total = young_pause[iteration_name] + \
                  full_pause[iteration_name]

          printf "%s,%s,%s,%s,%s,%s,%d,%d,%.6f,%.6f,%.6f\n", \
            suite, \
            benchmark, \
            heap, \
            config, \
            structure, \
            iteration_name, \
            young_count[iteration_name] + 0, \
            full_count[iteration_name] + 0, \
            young_pause[iteration_name] + 0, \
            full_pause[iteration_name] + 0, \
            total
        }


        total = young_pause["measurement"] + \
                full_pause["measurement"]

        printf "%s,%s,%s,%s,%s,measurement,%d,%d,%.6f,%.6f,%.6f\n", \
          suite, \
          benchmark, \
          heap, \
          config, \
          structure, \
          young_count["measurement"] + 0, \
          full_count["measurement"] + 0, \
          young_pause["measurement"] + 0, \
          full_pause["measurement"] + 0, \
          total
      }

    ' "${log}" >> "${GC_CSV}"


  else

    # --------------------------------------------------------
    # Renaissance
    # --------------------------------------------------------

    awk \
      -v suite="${suite}" \
      -v benchmark="${benchmark}" \
      -v heap="${heap}" \
      -v config="${config}" \
      -v structure="${structure}" '

      BEGIN {

        iteration = ""

        young_count[""] = 0
        full_count[""] = 0

        young_pause[""] = 0
        full_pause[""] = 0
      }


      /iteration [0-9]+ started/ {

        if (match($0, /iteration [0-9]+ started/)) {

          text = substr($0, RSTART, RLENGTH)

          gsub(/iteration /, "", text)
          gsub(/ started/, "", text)

          iteration = text
        }

        next
      }


      /Pause Young/ {

        if (iteration == "")
          next

        young_count[iteration]++

        for (i = 1; i <= NF; i++) {

          if ($i ~ /^[0-9]+(\.[0-9]+)?ms$/) {

            value = $i
            sub(/ms$/, "", value)

            young_pause[iteration] += value

            break
          }
        }

        next
      }


      /Pause Full/ {

        if (iteration == "")
          next

        full_count[iteration]++

        for (i = 1; i <= NF; i++) {

          if ($i ~ /^[0-9]+(\.[0-9]+)?ms$/) {

            value = $i
            sub(/ms$/, "", value)

            full_pause[iteration] += value

            break
          }
        }

        next
      }


      END {

        for (i = 0; i < 5; i++) {

          total = young_pause[i] + full_pause[i]

          printf "%s,%s,%s,%s,%s,%d,%d,%d,%.6f,%.6f,%.6f\n", \
            suite, \
            benchmark, \
            heap, \
            config, \
            structure, \
            i, \
            young_count[i] + 0, \
            full_count[i] + 0, \
            young_pause[i] + 0, \
            full_pause[i] + 0, \
            total
        }
      }

    ' "${log}" >> "${GC_CSV}"

  fi
}


# ============================================================
# Parse complete log
# ============================================================

parse_log() {

  local suite="$1"
  local benchmark="$2"
  local heap="$3"
  local config="$4"
  local structure="$5"
  local log="$6"

  parse_timing \
    "${suite}" \
    "${benchmark}" \
    "${heap}" \
    "${config}" \
    "${structure}" \
    "${log}"

  parse_runtime \
    "${suite}" \
    "${benchmark}" \
    "${heap}" \
    "${config}" \
    "${structure}" \
    "${log}"

  parse_gc \
    "${suite}" \
    "${benchmark}" \
    "${heap}" \
    "${config}" \
    "${structure}" \
    "${log}"
}


# ============================================================
# Run DaCapo
# ============================================================

run_dacapo() {

  local benchmark="$1"
  local heap="$2"
  local config="$3"
  local structure="$4"

  local gc_flags
  gc_flags=$(get_gc_flags "${config}")

  local structure_flag=""

  if [[ "${structure}" != "default" ]]; then
    structure_flag="-XX:G1HoleDataStructure=${structure}"
  fi

  local log="${LOG_DIR}/dacapo_${benchmark}_${heap}_${config}_structure${structure}.log"


  echo
  echo "============================================================"
  echo "DaCapo"
  echo "Benchmark : ${benchmark}"
  echo "Heap      : ${heap}"
  echo "Config    : ${config}"
  echo "Runs      : ${RUNS}"
  echo "Log       : ${log}"
  echo "============================================================"


  set +e

  timeout --signal=TERM --kill-after=30 600 \
  "${JAVA}/bin/java" \
    -XX:+UnlockDiagnosticVMOptions \
    -XX:+UnlockExperimentalVMOptions \
    -XX:-PrintCompilation \
    -XX:+AlwaysPreTouch \
    -XX:+UseLargePages \
    -XX:+DisableExplicitGC \
    -Xmx"${heap}" \
    -Xms"${heap}" \
    ${gc_flags} \
    ${structure_flag} \
    -Xlog:${LOGOPTS} \
    -jar "${DACAPO_JAR}" \
    -n "${RUNS}" \
    "${benchmark}" \
    > "${log}" 2>&1

  local exit_code=$?

  set -e


  echo "Exit code: ${exit_code}"

  parse_log \
    "dacapo" \
    "${benchmark}" \
    "${heap}" \
    "${config}" \
    "${structure}" \
    "${log}"
}


# ============================================================
# Run Renaissance
# ============================================================

run_renaissance() {

  local benchmark="$1"
  local heap="$2"
  local config="$3"
  local structure="$4"

  local gc_flags
  gc_flags=$(get_gc_flags "${config}")

  local structure_flag=""

  if [[ "${structure}" != "default" ]]; then
    structure_flag="-XX:G1HoleDataStructure=${structure}"
  fi

  local log="${LOG_DIR}/renaissance_${benchmark}_${heap}_${config}_structure${structure}.log"


  echo
  echo "============================================================"
  echo "Renaissance"
  echo "Benchmark : ${benchmark}"
  echo "Heap      : ${heap}"
  echo "Config    : ${config}"
  echo "Runs      : ${RUNS}"
  echo "Log       : ${log}"
  echo "============================================================"


  set +e

  timeout --signal=TERM --kill-after=30 600 \
  "${JAVA}/bin/java" \
    -XX:+UnlockDiagnosticVMOptions \
    -XX:+UnlockExperimentalVMOptions \
    -XX:-PrintCompilation \
    -XX:+AlwaysPreTouch \
    -XX:+UseLargePages \
    -XX:+DisableExplicitGC \
    -Xmx"${heap}" \
    -Xms"${heap}" \
    ${gc_flags} \
    ${structure_flag} \
    -Xlog:${LOGOPTS} \
    -jar "${RENAISSANCE_JAR}" \
    -r "${RUNS}" \
    "${benchmark}" \
    > "${log}" 2>&1

  local exit_code=$?

  set -e


  echo "Exit code: ${exit_code}"

  parse_log \
    "renaissance" \
    "${benchmark}" \
    "${heap}" \
    "${config}" \
    "${structure}" \
    "${log}"
}


# ============================================================
# DaCapo benchmarks
# ============================================================

echo
echo "############################################################"
echo "# Starting DaCapo benchmarks"
echo "############################################################"

for benchmark in "${!DACAPO_BENCHES[@]}"; do

  heap="${DACAPO_BENCHES[$benchmark]}"
  doubled_heap=$(double_heap "${heap}")

  for config in "${CONFIGS[@]}"; do

    if [[ "${config}" == "baseline" ]]; then
      # Baseline: both heap sizes, but only one run each
      run_dacapo \
        "${benchmark}" \
        "${heap}" \
        "${config}" \
        0

      run_dacapo \
        "${benchmark}" \
        "${doubled_heap}" \
        "${config}" \
        0

    else
      run_dacapo \
        "${benchmark}" \
        "${heap}" \
        "${config}" \
        2

      run_dacapo \
        "${benchmark}" \
        "${doubled_heap}" \
        "${config}" \
        2
    fi

  done
done


# ============================================================
# Renaissance benchmarks
# ============================================================

echo
echo "############################################################"
echo "# Starting Renaissance benchmarks"
echo "############################################################"

for benchmark in "${!RENAISSANCE_BENCHES[@]}"; do

  heap="${RENAISSANCE_BENCHES[$benchmark]}"
  doubled_heap=$(double_heap "${heap}")

  for config in "${CONFIGS[@]}"; do

    if [[ "${config}" == "baseline" ]]; then
      # Baseline: both heap sizes, but only one run each
      run_renaissance \
        "${benchmark}" \
        "${heap}" \
        "${config}" \
        0

      run_renaissance \
        "${benchmark}" \
        "${doubled_heap}" \
        "${config}" \
        0

    else
      run_renaissance \
        "${benchmark}" \
        "${heap}" \
        "${config}" \
        2

      # Doubled heap
      run_renaissance \
        "${benchmark}" \
        "${doubled_heap}" \
        "${config}" \
        2

    fi

  done
done


# ============================================================
# Finished
# ============================================================

echo
echo "############################################################"
echo "# All benchmarks finished"
echo "############################################################"

echo
echo "GC statistics:"
echo "  ${GC_CSV}"

echo
echo "Timing statistics:"
echo "  ${TIMING_CSV}"

echo
echo "Runtime statistics:"
echo "  ${RUNTIME_CSV}"

echo
echo "Individual logs:"
echo "  ${LOG_DIR}"