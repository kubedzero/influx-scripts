#!/usr/bin/sh

#This script pulls data from Arduino temperature sensors that publish their data to self-hosted web pages

#Set NODE IP addresses
NODEIP1="10.1.1.34" #34 is now the outside NodeMCU with PMS7003 and BME280 (nodemcu3 data feed)
NODEIP2="10.1.1.35" #35 is now the living room NodeMCU with a BMP280 and DHT22 (nodemcu1 data feed)
NODEIP3="10.1.1.36" #36 is now the inside bedroom NodeMCU with a BME280 (nodemcu2 data feed)


#process first NodeMCU listed for data feed 3
IN=`wget -qO- http://$NODEIP1` #get comma-delimited data from first NodeMCU
set -- "$IN"
IFS=","; declare -a PARSED=($*) #IFS separates a string into an array based on , delimiter
echo "Array: ${PARSED[@]}" #print entire array result to output
if [ ${#PARSED[@]} -eq 0 ] ; then #check to make sure the array has elements.
    echo "wget parsing failed, is the URL correct?"
else
    #print values to console
    echo "Humidity: ${PARSED[0]}"
    echo "Temperature C: ${PARSED[1]}" 
    echo "Temperature F: ${PARSED[2]}" 
    echo "Pressure (inHg): ${PARSED[3]}" 
    echo "PM1.0: ${PARSED[4]}" 
    echo "PM2.5: ${PARSED[5]}"
    echo "PM10: ${PARSED[6]}" 
    echo ""
    #Write the data to the database if it is not "nan" and >0. Spaces inside brackets are important. BC can do float comparison
    if [ "${PARSED[0]}" != "nan" ] && \
        [ "${PARSED[1]}"  != "nan" ] && \
        [ "${PARSED[2]}" != "nan" ] && \
        [ "${PARSED[3]}" != "nan" ] && \
        [ "${PARSED[4]}" != "nan" ] && \
        [ "${PARSED[5]}" != "nan" ] && \
        [ "${PARSED[6]}" != "nan" ] && \
        (( $(bc <<< "${PARSED[0]} > 0.0") )) && \
        (( $(bc <<< "${PARSED[1]} > 0.0") )) && \
        (( $(bc <<< "${PARSED[2]} > 0.0") )) && \
        (( $(bc <<< "${PARSED[3]} > 0.0") )) && \
        (( $(bc <<< "${PARSED[4]} > 0.0") )) && \
        (( $(bc <<< "${PARSED[5]} > 0.0") )) && \
        (( $(bc <<< "${PARSED[6]} > 0.0") )) ; then
        # Submit all values as one row to InfluxDB
        curl -i -XPOST 'http://10.1.1.7:8086/write?db=local_reporting' --data-binary \
        "environment,host=nodemcu3 humidity=${PARSED[0]},temperaturec=${PARSED[1]},temperaturef=${PARSED[2]},pressurehg=${PARSED[3]},pm100=${PARSED[4]},pm250=${PARSED[5]},pm1000=${PARSED[6]}"
    else
        echo "One or more values nan or 0, skipping submission"
    fi
fi


#process second NodeMCU listed for data feed 1
IN=`wget -qO- http://$NODEIP2` #get comma-delimited data from first NodeMCU
set -- "$IN"
IFS=","; declare -a PARSED=($*) #IFS separates a string into an array based on , delimiter
echo "Array: ${PARSED[@]}" #print entire array result to output
if [ ${#PARSED[@]} -eq 0 ] ; then #check to make sure the array has elements.
    echo "wget parsing failed, is the URL correct?"
else
    #print values to console
    echo "Humidity: ${PARSED[0]}"
    echo "Temperature C: ${PARSED[1]}" 
    echo "Temperature F: ${PARSED[2]}" 
    echo "Pressure (inHg): ${PARSED[3]}" 
    echo "PM1.0: ${PARSED[4]}" 
    echo "PM2.5: ${PARSED[5]}"
    echo "PM10: ${PARSED[6]}" 
    echo ""
    #Write the data to the database if it is not "nan" and >0. Spaces inside brackets are important. BC can do float comparison
    if [ "${PARSED[0]}" != "nan" ] && \
        [ "${PARSED[1]}"  != "nan" ] && \
        [ "${PARSED[2]}" != "nan" ] && \
        [ "${PARSED[3]}" != "nan" ] && \
        (( $(bc <<< "${PARSED[0]} > 0.0") )) && \
        (( $(bc <<< "${PARSED[1]} > 0.0") )) && \
        (( $(bc <<< "${PARSED[2]} > 0.0") )) && \
        (( $(bc <<< "${PARSED[3]} > 0.0") )) ; then
        # Submit all values as one row to InfluxDB
        curl -i -XPOST 'http://10.1.1.7:8086/write?db=local_reporting' --data-binary \
        "environment,host=nodemcu1 humidity=${PARSED[0]},temperaturec=${PARSED[1]},temperaturef=${PARSED[2]},pressurehg=${PARSED[3]}"
    else
        echo "One or more values nan or 0, skipping submission"
    fi
fi


#process third NodeMCU listed for data feed 2
IN=`wget -qO- http://$NODEIP3` #get comma-delimited data from first NodeMCU
set -- "$IN"
IFS=","; declare -a PARSED=($*) #IFS separates a string into an array based on , delimiter
echo "Array: ${PARSED[@]}" #print entire array result to output
if [ ${#PARSED[@]} -eq 0 ] ; then #check to make sure the array has elements.
    echo "wget parsing failed, is the URL correct?"
else
    #print values to console
    echo "Humidity: ${PARSED[0]}"
    echo "Temperature C: ${PARSED[1]}" 
    echo "Temperature F: ${PARSED[2]}" 
    echo "Pressure (inHg): ${PARSED[3]}" 
    echo "PM1.0: ${PARSED[4]}" 
    echo "PM2.5: ${PARSED[5]}"
    echo "PM10: ${PARSED[6]}" 
    echo ""
    #Write the data to the database if it is not "nan" and >0. Spaces inside brackets are important. BC can do float comparison
    if [ "${PARSED[0]}" != "nan" ] && \
        [ "${PARSED[1]}"  != "nan" ] && \
        [ "${PARSED[2]}" != "nan" ] && \
        [ "${PARSED[3]}" != "nan" ] && \
        (( $(bc <<< "${PARSED[0]} > 0.0") )) && \
        (( $(bc <<< "${PARSED[1]} > 0.0") )) && \
        (( $(bc <<< "${PARSED[2]} > 0.0") )) && \
        (( $(bc <<< "${PARSED[3]} > 0.0") )) ; then
        # Submit all values as one row to InfluxDB
        curl -i -XPOST 'http://10.1.1.7:8086/write?db=local_reporting' --data-binary \
        "environment,host=nodemcu2 humidity=${PARSED[0]},temperaturec=${PARSED[1]},temperaturef=${PARSED[2]},pressurehg=${PARSED[3]}"
    else
        echo "One or more values nan or 0, skipping submission"
    fi
fi
