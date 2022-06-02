#!/bin/bash

bash /opt/kafka-eagle/bin/ke.sh start
sleep 3
tail -f /opt/kafka-eagle/logs/log.log
