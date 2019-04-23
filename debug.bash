# #!/bin/bash
set -e
root=$(dirname $(realpath $0))
export ANDROID_SERIAL=emulator-5554
if [ $(adb devices | wc -l) -lt 3 ]; then
    echo "An emulator or Android device must be attached first" 1>&2
    exit 1
fi
if [ ! -d "$root/.debug" ]; then
    mkdir "$root/.debug"
    pushd "$root/.debug" >/dev/null
    mkdir sysroot 
    cd sysroot
    mkdir system
    adb pull /system/lib /system/bin system
    popd >/dev/null
fi
$root/gradlew installX86Debug
sysroot="$root/.debug/sysroot"
pushd "$sysroot" >/dev/null
if [[ -d data/app ]]; then
    rm -r data/app
fi
mkdir -p data/app
adb pull "/data/app/$(adb shell ls /data/app '|' grep io.podge.podge | tr -d '\r')" data/app
popd >/dev/null
cp "$root"/build/intermediates/cmake/x86/debug/obj/x86/*.so "$sysroot"/data/app/io.podge.podge*/lib/x86
adb shell am force-stop io.podge.podge
adb shell am start -D io.podge.podge/.PodgeActivity
pid=
attempts=0
while true; do
    pid=$(echo $(adb shell ps '|' grep io.podge.podge | grep -v do_exit) | cut -d ' ' -f 2)
    if ! [[ -z "$pid" ]]; then
        break;
    fi
    attempts=$(($attempts + 1))
    if [[ $attempts == 5 ]]; then
        echo 'Failed to start Podge' 1>&2
        exit 1
    fi
    sleep 0.5
done
local_jdwp_port=12345
android_gdbserver_port=13337
local_gdbserver_port=12346
if [ ! -z "$(adb forward --list | grep tcp:$local_jdwp_port)" ]; then
    adb forward --remove tcp:$local_jdwp_port
fi
if [ ! -z "$(adb forward --list | grep tcp:$local_gdbserver_port)" ]; then
    adb forward --remove tcp:$local_gdbserver_port
fi
adb forward tcp:$local_jdwp_port jdwp:$pid
adb forward tcp:$local_gdbserver_port tcp:$android_gdbserver_port
adb shell pkill gdbserver || true
adb shell gdbserver --attach 0.0.0.0:$android_gdbserver_port $pid >/dev/null &
ndk_bundle=~/Library/Android/sdk/ndk-bundle
gdb=$ndk_bundle/prebuilt/darwin-x86_64/bin/gdb
jdb_cmd="jdb -connect com.sun.jdi.SocketAttach:hostname=localhost,port=$local_jdwp_port"
gdb_cmd="$gdb -ex 'file $sysroot/system/bin/app_process32' -ex 'set solib-absolute-prefix $sysroot' -ex 'target remote localhost:$local_gdbserver_port' -ex 'set osabi GNU/Linux' -ex 'catch throw' -ex 'cont'"
unset TMUX
tmux new-session "tmux new-window "'"'"tmux split-window -h 'tmux select-pane -t 0 && adb -s $ANDROID_SERIAL logcat | grep $pid' && $gdb_cmd && tmux kill-session"'"'" && $jdb_cmd"
