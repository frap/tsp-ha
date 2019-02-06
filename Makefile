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

SHELL             = bash
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
SSH              := ssh
username         := atearoot
user_pri         := ${username}@${PRIMARY_SERVER}
user_sec         := ${username}@${SECONDARY_SERVER}
ssh_pri          := ${SSH} ${SSH_OPTS} ${user_pri}
ssh_sec          := ${SSH} ${SSH_OPTS} ${user_sec}

CURL_OPTS        := -I -o -L -s -w "%{http_code}" http://
CURL             := curl ${CURL_OPTS}
curl_pri         := ${CURL}${PRIMARY_SERVER}
curl_sec         := ${CURL}${SECONDARY_SERVER}
curl_pri_hot     := ${curl_pri}:${TOMCAT_HOT_PORT}
curl_sec_hot     := ${curl_sec}:${TOMCAT_HOT_PORT}
curl_pri_cold    := ${curl_pri}:${TOMCAT_COLD_PORT}
curl_sec_cold    := ${curl_sec}:${TOMCAT_COLD_PORT}

START_TIME       := $(shell date)
CURRENT_TIME      = $(shell date)
REQUIRED_DIRS     = ${data_dir}
_MKDIRS          := $(shell for d in $(REQUIRED_DIRS); \
                      do                               \
                        [[ -d $$d ]] || ${MKDIR} $$d;  \
                      done)
env_file = /tmp/env
env_shell = $(shell rm -f $(env_file))$(foreach V,$1,$(shell echo export$V=$($V) >> $(env_file)))$(shell echo '$2' >> $(env_file))$(shell /bin/bash -e $(env_file))
assert-command-present = $(if $(shell which $1),,$(error '$1' missing and needed for this build))
make-truth = $(if $1,T)
# fixed environment variables
# Variables with no definition expand to nothing - useful for use customisations
#
hostname       := $(shell hostname -s)

rsync_opts     := -avPz -e "ssh -i ~/.ssh/id_rsa" --delete-after --exclude="node_modules" --exclude=".git"

tspha_config    := ssh://git/~/repos/devops/make/tsp-ha.git
data_dir        := status


pri_status      = $(shell if [ $$(${curl_pri}) -eq 200 ]; then echo "up"; else echo "DOWN"; fi)
sec_status      = $(shell if [ $$(${curl_sec}) -eq 200 ]; then echo "up"; else echo "DOWN"; fi)
pri_tomcat_hot  = $(shell if [ $$(${curl_pri_hot}) -eq 200 ]; then echo "active"; else echo "DOWN"; fi)
sec_tomcat_hot  = $(shell if [ $$(${curl_sec_hot}) -eq 200 ]; then echo "active"; else echo "DOWN"; fi)
pri_tomcat_cold = $(shell if [ $$(${curl_pri_cold}) -eq 200 ]; then echo "active"; else echo "standby"; fi)
sec_tomcat_cold = $(shell if [ $$(${curl_sec_cold}) -eq 200 ]; then echo "active"; else echo "standby"; fi)

# $(call assert,condition,message)
define assert
$(if ,,$(error Assertion failed: ))
endef
# $(call assert-not-null,make-variable)
define assert-not-null
$(call assert,$(),The variable "" is null)
endef
# $(call file-exists, file-name)
#   Return non-null if a file exists.
file-exists = $(wildcard $1)

# $(call maybe-mkdir, directory-name-opt)
#   Create a directory if it doesn't exist.
#   If directory-name-opt is omitted use $@ for the directory-name.
maybe-mkdir = $(if $(call file-exists,          \
                     $(if $1,$1,$(dir $@))),,   \
                $(MKDIR) $(if $1,$1,$(dir $@)))

.PHONY : help
help : Makefile
	@sed -n 's/^##//p'  $<

## setup                      : Setup Atea TSP HA
setup : | ${HOME}/.ssh/${ha_key}
	@echo Setting up

${HOME}/.ssh/${ha_key}:
	@echo "Setting up ssh keys between pri=${PRIMARY_SERVER} and sec=${SECONDARY_SERVER}"
	ssh-keygen -b 2048 -C "Atea TSP HA key" -t rsa -f $@
	ssh-copy-id -i ~/.ssh/${ha_key} ${user_pri}
	ssh-copy-id -i ~/.ssh/${ha_key} ${user_sec}

## web-pri-status             : What is status of primary?
web-pri-status :
	@echo "Pri Server:${PRIMARY_SERVER} Status =         ${pri_status}"

## web-sec-status             : What is status of secondary?
web-sec-status : web-pri-status
	@echo "Sec Server:${SECONDARY_SERVER} Status =         ${sec_status}"

## web-hot-status             : What is status of 'hot' tomcat ?
web-hot-status : web-sec-status
	@echo "Pri Server Hot  Tomcat Status  =         ${pri_tomcat_hot}"
	@echo "Sec Server Hot  Tomcat Status  =         ${sec_tomcat_hot}"

## web-cold-status            : What is status of 'cold' tomcat ?
web-cold-status : web-hot-status
	@echo "Pri Server Cold Tomcat Status  =         ${pri_tomcat_cold}"
	@echo "Sec Server Cold Tomcat Status  =         ${sec_tomcat_cold}"

## jctl-cold-status           : What is journalctl status of 'cold' tomcat?
jctl-cold-status : ${HOME}/.ssh/${ha_key}
	@echo "Pri Server Cold Tomcat Latest Logs:"
	${QUIET} ${ssh_pri} "sudo journalctl -u tomcat -o cat -n 10"
	@echo "Sec Server Cold Tomcat Latest Logs:"
	${QUIET} ${ssh_sec} "sudo journalctl -u tomcat -o cat -n 10"

## sysd-cold-status           : What is systemd status of 'cold' tomcat?
sysd-cold-status : ${HOME}/.ssh/${ha_key}
	@echo "Pri Server Cold Tomcat Systemd Status:"
	${QUIET} ${ssh_pri} "sudo systemctl status ${TOMCAT_COLD_SYSTEMD} | grep Active"
	@echo "Sec Server Cold Tomcat Systemd Status:"
	${QUIET} ${ssh_sec} "sudo systemctl status ${TOMCAT_COLD_SYSTEMD} | grep Active"

## sysd-hot-status            : What is systemd status of 'hot' tomcat?
sysd-hot-status :
	@echo "Pri Server Hot Tomcat Systemd Status:"
	${QUIET} ${ssh_pri} "sudo systemctl status ${TOMCAT_HOT_SYSTEMD} | grep Active"
	@echo "Sec Server Hot Tomcat Systemd Status:"
	${QUIET} ${ssh_sec} "sudo systemctl status ${TOMCAT_HOT_SYSTEMD} | grep Active"

.PHONY: rsync
rsync:
	command -v $@ > /dev/null || yum install $@

#  Makefile ends here
