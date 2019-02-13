#  Makefile ---
#
#  Author: Andrés Gasson <agasson@red-elvis.net>
#  Copyright © 2019, Andrés Gasson, all rights reserved.
#  Created:  5 February 2019
#
# $@       the file name of the target
# $<       the name of the first prerequisite (i.e., dependency)
# $^       the names of all prerequisites (i.e., dependencies)
# $(@D)    the directory part of the target
# $(@F)    the file part of the target
# $(<D)    the directory part of the first prerequisite (i.e., dependency)
# $(<F)    the file part of the first prerequisite (i.e., dependency)

.NOTPARALLEL:
# include customer specific ENV variables
-include cust-env.mk

version         := $(shell cat version 2>/dev/null || echo '19.01')
atea_app        := $(shell cat atea_app 2>/dev/null || echo 'app-not-configured')
# ENV variables
QUIET             = @

SHELL            := bash
RM               := rm -f
MKDIR            := mkdir -p
AWK              := awk
CP               := cp
EGREP            := egrep
SED              := sed
SORT             := sort
TOUCH            := touch

ha_key           := tsp-ha
SSH_OPTS         := -i ~/.ssh/${ha_key}
SSH               = ssh
username         := atearoot
user_pri         := ${username}@${PRIMARY-SERVER-IP}
user_sec         := ${username}@${SECONDARY-SERVER-IP}
ssh_pri          := ${SSH_OPTS} ${user_pri}
ssh_sec          := ${SSH_OPTS} ${user_sec}

# -s silent mode -I HEAD request -l follow redirects  -max-time of 5s -o output head to null
CURL_OPTS        := -s -o /dev/null -I -L --max-time 5 -w "%{http_code}"
CURL             := curl
pri-http         := ${CURL_OPTS} http://${PRIMARY-SERVER-IP}
sec-http         := ${CURL_OPTS} http://${SECONDARY-SERVER-IP}
hot-sysd         := sudo systemctl status ${HOT-SERVICE-SYSD-NAME} | grep Active | sed -e "s/Active: \(.*\)/\1/"
cold-sysd        := sudo systemctl status ${COLD-SERVICE-SYSD-NAME} | grep Active | sed -e "s/Active: \(.*\)/\1/"
pri-tc-hot       := ${pri-http}:${HOT-SERVICE-PORT}
sec-tc-hot       := ${sec-http}:${HOT-SERVICE-PORT}
pri-tc-cold      := ${pri-http}:${COLD-SERVICE-PORT}
sec-tc-cold      := ${sec-http}:${COLD-SERVICE-PORT}

start-time       := $(shell date +"%S.%Ns")
current-time      = $(shell date +"%S.%Ns")

# Fixed environment variables
#
#
hostname       := $(shell hostname -s)
rsync_opts     := -avPz -e "ssh -i ~/.ssh/id_rsa" --delete-after --exclude="node_modules" --exclude=".git"
tspha_config    := ssh://git/~/repos/devops/make/tsp-ha.git
data_dir        := status

# $(call check-web-status, server-url)
check-web-status = $(if $(filter 200,$(shell ${CURL} $1)),active,DOWN)
# $(call check-sysd-status, ssh-host, tomcat-service )
check-sysd-status = $(if $(findstring run,$(shell ${SSH} $1 $2)),active,DOWN)


