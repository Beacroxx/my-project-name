#!/bin/bash

if [ -z "$1" ] || ! [[ "$1" =~ ^-?[0-9]+$ ]]; then
  echo "Usage: $0 [core count] (max cpu freq in hz, optional)"
  echo "Example: $0 128 5000000"
  exit 1
fi

cores=$(unset LD_PRELOAD; nproc)
targetcores=$1
extracores=$((targetcores-cores))

customfreq=""
if [ -n "$2" ] && [[ "$2" =~ ^-?[0-9]+$ ]]; then
  customfreq=$2
fi

if [ -d "./cpu_base" ]; then
  ./fakecpu-reset.sh auto
fi

if [[ "$customfreq" =~ ^-?[0-9]+$ ]]; then
  echo "Creating $extracores additional CPU cores and setting max clock to $customfreq Hz..."
else
  echo "Creating $extracores additional CPU cores..."
fi


sudo cp -r /sys/devices/system/cpu/cpu0 ./cpu_base 2>/dev/null
mkdir original_cpu_dir custom_cpu workdir
sudo mount --bind /sys/devices/system/cpu ./original_cpu_dir
echo "0-$((cores+extracores-1))" | sudo tee ./custom_cpu/online >/dev/null
echo "0-$((cores+extracores-1))" | sudo tee ./custom_cpu/possible >/dev/null
sudo mount -t overlay overlay -o lowerdir=$PWD/original_cpu_dir,upperdir=$PWD/custom_cpu,workdir=$PWD/workdir /sys/devices/system/cpu

for ((i=0; i<extracores+cores; i++)); do
  sed "s/^processor[[:space:]]*:[[:space:]]*[0-9]*/processor\t: $i/" /proc/cpuinfo | sed '/^$/q' >> ./cpuinfo
done

sudo mount --bind ./cpuinfo /proc/cpuinfo

grep '^cpu ' /proc/stat > ./stat
for ((i=0; i<extracores+cores; i++)); do
  grep '^cpu0 ' /proc/stat | sed "s/^cpu0/cpu$i/" >> ./stat
done
grep -v '^cpu' /proc/stat >> ./stat

sudo mount --bind ./stat /proc/stat

for ((i=cores; i<extracores+cores; i++)); do
  sudo cp ./cpu_base ./custom_cpu/cpu$i -r
  sudo chown root:root ./custom_cpu/cpu$i
  sudo chmod 755 ./custom_cpu/cpu$i
done

if [[ "$customfreq" =~ ^-?[0-9]+$ ]]; then
  for ((i=0; i<cores; i++)); do
    sudo mkdir -p ./custom_cpu/cpufreq/policy$i
    echo $customfreq | sudo tee ./custom_cpu/cpufreq/policy$i/cpuinfo_max_freq >/dev/null
  done
fi

gcc -shared -fPIC -DFAKE_NPROCESSORS=$((cores+extracores)) fake_sysconf.c -o libfakesysconf.so -ldl

echo "Load the shared library libfakesysconf.so using LD_PRELOAD."
echo "Bash:   'export LD_PRELOAD=$PWD/libfakesysconf.so'"
echo "Elvish: 'set-env LD_PRELOAD \$E:PWD/libfakesysconf.so'"
