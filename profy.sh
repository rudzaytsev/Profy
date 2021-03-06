#!/bin/bash

# profy is open source tool which is based on jmaps source code which had been written by Brendan Gregg 
# (https://github.com/brendangregg/Misc/blob/master/java/jmaps).
# It provide more configuration options for integration between   
# perf-map-agent (https://github.com/jrudolph/perf-map-agent)
# and FlameGraph (https://github.com/brendangregg/FlameGraph)
# Read help for details. 
#
# This script creates java /tmp/perf-PID.map symbol maps for all java processes (or concrete java process).
# Then it executes perf-map-agent on them all, creating symbol map files in /tmp. These map files
# are read by perf_events (aka "perf") when doing system profiles and results visualisation via flamegraph.
# Result of work is .svg file that contains graph of overhead for java program(s)

# Configure these options for correct work of utility
# path to Oracle Java
JAVA_HOME=/usr/lib/jvm/java-8-oracle
# path to perf-map-agent
AGENT_HOME=$HOME/scicon/sampling/perf-map-agent
# path to FlameGraph
FLAME_GRAPH_HOME=$HOME/scicon/sampling/FlameGraph

# utility name
UTILITY_NAME="profy.sh"
# default frequency
Freq=99
# default PidMode = 1 (disabled)
PidMode=1
# default profiling application pid id
ProfileAppPid=-1
# defalt filename for flame graph output svg file without extension
FGraphOutputFileName="flamegraph" 
while getopts ":F:p:o:h" opt; do
  case $opt in
   F)
     echo "Sampling Freq set to $OPTARG Hz"
     Freq=$OPTARG
     ;;     
   h)
     echo "usage: $UTILITY_NAME [-F sampleFrequency] [-p javaAppPid] [-o outputGraphFileName]"
     echo "usage: $UTILITY_NAME [-h]"
     echo "For obtaining correct results profiled java program should be running with XX:+PreserveFramePointer JDK option" 
     exit 0
     ;;
   p)
     echo "PID mode enabled"
     PidMode=0
     ProfileAppPid=$OPTARG     
     ;;
   o)
     echo "FlameGraph will be saved in $OPTARG.svg"
     FGraphOutputFileName=$OPTARG
     ;;
   :)
     echo "Option -$OPTARG requres an argument">&2
     exit 1
     ;;
   \?)
     echo "Invalid option -$OPTARG">&2
     exit 2
     ;;
  esac
done      

if [[ "$USER" != root ]]; then
	echo "ERROR: not root user? exiting..."
	exit 3
fi

if [[ ! -x $JAVA_HOME ]]; then
	echo "ERROR: JAVA_HOME not set correctly; edit $0 and fix"
	exit 4
fi

if [[ ! -x $AGENT_HOME ]]; then
	echo "ERROR: AGENT_HOME not set correctly; edit $0 and fix"
	exit 5
fi

echo "record -F $Freq -a -g -- sleep 30;" 
perf record -F $Freq -a -g -- sleep 30;

# figure out where the agent files are:
AGENT_OUT=""
AGENT_JAR=""
if [[ -e $AGENT_HOME/out/attach-main.jar ]]; then
	AGENT_JAR=$AGENT_HOME/out/attach-main.jar
elif [[ -e $AGENT_HOME/attach-main.jar ]]; then
	AGENT_JAR=$AGENT_HOME/attach-main.jar
fi
if [[ -e $AGENT_HOME/out/libperfmap.so ]]; then
	AGENT_OUT=$AGENT_HOME/out
elif [[ -e $AGENT_HOME/libperfmap.so ]]; then
	AGENT_OUT=$AGENT_HOME
fi
if [[ "$AGENT_OUT" == "" || "$AGENT_JAR" == "" ]]; then
	echo "ERROR: Missing perf-map-agent files in $AGENT_HOME. Check installation."
	exit
fi

echo "Fetching maps for all java processes..."
for pid in $(pgrep -x java); do
	mapfile=/tmp/perf-$pid.map
	[[ -e $mapfile ]] && rm $mapfile
	cmd="cd $AGENT_OUT; $JAVA_HOME/bin/java -Xms32m -Xmx128m -cp $AGENT_JAR:$JAVA_HOME/lib/tools.jar net.virtualvoid.perf.AttachOnce $pid"
echo $cmd
	user=$(ps ho user -p $pid)
	if [[ "$user" != root ]]; then
		# make $user the username if it is a UID:
		if [[ "$user" == [0-9]* ]]; then user=$(awk -F: '$3 == '$user' { print $1 }' /etc/passwd); fi
		cmd="sudo -u $user sh -c '$cmd'"
	fi
	echo "Mapping PID $pid (user $user):"
	time eval $cmd
	if [[ -e "$mapfile" ]]; then
		chown root $mapfile
		chmod 666 $mapfile
	else
		echo "ERROR: $mapfile not created."
	fi
	echo
	echo "wc(1): $(wc $mapfile)"
	echo
done

if [[ PidMode ]]; then
  cmd="perf script -f comm,pid,tid,cpu,time,event,ip,sym,dso,trace | \
    $FLAME_GRAPH_HOME/stackcollapse-perf.pl --pid | grep java-$ProfileAppPid | \
    $FLAME_GRAPH_HOME/flamegraph.pl --color=java --hash > $FGraphOutputFileName.svg"
else
  cmd="perf script | $FLAME_GRAPH_HOME/stackcollapse-perf.pl | \
    $FLAME_GRAPH_HOME/flamegraph.pl --color=java --hash > $FGraphOutputFileName.svg"  
fi

echo $cmd
eval $cmd


