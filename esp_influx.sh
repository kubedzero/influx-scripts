#!/usr/local/bin/bash
# macOS `sh` is located at /bin/sh for 3.2 or /usr/local/bin/bash if installed with Homebrew or /usr/bin/bash for *nix

# This script pulls data from Arduino ESP8266 sensors that publish their data to self-hosted web pages

# https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
set -euo pipefail

# https://linuxhint.com/bash_loop_list_strings/
declare -a EspIpArray=(
  "10.1.1.32" # living room NodeMCU with a BMP280, DHT22 (nodemcu1 data feed)
"10.1.1.36" # inside bedroom GeekCreit with a BME280, DHT22 (nodemcu2 data feed)
"10.1.1.34" # external-facing vent NodeMCU with PMS7003, BME280, DHT22 (nodemcu3 data feed)
)

declare -a EspDestArray=(
  "nodemcu1" # living room NodeMCU with a BMP280, DHT22 (nodemcu1 data feed)
"nodemcu2" # inside bedroom GeekCreit with a BME280, DHT22 (nodemcu2 data feed)
"nodemcu3" # external-facing vent NodeMCU with PMS7003, BME280, DHT22 (nodemcu3 data feed)
)

# Iterate the string array using for loop
# https://stackoverflow.com/questions/8880603/loop-through-an-array-of-strings-in-bash
# get length of an array
arraylength=${#EspIpArray[@]}

# use for loop to read all values and indexes
for (( i=1; i<${arraylength}+1; i++ ));
do
  echo $i "/" ${arraylength} ":" ${EspIpArray[$i-1]} "to" ${EspDestArray[$i-1]}
  # https://stackoverflow.com/questions/3742983/how-to-get-the-contents-of-a-webpage-in-a-shell-variable
  # --silent to hide the download prgress from the output
  webdata=$(curl --silent ${EspIpArray[$i-1]})
  # echo $webdata
  # Bash 4 support required for readarray -t y <<<"$webdata".
  readarray -t linesplitwebdata <<<"$webdata"
  # make sure the HTTP response is the proper length
  # https://stackoverflow.com/questions/13101621/checking-if-length-of-array-is-equal-to-a-variable-in-bash
  # https://stackoverflow.com/questions/9146136/check-if-file-exists-and-continue-else-exit-in-bash
if [ ! "${#linesplitwebdata[@]}" -eq "2" ]; then
    echo "Expected 2 lines of HTTP output, got:" ${#linesplitwebdata[@]}
    exit 0
fi
  # https://helpmanual.io/builtin/readarray/ -d specifies comma delimiter, -t removes trailing delimiter
  readarray -d , -t headercsvsplit <<<"${linesplitwebdata[0]}"
  readarray -d , -t datacsvsplit <<<"${linesplitwebdata[1]}"


  innerArrayLength=${#headercsvsplit[@]}

      areanynan=false
    areanyinf=false
    areanynegative=false

    # https://stackoverflow.com/questions/15691942/print-array-elements-on-separate-lines-in-bash
    #printf '%s\n' "${datacsvsplit[@]}"

  # use for loop to read all names and values
  for (( j=1; j<${innerArrayLength}+1; j++ ));
  do
    # trim whitespace https://stackoverflow.com/questions/369758/how-to-trim-whitespace-from-a-bash-variable
    headercsvsplit[$j-1]="$( echo ${headercsvsplit[$j-1]} | xargs echo -n)"
    datacsvsplit[$j-1]="$( echo ${datacsvsplit[$j-1]} | xargs echo -n)"

    currentHeaderValue=${headercsvsplit[$j-1]}
    currentDataValue=${datacsvsplit[$j-1]}

    echo $j "/" ${innerArrayLength} ": header" $currentHeaderValue "value" $currentDataValue

    # check that contents is numeric and above zero
    if [ "$currentDataValue" = "nan" ]; then
      echo "NAN value found for header:" $currentHeaderValue
      areanynan=true
    fi

    if [ "$currentDataValue" = "inf" ]; then
      echo "INF value found for header:" $currentHeaderValue
      areanyinf=true
    fi

        if (( $(bc <<< "$currentDataValue < 0.0") )) ; then
      echo "Subzero value found for header:" $currentHeaderValue "value" $currentDataValue
      areanynegative=true
    fi
  done

  if ( $areanynan ) || ( $areanyinf ) || ( $areanynegative ) ; then
    echo "Problematic values found, skipping submission"
  else

    # Map the input values to output values
    humidity=${datacsvsplit[3]}
    if [ "$humidity" = "inf" ]; then
    humidity=${datacsvsplit[0]}
    fi
    temperaturec=${datacsvsplit[4]}
        temperaturef=${datacsvsplit[5]}
            pressurehg=${datacsvsplit[7]}
                pm100=${datacsvsplit[8]}
                pm250=${datacsvsplit[9]}
                pm1000=${datacsvsplit[10]}

    # Submit all values as one record to InfluxDB
        curl -i -XPOST 'http://10.1.1.7:8086/write?db=local_reporting' --data-binary \
        "environment,host=${EspDestArray[$i-1]} humidity=$humidity,temperaturec=$temperaturec,temperaturef=$temperaturef,pressurehg=$pressurehg,pm100=$pm100,pm250=$pm250,pm1000=$pm1000"

  fi

done
