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
# include application specific ENV variables
-include env.mk

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
user_pri         := ${username}@${PRIMARY_SERVER}
user_sec         := ${username}@${SECONDARY_SERVER}
ssh_pri          := ${SSH_OPTS} ${user_pri}
ssh_sec          := ${SSH_OPTS} ${user_sec}

# -s silent mode -I HEAD request -l follow redirects  -max-time of 5s -o output head to null
CURL_OPTS        := -s -o /dev/null -I -L --max-time 5 -w "%{http_code}"
CURL             := curl
pri-http         := ${CURL_OPTS} http://${PRIMARY_SERVER}
sec-http         := ${CURL_OPTS} http://${SECONDARY_SERVER}
hot-sysd         := sudo systemctl status ${TOMCAT_HOT_SYSTEMD} | grep Active | sed -e "s/Active: \(.*\)/\1/"
cold-sysd        := sudo systemctl status ${TOMCAT_COLD_SYSTEMD} | grep Active | sed -e "s/Active: \(.*\)/\1/"
pri-tc-hot       := ${pri-http}:${TOMCAT_HOT_PORT}
sec-tc-hot       := ${sec-http}:${TOMCAT_HOT_PORT}
pri-tc-cold      := ${pri-http}:${TOMCAT_COLD_PORT}
sec-tc-cold      := ${sec-http}:${TOMCAT_COLD_PORT}

START_TIME       := $(shell date)
CURRENT_TIME      = $(shell date)

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
stop-pri-cold        = $(shell ${SSH} ${ssh_pri} sudo systemctl stop ${TOMCAT_COLD_SYSTEMD})
start-sec-cold       = $(shell ${SSH} ${ssh_sec} sudo systemctl start ${TOMCAT_COLD_SYSTEMD})
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
active-cold-server   = $(if $(filter active,${sysd-pri-cold-status}),${PRIMARY_SERVER},${SECONDARY_SERVER})

.PHONY : help
help : Makefile
	@sed -n 's/^##//p'  $<

## setup                      : Setup ssh keys bettwen pri and sec servers
setup : | ${HOME}/.ssh/${ha_key} ; ${call assert-command-present,curl}
	@echo Setting up pri and sec server ssh keys

${HOME}/.ssh/${ha_key}: ; ${call assert-command-present,ssh}
	@echo "Setting up ssh keys between pri=${PRIMARY_SERVER} and sec=${SECONDARY_SERVER}"
	ssh-keygen -b 2048 -C "${hostname} Atea TSP HA key" -t rsa -f $@
	ssh-copy-id -i ~/.ssh/${ha_key} ${user_pri}
	ssh-copy-id -i ~/.ssh/${ha_key} ${user_sec}

## bhp-srv-status             : Check BHP server status for A/A and A/S apps
bhp-srv-status : web-status
	@echo "#####################################################################"
	${QUIET} echo "BHP Current Active/Standby Server is   =         ${active-cold-server}"

## make-pri-active            : Make the pri server Active and put primary in DOWN state
make-pri-active: sysd-cold-status
	@echo "#### Making BHP Primary Server the Active Server ####################"
  ifeq "${sysd-sec-cold-status}" "DOWN"
	@echo "!!!! BHP Primary should be active as Secondary is currently DOWN: !!!"
	${start-pri-cold}
  else
	${stop-sec-cold}
	${start-pri-cold}
  endif

## make-sec-active            : Make the sec server Active and put primary in DOWN state
make-sec-active:
	@echo "#### Making BHP Standby Server the Active Server ####################"
  ifeq "${sysd-pri-cold-status}" "DOWN"
	@echo "!!!! BHP Secondary should be active as Primary is currently DOWN: !!!"
	${start-sec-cold}
  else
	${stop-pri-cold}
	${start-sec-cold}
  endif

## web-status                : What is the web status of BHP servers?
web-status :
	@echo "#####################################################################"
	${QUIET} echo "BHP Active  Server:${PRIMARY_SERVER} Status =         ${web-pri-status}"
	${QUIET} echo "BHP Standby Server:${SECONDARY_SERVER} Status =         ${web-sec-status}"

## web-hot-status            : What is the web status of 'hot' tomcat ?
web-hot-status :
	@echo "#####################################################################"
	${QUIET} echo "BHP Pri Server Hot  Tomcat Status  =         ${web_pri_hot_status}"
	${QUIET} echo "BHP Sec Server Hot  Tomcat Status  =         ${web_sec_hot_status}"

## sysd-cold-status          : What is systemctl status of 'cold' tomcat ?
sysd-cold-status :
	@echo "#####################################################################"
	${QUIET} echo "BHP Primary   Server Cold Tomcat Status  =         ${sysd-pri-cold-status}"
	${QUIET} echo "BHP Secondary Server Cold Tomcat Status  =         ${sysd-sec-cold-status}"

## sysd-hot-status           : What is systemctl status of 'hot' tomcat ?
sysd-hot-status :
	@echo "#####################################################################"
	${QUIET} echo "BHP Primary   Server Hot Tomcat Status   =         ${sysd-pri-hot-status}"
	${QUIET} echo "BHP Secondary Server Hot Tomcat Status   =         ${sysd-sec-hot-status}"

## jctl-cold-status          : What is journalctl status of 'cold' tomcat?
jctl-cold-status : | ${HOME}/.ssh/${ha_key}
	@echo "#####################################################################"
	@echo "#### BHP Pri Server Cold Tomcat Latest Logs:                     ####"
	${QUIET} ${SSH} ${ssh_pri} "sudo journalctl -u tomcat -o cat -n 10"
	@echo "#### BHP Sec Server Cold Tomcat Latest Logs:                     ####"
	${QUIET} ${SSH} ${ssh_sec} "sudo journalctl -u tomcat -o cat -n 10"

## FORCE-pri-active            : Force the pri server Active and put secondary in DOWN state
FORCE-pri-active: sysd-cold-status
	@echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
	@echo "!!! FORCING BHP Primary Server active                            !!!!"
	${QUIET} ${SSH} ${ssh_pri} sudo systemctl restart ${TOMCAT_COLD_SYSTEMD}

## FORCE-sec-active            : Force the sec server Active and put primary in DOWN state
FORCE-sec-active: sysd-cold-status
	@echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
	@echo "!!! FORCING BHP Secondary Server active                          !!!!"
	${QUIET} ${SSH} ${ssh_sec}  sudo systemctl restart ${TOMCAT_COLD_SYSTEMD}
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

# $(call maybe-mkdir, directory-name-opt)
#   Create a directory if it doesn't exist.
#   If directory-name-opt is omitted use $@ for the directory-name.
maybe-mkdir = $(if $(call file-exists,          \
                     $(if $1,$1,$(dir $@))),,   \
                $(MKDIR) $(if $1,$1,$(dir $@)))

print-%: ; @echo $* = '$($*)' from $(origin $*)

.PHONY: printvars
printvars:
	@$(foreach V,$(sort $(.VARIABLES)),            \
  $(if $(filter-out environment% default automatic,  \
  $(origin $V)),$(info $V=$($V) ($(value $V)))))

#  Makefile ends here
