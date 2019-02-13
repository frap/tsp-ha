# TSP HA Script
This script utilises ssh between 2 hosts to check systemd service availability.
It has the concept of hot and cold standby. 

*Hot Standby* is where both services run at the same time and service availability is
handled vy load-balancers or DNS.
*Cold Standby* is defined as one server runs in a Standby configuration where the
systemd for that service is stopped. We have a concept of a Primary server (the
server normally running the service) and a Secondary server. Service
availability is handled manually - hence the *cold* name. This script provides
that manual mechanism.

## Setup of script
All Customer specific variables are configured by editing the cust-env.mk file.
Change the variables to suit your customers needs. They should be pretty self
explanatory. The only thing difficult is getting the right names for the systemd
services on the Atea servers. It is the name used when you do systemctl status
xxxx (aka normally one is called tomcat)

## Running of script
In the directory where script is just call `make` and it will give you a help
menu

``` sh
$ make
 atea-status               : Check Atea server status for A/A and A/S apps
 cold-pri-active           : Make the pri server Active and put primary in DOWN state
 cold-sec-active           : Make the sec server Active and put primary in DOWN state
 web-status                : What is the web status of Atea servers?
 hot-web-status            : What is the web status of 'hot' tomcat ?
 cold-sysd-status          : What is systemctl status of 'cold' tomcat ?
 hot-sysd-status           : What is systemctl status of 'hot' tomcat ?
 cold-jctl-status          : What is journalctl status of 'cold' tomcat?
 FORCE-pri-active          : Force the pri server Active and put secondary in DOWN state
 FORCE-sec-active          : Force the sec server Active and put primary in DOWN state
```

i.e

``` sh
$ make atea-status
###### tsp-ha start : 52.Ns #################################
BHP Active  Server:10.66.99.100 Status =         active
BHP Standby Server:10.66.99.110 Status =         DOWN
BHP Current Active/Standby Server is   =         10.66.99.100
###### tsp-ha finish: 53.Ns #################################
```

