#  env.mk ---
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

PRIMARY_SERVER      = 10.66.99.100
SECONDARY_SERVER    = 10.66.99.110
TOMCAT_HOT_SYSTEMD  = vms-cdr-sync
TOMCAT_COLD_SYSTEMD = tomcat
TOMCAT_HOT_PORT     = 8077
TOMCAT_COLD_PORT    = 8088
#  env.mk ends here
