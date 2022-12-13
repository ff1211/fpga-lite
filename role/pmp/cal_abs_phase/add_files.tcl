#****************************************************************
# Copyright 2022 Tianjin University 305 Lab. All Rights Reserved.
#
# File:
# add_files.tcl
# 
# Description:
# Tcl script to add files to vivado project.
# 
# Revision history:
# Version  Date        Author      Changes      
# 1.0      2022.12.10  ff          Initial version
#****************************************************************

# Project specific configurations.

# Add source files
add_files                               \
    ../../../shell/common/sync_fifo.sv  \
    ./cal_abs_phase.sv                  \
    ./abs_phase_3steps.sv               
# Add simulation files
add_files                               \
    -fileset sim_1                      \
    ./tb.sv

# Add ip