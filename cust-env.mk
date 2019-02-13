#  cust-env.mk ---
#
#  Author: Andrés Gasson <agasson@ateasystems.com>
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

CUST-NAME               := "BHP"
PRIMARY-SERVER-IP       := "10.66.99.100"
SECONDARY-SERVER-IP     := 10.66.99.110
HOT-SERVICE-SYSD-NAME   := "mtail"
COLD-SERVICE-SYSD-NAME  := "tomcat"
HOT-SERVICE-PORT        := 8077
COLD-SERVICE-PORT       := 8088


#  cust-env.mk ends here