hot-pri-status       = $(shell ${SSH} ${ssh_pri} ${hot-sysd})
hot-sec-status       = $(shell ${SSH} ${ssh_sec} ${hot-sysd})
cold-pri-stop        = $(shell ${SSH} ${ssh_pri} sudo systemctl stop ${COLD-SERVICE-SYSD-NAME})
cold-pri-start       = $(shell ${SSH} ${ssh_pri} sudo systemctl start ${COLD-SERVICE-SYSD-NAME})
cold-sec-stop        = $(shell ${SSH} ${ssh_sec} sudo systemctl stop ${COLD-SERVICE-SYSD-NAME})
cold-sec-start       = $(shell ${SSH} ${ssh_sec} sudo systemctl start ${COLD-SERVICE-SYSD-NAME})
cold-pri-status      = $(shell ${SSH} ${ssh_pri} ${cold-sysd})
cold-sec-status      = $(shell ${SSH} ${ssh_sec} ${cold-sysd})
web-pri-status       = $(if $(filter 200,$(shell ${CURL} ${pri-http})),active,DOWN)
web-sec-status       = $(if $(filter 200,$(shell ${CURL} ${sec-http})),active,DOWN)
web-pri-hot-status   = $(if $(filter 200,$(shell ${CURL} ${pri-tc-hot})),active,DOWN)
web-sec-hot-status   = $(if $(filter 200,$(shell ${CURL} ${sec-tc-hot})),active,DOWN)
web-pri-cold-status  = $(if $(filter 200,$(shell ${CURL} ${pri-tc-cold})),active,standby)
web-sec-cold-status  = $(if $(filter 200,$(shell ${CURL} ${sec-tc-cold})),active,standby)
sysd-pri-cold-status = $(if $(findstring run,${cold-pri-status}),active,DOWN)
sysd-sec-cold-status = $(if $(findstring run,${cold-sec-status}),active,DOWN)
active-cold-server   = $(if $(filter active,${sysd-pri-cold-status}),${PRIMARY-SERVER-IP},${SECONDARY-SERVER-IP})

.PHONY : help
help : Makefile
	@sed -n 's/^##//p'  $<

## atea-status                 : Check Atea server status for A/A and A/S apps
atea-status : web-status
	${QUIET} echo "${CUST-NAME} Current Active/Standby Server is   =         ${active-cold-server}"
	@echo "###### ${atea_app} finish: ${current-time} #################################"

## cold-pri-active           : Make the pri server Active and put primary in DOWN state
cold-pri-active: cold-sysd-status
	@echo "#### Making ${CUST-NAME} Primary Server the Active Server ####################"
  ifeq "${sysd-pri-cold-status}" "active"
	@echo "!!!! ${CUST-NAME} Primary is already active - Exiting                      !!!"; exit -1
  else
	${cold-sec-stop}
	${cold-pri-start}
	@echo "###### ${atea_app} finish: ${current-time} #################################"
  endif

## cold-sec-active           : Make the sec server Active and put primary in DOWN state
cold-sec-active: cold-sysd-status
	@echo "#### Making ${CUST-NAME} Standby Server the Active Server for Service:${COLD-SERVICE-SYSD-NAME} ####"
  ifeq "${sysd-sec-cold-status}" "active"
	@echo "!!!! ${CUST-NAME} Standby server is already active - Exiting            !!!!"; exit -1
  else
	${cold-pri-stop}
	${cold-sec-start}
	@echo "###### ${atea_app} finish: ${current-time} #################################"
  endif

## web-status                : What is the web status of Atea servers?
web-status : start
	${QUIET} echo "${CUST-NAME} Active  Server:${PRIMARY-SERVER-IP} Status =         ${web-pri-status}"
	${QUIET} echo "${CUST-NAME} Standby Server:${SECONDARY-SERVER-IP} Status =         ${web-sec-status}"

## hot-web-status            : What is the web status of 'hot' tomcat ?
hot-web-status : start
	${QUIET} echo "${CUST-NAME} Pri Server Hot  Tomcat Status  =         ${web_pri_hot_status}"
	${QUIET} echo "${CUST-NAME} Sec Server Hot  Tomcat Status  =         ${web_sec_hot_status}"
	@echo "###### ${atea_app} finish: ${current-time} #################################"

## cold-sysd-status          : What is systemctl status of 'cold' tomcat ?
cold-sysd-status : | start
	${QUIET} echo "${CUST-NAME} Primary   Server Cold Tomcat Status  =         ${sysd-pri-cold-status}"
	${QUIET} echo "${CUST-NAME} Secondary Server Cold Tomcat Status  =         ${sysd-sec-cold-status}"

## hot-sysd-status           : What is systemctl status of 'hot' tomcat ?
hot-sysd-status : start
	${QUIET} echo "${CUST-NAME} Primary   Server Hot Tomcat Status   =         ${sysd-pri-hot-status}"
	${QUIET} echo "${CUST-NAME} Secondary Server Hot Tomcat Status   =         ${sysd-sec-hot-status}"
	@echo "###### ${atea_app} finish: ${current-time} #################################"

## cold-jctl-status          : What is journalctl status of 'cold' tomcat?
cold-jctl-status : start | ${HOME}/.ssh/${ha_key}
	@echo "#### ${CUST-NAME} Pri Server Cold Tomcat Latest Logs:          ####"
	${QUIET} ${SSH} ${ssh_pri} "sudo journalctl -u tomcat -o cat -n 10"
	@echo "#### ${CUST-NAME} Sec Server Cold Tomcat Latest Logs:          ####"
	${QUIET} ${SSH} ${ssh_sec} "sudo journalctl -u tomcat -o cat -n 10"
	@echo "###### ${atea_app} finish: ${current-time} #################################"

## FORCE-pri-active          : Force the pri server Active and put secondary in DOWN state
FORCE-pri-active: cold-sysd-status
	@echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
	@echo "!!! FORCING ${CUST-NAME} Primary Server active                            !!!!"
	${QUIET} ${SSH} ${ssh_pri} sudo systemctl restart ${TOMCAT_COLD_SYSTEMD}
	@echo "###### ${atea_app} finish: ${current-time} #################################"

## FORCE-sec-active          : Force the sec server Active and put primary in DOWN state
FORCE-sec-active: cold-sysd-status
	@echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
	@echo "!!! FORCING ${CUST-NAME} Secondary Server active                          !!!!"
	${QUIET} ${SSH} ${ssh_sec}  sudo systemctl restart ${TOMCAT_COLD_SYSTEMD}
	@echo "###### ${atea_app} finish: ${current-time} #################################"

.PHONY: start
start: setup-ssh-keys
	@echo "###### ${atea_app} start : ${start-time} #################################"

setup-ssh-keys : | ${HOME}/.ssh/${ha_key} ; ${call assert-command-present,curl}

${HOME}/.ssh/${ha_key}: ; ${call assert-command-present,ssh}
	@echo "Setting up ssh keys between pri=${PRIMARY-SERVER-IP} and sec=${SECONDARY-SERVER-IP}"
	ssh-keygen -b 2048 -C "${hostname} Atea TSP HA key" -t rsa -f $@
	ssh-copy-id -i ~/.ssh/${ha_key} ${user_pri}
	ssh-copy-id -i ~/.ssh/${ha_key} ${user_sec}

#
# some makefile debug parameters
#

#OLD_SHELL := $(SHELL)
#SHELL = $(warning bash Running $@$(if $<, (from $<))$(if $?, ($? newer)))$(OLD_SHELL) -x

env_file = /tmp/env
env_shell = $(shell rm -f $(env_file))$(foreach V,$1,$(shell echo export$V=$($V) >> $(env_file)))$(shell echo '$2' >> $(env_file))$(shell /bin/bash -e $(env_file))

assert-command-present = $(if $(shell which $1),,$(error '$1' missing and needed for this build))

make-truth = $(if $1,T)

check-sysd-status = $(if )
# $(call file-exists, file-name)
#   Return non-null if a file exists.
file-exists = $(wildcard $1)

# Debug variables in Makefile
print-%: ; @echo $* = '$($*)' from $(origin $*)

# print all VARs
.PHONY: printvars
printvars:
	@$(foreach V,$(sort $(.VARIABLES)),            \
  $(if $(filter-out environment% default automatic,  \
  $(origin $V)),$(info $V=$($V) ($(value $V)))))

#  Makefile ends here
